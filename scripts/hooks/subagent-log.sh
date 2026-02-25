#!/bin/bash
# subagent-log.sh — SubagentStop hook
# Logs subagent/teammate completion for audit and debugging.
# Universal: structured logging only, no external dependencies.

json=$(cat)

session_id=$(echo "$json" | jq -r '.session_id // "unknown"')
agent_id=$(echo "$json" | jq -r '.agent_id // "unknown"')
agent_type=$(echo "$json" | jq -r '.agent_type // "unknown"')
stop_reason=$(echo "$json" | jq -r '.stop_reason // "unknown"')

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
log_file="$repo_root/.claude/subagent.log"

mkdir -p "$(dirname "$log_file")"

timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

echo "{\"ts\":\"$timestamp\",\"session\":\"$session_id\",\"agent_id\":\"$agent_id\",\"agent_type\":\"$agent_type\",\"stop_reason\":\"$stop_reason\"}" >> "$log_file"

exit 0
