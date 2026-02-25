#!/bin/bash
# post-edit-lint.sh — PostToolUse hook for Edit|Write
# Runs the project linter on the edited file and feeds errors back to Claude.
# TEMPLATE: Customize the linter commands for your project.

json=$(cat)
file_path=$(echo "$json" | jq -r '.tool_input.file_path // empty')

if [ -z "$file_path" ] || [ ! -f "$file_path" ]; then
  exit 0
fi

lint_output=""
lint_exit=0

# --- JavaScript/TypeScript ---
if [[ "$file_path" =~ \.(js|ts|jsx|tsx|mjs|cjs)$ ]]; then
  if command -v npx &>/dev/null && [ -f "node_modules/.bin/eslint" ]; then
    lint_output=$(npx eslint "$file_path" --no-warn-ignored 2>&1)
    lint_exit=$?
  fi

# --- Python ---
elif [[ "$file_path" =~ \.py$ ]]; then
  if command -v black &>/dev/null; then
    fmt_output=$(black --check --quiet "$file_path" 2>&1)
    if [ $? -ne 0 ]; then
      black --quiet "$file_path" 2>/dev/null
      lint_output="black reformatted $file_path"
      lint_exit=1
    fi
  fi
  if command -v isort &>/dev/null; then
    isort_output=$(isort --check --quiet "$file_path" 2>&1)
    if [ $? -ne 0 ]; then
      isort --quiet "$file_path" 2>/dev/null
      lint_output="${lint_output:+$lint_output\n}isort reformatted $file_path"
      lint_exit=1
    fi
  fi
  if command -v ruff &>/dev/null; then
    ruff_output=$(ruff check "$file_path" 2>&1)
    if [ $? -ne 0 ]; then
      lint_output="${lint_output:+$lint_output\n}$ruff_output"
      lint_exit=1
    fi
  elif command -v flake8 &>/dev/null; then
    flake8_output=$(flake8 "$file_path" 2>&1)
    if [ $? -ne 0 ]; then
      lint_output="${lint_output:+$lint_output\n}$flake8_output"
      lint_exit=1
    fi
  fi

# --- Rust ---
elif [[ "$file_path" =~ \.rs$ ]]; then
  # Rust clippy is too slow for a hook — skip by default
  # Uncomment if you want it (set timeout to 120+ in settings):
  # lint_output=$(cargo clippy --message-format short 2>&1)
  # lint_exit=$?
  exit 0

# --- Go ---
elif [[ "$file_path" =~ \.go$ ]]; then
  if command -v golangci-lint &>/dev/null; then
    lint_output=$(golangci-lint run "$file_path" 2>&1)
    lint_exit=$?
  fi
fi

# Feed lint errors back to Claude as context
if [ $lint_exit -ne 0 ] && [ -n "$lint_output" ]; then
  # Truncate to avoid flooding context
  if [ ${#lint_output} -gt 2000 ]; then
    lint_output="${lint_output:0:1997}..."
  fi
  # Escape for JSON (prepend label before escaping so it's one valid JSON string)
  lint_output=$(printf "Lint errors in %s:\n%s" "$file_path" "$lint_output" | jq -Rs '.')
  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PostToolUse\",\"additionalContext\":$lint_output}}"
fi

exit 0
