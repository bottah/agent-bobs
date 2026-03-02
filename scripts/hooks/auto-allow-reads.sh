#!/bin/bash
# auto-allow-reads.sh — PermissionRequest hook
# Auto-allows read-only tools and safe bash commands to reduce permission dialog friction.
# Universal: only allows operations that cannot modify state.

json=$(cat)

tool_name=$(echo "$json" | jq -r '.tool_name // empty')
command=$(echo "$json" | jq -r '.tool_input.command // empty')

# Read-only tools — always safe
case "$tool_name" in
  Read|Glob|Grep|WebSearch|WebFetch)
    echo '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}'
    exit 0
    ;;
esac

# Safe bash commands — read-only operations only
if [ "$tool_name" = "Bash" ] && [ -n "$command" ]; then
  # Reject anything with shell operators that could chain or embed writes
  # (pipes, redirections, command chaining, command substitution, etc.)
  if echo "$command" | grep -qE '>\s|>>|[|]|&&|;|\|\||\$\(|`' ; then
    # Contains shell operator — not safe, let the normal permission flow handle it
    exit 0
  fi

  # Extract the base command (first word, ignoring env vars and flags)
  base_cmd=$(echo "$command" | sed 's/^[A-Z_]*=[^ ]* *//' | awk '{print $1}')

  # Safe read-only commands
  case "$base_cmd" in
    ls|cat|head|tail|wc|file|which|whoami|pwd|date|uname)
      echo '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}'
      exit 0
      ;;
    git)
      # Only allow read-only git subcommands
      # Strip "git" prefix and any -C <path> / -c key=val flags to find the subcommand
      git_subcmd=$(echo "$command" | sed 's/^git //' | sed 's/^-[Cc] *[^ ]* *//' | awk '{print $1}')
      case "$git_subcmd" in
        status|log|diff|show|branch|tag|remote|stash|rev-parse|describe|shortlog|blame)
          echo '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}'
          exit 0
          ;;
      esac
      ;;
    node|python|python3)
      # Only allow version checks
      if echo "$command" | grep -qE '^(node|python3?)\s+--version$'; then
        echo '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}'
        exit 0
      fi
      ;;
    gh)
      # Only allow read operations
      gh_subcmd=$(echo "$command" | sed 's/^gh //' | awk '{print $1, $2}')
      case "$gh_subcmd" in
        pr\ view|pr\ list|pr\ checks|pr\ diff|issue\ view|issue\ list|repo\ view|run\ list|run\ view)
          echo '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}'
          exit 0
        ;;
      esac
      ;;
    bd)
      # Only allow read-only bd (beads) subcommands
      bd_subcmd=$(echo "$command" | sed 's/^bd //' | awk '{print $1}')
      case "$bd_subcmd" in
        ready|show|list)
          echo '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}'
          exit 0
        ;;
      esac
      ;;
  esac
fi

# Everything else — defer to normal permission flow
exit 0
