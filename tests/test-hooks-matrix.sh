#!/bin/bash
# Comprehensive regression matrix for hook security bypasses (PR #60)
# Generated from exhaustive reviewer specification (review 3873907525).
# Run from repo root: bash tests/test-hooks-matrix.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
pass=0; fail=0; total=0

tool_policy() {
  jq -n --arg cmd "$1" '{tool_input:{command:$cmd}}' | bash "$SCRIPT_DIR/scripts/hooks/tool-policy.sh" 2>/dev/null
}

auto_allow() {
  jq -n --arg cmd "$1" '{tool_name:"Bash",tool_input:{command:$cmd}}' | bash "$SCRIPT_DIR/scripts/hooks/auto-allow-reads.sh" 2>/dev/null
}

expect_deny() {
  local desc="$1" cmd="$2"
  total=$((total + 1))
  local result
  result=$(tool_policy "$cmd")
  if echo "$result" | grep -q '"deny"'; then
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
    pass=$((pass + 1))
  else
    echo "FAIL [noauto]: $desc  (should NOT auto-allow)"
    echo "       cmd:    $cmd"
    echo "       got:    $result"
    fail=$((fail + 1))
  fi
}

# ── Data Arrays ──────────────────────────────────────────────────────────

# Payloads that must be blocked whenever they are executable.
blocked_payloads=(
  'git push'
  'git push origin main'
  'git push origin master'
  'gh pr merge 42 --merge'
  'gh pr merge 42 --admin'
  'gh api repos/o/r/pulls/1/reviews -f event=APPROVE'
)

# Benign commands that must stay allowed.
benign_payloads=(
  'echo ok'
  'printf "%s\n" "safe literal"'
  'git status'
  'gh pr view 42'
  'bd ready'
)

# Prefixes that are syntactically valid and should preserve matching semantics.
passive_prefixes=(
  ''
  'NO_COLOR=1 '
  'PATH=/usr/bin:/bin '
  'FOO=bar '
  'FOO+=bar '
  'FOO="a b" '
  "FOO='a b' "
  'FOO=a\ b '
  'FOO=$((1+2)) '
  'FOO=$((1 + 2)) '
  'FOO=$((a[1] + 2)) '
  'FOO=$[1 + 2] '
  'FOO=$[a[1] + 2] '
  'FOO=${BAR:-x} '
  'FOO=${BAR:-a b} '
  'FOO=${arr[1]} '
  'A=(a b) '
  'A=([0]=x [1]=y) '
)

# Prefixes containing executable shell forms — must deny regardless of payload.
executable_prefixes=(
  'FOO=$(printf x) '
  'FOO=`printf x` '
  'FOO=<(printf x) '
  'FOO=>(printf x) '
  'FOO=$(cat <(printf x)) '
  'FOO=<(echo $(printf x)) '
)

# Prefixes that look executable but are literal text — must NOT deny.
literal_exec_looking_prefixes=(
  'FOO="$ (" '
  "FOO='\$(' "
  'FOO="\$(printf)" '
  "FOO='\$(printf)' "
  'FOO="\`x\`" '
  'FOO="<(printf x)" '
  'FOO=">(printf x)" '
  "FOO='<(printf x)' "
  "FOO='>(printf x)' "
)

# Wrappers where the payload is still executable and must be blocked.
# %s is replaced with the payload.
executable_wrappers=(
  '%s'
  '(%s)'
  '{ %s; }'
  'true; %s'
  'true && %s'
  'false || %s'
  $'true\n%s'
  'true | %s'
  '%s | true'
  'true & %s'
  '%s & true'
  'if true; then %s; fi'
  'if true; then true; else %s; fi'
  'for x in 1; do %s; done'
  'while true; do %s; break; done'
  '! %s'
  'time %s'
  'command %s'
  'exec %s'
  'env NO_COLOR=1 %s'
  'env %s'
  '>/tmp/x %s'
  '2>/tmp/x %s'
  '>/tmp/x 2>&1 %s'
  'echo $(%s)'
  'echo "$(%s)"'
  'echo `%s`'
  'echo "`%s`"'
  'cat <(%s)'
  'cat >(%s)'
  'echo $(cat <(%s))'
  'echo $(cat <(echo $(%s)))'
  'echo $(cat <(echo $(cat <(%s))))'
  'echo $(( $(%s >/dev/null 2>&1; printf 1) + 1 ))'
  "bash -lc '%s'"
  "sh -c '%s'"
  "eval '%s'"
)

# Wrappers where blocked text is only literal data — must NOT deny.
# %s is replaced with the blocked text.
literal_wrappers=(
  'echo "%s"'
  "echo '%s'"
  'printf "%%s\n" "%s"'
  "printf '%%s\n' '%s'"
  'FOO="%s" echo ok'
  "FOO='%s' echo ok"
)

# Executable env-prefix wrappers — must deny.
env_exec_wrappers=(
  'FOO=$(%s) echo ok'
  'FOO=`%s` echo ok'
  'FOO=<(%s) echo ok'
  'FOO>(%s) echo ok'
  'FOO=$(cat <(%s)) echo ok'
)

# Auto-allow commands that MUST emit allow.
auto_allow_positive=(
  'gh pr view 42'
  'gh pr list'
  'gh pr diff 42'
  'git status'
  'git log --oneline -5'
  'bd ready'
  'cat README.md'
  'pwd'
  'date'
)

