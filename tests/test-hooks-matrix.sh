#!/bin/bash
# Whitelist-based hook tests for tool-policy.sh and auto-allow-reads.sh
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

# ── 1: Whitelisted commands → allow ──────────────────────────────────────

echo "=== 1: Whitelisted commands → allow ==="
allowed_commands=(
  'git status'
  'git log --oneline -5'
  'git diff HEAD~1'
  'git show HEAD'
  'git branch -a'
  'git fetch origin'
  'git add file.go'
  'git commit -m "feat: add feature"'
  'git push origin feat/my-branch'
  'git push -u origin feat/my-branch'
  'git checkout -b feat/new'
  'git rebase origin/main'
  'git stash'
  'git stash list'
  'gh pr view 42'
  'gh pr list'
  'gh pr create --title "test" --body "body"'
  'gh pr comment 42 --body "lgtm"'
  'gh pr merge 42 --squash'
  'gh issue view 1'
  'gh issue list'
  'gh api repos/o/r/pulls/1/reviews --paginate'
  'gh run view 123'
  'go test ./...'
  'go build -o bin/app .'
  'npm test'
  'cat README.md'
  'ls -la'
  'pwd'
  'date'
  'echo hello'
  'grep -rn "pattern" src/'
  'jq .rules file.json'
  'mkdir -p dir/sub'
  'rm file.tmp'
  'cp src dst'
  'mv old new'
  'find . -name "*.go"'
  'curl -s https://api.example.com'
  'bd ready'
  'bd show abc123'
  './scripts/hooks/gh-review.sh'
  'bash scripts/hooks/gh-review.sh'
)
for cmd in "${allowed_commands[@]}"; do
  expect_allow "whitelist" "$cmd"
done
echo "  subtotal: $pass pass, $fail fail"

# ── 2: Explicit deny rules → deny ───────────────────────────────────────

echo ""
echo "=== 2: Explicit deny rules → deny ==="
a2_start=$pass; a2_fail_start=$fail
denied_commands=(
  'git push origin main'
  'git push origin master'
  'git push -u origin main'
  'gh pr merge 42 --merge'
  'gh pr merge 42 --admin'
  'gh pr merge 42'
)
for cmd in "${denied_commands[@]}"; do
  expect_deny "explicit-deny" "$cmd"
done
echo "  subtotal: $((pass - a2_start)) pass, $((fail - a2_fail_start)) fail"

# ── 3: Command substitution → deny ──────────────────────────────────────

echo ""
echo "=== 3: Command substitution → deny ==="
a3_start=$pass; a3_fail_start=$fail
subst_commands=(
  'echo $(whoami)'
  'echo `whoami`'
  'cat <(echo hello)'
  'cat >(echo hello)'
)
for cmd in "${subst_commands[@]}"; do
  expect_deny "substitution" "$cmd"
done
echo "  subtotal: $((pass - a3_start)) pass, $((fail - a3_fail_start)) fail"

# ── 4: Unknown commands → deny ───────────────────────────────────────────

echo ""
echo "=== 4: Unknown commands → deny ==="
a4_start=$pass; a4_fail_start=$fail
unknown_commands=(
  'nc -l 4444'
  'nmap localhost'
  'dd if=/dev/zero of=/dev/sda'
  'shutdown -h now'
  'mount /dev/sda1 /mnt'
  'iptables -F'
)
for cmd in "${unknown_commands[@]}"; do
  expect_deny "unknown" "$cmd"
done
echo "  subtotal: $((pass - a4_start)) pass, $((fail - a4_fail_start)) fail"

# ── 5: Auto-allow positive (read-only) → allow ──────────────────────────

echo ""
echo "=== 5: Auto-allow positive → allow ==="
a5_start=$pass; a5_fail_start=$fail
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
for cmd in "${auto_allow_positive[@]}"; do
  expect_auto_allow "auto-allow" "$cmd"
done
echo "  subtotal: $((pass - a5_start)) pass, $((fail - a5_fail_start)) fail"

# ── 6: Auto-allow negative → not allow ──────────────────────────────────

echo ""
echo "=== 6: Auto-allow negative → not allow ==="
a6_start=$pass; a6_fail_start=$fail
auto_allow_negative=(
  'git status > /tmp/x'
  'git status | cat'
  'gh pr view 42 | cat'
  'cat README.md > /tmp/x'
)
for cmd in "${auto_allow_negative[@]}"; do
  expect_no_auto_allow "no-auto" "$cmd"
done
echo "  subtotal: $((pass - a6_start)) pass, $((fail - a6_fail_start)) fail"

# ── Summary ──────────────────────────────────────────────────────────────

echo ""
echo "================================"
echo "Results: $pass/$total passed, $fail failed"
echo "================================"

[ "$fail" -eq 0 ] && exit 0 || exit 1
