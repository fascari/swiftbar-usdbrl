package quote

import (
	"encoding/json"
	"strconv"
	"strings"
)

type (
	feedNumber string

	yahooResponse struct {
		Chart yahooChart `json:"chart"`
	}

	yahooChart struct {
		Result []yahooResult `json:"result"`
	}

	yahooResult struct {
		Meta yahooMeta `json:"meta"`
	}

	yahooMeta struct {
		Symbol    string       `json:"symbol"`
		Currency  currencyCode `json:"currency"`
		Price     feedNumber   `json:"regularMarketPrice"`
		ChangePct feedNumber   `json:"regularMarketChangePercent"`
		High      feedNumber   `json:"regularMarketDayHigh"`
		Low       feedNumber   `json:"regularMarketDayLow"`
		Time      feedNumber   `json:"regularMarketTime"`
	}
)

func parseYahoo(body []byte) (Quote, error) {
	var reply yahooResponse
	err := json.Unmarshal(body, &reply)
	if err != nil {
		return Quote{}, err
	}
	if len(reply.Chart.Result) == 0 {
		return Quote{}, errInvalidQuote
	}
	meta := reply.Chart.Result[0].Meta
	isDollarReal := (meta.Symbol == "USDBRL=X" || meta.Symbol == "BRL=X") && meta.Currency == currencyBRL
	if !isDollarReal {
		return Quote{}, errInvalidQuote
	}
	return parseText(Yahoo, quoteText{
		price:     meta.Price,
		changePct: meta.ChangePct,
		high:      meta.High,
		low:       meta.Low,
		epoch:     meta.Time,
	})
}

// UnmarshalJSON matches plutil's six-place formatting for real JSON numbers.
// Quoted numbers stay unchanged so the cache validator sees the original text.
func (n *feedNumber) UnmarshalJSON(raw []byte) error {
	if raw[0] == '"' {
		return json.Unmarshal(raw, (*string)(n))
	}
	var text json.Number
	if err := json.Unmarshal(raw, &text); err != nil {
		return err
	}
	value := string(text)
	if !strings.ContainsAny(value, ".eE") {
		*n = feedNumber(value)
		return nil
	}
	number, err := text.Float64()
	if err != nil {
		return err
	}
	*n = feedNumber(strconv.FormatFloat(number, 'f', 6, 64))
	return nil
}
