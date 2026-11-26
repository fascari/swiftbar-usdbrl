package menu

import (
	"path/filepath"
	"slices"
	"strings"
)

// SwiftBar reads the refresh interval from the wrapper file name, usdbrl.<interval>.sh.
const (
	wrapperPrefix = "usdbrl."
	wrapperSuffix = ".sh"
)

var intervals = [...]string{"30s", "1m", "5m", "15m", "30m"}

func ValidInterval(value string) bool {
	return slices.Contains(intervals[:], value)
}

func IntervalOf(path string) (string, bool) {
	interval, isWrapper := strings.CutPrefix(filepath.Base(path), wrapperPrefix)
	if !isWrapper {
		return "", false
	}
	return strings.CutSuffix(interval, wrapperSuffix)
}

func WrapperName(interval string) string {
	return wrapperPrefix + interval + wrapperSuffix
}

func intervalLabel(interval string) string {
	value := interval[:len(interval)-1]
	if strings.HasSuffix(interval, "s") {
		return value + " s"
	}
	return value + " min"
}
