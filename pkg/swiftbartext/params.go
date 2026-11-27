package swiftbartext

import "strconv"

func Command(plugin, action string, args ...string) []string {
	params := []string{`bash="` + plugin + `"`, "param1=" + action}
	for i, arg := range args {
		params = append(params, "param"+strconv.Itoa(i+2)+"="+arg)
	}
	return params
}

func Checked(selected bool) string {
	if selected {
		return "checked=true"
	}
	return ""
}
