package menu

import (
	"cmp"
	_ "embed"
	"encoding/base64"
	"fmt"
	"math"
	"strconv"
	"time"

	"github.com/fascari/swiftbar-usdbrl/internal/payout/provider"
	"github.com/fascari/swiftbar-usdbrl/pkg/swiftbartext"
)

//go:embed icons/higlobe.png
var higlobeIcon []byte

type ProviderView struct {
	Provider  provider.Details
	Display   Display
	Rate      string
	ChangePct *float64
	Checked   time.Time
	Attempted time.Time
	Stale     bool
	Failed    bool
	Total     int64
	HasTotal  bool
	Payments  int
}

func (v ProviderView) Active() bool {
	return v.Provider.ID != "" && string(v.Display) == v.Provider.ID
}

func (r renderer) conversionBar() (string, string, bool) {
	v := r.selectedProvider()
	if !v.Active() {
		return "", "", false
	}
	text := "R$ —"
	if v.HasTotal {
		text = "≈ R$ " + r.s.Cents(v.Total)
	}
	if v.Rate != "" {
		formattedRate := r.s.Decimal(formatProviderRate(v.Rate)) + "/" + v.Provider.Currency
		if v.Payments == 0 {
			text = "R$ " + formattedRate
		} else {
			text += " · " + formattedRate
		}
	}
	var color string
	if v.ChangePct != nil {
		change := r.s.Number(math.Abs(*v.ChangePct))
		arrow, changeColor := r.changeIndicator(*v.ChangePct, change)
		text += fmt.Sprintf(" %s %s%%", arrow, change)
		color = changeColor
	}
	if v.Stale {
		return text + " ⚠", warnColor, true
	}
	return text, color, true
}

func (r renderer) selectedProvider() ProviderView {
	for _, view := range r.v.Providers {
		if view.Active() {
			return view
		}
	}
	return ProviderView{}
}

func (r renderer) providers() {
	if len(r.v.Providers) == 0 {
		return
	}
	r.displayMenu()
	for _, view := range r.v.Providers {
		r.conversionMenu(view)
	}
}

func (r renderer) conversionMenu(v ProviderView) {
	params := []string(nil)
	if v.Provider.ID == "higlobe" {
		params = append(params, "image="+base64.StdEncoding.EncodeToString(higlobeIcon))
	}
	r.out.line(v.Provider.Name, params...)
	r.conversionAction(OpenConverter, v.Provider.ID, r.s.Text("conversion_open"))
	if v.Provider.Link != "" {
		r.providerItem(r.s.Text("conversion_link"), "href="+v.Provider.Link)
	}
	r.out.separator()
	if v.HasTotal && v.Active() {
		r.providerItem(fmt.Sprintf(r.s.Text("conversion_total"), r.s.Cents(v.Total)))
	}
	r.conversionStatus(v)
}

func (r renderer) conversionStatus(v ProviderView) {
	if v.Rate == "" {
		if v.Failed {
			r.providerItem(r.s.Text("conversion_failed"), warnColor)
			r.failedAttempt(v)
			return
		}
		r.providerItem(r.s.Text("conversion_no_rate"))
		return
	}
	if v.Payments > 0 && !v.HasTotal {
		r.providerItem(fmt.Sprintf(r.s.Text("conversion_invalid_amount"), v.Provider.Currency), warnColor)
	}
	r.providerItem(fmt.Sprintf(r.s.Text("conversion_rate"), r.s.Decimal(formatProviderRate(v.Rate)), v.Provider.Currency))
	location := cmp.Or(r.v.Location, time.Local)
	r.providerItem(fmt.Sprintf(r.s.Text("conversion_checked"), r.s.Stamp(v.Checked, location)))
	if v.Stale {
		r.providerItem(r.s.Text("conversion_stale"), warnColor)
	}
	if v.Failed {
		r.failedAttempt(v)
	}
}

func formatProviderRate(raw string) string {
	rate, err := strconv.ParseFloat(raw, 64)
	if err != nil {
		return raw
	}
	return strconv.FormatFloat(rate, 'f', 4, 64)
}

func (r renderer) failedAttempt(v ProviderView) {
	if !v.Attempted.IsZero() {
		location := cmp.Or(r.v.Location, time.Local)
		r.providerItem(fmt.Sprintf(r.s.Text("conversion_attempted"), r.s.Stamp(v.Attempted, location)))
	}
}

func (r renderer) providerItem(label string, params ...string) {
	r.out.line("--"+label, params...)
}

func (r renderer) conversionAction(action Action, id, label string) {
	params := command(r.v.Plugin, action, id)
	params = append(params, "sfimage=calculator")
	r.providerItem(label, append(params, "terminal=false", "refresh=true")...)
}

func (r renderer) displayMenu() {
	r.out.line(r.s.Text("display"))
	r.displayOption(DisplayUSD, r.s.Text("display_usd"))
	for _, v := range r.v.Providers {
		label := v.Provider.Name + " · " + v.Provider.Currency + "/BRL"
		r.displayOption(Display(v.Provider.ID), label)
	}
}

func (r renderer) displayOption(display Display, label string) {
	params := swiftbartext.Command(r.v.Plugin, string(SetDisplay), string(display))
	active := r.selectedProvider()
	selected := string(display) == active.Provider.ID || (!active.Active() && display == DisplayUSD)
	r.out.line("--"+label, append(params, "terminal=false", "refresh=true", swiftbartext.Checked(selected))...)
}
