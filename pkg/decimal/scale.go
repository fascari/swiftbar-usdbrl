package decimal

import (
	"errors"
	"math/big"
	"regexp"
)

var (
	fixedPoint = regexp.MustCompile(`^[+-]?[0-9]+(\.[0-9]+)?$`)
	errDecimal = errors.New("invalid decimal or result outside int64")
)

// Scale multiplies units by a base-10 factor, rounding ties away from zero.
func Scale(units int64, factor string) (int64, error) {
	if !fixedPoint.MatchString(factor) {
		return 0, errDecimal
	}
	value, ok := new(big.Rat).SetString(factor)
	if !ok {
		return 0, errDecimal
	}
	value.Mul(value, new(big.Rat).SetInt64(units))
	rounded, ok := new(big.Int).SetString(value.FloatString(0), 10)
	if !ok || !rounded.IsInt64() {
		return 0, errDecimal
	}
	return rounded.Int64(), nil
}
