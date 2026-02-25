#!/bin/bash
# desktop-notify.sh — Notification hook
# Sends a desktop notification when Claude Code is waiting for user input.
# Universal: uses native OS notifications, no dependencies.

json=$(cat)

message=$(echo "$json" | jq -r '.message // empty')

# Only fire for "waiting for input" notifications
if ! echo "$message" | grep -qi "waiting\|input\|needs your"; then
  exit 0
fi

title="Claude Code"
body="Agent is waiting for your input"

# macOS
if command -v osascript &>/dev/null; then
  osascript -e "display notification \"$body\" with title \"$title\"" 2>/dev/null &
# Linux (freedesktop)
elif command -v notify-send &>/dev/null; then
  notify-send "$title" "$body" 2>/dev/null &
fi

exit 0
