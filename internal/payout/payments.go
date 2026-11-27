package payout

import (
	"errors"
	"math"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"unicode"

	"github.com/fascari/swiftbar-usdbrl/pkg/filelock"
	"github.com/fascari/swiftbar-usdbrl/pkg/jsonfile"
)

const paymentsFile = "payments.json"

var (
	ErrPaymentChanged = errors.New("payment changed")
	errPaymentID      = errors.New("payment identifier exhausted")
)

type (
	Payment struct {
		ID        uint64 `json:"id"`
		Revision  uint64 `json:"revision"`
		Name      string `json:"name,omitempty"`
		Cents     int64  `json:"cents"`
		RequestID string `json:"request_id,omitempty"`
	}
	Payments struct {
		LastID  uint64    `json:"last_id"`
		Entries []Payment `json:"entries"`
	}
	Change struct {
		Before Payment
		After  Payment
		Remove bool
	}
)

func ValidPaymentName(name string) bool {
	return len([]rune(name)) <= 80 && !strings.ContainsAny(name, "\u2028\u2029") &&
		!strings.ContainsFunc(name, unicode.IsControl)
}

func (s Store) ReadPayments() (Payments, error) {
	var list Payments
	err := jsonfile.Read(filepath.Join(s.ConfigDir, paymentsFile), &list)
	if errors.Is(err, os.ErrNotExist) {
		return Payments{}, nil
	}
	return list, err
}

func (s Store) updatePayment(change Change) (uint64, error) {
	path := filepath.Join(s.ConfigDir, paymentsFile)
	lock, err := filelock.Lock(path + ".lock")
	if err != nil {
		return 0, err
	}
	defer func() { _ = lock.Close() }()
	list, err := s.ReadPayments()
	if err != nil {
		return 0, err
	}
	if change.Before.ID == 0 && change.After.RequestID != "" {
		if id, err := list.replayed(change.After); id != 0 || err != nil {
			return id, err
		}
	}
	if err := list.apply(change); err != nil {
		return 0, err
	}
	if !change.Remove {
		if err := list.validateTotal(s.ReadRate().Rate); err != nil {
			return 0, err
		}
	}
	if err := jsonfile.Write(path, list); err != nil {
		return 0, err
	}
	if change.Before.ID == 0 {
		return list.LastID, nil
	}
	return change.Before.ID, nil
}

func (l *Payments) validateTotal(rate string) error {
	if rate == "" {
		return nil
	}
	_, err := EstimateTotal(l.Entries, rate)
	return err
}

func (l *Payments) replayed(after Payment) (uint64, error) {
	for _, entry := range l.Entries {
		if entry.RequestID != after.RequestID {
			continue
		}
		if entry.Name != after.Name || entry.Cents != after.Cents {
			return 0, ErrPaymentChanged
		}
		return entry.ID, nil
	}
	return 0, nil
}

func (l *Payments) apply(change Change) error {
	before, after := change.Before, change.After
	if before.ID == 0 && !change.Remove {
		if l.LastID == math.MaxUint64 {
			return errPaymentID
		}
		l.LastID++
		after.ID, after.Revision = l.LastID, 0
		l.Entries = append(l.Entries, after)
		return nil
	}
	index := slices.IndexFunc(l.Entries, func(p Payment) bool { return p.ID == before.ID })
	if index < 0 || l.Entries[index] != before || before.Revision == math.MaxUint64 {
		return ErrPaymentChanged
	}
	if change.Remove {
		l.Entries = slices.Delete(l.Entries, index, index+1)
		return nil
	}
	after.ID, after.Revision, after.RequestID = before.ID, before.Revision+1, before.RequestID
	l.Entries[index] = after
	return nil
}
