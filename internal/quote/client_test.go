package quote

import (
	"bytes"
	"context"
	"io"
	"net/http"
	"net/url"
	"strings"
	"testing"
	"testing/iotest"
	"time"

	"github.com/stretchr/testify/require"
)

const feedURL = "https://query1.finance.yahoo.com/v8/finance/chart/USDBRL=X"

type roundTripFunc func(*http.Request) (*http.Response, error)

func (f roundTripFunc) RoundTrip(req *http.Request) (*http.Response, error) {
	return f(req)
}

func TestFetch_ShouldRequestJSON(t *testing.T) {
	client := NewClient(roundTripFunc(func(req *http.Request) (*http.Response, error) {
		require.Equal(t, http.MethodGet, req.Method)
		require.Equal(t, feedURL, req.URL.String())
		require.Equal(t, "application/json", req.Header.Get("Accept"))
		require.Equal(t, "usdbrl-swiftbar/1.0", req.Header.Get("User-Agent"))
		return new(http.Response{
			StatusCode: http.StatusOK,
			Body:       io.NopCloser(bytes.NewReader(yahooJSON)),
		}), nil
	}))

	got, err := client.Fetch(t.Context(), Yahoo, feedURL)
	require.NoError(t, err)
	require.Equal(t, "yahoo\t5.7266\t-1.6217\t5.8254\t5.7084\t1795704835", got.Line())
}

func TestFetch_ShouldClassifyResponses(t *testing.T) {
	tests := []struct {
		name   string
		status int
		body   io.Reader
		want   FetchError
	}{
		{
			name:   "upstream rejected",
			status: http.StatusServiceUnavailable,
			body:   strings.NewReader(""),
			want: FetchError{
				Kind:   HTTPError,
				Status: http.StatusServiceUnavailable,
			},
		},
		{
			name:   "redirect is not followed",
			status: http.StatusMovedPermanently,
			body:   bytes.NewReader(yahooJSON),
			want: FetchError{
				Kind:   Invalid,
				Status: http.StatusMovedPermanently,
			},
		},
		{
			name:   "oversized response",
			status: http.StatusOK,
			body:   strings.NewReader(strings.Repeat(" ", 65537)),
			want: FetchError{
				Kind:   Other,
				Status: http.StatusOK,
			},
		},
		{
			name:   "truncated response",
			status: http.StatusOK,
			body:   iotest.ErrReader(io.ErrUnexpectedEOF),
			want: FetchError{
				Kind:   HTTPError,
				Status: http.StatusOK,
			},
		},
		{
			name:   "response read timeout",
			status: http.StatusOK,
			body:   iotest.ErrReader(context.DeadlineExceeded),
			want: FetchError{
				Kind:   NoConnection,
				Status: http.StatusOK,
			},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			client := NewClient(roundTripFunc(func(req *http.Request) (*http.Response, error) {
				require.Equal(t, feedURL, req.URL.String())
				return new(http.Response{
					StatusCode: tt.status,
					Header:     http.Header{"Location": {"https://example.com/"}},
					Body:       io.NopCloser(tt.body),
				}), nil
			}))
			_, err := client.Fetch(t.Context(), Yahoo, feedURL)
			require.Equal(t, tt.want, err)
		})
	}
}

func TestFetch_ShouldRejectHTTP(t *testing.T) {
	client := NewClient(roundTripFunc(func(_ *http.Request) (*http.Response, error) {
		t.Fatal("unexpected HTTP request")
		return nil, nil
	}))
	insecure := url.URL{
		Scheme: "http",
		Host:   "query1.finance.yahoo.com",
	}
	_, err := client.Fetch(t.Context(), Yahoo, insecure.String())
	require.Equal(t, FetchError{Kind: Other}, err)
}

func TestFetch_ShouldBoundConnectionSetup(t *testing.T) {
	client := NewClient(roundTripFunc(func(req *http.Request) (*http.Response, error) {
		<-req.Context().Done()
		return nil, req.Context().Err()
	}))
	client.connectTimeout = time.Millisecond

	_, err := client.Fetch(t.Context(), Yahoo, feedURL)
	require.Equal(t, FetchError{Kind: NoConnection}, err)
}
