package quote

import (
	"context"
	"crypto/tls"
	"errors"
	"io"
	"net"
	"net/http"
	"net/http/httptrace"
	"time"
)

const (
	connectTimeout = 4 * time.Second
	requestTimeout = 8 * time.Second
	maxBodyBytes   = 64 * 1024
)

type Client struct {
	http           *http.Client
	connectTimeout time.Duration
}

// NewClient accepts a nil transport for the default connection policy. All requests have an 8 s limit.
func NewClient(rt http.RoundTripper) Client {
	if rt == nil {
		dialer := net.Dialer{Timeout: connectTimeout}
		rt = new(http.Transport{
			Proxy:               http.ProxyFromEnvironment,
			DialContext:         dialer.DialContext,
			TLSClientConfig:     new(tls.Config{MinVersion: tls.VersionTLS12}),
			TLSHandshakeTimeout: connectTimeout,
			DisableCompression:  true,
			ForceAttemptHTTP2:   true,
		})
	}
	return Client{
		http: new(http.Client{
			Transport: rt,
			Timeout:   requestTimeout,
			CheckRedirect: func(_ *http.Request, _ []*http.Request) error {
				return http.ErrUseLastResponse
			},
		}),
		connectTimeout: connectTimeout,
	}
}

// Fetch requires HTTPS, rejects redirects and reports failures as FetchError.
func (c Client) Fetch(ctx context.Context, source Source, url string) (Quote, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil || req.URL.Scheme != "https" || req.URL.Hostname() == "" {
		return Quote{}, FetchError{Kind: Other}
	}
	req.Header.Set("Accept", "application/json")
	req.Header.Set("User-Agent", "usdbrl-swiftbar/1.0")

	// Stop the connection timer only once DNS, TCP and TLS have all completed.
	ctx, cancel := context.WithCancelCause(ctx)
	defer cancel(nil)
	timer := time.AfterFunc(c.connectTimeout, func() {
		cancel(context.DeadlineExceeded)
	})
	defer timer.Stop()
	ctx = httptrace.WithClientTrace(ctx, new(httptrace.ClientTrace{
		GotConn: func(_ httptrace.GotConnInfo) {
			timer.Stop()
		},
	}))
	req = req.WithContext(ctx)
	resp, err := c.http.Do(req)
	if err != nil {
		if errors.Is(context.Cause(ctx), context.DeadlineExceeded) {
			return Quote{}, FetchError{Kind: NoConnection}
		}
		return Quote{}, requestError(err)
	}
	defer func() {
		_ = resp.Body.Close()
	}()
	return decodeResponse(source, resp)
}

func decodeResponse(source Source, resp *http.Response) (Quote, error) {
	var kind ErrorKind
	status := resp.StatusCode
	switch {
	case status >= http.StatusBadRequest:
		kind = HTTPError
	case status < http.StatusOK || status >= http.StatusMultipleChoices:
		kind = Invalid
	case resp.ContentLength > maxBodyBytes:
		kind = Other
	}
	if kind != 0 {
		return Quote{}, responseError(kind, status)
	}

	body, err := io.ReadAll(io.LimitReader(resp.Body, maxBodyBytes+1))
	if err != nil {
		kind = requestError(err).Kind
		if kind != NoConnection {
			kind = HTTPError
		}
		return Quote{}, responseError(kind, status)
	}
	if len(body) > maxBodyBytes {
		return Quote{}, responseError(Other, status)
	}

	var q Quote
	switch source {
	case Yahoo:
		q, err = parseYahoo(body)
	case Awesome:
		q, err = parseAwesome(body)
	default:
		err = errInvalidQuote
	}
	if err != nil {
		return Quote{}, responseError(Invalid, status)
	}
	return q, nil
}
