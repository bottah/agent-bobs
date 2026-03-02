#!/bin/bash
# context-loader.sh — SessionStart hook
# Injects project context (git state, recent activity) at the start of each session.
# TEMPLATE: Add project-specific context as needed.

# Only useful inside a git repo
if ! git rev-parse --is-inside-work-tree &>/dev/null; then
  exit 0
fi

context=""
repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# Current branch
branch=$(git branch --show-current 2>/dev/null)
if [ -n "$branch" ]; then
  context+="Branch: $branch\n"
  if [ "$branch" = "main" ] || [ "$branch" = "master" ]; then
    context+="WARNING: You are on the $branch branch. Use /branch to create a feature branch before making changes. Direct commits to $branch are blocked by skill guards and hook policies.\n"
  fi
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

# Beads status (if bd CLI is available)
if command -v bd &>/dev/null; then
  # Active review beads (open or in_progress) — identified by type:review label
  active_reviews=$(bd list --json 2>/dev/null | jq -r '[.[] | select((.labels // [] | index("type:review")) and (.status == "open" or .status == "in_progress"))] | length' 2>/dev/null)
  if [ -n "$active_reviews" ] && [ "$active_reviews" -gt 0 ]; then
    review_details=$(bd list --json 2>/dev/null | jq -r '[.[] | select((.labels // [] | index("type:review")) and (.status == "open" or .status == "in_progress"))] | .[] | "  \(.id): \(.title) [cycle \(.metadata.cycle // "?"), reviewer: \(.metadata.reviewer // "?"), status: \(.status)]"' 2>/dev/null)
    context+="Active review beads ($active_reviews):\n$review_details\n"
  fi
  # In-progress feature beads
  feature_count=$(bd list --json 2>/dev/null | jq -r '[.[] | select(.issue_type == "feature" and .status == "in_progress")] | length' 2>/dev/null)
  if [ -n "$feature_count" ] && [ "$feature_count" -gt 0 ]; then
    context+="In-progress feature beads: $feature_count\n"
  fi
fi

# Ruleset drift check (if .github/ruleset.json exists)
ruleset_file="$repo_root/.github/ruleset.json"
if [ -f "$ruleset_file" ] && command -v gh &>/dev/null && command -v jq &>/dev/null; then
  repo=$(git remote get-url origin 2>/dev/null | sed -E 's|(\.git)$||; s|.*[:/]([^/]+/[^/]+)$|\1|')
  if [ -n "$repo" ]; then
    local_name=$(jq -r '.ruleset.name // empty' "$ruleset_file" 2>/dev/null)
    if [ -n "$local_name" ]; then
      # Fetch remote rulesets (fail open — skip silently on auth or network errors)
      remote_rulesets=$(gh api "repos/$repo/rulesets" 2>/dev/null) || remote_rulesets=""
      if [ -n "$remote_rulesets" ]; then
        remote_match=$(echo "$remote_rulesets" | jq -r --arg name "$local_name" '[.[] | select(.name == $name)] | first // empty' 2>/dev/null)
        if [ -z "$remote_match" ] || [ "$remote_match" = "null" ]; then
          context+="WARNING: .github/ruleset.json defines '$local_name' but no matching GitHub ruleset found. Run /protect to apply.\n"
        else
          # Compare key parameters: required_approving_review_count and enforcement
          remote_id=$(echo "$remote_match" | jq -r '.id' 2>/dev/null)
          remote_detail=$(gh api "repos/$repo/rulesets/$remote_id" 2>/dev/null) || remote_detail=""
          if [ -n "$remote_detail" ]; then
            local_review_count=$(jq -r '.ruleset.rules[]? | select(.type == "pull_request") | .parameters.required_approving_review_count // empty' "$ruleset_file" 2>/dev/null)
            remote_review_count=$(echo "$remote_detail" | jq -r '.rules[]? | select(.type == "pull_request") | .parameters.required_approving_review_count // empty' 2>/dev/null)
            local_enforcement=$(jq -r '.ruleset.enforcement // empty' "$ruleset_file" 2>/dev/null)
            remote_enforcement=$(echo "$remote_detail" | jq -r '.enforcement // empty' 2>/dev/null)
            drift=""
            if [ -n "$local_review_count" ] && [ -n "$remote_review_count" ] && [ "$local_review_count" != "$remote_review_count" ]; then
              drift+="required_approving_review_count: local=$local_review_count, remote=$remote_review_count; "
            fi
            if [ -n "$local_enforcement" ] && [ -n "$remote_enforcement" ] && [ "$local_enforcement" != "$remote_enforcement" ]; then
              drift+="enforcement: local=$local_enforcement, remote=$remote_enforcement; "
            fi
            if [ -n "$drift" ]; then
              context+="WARNING: GitHub ruleset '$local_name' differs from .github/ruleset.json — ${drift}Run /protect to sync.\n"
            fi
          fi
        fi
      fi
    fi
  fi
fi

# Previous session context (written by session-cleanup.sh)
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
