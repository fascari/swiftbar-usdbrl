package provider

import "context"

type (
	Details struct {
		ID       string
		Name     string
		Currency string
		Link     string
	}

	// Source returns an effective BRL rate for one unit of its input currency.
	// Fetch receives no payment data.
	Source struct {
		Details
		Fetch func(context.Context) (string, error)
	}
)
