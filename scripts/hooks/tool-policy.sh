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
    local paren_depth=0
    local brace_depth=0
    local bracket_depth=0

    # Read one shell-ish token, honoring quotes and backslash escapes well
    # enough to find token boundaries without evaluating anything.
    # Track unescaped $( and backticks to detect command substitution.
    # Track paren/brace/bracket depth so spaces inside expansions don't
    # break the token: $(( )) arithmetic, ( ) arrays, ${ } params, $[ ] legacy.
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
        ' ' | $'\t')
          # Don't break inside expansions — spaces are valid there
          if (( paren_depth > 0 || brace_depth > 0 || bracket_depth > 0 )); then :; else break; fi ;;
        \\) esc=1 ;;
        "'") in_s=1 ;;
        '"') in_d=1 ;;
        '$') # Check for $(, $((, or ${ outside quotes (unescaped)
          if (( i + 1 < len )); then
            case "${s:i+1:1}" in
              '(')
                if (( i + 2 < len )) && [[ ${s:i+2:1} == '(' ]]; then
                  # $(( = arithmetic expansion — skip past $((
                  paren_depth=1
                  ((i += 2))
                else
                  # $( = command substitution
                  has_cmd_subst=1
                fi ;;
              '{')
                # ${ = parameter expansion — track brace depth
                ((brace_depth++))
                ((i++)) ;;
              '[')
                # $[ = legacy arithmetic expansion — track bracket depth
                ((bracket_depth++))
                ((i++)) ;;
            esac
          fi ;;
        '<' | '>')
          # <( and >( = process substitution (executes a command)
          if (( i + 1 < len )) && [[ ${s:i+1:1} == '(' ]]; then
            has_cmd_subst=1
          fi ;;
        '(') ((paren_depth++)) ;;
        ')') (( paren_depth > 0 )) && ((paren_depth--)) ;;
        '}') (( brace_depth > 0 )) && ((brace_depth--)) ;;
        '[') (( bracket_depth > 0 )) && ((bracket_depth++)) ;;
        ']') (( bracket_depth > 0 )) && ((bracket_depth--)) ;;
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

# Quote-aware split on shell separators (;, &&, ||, |, newlines).
# Respects single/double quotes, backslash escapes, and substitution
# nesting ($(), $(( )), <(), >()) so separators inside substitutions
# don't cause false splits.
split_command_segments() {
  local s="$1"
  local len=${#s}
  local i=0 start=0
  local c sq=0 dq=0 esc=0 sd=0

  while (( i < len )); do
    c=${s:i:1}

    if (( esc )); then esc=0; ((i++)); continue; fi
    if (( sq )); then [[ $c == "'" ]] && sq=0; ((i++)); continue; fi
    if (( dq )); then
      case "$c" in
        \\) esc=1 ;;
        '"') dq=0 ;;
        '$')
          if (( i+1 < len )) && [[ ${s:i+1:1} == '(' ]]; then
            if (( i+2 < len )) && [[ ${s:i+2:1} == '(' ]]; then
              ((sd += 2)); ((i += 2))
            else
              ((sd++)); ((i++))
            fi
          fi ;;
      esac
      ((i++)); continue
    fi

    case "$c" in
      \\) esc=1 ;;
      "'") sq=1 ;;
      '"') dq=1 ;;
      '$')
        if (( i+1 < len )); then
          case "${s:i+1:1}" in
            '(')
              if (( i+2 < len )) && [[ ${s:i+2:1} == '(' ]]; then
                ((sd += 2)); ((i += 2))
              else
                ((sd++)); ((i++))
              fi ;;
          esac
        fi ;;
      '<' | '>')
        if (( i+1 < len )) && [[ ${s:i+1:1} == '(' ]]; then
          ((sd++)); ((i++))
        fi ;;
      ')')
        (( sd > 0 )) && ((sd--)) ;;
      ';' | $'\n')
        if (( sd == 0 )); then
          printf '%s\n' "${s:start:i-start}"
          ((i++)); start=$i; continue
        fi ;;
      '&')
        if (( sd == 0 )) && (( i + 1 < len )) && [[ ${s:i+1:1} == '&' ]]; then
          printf '%s\n' "${s:start:i-start}"
          ((i += 2)); start=$i; continue
        fi ;;
      '|')
        if (( sd == 0 )); then
          if (( i + 1 < len )) && [[ ${s:i+1:1} == '|' ]]; then
            printf '%s\n' "${s:start:i-start}"
            ((i += 2)); start=$i; continue
          else
            printf '%s\n' "${s:start:i-start}"
            ((i++)); start=$i; continue
          fi
        fi ;;
    esac
    ((i++))
  done

  (( start < len )) && printf '%s\n' "${s:start}"
}

