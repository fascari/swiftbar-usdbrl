package menu

import (
	"flag"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/stretchr/testify/require"

	"github.com/fascari/swiftbar-usdbrl/internal/alert"
	"github.com/fascari/swiftbar-usdbrl/internal/locale"
	"github.com/fascari/swiftbar-usdbrl/internal/payout/provider"
	"github.com/fascari/swiftbar-usdbrl/internal/quote"
)

var update = flag.Bool("update", false, "rewrite the golden files in testdata")

func TestRender_ShouldShowSourceSilence(t *testing.T) {
	now := time.Date(2026, 11, 26, 15, 0, 0, 0, time.UTC)
	got := Render(View{
		Quote: new(quote.Quote{
			Source: quote.Yahoo,
			Price:  5.735,
			High:   5.824,
			Low:    5.615,
			Time:   now.Add(-901 * time.Second),
		}),
		LastOK:   now.Add(-30 * time.Second),
		Now:      now,
		Location: time.UTC,
		Plugin:   "/tmp/SwiftBar Plugins/usdbrl.5m.sh",
		Alerts: []alert.Alert{
			{
				Direction: alert.Above,
				Target:    "5.80",
				Value:     5.8,
			},
			{
				Direction: alert.Below,
				Target:    "5.6",
				Value:     5.6,
			},
		},
	})

	requireGolden(t, "silence.txt", got)
}

func TestRender_ShouldKeepHiglobeSubmenu(t *testing.T) {
	now := time.Date(2026, 11, 27, 16, 17, 0, 0, time.UTC)
	got := Render(View{
		Language: locale.Portuguese,
		Plugin:   "/tmp/usdbrl.5m.sh",
		Providers: []ProviderView{
			{
				Provider: provider.Details{
					ID:       testHiglobeID,
					Name:     "Higlobe",
					Currency: testCurrencyUSDC,
					Link:     "https://higlobe.com",
				},
				Display: testHiglobeID,
				Rate:    "5.51894",
				Checked: now,
				Total:   827841, HasTotal: true, Payments: 2,
			},
		},
	})

	require.Contains(t, got, "≈ R$ 8.278,41 · 5,5189/USDC\n")
	require.Contains(t, got, "\nCotação de mercado · USD/BRL | sfimage=chart.line.uptrend.xyaxis\n--⚠ Sem cotação disponível:")
	require.Contains(t, got, "\nExibir na barra\n--Cotação USD/BRL")
	require.Contains(t, got, "--Higlobe · USDC/BRL")
	require.NotContains(t, got, "Provedores")
	require.Contains(t, got, "\nHiglobe | image=")
	require.Contains(t, got, "--Abrir conversor…")
	require.Contains(t, got, "--Abrir site | href=https://higlobe.com\n")
	require.Contains(t, got, "---\n--Total mensal estimado: R$ 8.278,41\n")
	require.Contains(t, got, "param1=--open-converter param2=higlobe")
	require.Contains(t, got, "param1=--open-converter param2=higlobe sfimage=calculator")
	require.NotContains(t, got, "param1=--add-payment")
	require.NotContains(t, got, "param1=--manage-payments")
	require.NotContains(t, got, "param1=--refresh-provider")
	require.NotContains(t, got, "param1=--simulate-conversion")
	require.NotContains(t, got, "1.000,00")
}

func TestRender_ShouldGroupUSDMarketDetailsInHiglobeMode(t *testing.T) {
	now := time.Date(2026, 11, 27, 16, 17, 0, 0, time.UTC)
	got := Render(View{
		Quote: new(quote.Quote{
			Source:    quote.Yahoo,
			Price:     5.55,
			High:      5.65,
			Low:       5.45,
			ChangePct: -1.65,
			Time:      now,
		}),
		LastOK:   now,
		Now:      now,
		Location: time.UTC,
		Providers: []ProviderView{{
			Provider: provider.Details{ID: testHiglobeID, Currency: testCurrencyUSDC},
			Display:  testHiglobeID,
			Rate:     "5.6",
		}},
	})

	require.Contains(t, got, "\nMarket quote · USD/BRL | sfimage=chart.line.uptrend.xyaxis\n")
	require.Contains(t, got, "Market quote · USD/BRL | sfimage=chart.line.uptrend.xyaxis")
	require.Contains(t, got, "\n--Daily change: ▼ 1.65%")
	require.Contains(t, got, "\n--Day high: R$ 5.65\n--Day low: R$ 5.45\n-----\n")
	require.Contains(t, got, "\n--Source: Yahoo Finance |")
	require.Contains(t, got, "sfimage=bell")
	require.NotContains(t, got, "\nAlerts\n")
	require.Contains(t, got, "\n---\nRefresh now | sfimage=arrow.clockwise refresh=true")
	require.Contains(t, got, "\nRefresh interval\n")
}

func requireGolden(t *testing.T, name, got string) {
	t.Helper()
	path := filepath.Join("testdata", name)
	if *update {
		require.NoError(t, os.WriteFile(path, []byte(got), 0o600))
	}
	want, err := os.ReadFile(path)
	require.NoError(t, err)
	require.Equal(t, string(want), got)
}
