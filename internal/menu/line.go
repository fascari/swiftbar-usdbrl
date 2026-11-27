package menu

import (
	"fmt"
	"strings"

	"github.com/fascari/swiftbar-usdbrl/pkg/swiftbartext"
)

const (
	upColor   = "color=#1a7f37,#3fb950"
	downColor = "color=#cf222e,#ff7b72"
	warnColor = "color=#bc4c00,#ffa657"
)

type output struct {
	text   strings.Builder
	prefix string
}

func (o *output) line(text string, params ...string) {
	o.text.WriteString(o.prefix)
	o.text.WriteString(text)
	var used []string
	for _, param := range params {
		if param != "" {
			used = append(used, param)
		}
	}
	if len(used) > 0 {
		o.text.WriteString(" | ")
		o.text.WriteString(strings.Join(used, " "))
	}
	o.text.WriteByte('\n')
}

func (o *output) item(text string, params ...string) {
	o.line("--"+text, params...)
}

func (o *output) separator() {
	o.line("---")
}

func (o *output) linef(format string, args ...any) {
	o.line(fmt.Sprintf(format, args...))
}

func command(plugin string, action Action, args ...string) []string {
	return swiftbartext.Command(plugin, string(action), args...)
}
