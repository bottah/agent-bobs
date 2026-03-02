#!/bin/bash
# tool-policy.sh — PreToolUse hook for Bash
# Enforce rules on the git/gh agent-to-agent interface.
# Does NOT restrict other commands — that's not this hook's job.

json=$(cat)
command=$(echo "$json" | jq -r '.tool_input.command // empty')

[ -z "$command" ] && exit 0

deny() {
  local reason="$1"
  local escaped
  escaped=$(printf '%s' "Tool policy: $reason" | jq -Rs .)
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' "$escaped"
  exit 0
}

# Block push to main/master
if echo "$command" | grep -qE '^git push .* (main|master)($|:| )'; then
  deny "Push to main/master is blocked. Push to a feature branch instead."
fi

# Block pr merge without --squash
if echo "$command" | grep -qE '^gh pr merge' && ! echo "$command" | grep -q -- '--squash'; then
  deny "Use --squash flag for PR merges to maintain linear history."
fi
