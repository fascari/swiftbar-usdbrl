package quote

import (
	"errors"
	"fmt"
	"regexp"
	"strconv"
	"strings"
	"time"
)

const (
	Yahoo   Source = "yahoo"
	Awesome Source = "awesome"

	currencyUSD currencyCode = "USD"
	currencyBRL currencyCode = "BRL"
)

var (
	decimal         = regexp.MustCompile(`^[0-9]+(\.[0-9]+)?$`)
	signedDecimal   = regexp.MustCompile(`^-?[0-9]+(\.[0-9]+)?$`)
	epoch           = regexp.MustCompile(`^[0-9]{9,11}$`)
	errInvalidQuote = errors.New("invalid quote")
)

type (
	Source string

	currencyCode string

	Quote struct {
		Source    Source
		Price     float64
		ChangePct float64
		High      float64
		Low       float64
		Time      time.Time
	}

	quoteText struct {
		price     feedNumber
		changePct feedNumber
		high      feedNumber
		low       feedNumber
		epoch     feedNumber
	}
)

func isUSDToBRL(from, to currencyCode) bool {
	return from == currencyUSD && to == currencyBRL
}

func (s Source) Attribution() (name, href string) {
	if s == Yahoo {
		return "Yahoo Finance", "https://finance.yahoo.com/quote/USDBRL%3DX/"
	}
	return "AwesomeAPI", "https://docs.awesomeapi.com.br/api-de-moedas"
}

func (q Quote) Line() string {
	return strings.Join([]string{
		string(q.Source),
		strconv.FormatFloat(q.Price, 'f', -1, 64),
		strconv.FormatFloat(q.ChangePct, 'f', -1, 64),
		strconv.FormatFloat(q.High, 'f', -1, 64),
		strconv.FormatFloat(q.Low, 'f', -1, 64),
		fmt.Sprintf("%09d", q.Time.Unix()),
	}, "\t")
}

func ParseLine(line string) (Quote, error) {
	fields := strings.Split(strings.TrimSuffix(line, "\n"), "\t")
	if len(fields) != 6 {
		return Quote{}, errInvalidQuote
	}
	source := Source(fields[0])
	if source != Yahoo && source != Awesome {
		return Quote{}, errInvalidQuote
	}
	return parseText(source, quoteText{
		price:     feedNumber(fields[1]),
		changePct: feedNumber(fields[2]),
		high:      feedNumber(fields[3]),
		low:       feedNumber(fields[4]),
		epoch:     feedNumber(fields[5]),
	})
}

func parseText(source Source, text quoteText) (Quote, error) {
	valid := decimal.MatchString(string(text.price)) &&
		signedDecimal.MatchString(string(text.changePct)) &&
		decimal.MatchString(string(text.high)) &&
		decimal.MatchString(string(text.low)) &&
		epoch.MatchString(string(text.epoch))
	if !valid {
		return Quote{}, errInvalidQuote
	}

	price, priceErr := strconv.ParseFloat(string(text.price), 64)
	change, changeErr := strconv.ParseFloat(string(text.changePct), 64)
	high, highErr := strconv.ParseFloat(string(text.high), 64)
	low, lowErr := strconv.ParseFloat(string(text.low), 64)
	if price <= 0 {
		return Quote{}, errInvalidQuote
	}
	seconds, timeErr := strconv.ParseInt(string(text.epoch), 10, 64)
	if err := errors.Join(priceErr, changeErr, highErr, lowErr, timeErr); err != nil {
		return Quote{}, err
	}
	return Quote{
		Source:    source,
		Price:     price,
		ChangePct: change,
		High:      high,
		Low:       low,
		Time:      time.Unix(seconds, 0).UTC(),
	}, nil
}
