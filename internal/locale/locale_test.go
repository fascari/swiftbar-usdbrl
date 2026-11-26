package locale

import (
	"maps"
	"slices"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

func TestCatalogs_ShouldShareKeys(t *testing.T) {
	en, err := english()
	require.NoError(t, err)
	pt, err := portuguese()
	require.NoError(t, err)

	require.NotEmpty(t, en)
	require.Equal(t, slices.Sorted(maps.Keys(en)), slices.Sorted(maps.Keys(pt)))
}

func TestLanguage_ShouldFormatByLanguage(t *testing.T) {
	now := time.Date(2026, 11, 26, 14, 30, 5, 0, time.UTC)
	brazil := time.FixedZone("BRT", -3*60*60)
	tests := []struct {
		name   string
		code   Code
		number string
		stamp  string
		age    string
	}{
		{
			name:   "should format English",
			code:   English,
			number: "5.74",
			stamp:  "2026-11-26 11:30:05",
			age:    "1 h 03 min ago",
		},
		{
			name:   "should format Portuguese",
			code:   Portuguese,
			number: "5,74",
			stamp:  "26/11/2026 11:30:05",
			age:    "há 1 h 03 min",
		},
		{
			name:   "should format an unknown code as English",
			code:   Code("fr"),
			number: "5.74",
			stamp:  "2026-11-26 11:30:05",
			age:    "1 h 03 min ago",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			s := For(tt.code)
			require.Equal(t, tt.number, s.Number(5.735))
			require.Equal(t, tt.stamp, s.Stamp(now, brazil))
			require.Equal(t, tt.age, s.Ago(time.Hour+3*time.Minute))
		})
	}
}
