package desktop

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"time"

	"github.com/fascari/swiftbar-usdbrl/internal/payout"
	"github.com/fascari/swiftbar-usdbrl/pkg/boundedio"
)

const (
	Flag       = "--converter-json"
	Version    = 1
	maxRequest = 4096

	Read    Action = "read"
	Refresh Action = "refresh"
	Add     Action = "add"
	Edit    Action = "edit"
	Remove  Action = "remove"

	Invalid          Code = "invalid"
	VersionMismatch  Code = "version"
	UnknownProvider  Code = "provider"
	RateUnavailable  Code = "rate"
	Conflict         Code = "conflict"
	StateUnavailable Code = "state"
)

type (
	Action string
	Code   string

	Handler struct {
		Language string
		Market   string
		Now      func() time.Time
		Resolve  func(id string) (Provider, bool)
	}
	Provider struct {
		Name     string
		Currency string
		Service  payout.Service
	}
	request struct {
		Version   int            `json:"version"`
		Provider  string         `json:"provider"`
		Action    Action         `json:"action"`
		Payment   payout.Payment `json:"payment"`
		Name      string         `json:"name"`
		Amount    string         `json:"amount"`
		RequestID string         `json:"request_id"`
	}
	response struct {
		Version   int              `json:"version"`
		Error     Code             `json:"error,omitempty"`
		Name      string           `json:"name"`
		Currency  string           `json:"currency"`
		Language  string           `json:"language"`
		Rate      string           `json:"rate"`
		Market    string           `json:"market"`
		Checked   time.Time        `json:"checked"`
		Stale     bool             `json:"stale"`
		Payments  []payout.Payment `json:"payments"`
		PaymentID uint64           `json:"payment_id,omitempty"`
	}
)

func (h Handler) Run(ctx context.Context, input io.Reader) string {
	reply := h.handle(ctx, input)
	data, err := json.Marshal(reply)
	if err != nil {
		return "{\"version\":1,\"error\":\"state\"}\n"
	}
	return string(data) + "\n"
}

func (h Handler) handle(ctx context.Context, input io.Reader) response {
	var req request
	data, err := boundedio.ReadAll(input, maxRequest)
	if err != nil || json.Unmarshal(data, &req) != nil {
		return response{Version: Version, Error: Invalid}
	}
	if req.Version != Version {
		return response{Version: Version, Error: VersionMismatch}
	}
	source, ok := h.Resolve(req.Provider)
	if !ok {
		return response{Version: Version, Error: UnknownProvider}
	}
	id, result := apply(ctx, source.Service, req)
	reply := h.snapshot(source, result)
	reply.PaymentID = id
	return reply
}

func apply(ctx context.Context, service payout.Service, req request) (uint64, Code) {
	switch req.Action {
	case Read:
		return 0, ""
	case Refresh:
		cache := service.RefreshRate(ctx)
		if cache.Failed || cache.Rate == "" {
			return 0, RateUnavailable
		}
		return 0, ""
	case Add, Edit, Remove:
		return applyPayment(service, req)
	default:
		return 0, Invalid
	}
}

func applyPayment(service payout.Service, req request) (uint64, Code) {
	if (req.Action == Add) != (req.Payment.ID == 0) {
		return 0, Invalid
	}
	id, err := service.EditPayment(payout.PaymentEdit{
		Before: req.Payment, Name: req.Name, Amount: req.Amount, Remove: req.Action == Remove,
		RequestID: req.RequestID,
	})
	switch {
	case err == nil:
		return id, ""
	case errors.Is(err, payout.ErrInvalidPayment):
		return 0, Invalid
	case errors.Is(err, payout.ErrPaymentChanged):
		return 0, Conflict
	default:
		return 0, StateUnavailable
	}
}

func (h Handler) snapshot(source Provider, result Code) response {
	cache := source.Service.Store.ReadRate()
	reply := response{
		Version: Version, Error: result, Name: source.Name, Currency: source.Currency,
		Language: h.Language, Market: h.Market, Rate: cache.Rate, Checked: cache.Checked,
		Stale: cache.Stale(h.Now()),
	}
	list, err := source.Service.Store.ReadPayments()
	if err != nil {
		if reply.Error == "" {
			reply.Error = StateUnavailable
		}
		return reply
	}
	reply.Payments = list.Entries
	return reply
}
