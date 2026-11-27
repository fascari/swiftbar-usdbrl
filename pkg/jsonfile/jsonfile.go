package jsonfile

import (
	"encoding/json"
	"os"

	"github.com/fascari/swiftbar-usdbrl/pkg/atomicfile"
)

// Read decodes the JSON document at path into dest.
func Read(path string, dest any) error {
	data, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	return json.Unmarshal(data, dest)
}

// Write encodes value and atomically replaces path.
func Write(path string, value any) error {
	data, err := json.Marshal(value)
	if err != nil {
		return err
	}
	return atomicfile.Write(path, string(data)+"\n")
}
