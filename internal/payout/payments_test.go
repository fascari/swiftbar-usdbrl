package payout

import (
	"context"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

func TestEditPayment_ShouldRejectTotalOutsideSupportedRange(t *testing.T) {
	dir := t.TempDir()
	service := Service{
		Store: Store{ConfigDir: dir, CacheDir: dir},
		Now:   func() time.Time { return time.Unix(100, 0) },
		Fetch: func(context.Context) (string, error) { return "5", nil },
	}
	require.False(t, service.RefreshRate(t.Context()).Failed)
	_, err := service.EditPayment(PaymentEdit{Amount: "20000000000000000"})
	require.ErrorIs(t, err, ErrInvalidPayment)
	list, err := service.Store.ReadPayments()
	require.NoError(t, err)
	require.Equal(t, Payments{}, list)
}

func TestPayments_ShouldRejectEditFromPreviousRevision(t *testing.T) {
	var list Payments
	require.NoError(t, list.apply(Change{After: Payment{Cents: 10000}}))
	previous := list.Entries[0]
	updated := previous
	updated.Name = "Equipe"
	require.NoError(t, list.apply(Change{Before: previous, After: updated}))
	require.ErrorIs(t, list.apply(Change{Before: previous, Remove: true}), ErrPaymentChanged)

	updated.Revision++
	require.Equal(t, []Payment{updated}, list.Entries)
}
