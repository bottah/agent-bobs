#!/bin/bash
# audit-logger.sh — PostToolUse hook for all tools
# Appends a structured JSON log entry for every tool invocation.
# Universal: works for any project. Logs to .claude/audit.log by default.

json=$(cat)

# Extract fields
timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
session_id=$(echo "$json" | jq -r '.session_id // "unknown"')
tool_name=$(echo "$json" | jq -r '.tool_name // "unknown"')
tool_input=$(echo "$json" | jq -c '.tool_input // {}')

# Log directory (project-local)
log_dir="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/.claude"
log_file="$log_dir/audit.log"

# Ensure log directory exists
mkdir -p "$log_dir"

# Build log entry as valid JSON (jq handles escaping; truncate via string slice)
echo "$json" | jq -c --arg ts "$timestamp" --arg sid "$session_id" --arg tool "$tool_name" \
  '{ts: $ts, session: $sid, tool: $tool, input: (.tool_input // {} | tostring[:500])}' \
  >> "$log_file"

# Never block — just log
exit 0
