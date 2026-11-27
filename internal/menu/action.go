package menu

const (
	ActionSetInterval Action = "--set-interval"
	ActionSetLanguage Action = "--set-lang"
	ActionAddAlert    Action = "--add-alert"
	ActionRemoveAlert Action = "--remove-alert"
	ActionClearAlerts Action = "--clear-alerts"

	OpenConverter Action = "--open-converter"
	SetDisplay    Action = "--set-display"

	DisplayUSD Display = "usd"
)

type (
	Action  string
	Display string
)
