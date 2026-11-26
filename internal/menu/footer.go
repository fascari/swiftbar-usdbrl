package menu

import (
	"github.com/fascari/swiftbar-usdbrl/internal/alert"
	"github.com/fascari/swiftbar-usdbrl/internal/locale"
)

var languages = [...]struct {
	code locale.Code
	name string
}{
	{
		code: locale.English,
		name: "English",
	},
	{
		code: locale.Portuguese,
		name: "Português",
	},
}

func (r renderer) footer() {
	r.out.separator()
	r.out.line(r.s.Text("refresh"), "refresh=true")
	r.alerts()
	r.intervals()
	r.languages()
}

func (r renderer) alerts() {
	r.out.line(r.s.Text("alerts"))
	for _, a := range r.v.Alerts {
		sign := "≤"
		if a.Direction == alert.Above {
			sign = "≥"
		}
		params := command(r.v.Plugin, ActionRemoveAlert, string(a.Direction), a.Target)
		r.out.item(sign+" R$ "+r.s.Number(a.Value), append(params, "terminal=false", "refresh=true")...)
	}
	add := command(r.v.Plugin, ActionAddAlert)
	r.out.item(r.s.Text("add_alert"), append(add, "terminal=false", "refresh=true")...)
	if len(r.v.Alerts) == 0 {
		return
	}
	clearAlerts := command(r.v.Plugin, ActionClearAlerts)
	r.out.item(r.s.Text("clear_alerts"), append(clearAlerts, "terminal=false", "refresh=true")...)
	r.out.item(r.s.Text("alert_hint"), "size=11")
}

func (r renderer) intervals() {
	r.out.line(r.s.Text("interval"))
	current, _ := IntervalOf(r.v.Plugin)
	for _, interval := range intervals {
		params := command(r.v.Plugin, ActionSetInterval, interval)
		r.out.item(intervalLabel(interval), append(params, "terminal=false", checked(interval == current))...)
	}
}

func (r renderer) languages() {
	r.out.line(r.s.Text("language"))
	current := locale.Resolve(r.v.Language)
	for _, language := range languages {
		params := command(r.v.Plugin, ActionSetLanguage, string(language.code))
		r.out.item(language.name, append(params, "terminal=false", "refresh=true", checked(language.code == current))...)
	}
}
