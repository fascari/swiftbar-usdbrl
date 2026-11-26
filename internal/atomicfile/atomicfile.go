package atomicfile

import (
	"os"
	"path/filepath"
)

// Write replaces the file atomically with mode 0600 and creates missing directories with mode 0700.
func Write(path, text string) error {
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}
	file, err := os.CreateTemp(dir, ".tmp.*")
	if err != nil {
		return err
	}
	defer func() {
		_ = os.Remove(file.Name())
	}()
	_, writeErr := file.WriteString(text)
	closeErr := file.Close()
	if writeErr != nil {
		return writeErr
	}
	if closeErr != nil {
		return closeErr
	}
	return os.Rename(file.Name(), path)
}
