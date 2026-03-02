#!/bin/bash
# tool-policy.sh — PreToolUse hook for Bash
# Thin wrapper: reads command from stdin JSON, invokes the cmdpolicy Go binary.
# The binary parses shell AST via mvdan.cc/sh, extracts all executable sites,
# and matches against rules in tool-policy.json.
# Configure via scripts/hooks/tool-policy.json.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
POLICY_FILE="$SCRIPT_DIR/tool-policy.json"
BINARY="$SCRIPT_DIR/cmdpolicy/cmdpolicy"

# If no policy file, allow everything
if [ ! -f "$POLICY_FILE" ]; then
  exit 0
fi

json=$(cat)
command=$(echo "$json" | jq -r '.tool_input.command // empty')

if [ -z "$command" ]; then
  exit 0
fi

# Auto-build binary on first use
if [ ! -x "$BINARY" ]; then
  if ! command -v go >/dev/null 2>&1; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Tool policy: Go toolchain not available; cannot build cmdpolicy binary."}}'
    exit 0
  fi
  if ! (cd "$SCRIPT_DIR/cmdpolicy" && go build -o cmdpolicy . 2>&1); then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Tool policy: failed to build cmdpolicy binary."}}'
    exit 0
  fi
fi

# Invoke the binary and pass stdout through.
# Non-zero exit (binary crash, etc.) → fail closed.
result=$("$BINARY" -policy "$POLICY_FILE" "$command" 2>/dev/null) || {
  echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Tool policy: cmdpolicy binary error."}}'
  exit 0
}
if [ -n "$result" ]; then
  echo "$result"
fi
