#!/bin/bash
# tool-policy.sh — PreToolUse hook for Bash
# Intercepts blocked commands and suggests alternatives.
# Configure via scripts/hooks/tool-policy.json.
# Template: ships with empty rules; developers add their own.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
POLICY_FILE="$SCRIPT_DIR/tool-policy.json"

# If no policy file, allow everything
if [ ! -f "$POLICY_FILE" ]; then
  exit 0
fi

json=$(cat)
command=$(echo "$json" | jq -r '.tool_input.command // empty')

if [ -z "$command" ]; then
  exit 0
fi

# Read each rule from the policy file
# Each rule has: "match" (substring or regex), "message" (what to tell the agent)
rule_count=$(jq '.rules | length' "$POLICY_FILE" 2>/dev/null)

if [ -z "$rule_count" ] || [ "$rule_count" = "0" ] || [ "$rule_count" = "null" ]; then
  exit 0
fi

i=0
while [ "$i" -lt "$rule_count" ]; do
  match=$(jq -r ".rules[$i].match // empty" "$POLICY_FILE")
  message=$(jq -r ".rules[$i].message // empty" "$POLICY_FILE")
  mode=$(jq -r ".rules[$i].mode // \"substring\"" "$POLICY_FILE")

  if [ -n "$match" ]; then
    blocked=false

    if [ "$mode" = "regex" ]; then
      if echo "$command" | grep -qE "$match"; then
        blocked=true
      fi
    else
      # Default: substring match (word-boundary aware via grep -w where possible)
      if echo "$command" | grep -qw "$match" 2>/dev/null || [[ "$command" == *"$match"* ]]; then
        blocked=true
      fi
    fi

    if [ "$blocked" = true ]; then
      # Escape message for JSON
      escaped_message=$(echo "$message" | sed 's/"/\\"/g')
      echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"Tool policy: $escaped_message\"}}"
      exit 0
    fi
  fi

  i=$((i + 1))
done

# No rules matched — allow
exit 0
