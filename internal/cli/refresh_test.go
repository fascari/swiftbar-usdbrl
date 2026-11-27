package cli

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"

	"github.com/fascari/swiftbar-usdbrl/internal/alert"
	"github.com/fascari/swiftbar-usdbrl/internal/cli/mocks"
	"github.com/fascari/swiftbar-usdbrl/internal/menu"
	"github.com/fascari/swiftbar-usdbrl/internal/payout/provider"
	"github.com/fascari/swiftbar-usdbrl/internal/quote"
)

const (
	yahooURL   = "https://query1.finance.yahoo.com"
	awesomeURL = "https://economia.awesomeapi.com.br"
)

func TestRefresh_ShouldFetchSelectedProviderOnEachInterval(t *testing.T) {
	cfg := config(t)
	now := cfg.Now()
	cfg.Now = func() time.Time { return now }
	sources := mocks.NewSources(t)
	sources.EXPECT().Fetch(mock.Anything, quote.Yahoo, yahooURL).
		Return(rate(quote.Yahoo, now), nil).Times(4)
	const providerID = "higlobe"
	var fetched int
	source := provider.Source{
		Details: provider.Details{ID: providerID, Currency: "USDC"},
		Fetch: func(context.Context) (string, error) {
			fetched++
			if fetched == 1 {
				return "5", nil
			}
			return "5.5", nil
		},
	}
	runner := New(cfg, Dependencies{Sources: sources, providers: []provider.Source{source}})
	runner.Run(t.Context(), nil)
	require.Zero(t, fetched)
	runner.Run(t.Context(), []string{string(menu.SetDisplay), providerID})

	require.Contains(t, runner.Run(t.Context(), nil), "R$ 5.0000/USDC\n")
	runner.Run(t.Context(), nil)
	require.Equal(t, 1, fetched)
	now = now.Add(time.Minute)
	require.Contains(t, runner.Run(t.Context(), nil), "R$ 5.5000/USDC ▲ 10.00%")
	require.Equal(t, 2, fetched)
}

func TestRefresh_ShouldFallBackToAwesomeAPI(t *testing.T) {
	cfg := config(t)
	now := cfg.Now()
	sources := mocks.NewSources(t)
	sources.EXPECT().Fetch(mock.Anything, quote.Yahoo, yahooURL).
		Return(quote.Quote{}, quote.FetchError{Kind: quote.NoConnection}).Once()
	sources.EXPECT().Fetch(mock.Anything, quote.Awesome, awesomeURL).
		Return(rate(quote.Awesome, now), nil).Once()
	runner := New(cfg, Dependencies{Sources: sources})

	view, fired := runner.refreshView(t.Context())

	require.Equal(t, menu.View{
		Quote:    new(rate(quote.Awesome, now)),
		Warning:  "Yahoo Finance unavailable (no connection or timeout), using AwesomeAPI",
		LastOK:   now,
		Now:      now,
		Location: time.UTC,
		Plugin:   cfg.PluginPath,
	}, view)
	require.Empty(t, fired)
	require.Equal(t, "no connection or timeout\n", readState(t, runner.paths.pause))
}

func TestRefresh_ShouldSkipPausedYahoo(t *testing.T) {
	cfg := config(t)
	now := cfg.Now()
	runner := New(cfg, Dependencies{})
	writeState(t, runner.paths.pause, "no connection or timeout\n")
	pausedAt := now.Add(-time.Minute)
	require.NoError(t, os.Chtimes(runner.paths.pause, pausedAt, pausedAt))
	sources := mocks.NewSources(t)
	sources.EXPECT().Fetch(mock.Anything, quote.Awesome, awesomeURL).
		Return(rate(quote.Awesome, now), nil).Once()
	runner.dep.Sources = sources

	view, _ := runner.refreshView(t.Context())

	require.Equal(t, menu.View{
		Quote:    new(rate(quote.Awesome, now)),
		Warning:  "Yahoo Finance paused after a recent failure (no connection or timeout), using AwesomeAPI",
		LastOK:   now,
		Now:      now,
		Location: time.UTC,
		Plugin:   cfg.PluginPath,
	}, view)
}

