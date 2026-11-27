package provider

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"mime/multipart"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/fascari/swiftbar-usdbrl/internal/payout"
	"github.com/fascari/swiftbar-usdbrl/pkg/boundedio"
)

const (
	HiglobeURL  = "https://higlobe.com/api/public/withdrawals/quote"
	reference   = 1000
	maxResponse = 64 << 10
)

var errQuote = errors.New("invalid Higlobe quote")

type (
	quoteData struct {
		From         string `json:"from_amount"`
		To           string `json:"to_amount"`
		FromCurrency string `json:"from_currency"`
		ToCurrency   string `json:"to_currency"`
		Rate         string `json:"effective_exchange_rate"`
		Fee          string `json:"flat_fee"`
		Expires      int64  `json:"expires_at"`
		Warning      bool   `json:"rate_warning"`
	}

	HiglobeClient struct {
		URL string
		Now func() time.Time
	}
)

func (c HiglobeClient) Source() Source {
	return Source{
		Details: Details{
			ID: "higlobe", Name: "Higlobe", Currency: "USDC", Link: "https://higlobe.com/pt-br/withdraw",
		},
		Fetch: c.Fetch,
	}
}

func (c HiglobeClient) Fetch(ctx context.Context) (string, error) {
	var body bytes.Buffer
	form := multipart.NewWriter(&body)
	_ = form.WriteField("amount", strconv.Itoa(reference))
	_ = form.WriteField("country", "BRAZIL")
	_ = form.Close()
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.URL, &body)
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", form.FormDataContentType())
	req.Header.Set("Accept", "application/json")
	client := http.Client{Timeout: 5 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return "", err
	}
	defer func() { _ = resp.Body.Close() }()
	if resp.StatusCode != http.StatusOK {
		return "", errQuote
	}
	return decodeQuote(resp.Body, c.Now)
}

func decodeQuote(body io.Reader, now func() time.Time) (string, error) {
	var payload struct {
		Data   quoteData       `json:"data"`
		Errors json.RawMessage `json:"errors"`
	}
	data, err := boundedio.ReadAll(body, maxResponse)
	if err != nil {
		return "", errQuote
	}
	if err := json.Unmarshal(data, &payload); err != nil || string(payload.Errors) != "null" {
		return "", errQuote
	}
	return parseQuote(payload.Data, now())
}

func parseQuote(data quoteData, now time.Time) (string, error) {
	if data.FromCurrency != "usd" || data.ToCurrency != "brl" || data.Warning || data.Expires <= now.Unix() {
		return "", errQuote
	}
	if !matchesWhole(data.From, strconv.Itoa(reference)) || !matchesWhole(data.Fee, "0") {
		return "", errQuote
	}
	expected, err := payout.Convert(reference*100, data.Rate)
	if err != nil {
		return "", errQuote
	}
	actual, err := payout.ParseAmount(data.To)
	if err != nil || actual-expected > 1 || expected-actual > 1 {
		return "", errQuote
	}
	return data.Rate, nil
}

func matchesWhole(text, whole string) bool {
	integer, fraction, hasFraction := strings.Cut(text, ".")
	return integer == whole && (!hasFraction || (fraction != "" && strings.Trim(fraction, "0") == ""))
}