# Auto-allow commands that MUST NOT emit allow.
auto_allow_negative=(
  'git status && echo test'
  'git status || echo test'
  'git status; echo test'
  $'git status\necho test'
  'git status | cat'
  'git status >/tmp/x'
  'git status > /tmp/x'
  'git status >>/tmp/x'
  'git status >> /tmp/x'
  'cat README.md >/tmp/x'
  'cat README.md > /tmp/x'
  'cat <(printf x)'
  'cat >(printf x)'
  'git status $(printf x)'
  'git status `printf x`'
  'gh pr view 42; echo test'
  'gh pr view 42 && echo test'
  'gh pr view 42 | cat'
  $'gh pr view 42\necho test'
  'NO_COLOR=1 gh pr view 42; echo test'
  'git status & echo test'
  'gh pr view 42 & echo test'
  'FOO="a b" gh pr view 42; echo test'
)

# ── Assertion 1: blocked × passive × executable → deny ──────────────────

echo "=== Assertion 1: blocked × passive × executable → deny ==="
a1_pass=0; a1_fail=0
for payload in "${blocked_payloads[@]}"; do
  for prefix in "${passive_prefixes[@]}"; do
    for wrapper in "${executable_wrappers[@]}"; do
      cmd="${prefix}${wrapper//'%s'/$payload}"
      expect_deny "A1" "$cmd"
    done
  done
done
a1_pass=$pass; a1_fail=$fail
echo "  subtotal: $((a1_pass)) pass, $((a1_fail)) fail (of $((total)) so far)"

# ── Assertion 2: blocked × env_exec → deny ──────────────────────────────

echo ""
echo "=== Assertion 2: blocked × env_exec → deny ==="
a2_start=$pass
for payload in "${blocked_payloads[@]}"; do
  for wrapper in "${env_exec_wrappers[@]}"; do
    cmd="${wrapper//'%s'/$payload}"
    expect_deny "A2" "$cmd"
  done
done
echo "  subtotal: $((pass - a2_start)) pass, $((fail - a1_fail)) fail"

# ── Assertion 3: blocked × literal → allow ──────────────────────────────

echo ""
echo "=== Assertion 3: blocked × literal → allow ==="
a3_start=$pass; a3_fail_start=$fail
for payload in "${blocked_payloads[@]}"; do
  for wrapper in "${literal_wrappers[@]}"; do
    cmd="${wrapper//'%s'/$payload}"
    expect_allow "A3" "$cmd"
  done
done
echo "  subtotal: $((pass - a3_start)) pass, $((fail - a3_fail_start)) fail"

# ── Assertion 4: benign × passive → allow ───────────────────────────────

echo ""
echo "=== Assertion 4: benign × passive → allow ==="
a4_start=$pass; a4_fail_start=$fail
for payload in "${benign_payloads[@]}"; do
  for prefix in "${passive_prefixes[@]}"; do
    cmd="${prefix}${payload}"
    expect_allow "A4" "$cmd"
  done
done
echo "  subtotal: $((pass - a4_start)) pass, $((fail - a4_fail_start)) fail"

# ── Assertion 5: benign × literal_exec_looking → allow ──────────────────

echo ""
echo "=== Assertion 5: benign × literal_exec_looking → allow ==="
a5_start=$pass; a5_fail_start=$fail
for payload in "${benign_payloads[@]}"; do
  for prefix in "${literal_exec_looking_prefixes[@]}"; do
    cmd="${prefix}${payload}"
    expect_allow "A5" "$cmd"
  done
done
echo "  subtotal: $((pass - a5_start)) pass, $((fail - a5_fail_start)) fail"

# ── Assertion 6: executable_prefix × benign → deny ─────────────────────

echo ""
echo "=== Assertion 6: executable_prefix × benign → deny ==="
a6_start=$pass; a6_fail_start=$fail
for prefix in "${executable_prefixes[@]}"; do
  for payload in "${benign_payloads[@]}"; do
    cmd="${prefix}${payload}"
    expect_deny "A6" "$cmd"
  done
done
echo "  subtotal: $((pass - a6_start)) pass, $((fail - a6_fail_start)) fail"

# ── Assertion 7: auto_allow_positive → allow ────────────────────────────

echo ""
echo "=== Assertion 7: auto_allow_positive → allow ==="
a7_start=$pass; a7_fail_start=$fail
for cmd in "${auto_allow_positive[@]}"; do
  expect_auto_allow "A7" "$cmd"
done
echo "  subtotal: $((pass - a7_start)) pass, $((fail - a7_fail_start)) fail"

# ── Assertion 8: auto_allow_negative → not allow ────────────────────────

echo ""
echo "=== Assertion 8: auto_allow_negative → not allow ==="
a8_start=$pass; a8_fail_start=$fail
for cmd in "${auto_allow_negative[@]}"; do
  expect_no_auto_allow "A8" "$cmd"
done
echo "  subtotal: $((pass - a8_start)) pass, $((fail - a8_fail_start)) fail"

# ── Summary ─────────────────────────────────────────────────────────────

echo ""
echo "================================"
echo "Results: $pass/$total passed, $fail failed"
echo "================================"

[ "$fail" -eq 0 ] && exit 0 || exit 1