# Extract command substitution contents ($(), backticks, <(), >()) from a
# single segment. Outputs ONLY the extracted inner contents, not the original.
extract_subst_from() {
  local s="$1"
  local len=${#s} i=0 c sq=0 dq=0 esc=0 depth start
  while (( i < len )); do
    c=${s:i:1}
    if (( esc )); then esc=0; ((i++)); continue; fi
    if (( sq )); then [[ $c == "'" ]] && sq=0; ((i++)); continue; fi
    if (( dq )); then
      case "$c" in
        \\) esc=1 ;;
        '"') dq=0 ;;
        '$')
          if (( i+1 < len )) && [[ ${s:i+1:1} == '(' ]]; then
            if ! (( i+2 < len )) || [[ ${s:i+2:1} != '(' ]]; then
              ((i += 2)); start=$i; depth=1
              while (( i < len && depth > 0 )); do
                case "${s:i:1}" in '(') ((depth++)) ;; ')') ((depth--)) ;; esac
                (( depth > 0 )) && ((i++))
              done
              printf '%s\n' "${s:start:i-start}"
            fi
          fi ;;
        '`')
          ((i++)); start=$i
          while (( i < len )) && [[ ${s:i:1} != '`' ]]; do ((i++)); done
          printf '%s\n' "${s:start:i-start}"
          ;;
      esac
      ((i++)); continue
    fi
    case "$c" in
      \\) esc=1 ;;
      "'") sq=1 ;;
      '"') dq=1 ;;
      '$')
        if (( i+1 < len )) && [[ ${s:i+1:1} == '(' ]]; then
          if (( i+2 < len )) && [[ ${s:i+2:1} == '(' ]]; then
            ((i++))
          else
            ((i += 2)); start=$i; depth=1
            while (( i < len && depth > 0 )); do
              case "${s:i:1}" in '(') ((depth++)) ;; ')') ((depth--)) ;; esac
              (( depth > 0 )) && ((i++))
            done
            printf '%s\n' "${s:start:i-start}"
          fi
        fi ;;
      '<' | '>')
        if (( i+1 < len )) && [[ ${s:i+1:1} == '(' ]]; then
          ((i += 2)); start=$i; depth=1
          while (( i < len && depth > 0 )); do
            case "${s:i:1}" in '(') ((depth++)) ;; ')') ((depth--)) ;; esac
            (( depth > 0 )) && ((i++))
          done
          printf '%s\n' "${s:start:i-start}"
        fi ;;
      '`')
        ((i++)); start=$i
        while (( i < len )) && [[ ${s:i:1} != '`' ]]; do ((i++)); done
        printf '%s\n' "${s:start:i-start}"
        ;;
    esac
    ((i++))
  done
}

