package decimaltext

import (
	"fmt"
	"strconv"
)

// Cents formats hundredths with two decimals and optional thousands grouping.
func Cents(value int64, point, group string) string {
	whole := strconv.FormatInt(value/100, 10)
	fraction := value % 100
	sign := ""
	if value < 0 {
		sign = "-"
		fraction = -fraction
		if whole[0] == '-' {
			whole = whole[1:]
		}
	}
	if group != "" {
		for index := len(whole) - 3; index > 0; index -= 3 {
			whole = whole[:index] + group + whole[index:]
		}
	}
	return fmt.Sprintf("%s%s%s%02d", sign, whole, point, fraction)
}
