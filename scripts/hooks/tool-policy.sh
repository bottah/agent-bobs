#!/bin/bash
# tool-policy.sh — PreToolUse hook for Bash
# Intercepts blocked commands and suggests alternatives.
# Configure via scripts/hooks/tool-policy.json.
# Template: ships with empty rules; developers add their own.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
POLICY_FILE="$SCRIPT_DIR/tool-policy.json"

# If no policy file, allow everything
if [ ! -f "$POLICY_FILE" ]; then
  exit 0
fi

json=$(cat)
command=$(echo "$json" | jq -r '.tool_input.command // empty')

if [ -z "$command" ]; then
  exit 0
fi

# Normalize: strip leading env var assignments so anchored rules can't be
# bypassed by prefixing KEY=val. Walks the command character by character to
# handle quotes and escapes. Strips plain KEY=value prefixes; fails closed
# on values containing shell syntax ($(), backticks, etc.).
normalize_command_prefix() {
  local s="$1"
  local len=${#s}
  local i=0 start=0
  local c token value
  local in_s=0 in_d=0 esc=0

  # Skip leading horizontal whitespace.
  while (( i < len )); do
    c=${s:i:1}
    [[ $c == ' ' || $c == $'\t' ]] || break
    ((i++))
  done

  while (( i < len )); do
    start=$i
    in_s=0
    in_d=0
    esc=0
    local has_cmd_subst=0

    # Read one shell-ish token, honoring quotes and backslash escapes well
    # enough to find token boundaries without evaluating anything.
    # Track unescaped $( and backticks to detect command substitution.
    while (( i < len )); do
      c=${s:i:1}

      if (( esc )); then
        esc=0
        ((i++))
        continue
      fi

      if (( in_s )); then
        # Single quotes: everything is literal, no cmd subst possible
        [[ $c == "'" ]] && in_s=0
        ((i++))
        continue
      fi

      if (( in_d )); then
        case "$c" in
          \\) esc=1 ;;
          '"') in_d=0 ;;
          '$') # Check for $( inside double quotes (unescaped)
            # $((  = arithmetic expansion (safe), $( = command substitution
            if (( i + 1 < len )) && [[ ${s:i+1:1} == '(' ]]; then
              if (( i + 2 >= len )) || [[ ${s:i+2:1} != '(' ]]; then
                has_cmd_subst=1
              fi
            fi ;;
          '`') has_cmd_subst=1 ;;
        esac
        ((i++))
        continue
      fi

      case "$c" in
        ' ' | $'\t') break ;;
        \\) esc=1 ;;
        "'") in_s=1 ;;
        '"') in_d=1 ;;
        '$') # Check for $( outside quotes (unescaped)
          # $((  = arithmetic expansion (safe), $( = command substitution
          if (( i + 1 < len )) && [[ ${s:i+1:1} == '(' ]]; then
            if (( i + 2 >= len )) || [[ ${s:i+2:1} != '(' ]]; then
              has_cmd_subst=1
            fi
          fi ;;
        '`') has_cmd_subst=1 ;;
      esac
      ((i++))
    done

    token=${s:start:i-start}

    # First non-assignment token: this is the real command.
    if [[ ! $token =~ ^[A-Za-z_][A-Za-z_0-9]*\+?= ]]; then
      printf '%s\n' "${s:start}"
      return 0
    fi

    # Reject values with unescaped command substitution ($() or backticks).
    # Detected during tokenization with full escape/quote context.
    if (( has_cmd_subst )); then
      return 1
    fi

    # Skip whitespace before the next token.
    while (( i < len )); do
      c=${s:i:1}
      [[ $c == ' ' || $c == $'\t' ]] || break
      ((i++))
    done
  done

  printf '\n'
}

# Read each rule from the policy file
# Each rule has: "match" (substring or regex), "message" (what to tell the agent)
rule_count=$(jq '.rules | length' "$POLICY_FILE" 2>/dev/null)

if [ -z "$rule_count" ] || [ "$rule_count" = "0" ] || [ "$rule_count" = "null" ]; then
  exit 0
fi

# Normalize the command prefix. The lexer strips plain, quoted, and escaped
# env var assignments. It only fails for values containing command substitution
# ($() or backticks), which we deny outright — but only when rules exist
# (checked above), since there's nothing to bypass with an empty policy.
if ! command=$(normalize_command_prefix "$command"); then
  echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Tool policy: env-var prefixes with command substitution are blocked; remove the prefix or use a wrapper script."}}'
  exit 0
fi

i=0
while [ "$i" -lt "$rule_count" ]; do
  match=$(jq -r ".rules[$i].match // empty" "$POLICY_FILE")
  message=$(jq -r ".rules[$i].message // empty" "$POLICY_FILE")
  mode=$(jq -r ".rules[$i].mode // \"substring\"" "$POLICY_FILE")

  if [ -n "$match" ]; then
    blocked=false

    if [ "$mode" = "regex" ]; then
      if echo "$command" | grep -qE "$match"; then
        blocked=true
      fi
    elif [ "$mode" = "pcre" ]; then
      if echo "$command" | perl -ne "exit 0 if /$match/; exit 1" 2>/dev/null; then
        blocked=true
      fi
    else
      # Default: substring match (word-boundary aware via grep -w where possible)
      if echo "$command" | grep -qw "$match" 2>/dev/null || [[ "$command" == *"$match"* ]]; then
        blocked=true
      fi
    fi

    if [ "$blocked" = true ]; then
      # Escape message for JSON
      escaped_message=$(echo "$message" | sed 's/"/\\"/g')
      echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"Tool policy: $escaped_message\"}}"
      exit 0
    fi
  fi

  i=$((i + 1))
done

# No rules matched — allow
exit 0
