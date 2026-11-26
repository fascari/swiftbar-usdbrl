package quote

import (
	"bytes"
	_ "embed"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

//go:embed testdata/awesome.json
var awesomeJSON []byte

func TestParseAwesome_ShouldReadQuote(t *testing.T) {
	got, err := parseAwesome(awesomeJSON)
	require.NoError(t, err)
	require.Equal(t, Quote{
		Source:    Awesome,
		Price:     5.73,
		ChangePct: -1.61,
		High:      5.83,
		Low:       5.71,
		Time:      time.Unix(1795704700, 0).UTC(),
	}, got)
}

func TestParseAwesome_ShouldRejectWrongPair(t *testing.T) {
	body := bytes.ReplaceAll(awesomeJSON, []byte(`"USD"`), []byte(`"EUR"`))
	_, err := parseAwesome(body)
	require.Error(t, err)
}
