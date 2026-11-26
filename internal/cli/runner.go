package cli

import (
	"context"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/fascari/swiftbar-usdbrl/internal/locale"
	"github.com/fascari/swiftbar-usdbrl/internal/menu"
	"github.com/fascari/swiftbar-usdbrl/internal/quote"
)

//go:generate mockery --all --case=snake --disable-version-string --with-expecter

const VersionFlag = "--version"

// Preserve the v1.1.1 state filenames so upgrades and downgrades can share them.
const (
	cacheFile       = "last.tsv"
	pauseFile       = "yahoo.paused"
	refreshLockFile = ".refresh.lock"
	languageFile    = "lang"
	alertsFile      = "alerts"
	alertsLockFile  = ".alerts.lock"
)

type (
	// Sources returns quote.FetchError values so the menu can localize failures.
	Sources interface {
		Fetch(ctx context.Context, source quote.Source, url string) (quote.Quote, error)
	}

	Notifier interface {
		Notify(ctx context.Context, message string) error
	}

	// Prompter prefills answer and returns an error on cancellation.
	Prompter interface {
		Ask(ctx context.Context, prompt, answer string) (string, error)
	}
)

type (
	Config struct {
		CacheDir   string
		ConfigDir  string
		PluginPath string
		YahooURL   string
		AwesomeURL string
		Now        func() time.Time
		Location   *time.Location
		Version    string
	}

	Dependencies struct {
		Sources  Sources
		Notifier Notifier
		Prompter Prompter
	}

	Runner struct {
		cfg   Config
		dep   Dependencies
		paths paths
	}

	paths struct {
		cache       string
		pause       string
		refreshLock string
		language    string
		alerts      string
		alertsLock  string
	}
)

func New(cfg Config, dep Dependencies) Runner {
	return Runner{
		cfg: cfg,
		dep: dep,
		paths: paths{
			cache:       filepath.Join(cfg.CacheDir, cacheFile),
			pause:       filepath.Join(cfg.CacheDir, pauseFile),
			refreshLock: filepath.Join(cfg.CacheDir, refreshLockFile),
			language:    filepath.Join(cfg.ConfigDir, languageFile),
			alerts:      filepath.Join(cfg.ConfigDir, alertsFile),
			alertsLock:  filepath.Join(cfg.ConfigDir, alertsLockFile),
		},
	}
}

// Run renders a refresh with no arguments. Actions return no output except --version.
func (r Runner) Run(ctx context.Context, args []string) string {
	if len(args) == 0 {
		return r.refresh(ctx)
	}
	if args[0] == VersionFlag {
		return r.cfg.Version + "\n"
	}
	r.handleAction(ctx, args)
	return ""
}

func (r Runner) Empty() string {
	return menu.Render(menu.View{
		Language: r.language(),
		Plugin:   r.cfg.PluginPath,
		Alerts:   r.alerts(),
	})
}

func (r Runner) language() locale.Code {
	text, err := os.ReadFile(r.paths.language)
	if err != nil {
		return ""
	}
	return locale.Code(strings.TrimRight(string(text), "\n"))
}

func (r Runner) now() time.Time {
	return r.cfg.Now().Truncate(time.Second)
}

func (r Runner) cache() (*quote.Quote, time.Time) {
	file, err := os.Open(r.paths.cache)
	if err != nil {
		return nil, time.Time{}
	}
	defer func() {
		_ = file.Close()
	}()
	info, err := file.Stat()
	if err != nil {
		return nil, time.Time{}
	}
	data, err := io.ReadAll(file)
	if err != nil {
		return nil, time.Time{}
	}
	q, err := quote.ParseLine(string(data))
	if err != nil {
		return nil, time.Time{}
	}
	return new(q), info.ModTime()
}

// prefix cuts at a UTF-8 character boundary within the byte limit.
func prefix(text string, bytes int) string {
	if len(text) <= bytes {
		return text
	}
	for bytes > 0 && !utf8.RuneStart(text[bytes]) {
		bytes--
	}
	return text[:bytes]
}
