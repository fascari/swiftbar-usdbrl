package utf8text

import "unicode/utf8"

// Prefix returns at most limit bytes without splitting a UTF-8 rune.
func Prefix(text string, limit int) string {
	if limit >= len(text) {
		return text
	}
	limit = max(0, limit)
	for limit > 0 && !utf8.RuneStart(text[limit]) {
		limit--
	}
	return text[:limit]
}
