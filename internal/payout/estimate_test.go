package payout

import (
	"math"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestConvert_ShouldRoundHalfUp(t *testing.T) {
	amount, err := ParseAmount("250,50")
	require.NoError(t, err)
	cents, err := Convert(amount, "5.51894")
	require.NoError(t, err)
	require.EqualValues(t, 138249, cents)
	cents, err = Convert(1, "5.5")
	require.NoError(t, err)
	require.EqualValues(t, 6, cents)
	_, err = Convert(1<<63-1, "5.5")
	require.Error(t, err)
}

func TestEstimateTotal_ShouldRoundEachPaymentBeforeSumming(t *testing.T) {
	payments := []Payment{
		{Cents: 1},
		{Cents: 1},
	}

	total, err := EstimateTotal(payments, "1.5")

	require.NoError(t, err)
	require.EqualValues(t, 4, total)
}

func TestEstimateTotal_ShouldRejectOverflow(t *testing.T) {
	payments := []Payment{
		{Cents: math.MaxInt64/2 + 1},
		{Cents: math.MaxInt64/2 + 1},
	}

	_, err := EstimateTotal(payments, "1")

	require.ErrorIs(t, err, ErrInvalidPayment)
}
