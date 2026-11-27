package cli

import (
	"cmp"
	"context"
	"errors"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/fascari/swiftbar-usdbrl/internal/alert"
	"github.com/fascari/swiftbar-usdbrl/internal/locale"
	"github.com/fascari/swiftbar-usdbrl/internal/menu"
	"github.com/fascari/swiftbar-usdbrl/internal/quote"
	"github.com/fascari/swiftbar-usdbrl/pkg/atomicfile"
	"github.com/fascari/swiftbar-usdbrl/pkg/filelock"
	"github.com/fascari/swiftbar-usdbrl/pkg/utf8text"
)

const yahooPause = 5 * time.Minute

func (r Runner) refresh(ctx context.Context) string {
	view, fired := r.refreshView(ctx)
	s := locale.For(view.Language)
	for _, a := range fired {
		target := s.Number(a.Value)
		message := fmt.Sprintf(s.Text("alert_hit"), target)
		if current := s.Number(view.Quote.Price); current != target {
			message += fmt.Sprintf(s.Text("alert_now"), current)
		}
		_ = r.dep.Notifier.Notify(ctx, message)
	}
	view.Providers = r.menuPlugin().RefreshViews(ctx)
	return menu.Render(view)
}

func (r Runner) refreshView(ctx context.Context) (menu.View, []alert.Alert) {
	lock, err := filelock.Lock(r.paths.refreshLock)
	if err == nil {
		defer func() {
			_ = lock.Close()
		}()
	}

	cached, lastOK := r.cache()
	view := menu.View{
		Quote:    cached,
		LastOK:   lastOK,
		Location: r.cfg.Location,
		Language: r.language(),
		Plugin:   r.cfg.PluginPath,
	}
	s := locale.For(view.Language)
	fresh, warning, err := r.fetch(ctx, s, lock)
	view.Now = r.now()
	if err != nil {
		view.Reason = fmt.Sprintf(s.Text("all_down"), fetchReason(s, err))
		view.Alerts = r.alerts()
		return view, nil
	}

	view.LastOK = view.Now
	view.Warning = warning
	keepCached := cached != nil && cached.Time.After(fresh.Time)
	if !keepCached {
		view.Quote = new(fresh)
	}
	if lock != nil && keepCached {
		_ = os.Chtimes(r.paths.cache, view.Now, view.Now)
	}
	if lock != nil && !keepCached {
		_ = atomicfile.Write(r.paths.cache, fresh.Line()+"\n")
	}

	fired, remaining := r.collectAlerts(view.Quote.Price)
	view.Alerts = remaining
	return view, fired
}

func (r Runner) fetch(ctx context.Context, s locale.Language, lock *os.File) (quote.Quote, string, error) {
	if warning, paused := r.pausedWarning(s); paused {
		return r.fetchFallback(ctx, warning)
	}
	q, err := r.dep.Sources.Fetch(ctx, quote.Yahoo, r.cfg.YahooURL)
	if err == nil {
		r.updateYahooPause(lock, "")
		return q, "", nil
	}
	reason := fetchReason(s, err)
	r.updateYahooPause(lock, reason)
	return r.fetchFallback(ctx, fmt.Sprintf(s.Text("yahoo_down"), reason))
}

func (r Runner) fetchFallback(ctx context.Context, warning string) (quote.Quote, string, error) {
	q, err := r.dep.Sources.Fetch(ctx, quote.Awesome, r.cfg.AwesomeURL)
	return q, warning, err
}

func (r Runner) pausedWarning(s locale.Language) (string, bool) {
	info, err := os.Stat(r.paths.pause)
	if err != nil || r.now().Sub(info.ModTime()) >= yahooPause {
		return "", false
	}
	data, _ := os.ReadFile(r.paths.pause)
	reason := strings.NewReplacer("|", "", "\n", "", "\r", "").Replace(utf8text.Prefix(string(data), 120))
	return fmt.Sprintf(s.Text("yahoo_paused"), cmp.Or(reason, "?")), true
}

func (r Runner) updateYahooPause(refreshLock *os.File, reason string) {
	if refreshLock == nil {
		return
	}
	if reason == "" {
		_ = os.Remove(r.paths.pause)
		return
	}
	failedAt := r.now()
	if err := atomicfile.Write(r.paths.pause, reason+"\n"); err == nil {
		_ = os.Chtimes(r.paths.pause, failedAt, failedAt)
	}
}

func fetchReason(s locale.Language, err error) string {
	fetch, _ := errors.AsType[quote.FetchError](err)
	if fetch.Kind == quote.HTTPError {
		return s.Text("request_http")
	}
	if fetch.Kind == quote.NoConnection {
		return s.Text("request_connection")
	}
	if fetch.Kind == quote.TLS {
		return s.Text("request_tls")
	}
	if fetch.Kind == quote.Invalid {
		return fmt.Sprintf(s.Text("request_invalid"), fetch.Status)
	}
	return s.Text("request_failed")
}

func (r Runner) collectAlerts(price float64) (fired, remaining []alert.Alert) {
	if _, err := os.Stat(r.paths.alerts); err != nil {
		return nil, r.alerts()
	}
	edited := r.editAlerts(func(current []alert.Alert) {
		remaining = current
		reached, pending := alert.Check(current, price)
		// Persist the removal before notifying, so overlapping refreshes cannot fire twice.
		if len(reached) > 0 && r.saveAlerts(pending) == nil {
			fired, remaining = reached, pending
		}
	})
	if !edited {
		return nil, r.alerts()
	}
	return fired, remaining
}
