package osascript

import (
	"context"
	"os"
	"os/exec"
	"strings"
)

const path = "/usr/bin/osascript"

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
	return exec.CommandContext(ctx, path,
		"-e", "on run argv",
		"-e", `display notification (item 1 of argv) with title "USD/BRL" sound name "Glass"`,
		"-e", "end run", message).Run()
}

func (s Script) Ask(ctx context.Context, prompt, answer string) (string, error) {
	out, err := exec.CommandContext(ctx, path,
		"-e", "on run argv",
		"-e", `text returned of (display dialog (item 1 of argv) default answer (item 2 of argv) with title "USD/BRL")`,
		"-e", "end run", prompt, answer).Output()
	if err != nil {
		return "", err
	}
	return strings.TrimRight(string(out), "\n"), nil
}
