package quote

import (
	"context"
	"crypto/tls"
	"errors"
	"net"
	"net/http"
	"net/http/httptrace"
	"time"

	"github.com/fascari/swiftbar-usdbrl/pkg/boundedio"
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
	body, err := readResponse(resp)
	if err != nil {
		return Quote{}, err
	}
	q, err := parseQuote(source, body)
	if err != nil {
		return Quote{}, responseError(Invalid, resp.StatusCode)
	}
	return q, nil
}

func readResponse(resp *http.Response) ([]byte, error) {
	status := resp.StatusCode
	if status >= http.StatusBadRequest {
		return nil, responseError(HTTPError, status)
	}
	if status < http.StatusOK || status >= http.StatusMultipleChoices {
		return nil, responseError(Invalid, status)
	}
	if resp.ContentLength > maxBodyBytes {
		return nil, responseError(Other, status)
	}

	body, err := boundedio.ReadAll(resp.Body, maxBodyBytes)
	if errors.Is(err, boundedio.ErrLimit) {
		return nil, responseError(Other, status)
	}
	if err != nil {
		kind := requestError(err).Kind
		if kind != NoConnection {
			kind = HTTPError
		}
		return nil, responseError(kind, status)
	}
	return body, nil
}

func parseQuote(source Source, body []byte) (Quote, error) {
	if source == Yahoo {
		return parseYahoo(body)
	}
	if source == Awesome {
		return parseAwesome(body)
	}
	return Quote{}, errInvalidQuote
}
