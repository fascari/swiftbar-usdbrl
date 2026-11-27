package menu

import (
	"context"
	"os"
	"path/filepath"
	"time"

	"github.com/fascari/swiftbar-usdbrl/internal/locale"
	"github.com/fascari/swiftbar-usdbrl/internal/payout"
	"github.com/fascari/swiftbar-usdbrl/internal/payout/provider"
	"github.com/fascari/swiftbar-usdbrl/pkg/atomicfile"
)

const displayFile = "display"

type (
	Plugin struct {
		ConfigDir  string
		CacheDir   string
		PluginPath string
		Language   locale.Code
		Now        func() time.Time
		Providers  []provider.Source
	}
)

func (a Plugin) service(source provider.Source) payout.Service {
	return payout.Service{
		Store: payout.Store{
			ConfigDir: filepath.Join(a.ConfigDir, source.ID),
			CacheDir:  filepath.Join(a.CacheDir, source.ID),
		},
		Now:   a.Now,
		Fetch: source.Fetch,
	}
}

func (a Plugin) setDisplay(display Display) {
	if display == DisplayUSD || a.providerByID(string(display)).ID != "" {
		_ = atomicfile.Write(filepath.Join(a.ConfigDir, displayFile), string(display))
	}
}

func (a Plugin) Views() []ProviderView {
	return a.views(a.selectedSource())
}

func (a Plugin) RefreshViews(ctx context.Context) []ProviderView {
	selected := a.selectedSource()
	if selected.ID != "" {
		a.service(selected).RefreshRateOnTick(ctx)
	}
	return a.views(selected)
}

func (a Plugin) selectedSource() provider.Source {
	raw, _ := os.ReadFile(filepath.Join(a.ConfigDir, displayFile))
	return a.providerByID(string(raw))
}

func (a Plugin) views(selected provider.Source) []ProviderView {
	display := Display(selected.ID)
	if display == "" {
		display = DisplayUSD
	}
	var views []ProviderView
	for _, source := range a.Providers {
		views = append(views, a.view(source, display))
	}
	return views
}

func (a Plugin) providerByID(id string) provider.Source {
	for _, source := range a.Providers {
		if source.ID == id {
			return source
		}
	}
	return provider.Source{}
}

func (a Plugin) view(source provider.Source, display Display) ProviderView {
	store := a.service(source).Store
	cache := store.ReadRate()
	list, _ := store.ReadPayments()
	total, err := payout.EstimateTotal(list.Entries, cache.Rate)
	view := ProviderView{
		Provider: source.Details,
		Display:  display, Rate: cache.Rate, Checked: cache.Checked,
		Attempted: cache.Attempted, Stale: cache.Stale(a.Now()), Failed: cache.Failed,
		Total: total, HasTotal: cache.Rate != "" && len(list.Entries) > 0 && err == nil,
		Payments:  len(list.Entries),
		ChangePct: cache.ChangePercent(),
	}
	return view
}

func (a Plugin) Handle(ctx context.Context, action Action, id string) {
	if action == SetDisplay {
		a.setDisplay(Display(id))
		return
	}
	if action != OpenConverter {
		return
	}
	source := a.providerByID(id)
	if source.ID == "" {
		return
	}
	_ = a.openConverter(ctx, source.ID)
}
