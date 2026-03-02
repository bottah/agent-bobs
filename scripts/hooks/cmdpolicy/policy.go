package main

import (
	"encoding/json"
	"fmt"
	"os"
	"regexp"
	"strings"

	"github.com/dlclark/regexp2"
)

// Rule represents a single policy rule from tool-policy.json.
type Rule struct {
	Match   string `json:"match"`
	Message string `json:"message"`
	Mode    string `json:"mode"` // "substring" (default), "regex", "pcre"
}

// CompiledRule is a Rule with pre-compiled pattern.
type CompiledRule struct {
	Rule
	re   *regexp.Regexp
	pcre *regexp2.Regexp
}

// PolicyFile represents the JSON structure of tool-policy.json.
type PolicyFile struct {
	Rules []Rule `json:"rules"`
}

// LoadPolicy reads and compiles rules from the policy JSON file.
func LoadPolicy(path string) ([]CompiledRule, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var pf PolicyFile
	if err := json.Unmarshal(data, &pf); err != nil {
		return nil, err
	}

	compiled := make([]CompiledRule, 0, len(pf.Rules))
	for _, r := range pf.Rules {
		cr := CompiledRule{Rule: r}
		switch r.Mode {
		case "regex":
			re, err := regexp.Compile(r.Match)
			if err != nil {
				return nil, fmt.Errorf("rule %q: invalid regex: %w", r.Match, err)
			}
			cr.re = re
		case "pcre":
			re, err := regexp2.Compile(r.Match, regexp2.None)
			if err != nil {
				return nil, fmt.Errorf("rule %q: invalid pcre: %w", r.Match, err)
			}
			cr.pcre = re
		case "substring", "":
			// no compilation needed
		default:
			return nil, fmt.Errorf("rule %q: unknown mode %q", r.Match, r.Mode)
		}
		compiled = append(compiled, cr)
	}
	return compiled, nil
}

// MatchCommand checks a command string against all compiled rules.
// Returns the first matching rule's message, or empty string.
func MatchCommand(command string, rules []CompiledRule) string {
	command = strings.TrimSpace(command)
	if command == "" {
		return ""
	}
	for _, rule := range rules {
		if ruleMatches(command, &rule) {
			return rule.Message
		}
	}
	return ""
}

func ruleMatches(command string, rule *CompiledRule) bool {
	switch rule.Mode {
	case "regex":
		return rule.re.MatchString(command)
	case "pcre":
		matched, err := rule.pcre.MatchString(command)
		return err == nil && matched
	case "substring", "":
		return strings.Contains(command, rule.Match)
	}
	return false
}

// CheckAllCommands checks a list of extracted commands against all rules.
// Returns the first match message, or empty string.
func CheckAllCommands(commands []string, rules []CompiledRule) string {
	for _, cmd := range commands {
		if msg := MatchCommand(cmd, rules); msg != "" {
			return msg
		}
	}
	return ""
}
