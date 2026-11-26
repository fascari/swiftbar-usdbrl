package quote

import "encoding/json"

type awesomeResponse struct {
	USDBRL struct {
		From      string     `json:"code"`
		To        string     `json:"codein"`
		Price     feedNumber `json:"bid"`
		ChangePct feedNumber `json:"pctChange"`
		High      feedNumber `json:"high"`
		Low       feedNumber `json:"low"`
		Time      feedNumber `json:"timestamp"`
	} `json:"USDBRL"`
}

func parseAwesome(body []byte) (Quote, error) {
	var reply awesomeResponse
	err := json.Unmarshal(body, &reply)
	if err != nil {
		return Quote{}, err
	}
	q := reply.USDBRL
	isDollarReal := q.From == "USD" && q.To == "BRL"
	if !isDollarReal {
		return Quote{}, errInvalidQuote
	}
	return parseText(Awesome, quoteText{
		price:     q.Price,
		changePct: q.ChangePct,
		high:      q.High,
		low:       q.Low,
		epoch:     q.Time,
	})
}