# Extract arguments passed to shell interpreters (bash -c, sh -c, eval).
# Outputs the inner command string to be added as a segment for rule checking.
extract_shell_exec_arg() {
  local s="$1"
  # Strip leading whitespace and grouping syntax
  while true; do
    case "$s" in
      ' '*|$'\t'*) s="${s#?}" ;; '('*) s="${s#(}" ;; '{ '*) s="${s#\{ }" ;;
      *) break ;;
    esac
  done

  local inner=""
  local cmd_word="${s%% *}"

  case "$cmd_word" in
    bash|sh|dash|zsh|ksh)
      # Match: shell [flags] -[opts]c <arg>  (e.g., bash -lc 'cmd', sh -c 'cmd')
      if [[ "$s" =~ ^[a-z]+[[:space:]]+(-[A-Za-z]+[[:space:]]+)*-[A-Za-z]*c[[:space:]]+(.*) ]]; then
        inner="${BASH_REMATCH[2]}"
      fi ;;
    eval)
      inner="${s#eval}"
      inner="${inner#"${inner%%[![:space:]]*}"}" ;;
  esac

  if [[ -n "$inner" ]]; then
    case "${inner:0:1}" in
      "'") inner="${inner:1}"; printf '%s\n' "${inner%%\'*}" ;;
      '"') inner="${inner:1}"; printf '%s\n' "${inner%%\"*}" ;;
      *)   printf '%s\n' "$inner" ;;
    esac
  fi
}

# Build segment list: start with top-level splits, then iteratively extract
# substitution contents and shell interpreter arguments. Extracted content is
# re-split on shell operators so nested separators (;, &&, etc.) are handled.
IFS=$'\n' read -r -d '' -a segments <<< "$(split_command_segments "$command")"
idx=0
while (( idx < ${#segments[@]} )); do
  while IFS= read -r extracted; do
    [[ -n "$extracted" ]] || continue
    while IFS= read -r sub; do
      [[ -n "$sub" ]] && segments+=("$sub")
    done <<< "$(split_command_segments "$extracted")"
  done <<< "$(extract_subst_from "${segments[$idx]}")"
  while IFS= read -r extracted; do
    [[ -n "$extracted" ]] || continue
    while IFS= read -r sub; do
      [[ -n "$sub" ]] && segments+=("$sub")
    done <<< "$(split_command_segments "$extracted")"
  done <<< "$(extract_shell_exec_arg "${segments[$idx]}")"
  ((idx++))
done

i=0
while [ "$i" -lt "$rule_count" ]; do
  match=$(jq -r ".rules[$i].match // empty" "$POLICY_FILE")
  message=$(jq -r ".rules[$i].message // empty" "$POLICY_FILE")
  mode=$(jq -r ".rules[$i].mode // \"substring\"" "$POLICY_FILE")

  if [ -n "$match" ]; then
    for seg in "${segments[@]}"; do
      # Strip leading whitespace and grouping syntax from each segment
      while true; do
        case "$seg" in
          '('*) seg="${seg#(}" ;; '{ '*) seg="${seg#\{ }" ;;
          ' '*|$'\t'*) seg="${seg#?}" ;; *) break ;;
        esac
      done
      # Strip trailing grouping syntax, semicolons, and whitespace
      while true; do
        case "$seg" in
          *')') seg="${seg%)}" ;; *' }') seg="${seg% \}}" ;;
          *';') seg="${seg%;}" ;; *' '|*$'\t') seg="${seg%?}" ;;
          *) break ;;
        esac
      done

      blocked=false

      if [ "$mode" = "regex" ]; then
        if echo "$seg" | grep -qE "$match"; then
          blocked=true
        fi
      elif [ "$mode" = "pcre" ]; then
        if echo "$seg" | perl -ne "exit 0 if /$match/; exit 1" 2>/dev/null; then
          blocked=true
        fi
      else
        # Default: substring match (word-boundary aware via grep -w where possible)
        if echo "$seg" | grep -qw "$match" 2>/dev/null || [[ "$seg" == *"$match"* ]]; then
          blocked=true
        fi
      fi

      if [ "$blocked" = true ]; then
        # Escape message for JSON
        escaped_message=$(echo "$message" | sed 's/"/\\"/g')
        echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"Tool policy: $escaped_message\"}}"
        exit 0
      fi
    done
  fi

  i=$((i + 1))
done

# No rules matched — allow
exit 0
