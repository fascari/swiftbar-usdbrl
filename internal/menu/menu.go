package menu

import (
	"cmp"
	"fmt"
	"math"
	"time"

	"github.com/fascari/swiftbar-usdbrl/internal/alert"
	"github.com/fascari/swiftbar-usdbrl/internal/locale"
	"github.com/fascari/swiftbar-usdbrl/internal/quote"
)

const staleAfter = 15 * time.Minute

type (
	View struct {
		Quote    *quote.Quote
		Reason   string
		Warning  string
		LastOK   time.Time
		Now      time.Time
		Location *time.Location
		Language locale.Code
		Plugin   string
		Alerts   []alert.Alert
	}

	renderer struct {
		out *output
		s   locale.Language
		v   View
	}
)

func Render(v View) string {
	r := renderer{
		out: new(output{}),
		s:   locale.For(v.Language),
		v:   v,
	}
	r.body()
	r.footer()
	return r.out.text.String()
}

func (r renderer) body() {
	if r.v.Quote == nil {
		r.empty()
		return
	}
	r.quote(*r.v.Quote)
}

func (r renderer) empty() {
	r.out.line("US$ --.-- ⚠")
	r.out.separator()
	r.out.line(fmt.Sprintf("⚠ %s: %s", r.s.Text("no_quote"), cmp.Or(r.v.Reason, r.s.Text("invalid_cache"))), warnColor)
	r.out.line(r.s.Text("no_cache"))
}

func (r renderer) quote(q quote.Quote) {
	price := r.s.Number(q.Price)
	change := r.s.Number(math.Abs(q.ChangePct))
	arrow, color := r.changeIndicator(q.ChangePct, change)
	bar := fmt.Sprintf("US$ %s %s %s%%", price, arrow, change)
	if r.v.Reason != "" {
		bar += " ⚠"
	}
	r.out.line(bar, color)
	r.out.separator()
	r.out.linef("%s: R$ %s", r.s.Text("current"), price)
	r.out.line(fmt.Sprintf("%s: %s %s%%", r.s.Text("change"), arrow, change), color)
	r.out.linef("%s: R$ %s", r.s.Text("high"), r.s.Number(q.High))
	r.out.linef("%s: R$ %s", r.s.Text("low"), r.s.Number(q.Low))
	r.out.separator()

	age := r.v.Now.Sub(q.Time)
	r.out.linef("%s: %s (%s)", r.s.Text("updated"), r.s.Stamp(q.Time, r.v.Location), r.s.Ago(age))
	r.check(age)
	if r.v.Warning != "" {
		r.out.line("⚠ "+r.v.Warning, warnColor)
	}
	name, href := q.Source.Attribution()
	r.out.line(fmt.Sprintf("%s: %s", r.s.Text("source"), name), "href="+href)
}

func (r renderer) changeIndicator(changePct float64, formatted string) (arrow, color string) {
	if formatted == r.s.Number(0) {
		return "•", ""
	}
	if changePct > 0 {
		return "▲", upColor
	}
	return "▼", downColor
}

func (r renderer) check(age time.Duration) {
	if r.v.Reason != "" {
		r.out.line(fmt.Sprintf("⚠ %s: %s", r.s.Text("stale"), r.v.Reason), warnColor)
		r.out.linef("%s: %s (%s)", r.s.Text("last_ok"), r.s.Stamp(r.v.LastOK, r.v.Location), r.s.Ago(r.v.Now.Sub(r.v.LastOK)))
		return
	}
	r.out.linef("%s %s", r.s.Text("checked"), r.v.LastOK.In(r.v.Location).Format(time.TimeOnly))
	if age > staleAfter {
		silent := fmt.Sprintf(r.s.Text("silent"), r.s.Ago(age))
		r.out.line(fmt.Sprintf("⚠ %s: %s", r.s.Text("stale"), silent), warnColor)
	}
}
