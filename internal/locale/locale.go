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

	"github.com/fascari/swiftbar-usdbrl/pkg/decimaltext"
)

const (
	English    Code = "en"
	Portuguese Code = "pt"
)

var (
	//go:embed en.json
	englishJSON []byte

	//go:embed pt.json
	portugueseJSON []byte

	english = sync.OnceValues(func() (map[string]string, error) {
		return load(englishJSON)
	})
	portuguese = sync.OnceValues(func() (map[string]string, error) {
		return load(portugueseJSON)
	})
)

type (
	Code string

	Language struct {
		portuguese bool
	}
)

func Supported(code string) bool {
	return Code(code) == English || Code(code) == Portuguese
}

func Resolve(code Code) Code {
	if code == Portuguese {
		return Portuguese
	}
	return English
}

func For(code Code) Language {
	return Language{portuguese: Resolve(code) == Portuguese}
}

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

func (l Language) Decimal(value string) string {
	if l.portuguese {
		return strings.Replace(value, ".", ",", 1)
	}
	return value
}

func (l Language) Cents(cents int64) string {
	if l.portuguese {
		return decimaltext.Cents(cents, ",", ".")
	}
	return decimaltext.Cents(cents, ".", ",")
}

func (l Language) Stamp(at time.Time, loc *time.Location) string {
	at = at.In(loc)
	if l.portuguese {
		return at.Format("02/01/2006 15:04:05")
	}
	return at.Format(time.DateTime)
}

func (l Language) Ago(age time.Duration) string {
	if age < time.Minute {
		return l.Text("just_now")
	}
	return fmt.Sprintf(l.Text("ago"), elapsed(age))
}

func elapsed(age time.Duration) string {
	const day = 24 * time.Hour
	if age < time.Hour {
		return fmt.Sprintf("%d min", age/time.Minute)
	}
	if age < day {
		return fmt.Sprintf("%d h %02d min", age/time.Hour, (age%time.Hour)/time.Minute)
	}
	return fmt.Sprintf("%d d %d h", age/day, (age%day)/time.Hour)
}

func load(data []byte) (map[string]string, error) {
	var messages map[string]string
	if err := json.Unmarshal(data, &messages); err != nil {
		return nil, err
	}
	return messages, nil
}
