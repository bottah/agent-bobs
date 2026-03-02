package main

import (
	"strings"

	"mvdan.cc/sh/v3/syntax"
)

// transparentPrefixes are commands that execute their trailing arguments.
var transparentPrefixes = map[string]bool{
	"command": true,
	"builtin": true,
	"exec":    true,
	"env":     true,
	"nice":    true,
	"nohup":   true,
	"sudo":    true,
	"strace":  true,
}

// shellInterpreters take a command string via -c flag.
var shellInterpreters = map[string]bool{
	"bash": true,
	"sh":   true,
	"dash": true,
	"zsh":  true,
	"ksh":  true,
}

// ExtractCommands parses a shell command string and returns all executable
// command invocations found in the AST, normalized by stripping transparent
// prefixes and resolving shell interpreter / eval arguments.
func ExtractCommands(command string) ([]string, error) {
	parser := syntax.NewParser(syntax.Variant(syntax.LangBash))
	file, err := parser.Parse(strings.NewReader(command), "")
	if err != nil {
		return nil, err
	}
	var commands []string
	extractFromFile(file, &commands)
	return commands, nil
}

func extractFromFile(file *syntax.File, commands *[]string) {
	for _, stmt := range file.Stmts {
		extractFromStmt(stmt, commands)
	}
}

func extractFromStmt(stmt *syntax.Stmt, commands *[]string) {
	if stmt == nil || stmt.Cmd == nil {
		return
	}
	// Walk redirections for process substitutions
	for _, redir := range stmt.Redirs {
		if redir.Word != nil {
			walkSubstitutionsInWord(redir.Word, commands)
		}
	}
	extractFromCommand(stmt.Cmd, commands)
}

func extractFromCommand(cmd syntax.Command, commands *[]string) {
	switch c := cmd.(type) {
	case *syntax.CallExpr:
		processCallExpr(c, commands)
	case *syntax.BinaryCmd:
		extractFromStmt(c.X, commands)
		extractFromStmt(c.Y, commands)
	case *syntax.Subshell:
		for _, s := range c.Stmts {
			extractFromStmt(s, commands)
		}
	case *syntax.Block:
		for _, s := range c.Stmts {
			extractFromStmt(s, commands)
		}
	case *syntax.IfClause:
		for _, s := range c.Cond {
			extractFromStmt(s, commands)
		}
		for _, s := range c.Then {
			extractFromStmt(s, commands)
		}
		if c.Else != nil {
			extractFromCommand(c.Else, commands)
		}
	case *syntax.ForClause:
		for _, s := range c.Do {
			extractFromStmt(s, commands)
		}
	case *syntax.WhileClause:
		for _, s := range c.Cond {
			extractFromStmt(s, commands)
		}
		for _, s := range c.Do {
			extractFromStmt(s, commands)
		}
	case *syntax.CaseClause:
		walkSubstitutionsInWord(c.Word, commands)
		for _, ci := range c.Items {
			for _, s := range ci.Stmts {
				extractFromStmt(s, commands)
			}
		}
	case *syntax.TimeClause:
		if c.Stmt != nil {
			extractFromStmt(c.Stmt, commands)
		}
	case *syntax.CoprocClause:
		if c.Stmt != nil {
			extractFromStmt(c.Stmt, commands)
		}
	case *syntax.DeclClause:
		// declare/export/local: walk assign values for substitutions
		for _, a := range c.Args {
			if a.Value != nil {
				walkSubstitutionsInWord(a.Value, commands)
			}
		}
	}
}

