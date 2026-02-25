#!/bin/bash
# session-cleanup.sh — Stop hook
# Captures session context for continuity and cleans up stale artifacts.
# Universal: works for any project without configuration.

json=$(cat)

session_id=$(echo "$json" | jq -r '.session_id // "unknown"')
stop_reason=$(echo "$json" | jq -r '.stop_reason // "unknown"')

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
claude_dir="$repo_root/.claude"

# --- Memory capture ---
# Write a last-session snapshot so context-loader.sh (or a human) can pick up where we left off.

memory_file="$claude_dir/last-session.json"
mkdir -p "$claude_dir"

snapshot="{}"

# Git state at session end
if git rev-parse --is-inside-work-tree &>/dev/null; then
  branch=$(git branch --show-current 2>/dev/null)
  dirty_files=$(git status --porcelain 2>/dev/null | head -20)
  dirty_count=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  last_commit=$(git log --oneline -1 2>/dev/null)

  snapshot=$(echo "$snapshot" | jq \
    --arg sid "$session_id" \
    --arg ts "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    --arg reason "$stop_reason" \
    --arg branch "$branch" \
    --arg dirty_count "$dirty_count" \
    --arg dirty "$dirty_files" \
    --arg last_commit "$last_commit" \
    '{
      session_id: $sid,
      ended_at: $ts,
      stop_reason: $reason,
      branch: $branch,
      uncommitted_files: ($dirty_count | tonumber),
      dirty_files: ($dirty | split("\n") | map(select(length > 0))),
      last_commit: $last_commit
    }')
else
  snapshot=$(echo "$snapshot" | jq \
    --arg sid "$session_id" \
    --arg ts "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    --arg reason "$stop_reason" \
    '{session_id: $sid, ended_at: $ts, stop_reason: $reason}')
fi

echo "$snapshot" > "$memory_file"

# --- Cleanup ---

# Prune empty or zero-byte log files
find "$claude_dir" -maxdepth 1 -name "*.log" -empty -delete 2>/dev/null

# Prune stale transcript backups (redundant safety — pre-compact-backup.sh also prunes)
backup_dir="$claude_dir/transcript-backups"
if [ -d "$backup_dir" ]; then
  find "$backup_dir" -name "*.jsonl" -mtime +7 -delete 2>/dev/null
fi

exit 0
