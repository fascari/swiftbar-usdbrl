package cli

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"

	"github.com/fascari/swiftbar-usdbrl/internal/alert"
	"github.com/fascari/swiftbar-usdbrl/internal/atomicfile"
	"github.com/fascari/swiftbar-usdbrl/internal/filelock"
	"github.com/fascari/swiftbar-usdbrl/internal/locale"
	"github.com/fascari/swiftbar-usdbrl/internal/menu"
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
		if locale.Supported(value) {
			_ = atomicfile.Write(r.paths.language, value+"\n")
		}
	case menu.ActionAddAlert:
		r.addAlert(ctx, value)
	case menu.ActionRemoveAlert:
		if len(args) > 2 {
			r.editAlerts(func(current []alert.Alert) {
				_ = r.saveAlerts(alert.Remove(current, alert.Direction(value), args[2]))
			})
		}
	case menu.ActionClearAlerts:
		r.editAlerts(func(_ []alert.Alert) {
			_ = r.saveAlerts(nil)
		})
	}
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
	s := locale.For(r.language())
	if q == nil {
		_ = r.dep.Notifier.Notify(ctx, s.Text("alert_no_rate"))
		return
	}
	var target string
	var err error
	switch value {
	case "":
		target, err = r.askTarget(ctx, s, q.Price)
	default:
		target, err = alert.ParseTarget(value)
	}
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

func (r Runner) askTarget(ctx context.Context, s locale.Language, price float64) (string, error) {
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
		prompt = fmt.Sprintf(s.Text("alert_invalid"), prefix(text, 20)) + "\n\n" + basePrompt
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

// editAlerts holds the lock for the entire read and edit. It skips edit if locking fails.
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
