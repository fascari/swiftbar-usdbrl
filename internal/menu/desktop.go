package menu

import (
	"context"
	"io"
	"os"
	"os/exec"
	"path/filepath"

	"github.com/fascari/swiftbar-usdbrl/internal/locale"
	"github.com/fascari/swiftbar-usdbrl/internal/payout/desktop"
	"github.com/fascari/swiftbar-usdbrl/pkg/jsonfile"
)

func (a Plugin) openConverter(ctx context.Context, sourceID string) error {
	app := filepath.Join(a.ConfigDir, "Converter.app")
	if _, err := os.Stat(app); err != nil {
		return err
	}
	session := map[string]string{
		"provider": sourceID, "cache": a.CacheDir, "wrapper": a.PluginPath,
	}
	if err := jsonfile.Write(filepath.Join(a.ConfigDir, "converter-session.json"), session); err != nil {
		return err
	}
	return exec.CommandContext(ctx, "/usr/bin/open", "-a", app, "usdbrl-converter://open").Run()
}

func (a Plugin) Desktop(ctx context.Context, input io.Reader, market string) string {
	handler := desktop.Handler{
		Language: string(locale.Resolve(a.Language)),
		Now:      a.Now,
		Market:   market,
		Resolve: func(id string) (desktop.Provider, bool) {
			source := a.providerByID(id)
			if source.ID == "" {
				return desktop.Provider{}, false
			}
			return desktop.Provider{
				Name: source.Name, Currency: source.Currency, Service: a.service(source),
			}, true
		},
	}
	return handler.Run(ctx, input)
}
