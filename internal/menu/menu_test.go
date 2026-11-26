package menu

import (
	"flag"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/stretchr/testify/require"

	"github.com/fascari/swiftbar-usdbrl/internal/alert"
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
