package boundedio

import (
	"errors"
	"io"
	"math"
)

var ErrLimit = errors.New("input exceeds byte limit")

// ReadAll reads up to limit bytes and rejects input longer than limit.
func ReadAll(reader io.Reader, limit int64) ([]byte, error) {
	if limit < 0 || limit == math.MaxInt64 {
		return nil, ErrLimit
	}
	data, err := io.ReadAll(io.LimitReader(reader, limit+1))
	if err != nil {
		return nil, err
	}
	if int64(len(data)) > limit {
		return nil, ErrLimit
	}
	return data, nil
}
