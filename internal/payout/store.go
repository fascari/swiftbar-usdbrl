package payout

import (
	"context"
	"path/filepath"
	"strconv"
	"time"

	"github.com/fascari/swiftbar-usdbrl/pkg/filelock"
	"github.com/fascari/swiftbar-usdbrl/pkg/jsonfile"
)

const (
	rateFile       = "rate.json"
	duplicateCheck = 10 * time.Second
)

type (
	Store struct {
		ConfigDir string
		CacheDir  string
	}
	Service struct {
		Store Store
		Now   func() time.Time
		Fetch func(context.Context) (string, error)
	}
	CachedRate struct {
		Rate         string    `json:"rate"`
		PreviousRate string    `json:"previous_rate,omitempty"`
		Checked      time.Time `json:"checked"`
		Failed       bool      `json:"failed"`
		Attempted    time.Time `json:"attempted"`
	}
)

func (c CachedRate) Stale(now time.Time) bool {
	return c.Failed || (!c.Checked.IsZero() && now.Sub(c.Checked) >= time.Hour)
}

func (c CachedRate) ChangePercent() *float64 {
	if !rateFormat.MatchString(c.PreviousRate) || !rateFormat.MatchString(c.Rate) {
		return nil
	}
	previous, _ := strconv.ParseFloat(c.PreviousRate, 64)
	current, _ := strconv.ParseFloat(c.Rate, 64)
	if previous == 0 || current == 0 {
		return nil
	}
	return new((current - previous) / previous * 100)
}

func (s Store) ReadRate() CachedRate {
	var cache CachedRate
	if jsonfile.Read(filepath.Join(s.CacheDir, rateFile), &cache) != nil {
		return CachedRate{}
	}
	if cache.Rate == "" {
		return CachedRate{Failed: cache.Failed, Attempted: cache.Attempted}
	}
	if _, err := Convert(100, cache.Rate); err != nil || cache.Checked.IsZero() {
		return CachedRate{}
	}
	return cache
}

func (s Service) RefreshRate(ctx context.Context) CachedRate {
	return s.refreshRate(ctx, 0)
}

// RefreshRateOnTick reuses a recent attempt because a manual update also triggers a SwiftBar refresh.
func (s Service) RefreshRateOnTick(ctx context.Context) CachedRate {
	return s.refreshRate(ctx, duplicateCheck)
}

func (s Service) refreshRate(ctx context.Context, minimumAge time.Duration) CachedRate {
	path := filepath.Join(s.Store.CacheDir, rateFile)
	lock, err := filelock.Lock(path + ".lock")
	if err != nil {
		previous := s.Store.ReadRate()
		previous.Failed = true
		return previous
	}
	defer func() { _ = lock.Close() }()
	cache := s.Store.ReadRate()
	if s.Fetch == nil {
		return cache
	}
	if minimumAge > 0 && !cache.Attempted.IsZero() {
		age := s.Now().Sub(cache.Attempted)
		if age >= 0 && age < minimumAge {
			return cache
		}
	}
	rate, err := s.Fetch(ctx)
	attempted := s.Now()
	if _, invalid := Convert(100, rate); err != nil || invalid != nil {
		cache.Failed = true
		cache.Attempted = attempted
		return s.Store.saveRate(path, cache)
	}
	return s.Store.saveRate(path, CachedRate{
		Rate:         rate,
		PreviousRate: cache.Rate,
		Checked:      attempted,
		Attempted:    attempted,
	})
}

func (s Store) saveRate(path string, cache CachedRate) CachedRate {
	if jsonfile.Write(path, cache) != nil {
		previous := s.ReadRate()
		previous.Failed = true
		return previous
	}
	return cache
}
