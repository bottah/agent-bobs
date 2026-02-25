#!/bin/bash
# pre-compact-backup.sh — PreCompact hook
# Backs up the conversation transcript before context compression.
# Universal: preserves audit trail without configuration.

json=$(cat)

# Extract transcript path and session ID
transcript_path=$(echo "$json" | jq -r '.transcript_path // empty')
session_id=$(echo "$json" | jq -r '.session_id // "unknown"')

# Nothing to back up if no transcript
if [ -z "$transcript_path" ] || [ ! -f "$transcript_path" ]; then
  exit 0
fi

# Backup directory (project-local)
repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
backup_dir="$repo_root/.claude/transcript-backups"
mkdir -p "$backup_dir"

# Timestamped backup filename
timestamp=$(date -u +"%Y%m%dT%H%M%SZ")
backup_file="$backup_dir/${session_id}_${timestamp}.jsonl"

# Copy transcript
cp "$transcript_path" "$backup_file" 2>/dev/null

# Prune backups older than 7 days to prevent unbounded growth
find "$backup_dir" -name "*.jsonl" -mtime +7 -delete 2>/dev/null

exit 0
