#!/bin/bash
# Regression matrix for hook security bypasses (PR #60)
# Run from repo root: bash tests/test-hooks-matrix.sh

set -euo pipefail

pass=0; fail=0; total=0

tool_policy() {
  jq -n --arg cmd "$1" '{tool_input:{command:$cmd}}' | bash scripts/hooks/tool-policy.sh 2>/dev/null
}

auto_allow() {
  jq -n --arg cmd "$1" '{tool_name:"Bash",tool_input:{command:$cmd}}' | bash scripts/hooks/auto-allow-reads.sh 2>/dev/null
}

expect_deny() {
  local desc="$1" cmd="$2"
  total=$((total + 1))
  local result
  result=$(tool_policy "$cmd")
  if echo "$result" | grep -q '"deny"'; then
    echo "PASS [deny]:  $desc"
    pass=$((pass + 1))
  else
    echo "FAIL [deny]:  $desc"
    echo "       cmd:   $cmd"
    echo "       got:   ${result:-(empty)}"
    fail=$((fail + 1))
  fi
}

expect_allow() {
  local desc="$1" cmd="$2"
  total=$((total + 1))
  local result
  result=$(tool_policy "$cmd")
  if [ -z "$result" ] || ! echo "$result" | grep -q '"deny"'; then
    echo "PASS [allow]: $desc"
    pass=$((pass + 1))
  else
    echo "FAIL [allow]: $desc"
    echo "       cmd:   $cmd"
    echo "       got:   $result"
    fail=$((fail + 1))
  fi
}

expect_auto_allow() {
  local desc="$1" cmd="$2"
  total=$((total + 1))
  local result
  result=$(auto_allow "$cmd")
  if echo "$result" | grep -q '"allow"'; then
    echo "PASS [auto]:  $desc"
    pass=$((pass + 1))
  else
    echo "FAIL [auto]:  $desc  (expected allow)"
    echo "       cmd:   $cmd"
    echo "       got:   ${result:-(empty/defer)}"
    fail=$((fail + 1))
  fi
}

expect_no_auto_allow() {
  local desc="$1" cmd="$2"
  total=$((total + 1))
  local result
  result=$(auto_allow "$cmd")
  if [ -z "$result" ] || ! echo "$result" | grep -q '"allow"'; then
    echo "PASS [noauto]: $desc"
    pass=$((pass + 1))
  else
    echo "FAIL [noauto]: $desc  (should NOT auto-allow)"
    echo "       cmd:    $cmd"
    echo "       got:    $result"
    fail=$((fail + 1))
  fi
}

echo "=== tool-policy.sh: must DENY ==="

expect_deny "bare merge"                   'gh pr merge 42 --merge'
expect_deny "bare push"                    'git push origin main'
expect_deny "env var prefix"               'NO_COLOR=1 gh pr merge 42 --merge'
expect_deny "quoted env var"               'FOO="a b" gh pr merge 42 --merge'
expect_deny "arith env var"                'FOO=$((1 + 2)) gh pr merge 42 --merge'
expect_deny "param expansion env"          'FOO=${BAR:-a b} gh pr merge 42 --merge'
expect_deny "array assign env"             'A=(a b) gh pr merge 42 --merge'
expect_deny "subshell wrap"                '(gh pr merge 42 --merge)'
expect_deny "brace group wrap"             '{ gh pr merge 42 --merge; }'
expect_deny "semicolon chain"              'true; gh pr merge 42 --merge'
expect_deny "&& chain"                     'true && git push origin main'
expect_deny "pipe chain"                   'true | gh pr merge 42 --merge'
expect_deny 'bare $()'                     'echo $(gh pr merge 42 --merge)'
expect_deny 'double-quoted $()'            'echo "$(gh pr merge 42 --merge)"'
expect_deny 'double-quoted backtick'       'echo "`gh pr merge 42 --merge`"'
expect_deny 'process subst <()'            'cat <(gh pr merge 42 --merge)'
expect_deny 'process subst >()'            'cat >(gh pr merge 42 --merge)'
expect_deny 'nested $(<())'               'echo $(cat <(gh pr merge 42 --merge))'
expect_deny '3-level nesting'              'echo $(cat <(echo $(gh pr merge 42 --merge)))'
expect_deny 'cmd subst in env $()'         'FOO=$(gh pr merge 42 --merge) echo ok'
expect_deny 'proc subst in env <()'        'FOO=<(gh pr merge 42 --merge) echo ok'
expect_deny 'cmd subst in env push'        'FOO=$(git push origin main) echo ok'
expect_deny 'proc subst in env push'       'FOO=<(git push origin main) echo ok'

echo ""
echo "=== tool-policy.sh: must NOT deny ==="

expect_allow "blocked pattern in string arg"   'printf "%s\n" "x; gh pr merge 42 --merge"'
expect_allow "blocked pattern in echo string"  'echo "gh pr merge 42 --merge"'
expect_allow 'dq literal <()'                  'FOO="<(printf x)" echo ok'
expect_allow 'dq literal >()'                  'FOO=">(printf x)" echo ok'
expect_allow 'sq literal <()'                  "FOO='<(printf x)' echo ok"
expect_allow 'sq literal >()'                  "FOO='>(printf x)' echo ok"
expect_allow 'sq literal $('                   "FOO='\$(' echo ok"
expect_allow 'escaped $()'                     'FOO=\$(printf) echo ok'
expect_allow 'dq escaped $()'                  'FOO="\$(printf)" echo ok'
expect_allow 'dq escaped backtick'             'FOO="\`x\`" echo ok'
expect_allow 'arith $((1+2))'                  'FOO=$((1+2)) echo ok'
expect_allow 'legacy arith $[1+2]'             'FOO=$[1 + 2] echo ok'

echo ""
echo "=== auto-allow-reads.sh: must ALLOW ==="

expect_auto_allow "gh pr view"     'gh pr view 42'
expect_auto_allow "git status"     'git status'
expect_auto_allow "bd ready"       'bd ready'
expect_auto_allow "cat README"     'cat README.md'

echo ""
echo "=== auto-allow-reads.sh: must NOT allow ==="

expect_no_auto_allow "&& chain"          'git status && git push'
expect_no_auto_allow "> redirect"        'git status >/tmp/x'
expect_no_auto_allow "cat > redirect"    'cat README.md >/tmp/x'
expect_no_auto_allow "proc subst <()"    'cat <(printf x)'
expect_no_auto_allow 'cmd subst $()'     'git status $(printf x)'
expect_no_auto_allow "semicolon chain"   'gh pr view 42; touch /tmp/x'
expect_no_auto_allow "pipe"              'gh pr view 42 | cat'

# Newline-separated command
nl_cmd=$(printf 'git status\ntouch /tmp/x')
expect_no_auto_allow "newline chain"     "$nl_cmd"

echo ""
echo "================================"
echo "Results: $pass/$total passed, $fail failed"
echo "================================"

[ "$fail" -eq 0 ] && exit 0 || exit 1
