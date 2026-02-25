#!/bin/bash
# affected-tests.sh — PostToolUse hook for Edit|Write
# Finds and runs tests related to the edited file, feeds results back to Claude.
# TEMPLATE: Customize test discovery and runner for your project.

json=$(cat)
file_path=$(echo "$json" | jq -r '.tool_input.file_path // empty')

if [ -z "$file_path" ] || [ ! -f "$file_path" ]; then
  exit 0
fi

# Skip non-source files
if [[ "$file_path" =~ \.(md|txt|json|yaml|yml|toml|lock|log|csv)$ ]]; then
  exit 0
fi

test_file=""
test_cmd=""

# --- JavaScript/TypeScript ---
if [[ "$file_path" =~ \.(js|ts|jsx|tsx)$ ]]; then
  # Skip if this IS a test file
  if [[ "$file_path" =~ \.(test|spec)\.(js|ts|jsx|tsx)$ ]]; then
    test_file="$file_path"
  else
    # Look for co-located test file
    base="${file_path%.*}"
    ext="${file_path##*.}"
    for suffix in ".test.$ext" ".spec.$ext"; do
      candidate="${base}${suffix}"
      if [ -f "$candidate" ]; then
        test_file="$candidate"
        break
      fi
    done
    # Look in __tests__ directory
    if [ -z "$test_file" ]; then
      dir=$(dirname "$file_path")
      name=$(basename "${file_path%.*}")
      ext="${file_path##*.}"
      candidate="$dir/__tests__/$name.test.$ext"
      if [ -f "$candidate" ]; then
        test_file="$candidate"
      fi
    fi
  fi
  if [ -n "$test_file" ]; then
    if [ -f "node_modules/.bin/jest" ]; then
      test_cmd="npx jest '$test_file' --silent --no-coverage 2>&1"
    elif [ -f "node_modules/.bin/vitest" ]; then
      test_cmd="npx vitest run '$test_file' --silent 2>&1"
    fi
  fi

# --- Python ---
elif [[ "$file_path" =~ \.py$ ]]; then
  if [[ "$file_path" =~ test_ ]] || [[ "$file_path" =~ _test\.py$ ]]; then
    test_file="$file_path"
  else
    dir=$(dirname "$file_path")
    name=$(basename "${file_path%.py}")
    for candidate in "$dir/test_$name.py" "$dir/${name}_test.py" "$dir/tests/test_$name.py" "tests/test_$name.py"; do
      if [ -f "$candidate" ]; then
        test_file="$candidate"
        break
      fi
    done
  fi
  if [ -n "$test_file" ]; then
    if command -v pytest &>/dev/null; then
      test_cmd="PYTHONPATH=. pytest '$test_file' -x -q 2>&1"
    fi
  fi

# --- Go ---
elif [[ "$file_path" =~ \.go$ ]]; then
  if [[ "$file_path" =~ _test\.go$ ]]; then
    test_file="$file_path"
  else
    candidate="${file_path%.go}_test.go"
    if [ -f "$candidate" ]; then
      test_file="$candidate"
    fi
  fi
  if [ -n "$test_file" ]; then
    test_dir=$(dirname "$test_file")
    test_cmd="go test './$test_dir' -count=1 -short 2>&1"
  fi
fi

# Run the test if found
if [ -n "$test_cmd" ]; then
  # Use gtimeout on macOS (coreutils), timeout on Linux, fallback to no timeout
  timeout_cmd=""
  if command -v timeout &>/dev/null; then
    timeout_cmd="timeout 30"
  elif command -v gtimeout &>/dev/null; then
    timeout_cmd="gtimeout 30"
  fi
  test_output=$($timeout_cmd bash -c "$test_cmd" 2>&1)
  test_exit=$?

  if [ $test_exit -ne 0 ]; then
    # Truncate long output
    if [ ${#test_output} -gt 2000 ]; then
      test_output="${test_output:0:1997}..."
    fi
    # Escape for JSON (prepend label before escaping so it's one valid JSON string)
    test_output=$(printf "Test failures after editing %s:\n%s" "$file_path" "$test_output" | jq -Rs '.')
    echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PostToolUse\",\"additionalContext\":$test_output}}"
  fi
fi

exit 0
