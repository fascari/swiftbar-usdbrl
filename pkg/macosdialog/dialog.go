package macosdialog

import (
	"context"
	_ "embed"
	"encoding/json"
	"os/exec"
	"strings"
)

//go:embed dialog.js
var program string

type (
	Dialog struct {
		Title   string   `json:"title"`
		Message string   `json:"message"`
		Answer  *string  `json:"answer"`
		Choices []string `json:"choices"`
	}
	Notification struct {
		Title   string
		Message string
		Sound   string
	}
)

// Show passes dialog data through stdin rather than process arguments.
func Show(ctx context.Context, dialog Dialog) (string, error) {
	options, err := json.Marshal(dialog)
	if err != nil {
		return "", err
	}
	cmd := exec.CommandContext(ctx, "/usr/bin/osascript", "-l", "JavaScript", "-")
	cmd.Stdin = strings.NewReader(program + "\ndialog = " + string(options) + ";\n")
	out, err := cmd.Output()
	if err != nil {
		return "", err
	}
	return strings.TrimSuffix(string(out), "\n"), nil
}

func Notify(ctx context.Context, notification Notification) error {
	return exec.CommandContext(ctx, "/usr/bin/osascript",
		"-e", "on run argv",
		"-e", "display notification (item 1 of argv) with title (item 2 of argv) sound name (item 3 of argv)",
		"-e", "end run", notification.Message, notification.Title, notification.Sound).Run()
}
