package payout

import (
	"errors"
	"math"
	"regexp"
	"strings"

	"github.com/fascari/swiftbar-usdbrl/pkg/decimal"
)

var (
	rateFormat   = regexp.MustCompile(`^[0-9]{1,18}(\.[0-9]{1,12})?$`)
	amountFormat = regexp.MustCompile(`^[0-9]{1,18}([.,][0-9]{1,2})?$`)
	errAmount    = errors.New("invalid amount")
)

func ParseAmount(text string) (int64, error) {
	text = strings.TrimSpace(text)
	if !amountFormat.MatchString(text) {
		return 0, errAmount
	}
	cents, err := Convert(100, strings.Replace(text, ",", ".", 1))
	if err != nil || cents == 0 {
		return 0, errAmount
	}
	return cents, nil
}

func Convert(cents int64, rate string) (int64, error) {
	if cents <= 0 || !rateFormat.MatchString(rate) || strings.Trim(rate, "0.") == "" {
		return 0, errAmount
	}
	return decimal.Scale(cents, rate)
}

// EstimateTotal converts each payment independently before summing the results.
// It returns ErrInvalidPayment if a payment cannot be converted or the total overflows.
func EstimateTotal(payments []Payment, rate string) (int64, error) {
	var total int64
	for _, payment := range payments {
		converted, err := Convert(payment.Cents, rate)
		if err != nil || converted > math.MaxInt64-total {
			return 0, ErrInvalidPayment
		}
		total += converted
	}
	return total, nil
}
