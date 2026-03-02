#!/bin/bash
# tool-policy.sh — PreToolUse hook for Bash
# Whitelist model: allow only known command patterns, deny everything else.
# No shell parsing. No human in the loop.

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
# These embed executable code inside arguments — block unconditionally.
case "$command" in
  *'$('*)  deny "Command substitution \$() is not allowed." ;;
  *'`'*)   deny "Backtick substitution is not allowed." ;;
  *'<('*)  deny "Process substitution <() is not allowed." ;;
  *'>('*)  deny "Process substitution >() is not allowed." ;;
esac

# ── Explicit deny rules ─────────────────────────────────────────────────

# Block push to main/master
if echo "$command" | grep -qE '^git push .*(main|master)'; then
  deny "Push to main/master is blocked. Push to a feature branch instead."
fi

# Block pr merge without --squash
if echo "$command" | grep -qE '^gh pr merge' && ! echo "$command" | grep -q -- '--squash'; then
  deny "Use --squash flag for PR merges to maintain linear history."
fi

# ── Whitelist ────────────────────────────────────────────────────────────

allowed_patterns=(
  # Git
  '^git '
  '^git$'

  # GitHub CLI
  '^gh '

  # Scripts and shell
  '^\./scripts/'
  '^bash '
  '^sh '
  '^source '

  # Build / test
  '^go (build|test|mod|vet|fmt|run|install|get|doc|env)'
  '^(npm|npx|yarn|bun|pnpm) '
  '^(node|python3?|ruby|cargo|make|cmake) '

  # Common CLI tools
  '^(cat|ls|head|tail|wc|file|which|whoami|pwd|date|uname|find|mkdir|sort|tr|cut|sed|awk|jq|dirname|basename|realpath|tee|touch|chmod|test|true|false|echo|printf|rm|cp|mv|diff|comm|uniq|xargs|tar|gzip|gunzip|zip|unzip|grep|rg|fd|fzf|curl|wget|sleep|env|cd|pushd|popd|read|set|export|unset|mktemp|stat|readlink|open|less|more|column|rev|shuf|seq|yes|timeout|install|ln) '
  '^(cat|ls|head|tail|wc|file|which|whoami|pwd|date|uname|echo|printf|true|false|set|env|cd) *$'

  # Beads
  '^bd '
  '^bd$'
)

for pattern in "${allowed_patterns[@]}"; do
  if echo "$command" | grep -qE "$pattern"; then
    exit 0
  fi
done

# Default: deny
deny "Command not on the allowlist. Only approved git, gh, and build commands are permitted."
