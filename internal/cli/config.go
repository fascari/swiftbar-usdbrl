package cli

import (
	"cmp"
	"os"
	"path/filepath"
	"time"

	"github.com/fascari/swiftbar-usdbrl/internal/osascript"
	"github.com/fascari/swiftbar-usdbrl/internal/payout/provider"
	"github.com/fascari/swiftbar-usdbrl/internal/quote"
)

const (
	defaultYahooURL   = "https://query1.finance.yahoo.com/v8/finance/chart/USDBRL=X?range=1d&interval=1d"
	defaultAwesomeURL = "https://economia.awesomeapi.com.br/json/last/USD-BRL"
)

type Config struct {
	CacheDir   string
	ConfigDir  string
	PluginPath string
	YahooURL   string
	AwesomeURL string
	Now        func() time.Time
	Location   *time.Location
}

func ConfigFromEnvironment() (Config, error) {
	cfg := Config{
		CacheDir:   os.Getenv("USDBRL_CACHE_DIR"),
		ConfigDir:  os.Getenv("USDBRL_CONFIG_DIR"),
		PluginPath: pluginPath(),
		YahooURL:   cmp.Or(os.Getenv("USDBRL_YAHOO_URL"), defaultYahooURL),
		AwesomeURL: cmp.Or(os.Getenv("USDBRL_AWESOME_URL"), defaultAwesomeURL),
		Now:        time.Now,
		Location:   time.Local,
	}
	if cfg.CacheDir != "" && cfg.ConfigDir != "" {
		return cfg, nil
	}

	home, err := os.UserHomeDir()
	if err != nil {
		return Config{}, err
	}
	cfg.CacheDir = cmp.Or(cfg.CacheDir, filepath.Join(home, "Library", "Caches", "usdbrl-swiftbar"))
	cfg.ConfigDir = cmp.Or(cfg.ConfigDir, filepath.Join(home, "Library", "Application Support", "usdbrl-swiftbar"))
	return cfg, nil
}

func pluginPath() string {
	return cmp.Or(os.Getenv("USDBRL_PLUGIN_PATH"), os.Getenv("SWIFTBAR_PLUGIN_PATH"), os.Args[0])
}

func DependenciesFromEnvironment() Dependencies {
	script := osascript.Script{NotifyLog: os.Getenv("USDBRL_NOTIFY_LOG")}
	return Dependencies{
		Sources:  quote.NewClient(nil),
		Notifier: script,
		Prompter: script,
		providers: []provider.Source{provider.HiglobeClient{
			URL: cmp.Or(os.Getenv("USDBRL_HIGLOBE_URL"), provider.HiglobeURL),
			Now: time.Now,
		}.Source()},
	}
}
