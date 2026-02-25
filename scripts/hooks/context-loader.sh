#!/bin/bash
# context-loader.sh — SessionStart hook
# Injects project context (git state, recent activity) at the start of each session.
# TEMPLATE: Add project-specific context as needed.

# Only useful inside a git repo
if ! git rev-parse --is-inside-work-tree &>/dev/null; then
  exit 0
fi

context=""

# Current branch
branch=$(git branch --show-current 2>/dev/null)
if [ -n "$branch" ]; then
  context+="Branch: $branch\n"
fi

# Uncommitted changes summary
status=$(git status --porcelain 2>/dev/null)
if [ -n "$status" ]; then
  modified=$(echo "$status" | grep -c '^ M\|^M ')
  added=$(echo "$status" | grep -c '^A \|^??')
  deleted=$(echo "$status" | grep -c '^ D\|^D ')
  context+="Uncommitted changes: ${modified} modified, ${added} added/untracked, ${deleted} deleted\n"
else
  context+="Working tree: clean\n"
fi

# Recent commits (last 5)
recent=$(git log --oneline -5 2>/dev/null)
if [ -n "$recent" ]; then
  context+="Recent commits:\n$recent\n"
fi

# Stash count
stash_count=$(git stash list 2>/dev/null | wc -l | tr -d ' ')
if [ "$stash_count" -gt 0 ]; then
  context+="Stashes: $stash_count\n"
fi

# Previous session context (written by session-cleanup.sh)
repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
last_session="$repo_root/.claude/last-session.json"
if [ -f "$last_session" ]; then
  prev_branch=$(jq -r '.branch // empty' "$last_session" 2>/dev/null)
  prev_reason=$(jq -r '.stop_reason // empty' "$last_session" 2>/dev/null)
  prev_uncommitted=$(jq -r '.uncommitted_files // 0' "$last_session" 2>/dev/null)
  prev_commit=$(jq -r '.last_commit // empty' "$last_session" 2>/dev/null)
  prev_ended=$(jq -r '.ended_at // empty' "$last_session" 2>/dev/null)
  if [ -n "$prev_ended" ]; then
    context+="Previous session ended: $prev_ended (reason: $prev_reason)\n"
    if [ -n "$prev_branch" ] && [ "$prev_branch" != "$branch" ]; then
      context+="Note: branch changed since last session ($prev_branch -> $branch)\n"
    fi
    if [ "$prev_uncommitted" -gt 0 ]; then
      context+="Previous session left $prev_uncommitted uncommitted files\n"
    fi
  fi
fi

# Output context for Claude
if [ -n "$context" ]; then
  context=$(echo -e "$context" | jq -Rs '.')
  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"additionalContext\":$context}}"
fi

exit 0
