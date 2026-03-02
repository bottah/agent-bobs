package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
)

func main() {
	policyPath := flag.String("policy", "", "Path to tool-policy.json")
	flag.Parse()

	if *policyPath == "" || flag.NArg() != 1 {
		fmt.Fprintf(os.Stderr, "usage: cmdpolicy -policy <json-path> <command-string>\n")
		os.Exit(2)
	}

	command := flag.Arg(0)
	if command == "" {
		os.Exit(0)
	}

	rules, err := LoadPolicy(*policyPath)
	if err != nil {
		printDeny("failed to load policy file: " + err.Error())
		os.Exit(0)
	}

	if len(rules) == 0 {
		os.Exit(0)
	}

	commands, err := ExtractCommands(command)
	if err != nil {
		printDeny("command parse error (fail closed): " + err.Error())
		os.Exit(0)
	}

	if msg := CheckAllCommands(commands, rules); msg != "" {
		printDeny(msg)
	}
}

func printDeny(reason string) {
	full := "Tool policy: " + reason
	escaped, _ := json.Marshal(full)
	// json.Marshal produces "string" with quotes; use it directly in the template
	fmt.Printf(`{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}`, escaped)
	fmt.Println()
}
