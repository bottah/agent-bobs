#!/bin/bash
# beads-logger.sh — PostToolUse hook for Bash
# Logs bd (beads) CLI invocations to .claude/beads-audit.log.
# Template: beads-specific audit trail for the code review workflow.

json=$(cat)

# Only log Bash tool invocations
tool_name=$(echo "$json" | jq -r '.tool_name // empty')
if [ "$tool_name" != "Bash" ]; then
  exit 0
fi

# Only log bd commands
command=$(echo "$json" | jq -r '.tool_input.command // empty')
if ! echo "$command" | grep -q '^bd '; then
  exit 0
fi

# Extract fields
timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
session_id=$(echo "$json" | jq -r '.session_id // "unknown"')
bd_subcmd=$(echo "$command" | awk '{print $2}')

# Log directory (project-local)
log_dir="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/.claude"
log_file="$log_dir/beads-audit.log"

# Ensure log directory exists
mkdir -p "$log_dir"

# Build log entry as valid JSON (truncate command to 500 chars)
echo "$json" | jq -c --arg ts "$timestamp" --arg sid "$session_id" --arg subcmd "$bd_subcmd" \
  '{ts: $ts, session: $sid, tool: "bd", subcmd: $subcmd, command: (.tool_input.command // "" | .[0:500])}' \
  >> "$log_file" 2>/dev/null

# Never block — just log
exit 0
