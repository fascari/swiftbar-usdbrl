package alert

import (
	"errors"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"unicode"
)

const (
	Above     Direction = "above"
	Below     Direction = "below"
	maxAlerts           = 10
)

var (
	decimal          = regexp.MustCompile(`^[0-9]+(\.[0-9]+)?$`)
	errInvalidTarget = errors.New("invalid alert target")
)

type (
	Direction string

	Alert struct {
		Direction Direction
		Target    string
		Value     float64
	}
)

// ParseTarget normalizes input such as "R$ 5,80" to "5.8" and rejects targets that round to zero.
func ParseTarget(input string) (string, error) {
	text := strings.Map(func(r rune) rune {
		switch {
		case unicode.IsSpace(r):
			return -1
		case r == ',':
			return '.'
		default:
			return r
		}
	}, input)
	value, err := parseValue(strings.TrimPrefix(text, "R$"))
	if err != nil {
		return "", err
	}
	rounded := strconv.FormatFloat(value, 'f', 2, 64)
	if rounded == "0.00" {
		return "", errInvalidTarget
	}
	return strings.TrimSuffix(strings.TrimRight(rounded, "0"), "."), nil
}

// Parse skips malformed lines and preserves legacy target text for exact removal.
func Parse(content string) []Alert {
	var alerts []Alert
	lines := strings.SplitSeq(content, "\n")
	for line := range lines {
		fields := strings.Fields(line)
		if len(fields) != 2 {
			continue
		}
		direction := Direction(fields[0])
		if direction != Above && direction != Below {
			continue
		}
		value, err := parseValue(fields[1])
		if err != nil {
			continue
		}
		alerts = append(alerts, Alert{
			Direction: direction,
			Target:    fields[1],
			Value:     value,
		})
	}
	return alerts
}

func Lines(alerts []Alert) string {
	var text strings.Builder
	for _, a := range alerts {
		text.WriteString(string(a.Direction))
		text.WriteByte(' ')
		text.WriteString(a.Target)
		text.WriteByte('\n')
	}
	return text.String()
}

// Add expects a normalized target from ParseTarget. An identical alert or a full list is a no-op.
func Add(alerts []Alert, target string, price float64) []Alert {
	updated := slices.Clone(alerts)
	if len(alerts) >= maxAlerts {
		return updated
	}
	value, err := parseValue(target)
	if err != nil {
		return updated
	}
	direction := Below
	if value >= round(price) {
		direction = Above
	}
	item := Alert{
		Direction: direction,
		Target:    target,
		Value:     value,
	}
	if slices.Contains(alerts, item) {
		return updated
	}
	return append(updated, item)
}

// Remove matches the stored target text, so "5.80" and "5.8" are distinct.
func Remove(alerts []Alert, direction Direction, target string) []Alert {
	return slices.DeleteFunc(slices.Clone(alerts), func(a Alert) bool {
		return a.Direction == direction && a.Target == target
	})
}

// Check uses the same two-decimal precision as the menu bar.
func Check(alerts []Alert, price float64) (fired, remaining []Alert) {
	current := round(price)
	for _, a := range alerts {
		target := round(a.Value)
		reachedAbove := a.Direction == Above && current >= target
		reachedBelow := a.Direction == Below && current <= target
		if reachedAbove || reachedBelow {
			fired = append(fired, a)
			continue
		}
		remaining = append(remaining, a)
	}
	return fired, remaining
}

func parseValue(text string) (float64, error) {
	if !decimal.MatchString(text) {
		return 0, errInvalidTarget
	}
	return strconv.ParseFloat(text, 64)
}

func round(value float64) float64 {
	// Parsing the displayed value avoids a second rounding when multiplying by 100.
	rounded, _ := strconv.ParseFloat(strconv.FormatFloat(value, 'f', 2, 64), 64)
	return rounded
}