// processCallExpr normalizes a simple command by stripping transparent
// prefixes and handling shell interpreters, eval, and env -S.
func processCallExpr(ce *syntax.CallExpr, commands *[]string) {
	// Walk substitutions in assignment values (e.g., FOO=$(cmd))
	for _, a := range ce.Assigns {
		if a.Value != nil {
			walkSubstitutionsInWord(a.Value, commands)
		}
		if a.Array != nil {
			for _, elem := range a.Array.Elems {
				if elem.Value != nil {
					walkSubstitutionsInWord(elem.Value, commands)
				}
			}
		}
	}

	if len(ce.Args) == 0 {
		return
	}

	// Walk substitutions in command arguments
	for _, w := range ce.Args {
		walkSubstitutionsInWord(w, commands)
	}

	// Extract literal argument strings
	args := make([]string, 0, len(ce.Args))
	for _, w := range ce.Args {
		args = append(args, wordToLiteral(w))
	}

	// Strip transparent prefixes
	args = stripPrefixes(args)
	if len(args) == 0 {
		return
	}

	cmd := args[0]

	// Handle shell interpreters: bash/sh/dash/zsh/ksh -c 'command'
	if shellInterpreters[cmd] {
		if inner, ok := extractShellCArg(args); ok {
			recursiveParse(inner, commands)
			return
		}
	}

	// Handle eval: recursively parse all remaining arguments
	if cmd == "eval" && len(args) > 1 {
		inner := strings.Join(args[1:], " ")
		recursiveParse(inner, commands)
		return
	}

	// Handle env -S: recursively parse the -S argument
	if cmd == "env" {
		if inner, ok := extractEnvSArg(args[1:]); ok {
			recursiveParse(inner, commands)
			return
		}
	}

	// Normal command: add the full normalized command string
	*commands = append(*commands, strings.Join(args, " "))
}

// wordToLiteral extracts the literal text from a Word, stripping quotes.
// Non-literal parts (expansions) are omitted.
func wordToLiteral(w *syntax.Word) string {
	var sb strings.Builder
	wordPartsToLiteral(w.Parts, &sb)
	return sb.String()
}

func wordPartsToLiteral(parts []syntax.WordPart, sb *strings.Builder) {
	for _, part := range parts {
		switch p := part.(type) {
		case *syntax.Lit:
			sb.WriteString(p.Value)
		case *syntax.SglQuoted:
			sb.WriteString(p.Value)
		case *syntax.DblQuoted:
			wordPartsToLiteral(p.Parts, sb)
		}
	}
}

// stripPrefixes removes transparent prefix commands, their flags,
// and env-var assignments from the argument list.
// Also strips ! (negation) and time keywords that the parser may place
// in Args when assignments precede them.
func stripPrefixes(args []string) []string {
	for len(args) > 0 {
		cmd := args[0]

		// Strip ! and time keywords (appear as args when preceded by assignments)
		if cmd == "!" || cmd == "time" {
			args = args[1:]
			continue
		}

		if cmd == "env" {
			// If env has -S, don't strip — let processCallExpr handle it
			if _, ok := extractEnvSArg(args[1:]); ok {
				break
			}
			args = stripEnvPrefix(args[1:])
			continue
		}

		if transparentPrefixes[cmd] {
			args = args[1:]
			args = stripFlagsForPrefix(cmd, args)
			continue
		}

		if isEnvAssignment(cmd) {
			args = args[1:]
			continue
		}

		break
	}
	return args
}

// isEnvAssignment returns true if s matches NAME=value or NAME+=value.
func isEnvAssignment(s string) bool {
	for i := 0; i < len(s); i++ {
		c := s[i]
		if c == '=' {
			return i > 0
		}
		if c == '+' && i > 0 && i+1 < len(s) && s[i+1] == '=' {
			return true
		}
		if i == 0 {
			if !isLetter(c) && c != '_' {
				return false
			}
		} else {
			if !isLetterOrDigit(c) && c != '_' {
				return false
			}
		}
	}
	return false
}

