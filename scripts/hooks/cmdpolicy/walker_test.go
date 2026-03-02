package main

import (
	"sort"
	"strings"
	"testing"
)

func TestExtractCommands(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected []string
	}{
		// Basic commands
		{"simple", "git status", []string{"git status"}},
		{"with args", "echo hello world", []string{"echo hello world"}},

		// Separators
		{"semicolon", "echo a; echo b", []string{"echo a", "echo b"}},
		{"and", "true && echo b", []string{"true", "echo b"}},
		{"or", "false || echo b", []string{"false", "echo b"}},
		{"pipe", "echo hello | grep h", []string{"echo hello", "grep h"}},
		{"background", "echo a & echo b", []string{"echo a", "echo b"}},
		{"newline", "echo a\necho b", []string{"echo a", "echo b"}},

		// Grouping
		{"subshell", "(echo hello)", []string{"echo hello"}},
		{"block", "{ echo hello; }", []string{"echo hello"}},

		// Control flow
		{"if then", "if true; then echo a; fi", []string{"true", "echo a"}},
		{"if else", "if true; then echo a; else echo b; fi", []string{"true", "echo a", "echo b"}},
		{"for", "for x in 1 2; do echo $x; done", []string{"echo"}},
		{"while", "while true; do echo a; break; done", []string{"true", "echo a", "break"}},

		// Negation and time
		{"negated", "! echo hello", []string{"echo hello"}},
		{"negated with assign", "NO_COLOR=1 ! echo hello", []string{"echo hello"}},
		{"time with assign", "NO_COLOR=1 time echo hello", []string{"echo hello"}},

		// Env var prefix
		{"env var", "NO_COLOR=1 git status", []string{"git status"}},
		{"multi env var", "A=1 B=2 git status", []string{"git status"}},

		// Transparent prefixes
		{"command", "command git status", []string{"git status"}},
		{"command -p", "command -p git status", []string{"git status"}},
		{"builtin", "builtin echo hello", []string{"echo hello"}},
		{"exec", "exec echo hello", []string{"echo hello"}},
		{"exec -a", "exec -a myname echo hello", []string{"echo hello"}},
		{"env simple", "env git status", []string{"git status"}},
		{"env -i", "env -i git status", []string{"git status"}},
		{"env -u TERM", "env -u TERM git status", []string{"git status"}},
		{"env with assign", "env NO_COLOR=1 git status", []string{"git status"}},
		{"nice", "nice echo hello", []string{"echo hello"}},
		{"nohup", "nohup echo hello", []string{"echo hello"}},
		{"sudo", "sudo echo hello", []string{"echo hello"}},
		{"strace", "strace echo hello", []string{"echo hello"}},

		// Chained prefixes
		{"command env", "command env NO_COLOR=1 git status", []string{"git status"}},

		// Shell interpreters
		{"bash -c", "bash -c 'echo hello'", []string{"echo hello"}},
		{"sh -c", "sh -c 'echo hello'", []string{"echo hello"}},
		{"bash -lc", "bash -lc 'echo hello'", []string{"echo hello"}},

		// eval
		{"eval", "eval 'echo hello'", []string{"echo hello"}},
		{"builtin eval", "builtin eval 'echo hello'", []string{"echo hello"}},

		// env -S
		{"env -S", "env -S 'echo hello'", []string{"echo hello"}},
		{"env -i -S", "env -i -S 'echo hello'", []string{"echo hello"}},

		// Command substitution
		{"cmd subst in echo", "echo $(git status)", []string{"echo", "git status"}},
		{"cmd subst in assign", "FOO=$(git status) echo ok", []string{"echo ok", "git status"}},

		// Process substitution
		{"proc subst in", "cat <(echo hello)", []string{"cat", "echo hello"}},
		{"proc subst out", "cat >(echo hello)", []string{"cat", "echo hello"}},

		// Nested substitution
		{"nested subst", "echo $(cat <(echo hello))", []string{"echo", "cat", "echo hello"}},

		// Arithmetic expansion with command substitution
		{"arith with cmd subst", "echo $(( $(echo 1) + 1 ))", []string{"echo", "echo 1"}},

		// Redirections (not in args)
		{"redirect out", "echo hello > /tmp/x", []string{"echo hello"}},
		{"redirect before cmd", ">/tmp/x echo hello", []string{"echo hello"}},

		// Quoted command words (should keep the command as-is)
		{"single-quoted cmd", "'true' arg1 arg2", []string{"true arg1 arg2"}},
		{"double-quoted cmd", "\"true\" arg1 arg2", []string{"true arg1 arg2"}},

		// Pure assignment (no command)
		{"pure assign", "FOO=bar", nil},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := ExtractCommands(tt.input)
			if err != nil {
				t.Fatalf("parse error: %v", err)
			}
			if !sameElements(got, tt.expected) {
				t.Errorf("ExtractCommands(%q)\n  got:  %v\n  want: %v", tt.input, got, tt.expected)
			}
		})
	}
}

func TestExtractCommandsParseError(t *testing.T) {
	_, err := ExtractCommands("if then")
	if err == nil {
		t.Error("expected parse error for invalid syntax")
	}
}

func sameElements(a, b []string) bool {
	if len(a) == 0 && len(b) == 0 {
		return true
	}
	if len(a) != len(b) {
		return false
	}
	// Normalize whitespace and sort for comparison
	aCopy := make([]string, len(a))
	bCopy := make([]string, len(b))
	for i, s := range a {
		aCopy[i] = strings.TrimSpace(s)
	}
	for i, s := range b {
		bCopy[i] = strings.TrimSpace(s)
	}
	sort.Strings(aCopy)
	sort.Strings(bCopy)
	for i := range aCopy {
		if aCopy[i] != bCopy[i] {
			return false
		}
	}
	return true
}
