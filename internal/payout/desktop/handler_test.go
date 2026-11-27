package desktop

import (
	"encoding/json"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/require"

	"github.com/fascari/swiftbar-usdbrl/internal/payout"
)

func TestHandler_ShouldPreservePaymentOnVersionMismatchAndConflict(t *testing.T) {
	const providerID = "sample"
	dir := t.TempDir()
	h := Handler{
		Now: func() time.Time { return time.Unix(100, 0) },
		Resolve: func(id string) (Provider, bool) {
			return Provider{
				Currency: "USD",
				Service: payout.Service{
					Store: payout.Store{ConfigDir: dir, CacheDir: dir},
				},
			}, id == providerID
		},
	}
	call := func(input request) response {
		data, err := json.Marshal(input)
		require.NoError(t, err)
		return h.handle(t.Context(), strings.NewReader(string(data)))
	}
	input := request{
		Version: Version + 1, Provider: providerID,
		Action: Add, Name: "Example", Amount: "1000,50",
		RequestID: "retry-key",
	}
	require.Equal(t, VersionMismatch, call(input).Error)
	input.Version = Version
	created := call(input)
	require.Empty(t, created.Error)
	require.Len(t, created.Payments, 1)
	require.Equal(t, created.PaymentID, created.Payments[0].ID)
	require.Equal(t, created, call(input))
	input.Action = Edit
	input.Payment = created.Payments[0]
	input.Amount = "700"
	edited := call(input)
	require.Empty(t, edited.Error)
	require.EqualValues(t, 70000, edited.Payments[0].Cents)
	input.Action = Remove
	rejected := call(input)
	require.Equal(t, Conflict, rejected.Error)
	require.Equal(t, edited.Payments, rejected.Payments)
}
