package menu

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/require"

	"github.com/fascari/swiftbar-usdbrl/internal/locale"
	"github.com/fascari/swiftbar-usdbrl/internal/payout"
	"github.com/fascari/swiftbar-usdbrl/internal/payout/provider"
)

const (
	testHiglobeID    = "higlobe"
	testCurrencyUSDC = "USDC"
	testProviderID   = "sample"
)

func TestPlugin_ShouldCompareProviderRateWithLastSuccessfulCheck(t *testing.T) {
	var rate string
	source := provider.Source{
		Details: provider.Details{ID: testHiglobeID, Currency: testCurrencyUSDC},
		Fetch: func(context.Context) (string, error) {
			if rate == "" {
				return "", errors.New("offline")
			}
			return rate, nil
		},
	}
	plugin := testPlugin(t)
	plugin.Providers = []provider.Source{source}
	plugin.Handle(t.Context(), SetDisplay, testHiglobeID)
	service := plugin.service(source)

	for _, step := range []struct {
		rate       string
		wantPrefix string
	}{
		{rate: "5", wantPrefix: "R$ 5.0000/USDC"},
		{rate: "5.5", wantPrefix: "R$ 5.5000/USDC ▲ 10.00%"},
		{rate: "", wantPrefix: "R$ 5.5000/USDC ▲ 10.00% ⚠"},
		{rate: "4.95", wantPrefix: "R$ 4.9500/USDC ▼ 10.00%"},
		{rate: "4.95", wantPrefix: "R$ 4.9500/USDC • 0.00%"},
	} {
		rate = step.rate
		service.RefreshRate(t.Context())
		rendered := Render(View{Language: locale.English, Providers: plugin.Views()})
		bar, _, _ := strings.Cut(rendered, "\n")
		label, _, _ := strings.Cut(bar, " | ")
		require.Equal(t, step.wantPrefix, label)
	}
}

func TestPlugin_ShouldPersistDisplayPreference(t *testing.T) {
	r := testPlugin(t)
	r.Providers = []provider.Source{{
		Details: provider.Details{ID: testHiglobeID, Currency: testCurrencyUSDC},
	}}
	r.Handle(t.Context(), SetDisplay, testHiglobeID)

	require.Equal(t, Display(testHiglobeID), r.Views()[0].Display)
	require.True(t, r.Views()[0].Active())
}

func TestPlugin_ShouldDefaultDisplayToUSD(t *testing.T) {
	r := testPlugin(t)
	r.Providers = []provider.Source{{
		Details: provider.Details{ID: testHiglobeID, Currency: testCurrencyUSDC},
	}}

	require.Equal(t, DisplayUSD, r.Views()[0].Display)
}

func TestPlugin_ShouldEstimateMonthlyTotalFromSavedPayments(t *testing.T) {
	source := provider.Source{
		Details: provider.Details{ID: testHiglobeID, Currency: testCurrencyUSDC},
		Fetch:   func(context.Context) (string, error) { return "1.5", nil },
	}
	r := testPlugin(t)
	r.Providers = []provider.Source{source}
	service := r.service(source)
	require.False(t, service.RefreshRate(t.Context()).Failed)
	for range 2 {
		_, err := service.EditPayment(payout.PaymentEdit{Amount: "0.01"})
		require.NoError(t, err)
	}

	view := r.Views()[0]

	require.True(t, view.HasTotal)
	require.EqualValues(t, 4, view.Total)
	require.Equal(t, 2, view.Payments)
}

func testPlugin(t *testing.T) Plugin {
	t.Helper()
	return Plugin{
		ConfigDir: t.TempDir(),
		CacheDir:  t.TempDir(),
		Now:       func() time.Time { return time.Unix(100, 0) },
	}
}
