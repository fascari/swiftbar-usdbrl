package quote

import (
	"bytes"
	_ "embed"
	"testing"

	"github.com/stretchr/testify/require"
)

//go:embed testdata/yahoo.json
var yahooJSON []byte

//go:embed testdata/yahooprecision.json
var yahooPrecisionJSON []byte

func TestParseYahoo_ShouldUseLegacyNumericPrecision(t *testing.T) {
	got, err := parseYahoo(yahooPrecisionJSON)
	require.NoError(t, err)
	require.Equal(t, "yahoo\t5.735\t0.000349\t5.8254\t5.7084\t1795704835", got.Line())
}

func TestParseYahoo_ShouldRejectInvalidResponses(t *testing.T) {
	tests := []struct {
		name string
		body []byte
	}{
		{
			name: "wrong symbol",
			body: bytes.ReplaceAll(yahooJSON, []byte(`"USDBRL=X"`), []byte(`"EURBRL=X"`)),
		},
		{
			name: "missing high",
			body: bytes.ReplaceAll(yahooJSON, []byte(`"regularMarketDayHigh"`), []byte(`"unused"`)),
		},
		{
			name: "exponent encoded as text",
			body: bytes.ReplaceAll(yahooJSON, []byte(`5.726600`), []byte(`"1e3"`)),
		},
		{
			name: "timestamp encoded as real number",
			body: bytes.ReplaceAll(yahooJSON, []byte(`1795704835`), []byte(`1.795704835e9`)),
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := parseYahoo(tt.body)
			require.Error(t, err)
		})
	}
}
