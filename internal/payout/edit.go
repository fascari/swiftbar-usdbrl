package payout

import (
	"errors"
	"strings"
)

var ErrInvalidPayment = errors.New("invalid payment")

type PaymentEdit struct {
	Before    Payment
	Name      string
	Amount    string
	Remove    bool
	RequestID string
}

func (s Service) EditPayment(edit PaymentEdit) (uint64, error) {
	if edit.Remove {
		if edit.Before.ID == 0 {
			return 0, ErrInvalidPayment
		}
		return s.Store.updatePayment(Change{Before: edit.Before, Remove: true})
	}
	name := strings.TrimSpace(edit.Name)
	cents, err := ParseAmount(edit.Amount)
	if err != nil || !ValidPaymentName(name) {
		return 0, ErrInvalidPayment
	}
	return s.Store.updatePayment(Change{
		Before: edit.Before,
		After:  Payment{Name: name, Cents: cents, RequestID: edit.RequestID},
	})
}
