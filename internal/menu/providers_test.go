package menu

import (
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/require"

	"github.com/fascari/swiftbar-usdbrl/internal/locale"
	"github.com/fascari/swiftbar-usdbrl/internal/payout/provider"
)

func TestRender_ShouldShowOnlyProviderRateWithoutPayments(t *testing.T) {
	got := Render(View{
		Language: locale.English,
		Providers: []ProviderView{{
			Provider: provider.Details{ID: testHiglobeID, Currency: testCurrencyUSDC},
			Display:  testHiglobeID,
			Rate:     "5.53890",
		}},
	})

	bar, _, _ := strings.Cut(got, "\n")
	require.Equal(t, "R$ 5.5389/USDC", bar)
}

func TestRender_ShouldUseSelectedProvidersRate(t *testing.T) {
	const selectedID = "sample-usdc"
	now := time.Date(2026, 11, 27, 16, 17, 0, 0, time.UTC)
	got := Render(View{
		Location: time.UTC, Language: locale.Portuguese,
		Providers: []ProviderView{
			{
				Provider: provider.Details{ID: "sample-usd", Name: "Example USD", Currency: "USD"},
				Display:  selectedID,
				Rate:     "5.41",
				Checked:  now,
			},
			{
				Provider: provider.Details{
					ID: selectedID, Name: "Example USDC", Currency: testCurrencyUSDC, Link: "https://example.com",
				},
				Display:  selectedID,
				Rate:     "5.51894",
				Checked:  now,
				Total:    827841,
				HasTotal: true,
				Payments: 2,
			},
		},
	})
	require.Contains(t, got, "≈ R$ 8.278,41 · 5,5189/USDC\n")
	require.NotContains(t, got, "Provedores")
	require.Contains(t, got, "\nExample USD\n")
	require.Contains(t, got, "param1=--open-converter param2=sample-usdc")
	require.Contains(t, got, "Taxa efetiva de referência: R$ 5,5189 por USDC")
	require.Contains(t, got, "Cotação consultada em 27/11/2026 16:17:00")
	require.Contains(t, got, "Abrir site")
	require.NotContains(t, got, "param1=--add-payment")
	require.NotContains(t, got, "param1=--manage-payments")
	require.NotContains(t, got, "param1=--refresh-provider")
	require.NotContains(t, got, "param1=--simulate-conversion")
	require.NotContains(t, got, "R$ 5.518,94")
}

func TestRender_ShouldShowFirstFailedAttempt(t *testing.T) {
	attempted := time.Date(2026, 11, 27, 16, 17, 0, 0, time.UTC)
	got := Render(View{
		Location: time.UTC,
		Providers: []ProviderView{
			{
				Provider:  provider.Details{ID: testProviderID},
				Display:   testProviderID,
				Attempted: attempted,
				Stale:     true,
				Failed:    true,
				Payments:  1,
			},
		},
	})
	require.Contains(t, got, "\n--Last attempt failed at 2026-11-27 16:17:00")
}

func TestRender_ShouldKeepStaleRateWarning(t *testing.T) {
	got := Render(View{
		Language: locale.Portuguese,
		Providers: []ProviderView{{
			Provider: provider.Details{ID: testProviderID, Name: "Example", Currency: testCurrencyUSDC},
			Rate:     "5.5",
			Stale:    true,
		}},
	})

	require.Contains(t, got, "Cotação desatualizada")
}
