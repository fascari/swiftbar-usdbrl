package alert

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestAdd_ShouldLimitActiveAlerts(t *testing.T) {
	alerts := Parse("above 6\nabove 7\nabove 8\nabove 9\nabove 10\nabove 11\nabove 12\nabove 13\nabove 14\nabove 15\n")

	updated := Add(alerts, "16", 5.7351)

	require.Equal(t, alerts, updated)
}

func TestRemove_ShouldMatchStoredTarget(t *testing.T) {
	alerts := Parse("above 5.80\nbelow 5.6\n")

	remaining := Remove(alerts, Above, "5.80")

	require.Equal(t, []Alert{
		{
			Direction: Below,
			Target:    "5.6",
			Value:     5.6,
		},
	}, remaining)
}