func isLetter(c byte) bool {
	return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

func isLetterOrDigit(c byte) bool {
	return isLetter(c) || (c >= '0' && c <= '9')
}

// stripEnvPrefix handles env's flag grammar:
// env [-i] [-0] [-u NAME] [-C dir] [--] [NAME=val]... COMMAND
func stripEnvPrefix(args []string) []string {
	i := 0
	for i < len(args) {
		a := args[i]
		if !strings.HasPrefix(a, "-") {
			break
		}
		if a == "--" {
			i++
			break
		}
		// Flags that take an argument: -u, -C
		if a == "-u" || a == "-C" {
			i += 2
			continue
		}
		// -S and --split-string are handled by extractEnvSArg
		if a == "-S" || strings.HasPrefix(a, "-S") || a == "--split-string" || strings.HasPrefix(a, "--split-string=") {
			// Don't strip past -S; let the caller handle it
			return args[i:]
		}
		i++
	}
	// Skip NAME=val assignments
	for i < len(args) && isEnvAssignment(args[i]) {
		i++
	}
	if i >= len(args) {
		return nil
	}
	return args[i:]
}

// stripFlagsForPrefix strips leading flags after a transparent prefix.
func stripFlagsForPrefix(prefix string, args []string) []string {
	i := 0
	for i < len(args) {
		if !strings.HasPrefix(args[i], "-") {
			break
		}
		if args[i] == "--" {
			i++
			break
		}
		// exec -a takes a name argument
		if prefix == "exec" && args[i] == "-a" && i+1 < len(args) {
			i += 2
			continue
		}
		// sudo -u, sudo -g, sudo -C take arguments
		if prefix == "sudo" && (args[i] == "-u" || args[i] == "-g" || args[i] == "-C") && i+1 < len(args) {
			i += 2
			continue
		}
		// nice -n takes a priority argument
		if prefix == "nice" && args[i] == "-n" && i+1 < len(args) {
			i += 2
			continue
		}
		// strace -p takes a PID argument, -e takes an expression
		if prefix == "strace" && (args[i] == "-p" || args[i] == "-e" || args[i] == "-o") && i+1 < len(args) {
			i += 2
			continue
		}
		i++
	}
	if i >= len(args) {
		return nil
	}
	return args[i:]
}

// extractShellCArg finds -c argument in a shell interpreter invocation.
func extractShellCArg(args []string) (string, bool) {
	for i := 1; i < len(args); i++ {
		a := args[i]
		if a == "-c" && i+1 < len(args) {
			return args[i+1], true
		}
		// Handle combined flags like -lc
		if strings.HasPrefix(a, "-") && !strings.HasPrefix(a, "--") &&
			strings.HasSuffix(a, "c") && len(a) > 2 {
			if i+1 < len(args) {
				return args[i+1], true
			}
		}
	}
	return "", false
}

// extractEnvSArg finds -S / --split-string argument in env args.
func extractEnvSArg(args []string) (string, bool) {
	for i := 0; i < len(args); i++ {
		a := args[i]
		if a == "-S" || a == "--split-string" {
			if i+1 < len(args) {
				return args[i+1], true
			}
		}
		if strings.HasPrefix(a, "-S") && len(a) > 2 {
			return a[2:], true
		}
		if strings.HasPrefix(a, "--split-string=") {
			return strings.TrimPrefix(a, "--split-string="), true
		}
	}
	return "", false
}

// walkSubstitutionsInWord finds CmdSubst and ProcSubst within a Word
// and extracts commands from their statement lists.
func walkSubstitutionsInWord(w *syntax.Word, commands *[]string) {
	if w == nil {
		return
	}
	walkSubstitutionsInParts(w.Parts, commands)
}

func walkSubstitutionsInParts(parts []syntax.WordPart, commands *[]string) {
	for _, part := range parts {
		switch p := part.(type) {
		case *syntax.CmdSubst:
			for _, s := range p.Stmts {
				extractFromStmt(s, commands)
			}
		case *syntax.ProcSubst:
			for _, s := range p.Stmts {
				extractFromStmt(s, commands)
			}
		case *syntax.DblQuoted:
			walkSubstitutionsInParts(p.Parts, commands)
		case *syntax.ParamExp:
			// ${var:-$(cmd)} — walk the default/replacement words
			if p.Exp != nil && p.Exp.Word != nil {
				walkSubstitutionsInWord(p.Exp.Word, commands)
			}
		case *syntax.ArithmExp:
			// $((expr)) — walk arithmetic expression for nested CmdSubst
			walkArithmExpr(p.X, commands)
		}
	}
}

// walkArithmExpr recursively walks an arithmetic expression tree
// looking for Word nodes that may contain CmdSubst or ProcSubst.
func walkArithmExpr(expr syntax.ArithmExpr, commands *[]string) {
	if expr == nil {
		return
	}
	switch e := expr.(type) {
	case *syntax.BinaryArithm:
		walkArithmExpr(e.X, commands)
		walkArithmExpr(e.Y, commands)
	case *syntax.UnaryArithm:
		walkArithmExpr(e.X, commands)
	case *syntax.ParenArithm:
		walkArithmExpr(e.X, commands)
	case *syntax.Word:
		walkSubstitutionsInWord(e, commands)
	}
}

// recursiveParse parses a string as shell code and extracts commands.
func recursiveParse(code string, commands *[]string) {
	parser := syntax.NewParser(syntax.Variant(syntax.LangBash))
	file, err := parser.Parse(strings.NewReader(code), "")
	if err != nil {
		// Parse error in nested code: treat the raw string as a command
		// so rules can still match it (fail closed).
		*commands = append(*commands, code)
		return
	}
	extractFromFile(file, commands)
}
