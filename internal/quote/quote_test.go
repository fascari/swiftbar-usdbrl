package quote

import (
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

const legacyLine = "yahoo\t5.726600\t-1.621700\t5.825400\t5.708400\t1795704835"

func TestParseLine_ShouldReadLegacyCache(t *testing.T) {
	q, err := ParseLine(legacyLine + "\n")
	require.NoError(t, err)
	require.Equal(t, Quote{
		Source:    Yahoo,
		Price:     5.7266,
		ChangePct: -1.6217,
		High:      5.8254,
		Low:       5.7084,
		Time:      time.Unix(1795704835, 0).UTC(),
	}, q)
}

func TestParseLine_ShouldRejectInvalidPrice(t *testing.T) {
	tests := []struct {
		name  string
		price string
	}{
		{
			name:  "should reject a zero price",
			price: "0",
		},
		{
			name:  "should reject an exponent",
			price: "1e3",
		},
		{
			name:  "should reject a price out of float range",
			price: strings.Repeat("9", 310),
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := ParseLine(strings.Replace(legacyLine, "5.726600", tt.price, 1))
			require.Error(t, err)
		})
	}
}
