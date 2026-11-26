package main

import (
	"context"
	"fmt"
	"os"

	"github.com/fascari/swiftbar-usdbrl/internal/cli"
)

const versionFlag = "--version"

var version = "dev"

func main() {
	args := os.Args[1:]
	if len(args) > 0 && args[0] == versionFlag {
		_, _ = fmt.Println(version)
		return
	}

	cfg, err := cli.ConfigFromEnvironment()
	if err != nil {
		if len(args) == 0 {
			_, _ = fmt.Print(cli.MissingHomeMenu())
		}
		return
	}

	runner := cli.New(cfg, cli.DependenciesFromEnvironment())
	defer func() {
		if recover() != nil && len(args) == 0 {
			_, _ = fmt.Print(runner.Empty())
		}
	}()
	_, _ = fmt.Print(runner.Run(context.Background(), args))
}
