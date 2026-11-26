package main

import (
	"cmp"
	"context"
	"fmt"
	"os"
	"path/filepath"
	"time"

	"github.com/fascari/swiftbar-usdbrl/internal/cli"
	"github.com/fascari/swiftbar-usdbrl/internal/locale"
	"github.com/fascari/swiftbar-usdbrl/internal/menu"
	"github.com/fascari/swiftbar-usdbrl/internal/osascript"
	"github.com/fascari/swiftbar-usdbrl/internal/quote"
)

var version = "dev"

func main() {
	args := os.Args[1:]
	pluginPath := cmp.Or(os.Getenv("USDBRL_PLUGIN_PATH"), os.Getenv("SWIFTBAR_PLUGIN_PATH"), os.Args[0])
	cacheDir, configDir, err := stateDirs()
	if err != nil {
		if len(args) == 0 {
			_, _ = fmt.Print(menu.Render(menu.View{
				Reason: locale.For(locale.English).Text("no_home"),
				Plugin: pluginPath,
			}))
		}
		if len(args) == 0 || args[0] != cli.VersionFlag {
			return
		}
	}

	script := osascript.Script{NotifyLog: os.Getenv("USDBRL_NOTIFY_LOG")}
	runner := cli.New(cli.Config{
		CacheDir:   cacheDir,
		ConfigDir:  configDir,
		PluginPath: pluginPath,
		YahooURL:   cmp.Or(os.Getenv("USDBRL_YAHOO_URL"), "https://query1.finance.yahoo.com/v8/finance/chart/USDBRL=X?range=1d&interval=1d"),
		AwesomeURL: cmp.Or(os.Getenv("USDBRL_AWESOME_URL"), "https://economia.awesomeapi.com.br/json/last/USD-BRL"),
		Now:        time.Now,
		Location:   time.Local,
		Version:    version,
	}, cli.Dependencies{
		Sources:  quote.NewClient(nil),
		Notifier: script,
		Prompter: script,
	})
	defer func() {
		if recover() != nil && len(args) == 0 {
			_, _ = fmt.Print(runner.Empty())
		}
	}()
	_, _ = fmt.Print(runner.Run(context.Background(), args))
}

func stateDirs() (cache, config string, err error) {
	cache, config = os.Getenv("USDBRL_CACHE_DIR"), os.Getenv("USDBRL_CONFIG_DIR")
	if cache != "" && config != "" {
		return cache, config, nil
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return "", "", err
	}
	return cmp.Or(cache, filepath.Join(home, "Library", "Caches", "usdbrl-swiftbar")),
		cmp.Or(config, filepath.Join(home, "Library", "Application Support", "usdbrl-swiftbar")),
		nil
}
