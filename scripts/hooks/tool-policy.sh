#!/bin/bash
# tool-policy.sh — PreToolUse hook for Bash
# Whitelist model: only git and gh commands are allowed.
# Agents communicate via git/gh interface only.

json=$(cat)
command=$(echo "$json" | jq -r '.tool_input.command // empty')

if [ -z "$command" ]; then
  exit 0
fi

deny() {
  local reason="$1"
  local escaped
  escaped=$(printf '%s' "Tool policy: $reason" | jq -Rs .)
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' "$escaped"
  exit 0
}

# ── Reject command/process substitution ──────────────────────────────────
case "$command" in
  *'$('*)  deny "Command substitution is not allowed." ;;
  *'`'*)   deny "Backtick substitution is not allowed." ;;
  *'<('*)  deny "Process substitution is not allowed." ;;
  *'>('*)  deny "Process substitution is not allowed." ;;
esac

# ── Explicit deny rules ─────────────────────────────────────────────────

# Block push to main/master
if echo "$command" | grep -qE '^git push .* (main|master)($|:| )'; then
  deny "Push to main/master is blocked. Push to a feature branch instead."
fi

# Block pr merge without --squash
if echo "$command" | grep -qE '^gh pr merge' && ! echo "$command" | grep -q -- '--squash'; then
  deny "Use --squash flag for PR merges to maintain linear history."
fi

# ── Whitelist: git and gh only ───────────────────────────────────────────

allowed_patterns=(
  '^git '
  '^git$'
  '^gh '
)

for pattern in "${allowed_patterns[@]}"; do
  if echo "$command" | grep -qE "$pattern"; then
    exit 0
  fi
done

# Default: deny
deny "Only git and gh commands are allowed."
