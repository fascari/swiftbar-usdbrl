package osascript

import (
	"context"
	"os"

	"github.com/fascari/swiftbar-usdbrl/pkg/macosdialog"
)

type Script struct {
	NotifyLog string
}

func (s Script) Notify(ctx context.Context, message string) error {
	if s.NotifyLog != "" {
		file, err := os.OpenFile(s.NotifyLog, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o600)
		if err != nil {
			return err
		}
		_, writeErr := file.WriteString(message + "\n")
		closeErr := file.Close()
		if writeErr != nil {
			return writeErr
		}
		return closeErr
	}
	return macosdialog.Notify(ctx, macosdialog.Notification{
		Title: "USD/BRL", Message: message, Sound: "Glass",
	})
}

func (s Script) Ask(ctx context.Context, prompt, answer string) (string, error) {
	return macosdialog.Show(ctx, macosdialog.Dialog{Title: "USD/BRL", Message: prompt, Answer: new(answer)})
}