func TestRefresh_ShouldKeepNewerCache(t *testing.T) {
	cfg := config(t)
	now := cfg.Now()
	runner := New(cfg, Dependencies{})
	newer := rate(quote.Yahoo, now)
	writeState(t, runner.paths.cache, newer.Line()+"\n")
	lastCheck := now.Add(-time.Hour)
	require.NoError(t, os.Chtimes(runner.paths.cache, lastCheck, lastCheck))
	older := rate(quote.Yahoo, now.Add(-time.Minute))
	older.Price = 5.63
	checkedAt := now.Add(3 * time.Second)
	sources := mocks.NewSources(t)
	sources.EXPECT().Fetch(mock.Anything, quote.Yahoo, yahooURL).
		Run(func(_ context.Context, _ quote.Source, _ string) {
			now = checkedAt
		}).Return(older, nil).Once()
	runner.dep.Sources = sources
	runner.cfg.Now = func() time.Time {
		return now
	}

	view, _ := runner.refreshView(t.Context())

	require.Equal(t, menu.View{
		Quote:    new(newer),
		LastOK:   checkedAt,
		Now:      checkedAt,
		Location: time.UTC,
		Plugin:   cfg.PluginPath,
	}, view)
	require.Equal(t, newer.Line()+"\n", readState(t, runner.paths.cache))
	info, err := os.Stat(runner.paths.cache)
	require.NoError(t, err)
	require.True(t, checkedAt.Equal(info.ModTime()))
}

func TestRefresh_ShouldFireReachedAlerts(t *testing.T) {
	cfg := config(t)
	now := cfg.Now()
	runner := New(cfg, Dependencies{})
	writeState(t, runner.paths.alerts, "above 5.74\nbelow 5.73\nbroken\n")
	sources := mocks.NewSources(t)
	sources.EXPECT().Fetch(mock.Anything, quote.Yahoo, yahooURL).
		Return(rate(quote.Yahoo, now), nil).Once()
	runner.dep.Sources = sources

	view, fired := runner.refreshView(t.Context())

	require.Equal(t, []alert.Alert{
		{
			Direction: alert.Above,
			Target:    "5.74",
			Value:     5.74,
		},
	}, fired)
	require.Equal(t, menu.View{
		Quote:    new(rate(quote.Yahoo, now)),
		LastOK:   now,
		Now:      now,
		Location: time.UTC,
		Plugin:   cfg.PluginPath,
		Alerts: []alert.Alert{
			{
				Direction: alert.Below,
				Target:    "5.73",
				Value:     5.73,
			},
		},
	}, view)
	require.Equal(t, "below 5.73\n", readState(t, runner.paths.alerts))
}

func TestRefresh_ShouldNotifyReachedAlerts(t *testing.T) {
	cfg := config(t)
	runner := New(cfg, Dependencies{})
	writeState(t, runner.paths.alerts, "above 5.7\n")
	sources := mocks.NewSources(t)
	sources.EXPECT().Fetch(mock.Anything, quote.Yahoo, yahooURL).
		Return(rate(quote.Yahoo, cfg.Now()), nil).Once()
	notifier := mocks.NewNotifier(t)
	notifier.EXPECT().Notify(mock.Anything, "USD/BRL reached R$ 5.70 (now R$ 5.74)").Return(nil).Once()
	runner.dep = Dependencies{
		Sources:  sources,
		Notifier: notifier,
	}

	runner.Run(t.Context(), nil)
}

func config(t *testing.T) Config {
	t.Helper()
	dir := t.TempDir()
	return Config{
		CacheDir:   filepath.Join(dir, "cache"),
		ConfigDir:  filepath.Join(dir, "config"),
		PluginPath: filepath.Join(dir, "SwiftBar Plugins", "usdbrl.1m.sh"),
		YahooURL:   yahooURL,
		AwesomeURL: awesomeURL,
		Now: func() time.Time {
			return time.Date(2026, 11, 26, 15, 0, 0, 0, time.UTC)
		},
		Location: time.UTC,
	}
}

func writeState(t *testing.T, path, content string) {
	t.Helper()
	require.NoError(t, os.MkdirAll(filepath.Dir(path), 0o700))
	require.NoError(t, os.WriteFile(path, []byte(content), 0o600))
}

func readState(t *testing.T, path string) string {
	t.Helper()
	content, err := os.ReadFile(path)
	require.NoError(t, err)
	return string(content)
}

func rate(source quote.Source, at time.Time) quote.Quote {
	return quote.Quote{
		Source:    source,
		Price:     5.7351,
		ChangePct: -1.62,
		High:      5.83,
		Low:       5.61,
		Time:      at,
	}
}
