package locale

import (
	"cmp"
	_ "embed"
	"encoding/json"
	"fmt"
	"strconv"
	"strings"
	"sync"
	"time"
)

//go:embed en.json
var englishJSON []byte

//go:embed pt.json
var portugueseJSON []byte

var (
	english = sync.OnceValues(func() (map[string]string, error) {
		return load(englishJSON)
	})
	portuguese = sync.OnceValues(func() (map[string]string, error) {
		return load(portugueseJSON)
	})
)

type Code string

const (
	English    Code = "en"
	Portuguese Code = "pt"
)

type Language struct {
	portuguese bool
}

func Supported(code string) bool {
	return Code(code) == English || Code(code) == Portuguese
}

// Resolve defaults unsupported codes to English.
func Resolve(code Code) Code {
	if code == Portuguese {
		return Portuguese
	}
	return English
}

// For defaults unsupported codes to English.
func For(code Code) Language {
	return Language{portuguese: Resolve(code) == Portuguese}
}

// Text returns the message for key, falling back to English and then to the key itself.
func (l Language) Text(key string) string {
	defaults, _ := english()
	if l.portuguese {
		translated, _ := portuguese()
		return cmp.Or(translated[key], defaults[key], key)
	}
	return cmp.Or(defaults[key], key)
}

func (l Language) Number(value float64) string {
	text := strconv.FormatFloat(value, 'f', 2, 64)
	if l.portuguese {
		return strings.Replace(text, ".", ",", 1)
	}
	return text
}

func (l Language) Stamp(at time.Time, loc *time.Location) string {
	at = at.In(loc)
	if l.portuguese {
		return at.Format("02/01/2006 15:04:05")
	}
	return at.Format(time.DateTime)
}

func (l Language) Ago(age time.Duration) string {
	const day = 24 * time.Hour

	var text string
	switch {
	case age < time.Minute:
		return l.Text("just_now")
	case age < time.Hour:
		text = fmt.Sprintf("%d min", age/time.Minute)
	case age < day:
		text = fmt.Sprintf("%d h %02d min", age/time.Hour, (age%time.Hour)/time.Minute)
	default:
		text = fmt.Sprintf("%d d %d h", age/day, (age%day)/time.Hour)
	}
	return fmt.Sprintf(l.Text("ago"), text)
}

func load(data []byte) (map[string]string, error) {
	var messages map[string]string
	if err := json.Unmarshal(data, &messages); err != nil {
		return nil, err
	}
	return messages, nil
}
