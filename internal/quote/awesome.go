package quote

import "encoding/json"

type (
	awesomeResponse struct {
		USDBRL awesomeRate `json:"USDBRL"`
	}

	awesomeRate struct {
		From      currencyCode `json:"code"`
		To        currencyCode `json:"codein"`
		Price     feedNumber   `json:"bid"`
		ChangePct feedNumber   `json:"pctChange"`
		High      feedNumber   `json:"high"`
		Low       feedNumber   `json:"low"`
		Time      feedNumber   `json:"timestamp"`
	}
)

func parseAwesome(body []byte) (Quote, error) {
	var reply awesomeResponse
	err := json.Unmarshal(body, &reply)
	if err != nil {
		return Quote{}, err
	}
	q := reply.USDBRL
	if !isUSDToBRL(q.From, q.To) {
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
