package menu

const (
	ActionSetInterval Action = "--set-interval"
	ActionSetLanguage Action = "--set-lang"
	ActionAddAlert    Action = "--add-alert"
	ActionRemoveAlert Action = "--remove-alert"
	ActionClearAlerts Action = "--clear-alerts"
)

type Action string
