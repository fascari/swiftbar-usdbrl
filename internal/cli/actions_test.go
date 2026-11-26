package cli

import (
	"testing"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"

	"github.com/fascari/swiftbar-usdbrl/internal/cli/mocks"
	"github.com/fascari/swiftbar-usdbrl/internal/locale"
	"github.com/fascari/swiftbar-usdbrl/internal/menu"
	"github.com/fascari/swiftbar-usdbrl/internal/quote"
)

func TestAddAlert_ShouldRetryInvalidDialogInput(t *testing.T) {
	cfg := config(t)
	runner := New(cfg, Dependencies{})
	writeState(t, runner.paths.language, "pt\n")
	writeState(t, runner.paths.cache, rate(quote.Yahoo, cfg.Now()).Line()+"\n")
	prompt := "Avisar quando o USD/BRL chegar a (R$, ex.: 5,80):"
	prompter := mocks.NewPrompter(t)
	prompter.EXPECT().Ask(mock.Anything, prompt, "5,74").Return("inválido", nil).Once()
	prompter.EXPECT().Ask(mock.Anything, "Valor inválido: \"inválido\". Use um número como 5,80.\n\n"+prompt, "inválido").
		Return("5,65", nil).Once()
	runner.dep.Prompter = prompter

	got := runner.Run(t.Context(), []string{string(menu.ActionAddAlert)})

	require.Empty(t, got)
	require.Equal(t, "below 5.65\n", readState(t, runner.paths.alerts))
}

func TestSetLanguage_ShouldStoreOnlySupportedCodes(t *testing.T) {
	tests := []struct {
		name  string
		value string
		want  string
	}{
		{
			name:  "should store Portuguese",
			value: string(locale.Portuguese),
			want:  "pt\n",
		},
		{
			name:  "should ignore an unsupported code",
			value: "fr",
			want:  "en\n",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			runner := New(config(t), Dependencies{})
			writeState(t, runner.paths.language, "en\n")

			runner.Run(t.Context(), []string{string(menu.ActionSetLanguage), tt.value})

			require.Equal(t, tt.want, readState(t, runner.paths.language))
		})
	}
}
