package provider

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

func TestFetch_ShouldSendOnlyReferenceAmount(t *testing.T) {
	requests := make(chan map[string][]string, 1)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost || r.ParseMultipartForm(4096) != nil {
			w.WriteHeader(http.StatusBadRequest)
			return
		}
		requests <- r.MultipartForm.Value
		_, _ = w.Write([]byte(`{"data":{"from_amount":"1000.0000","to_amount":"5518.94","from_currency":"usd","to_currency":"brl","effective_exchange_rate":"5.51894","flat_fee":"0.00","expires_at":200},"errors":null}`))
	}))
	defer server.Close()

	client := HiglobeClient{URL: server.URL, Now: func() time.Time { return time.Unix(100, 0) }}
	rate, err := client.Fetch(t.Context())
	require.NoError(t, err)
	require.Equal(t, "5.51894", rate)
	require.Equal(t, map[string][]string{"amount": {"1000"}, "country": {"BRAZIL"}}, <-requests)
}

func TestParseQuote_ShouldRejectNonProportionalQuote(t *testing.T) {
	data := quoteData{
		From: "1000.0000", To: "5518.94", FromCurrency: "usd", ToCurrency: "brl",
		Rate: "5.51894", Fee: "0.00", Expires: 200,
	}
	now := time.Unix(100, 0)
	rate, err := parseQuote(data, now)
	require.NoError(t, err)
	require.Equal(t, "5.51894", rate)
	data.Fee = "1.00"
	_, err = parseQuote(data, now)
	require.Error(t, err)
}
