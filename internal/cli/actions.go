package cli

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"

	"github.com/fascari/swiftbar-usdbrl/internal/alert"
	"github.com/fascari/swiftbar-usdbrl/internal/locale"
	"github.com/fascari/swiftbar-usdbrl/internal/menu"
	"github.com/fascari/swiftbar-usdbrl/pkg/atomicfile"
	"github.com/fascari/swiftbar-usdbrl/pkg/filelock"
	"github.com/fascari/swiftbar-usdbrl/pkg/utf8text"
)

var errInvalidTarget = errors.New("no valid alert target")

func (r Runner) handleAction(ctx context.Context, args []string) {
	var value string
	if len(args) > 1 {
		value = args[1]
	}
	switch menu.Action(args[0]) {
	case menu.ActionSetInterval:
		r.setInterval(value)
	case menu.ActionSetLanguage:
		r.setLanguage(value)
	case menu.ActionAddAlert:
		r.addAlert(ctx, value)
	case menu.ActionRemoveAlert:
		r.removeAlert(args[1:])
	case menu.ActionClearAlerts:
		r.clearAlerts()
	default:
		r.menuPlugin().Handle(ctx, menu.Action(args[0]), value)
	}
}

func (r Runner) setLanguage(code string) {
	if !locale.Supported(code) {
		return
	}
	_ = atomicfile.Write(r.paths.language, code+"\n")
}

func (r Runner) setInterval(value string) {
	if !menu.ValidInterval(value) {
		return
	}
	if _, isWrapper := menu.IntervalOf(r.cfg.PluginPath); !isWrapper {
		return
	}
	dest := filepath.Join(filepath.Dir(r.cfg.PluginPath), menu.WrapperName(value))
	if r.cfg.PluginPath != dest {
		_ = os.Rename(r.cfg.PluginPath, dest)
	}
}

func (r Runner) addAlert(ctx context.Context, value string) {
	q, _ := r.cache()
	if q == nil {
		s := locale.For(r.language())
		_ = r.dep.Notifier.Notify(ctx, s.Text("alert_no_rate"))
		return
	}
	target, err := r.alertTarget(ctx, value, q.Price)
	if err != nil {
		return
	}

	r.editAlerts(func(current []alert.Alert) {
		updated := alert.Add(current, target, q.Price)
		if len(updated) > len(current) {
			_ = r.saveAlerts(updated)
		}
	})
}

func (r Runner) removeAlert(args []string) {
	if len(args) < 2 {
		return
	}
	direction, target := alert.Direction(args[0]), args[1]
	r.editAlerts(func(current []alert.Alert) {
		_ = r.saveAlerts(alert.Remove(current, direction, target))
	})
}

func (r Runner) clearAlerts() {
	r.editAlerts(func(_ []alert.Alert) {
		_ = r.saveAlerts(nil)
	})
}

func (r Runner) alertTarget(ctx context.Context, value string, price float64) (string, error) {
	if value != "" {
		return alert.ParseTarget(value)
	}
	s := locale.For(r.language())
	answer := s.Number(price)
	basePrompt := s.Text("alert_prompt")
	prompt := basePrompt
	for range 3 {
		text, err := r.dep.Prompter.Ask(ctx, prompt, answer)
		if err != nil {
			return "", err
		}
		target, err := alert.ParseTarget(text)
		if err == nil {
			return target, nil
		}
		answer = text
		prompt = fmt.Sprintf(s.Text("alert_invalid"), utf8text.Prefix(text, 20)) + "\n\n" + basePrompt
	}
	return "", errInvalidTarget
}

func (r Runner) alerts() []alert.Alert {
	data, err := os.ReadFile(r.paths.alerts)
	if err != nil {
		return nil
	}
	return alert.Parse(string(data))
}

func (r Runner) saveAlerts(alerts []alert.Alert) error {
	if len(alerts) > 0 {
		return atomicfile.Write(r.paths.alerts, alert.Lines(alerts))
	}
	err := os.Remove(r.paths.alerts)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	return err
}

func (r Runner) editAlerts(edit func([]alert.Alert)) bool {
	lock, err := filelock.Lock(r.paths.alertsLock)
	if err != nil {
		return false
	}
	defer func() {
		_ = lock.Close()
	}()
	edit(r.alerts())
	return true
}
