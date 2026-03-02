#!/bin/bash
# Tests for tool-policy.sh (inter-agent interface rules)
# Run from repo root: bash tests/test-hooks-matrix.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
pass=0; fail=0; total=0

tool_policy() {
  jq -n --arg cmd "$1" '{tool_input:{command:$cmd}}' | bash "$SCRIPT_DIR/scripts/hooks/tool-policy.sh" 2>/dev/null
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

# ── 1: Push to main/master → deny ─────────────────────────────────────

echo "=== 1: Push to main/master → deny ==="
expect_deny "push main"   "git push origin main"
expect_deny "push master" "git push origin master"
expect_deny "push -u main" "git push -u origin main"
expect_deny "refspec main" "git push origin HEAD:main"
expect_deny "refspec refs/heads/main" "git push origin HEAD:refs/heads/main"
echo "  subtotal: $pass pass, $fail fail"

# ── 2: Push to feature branches → allow ──────────────────────────────

echo ""
echo "=== 2: Push to feature branches → allow ==="
a2_start=$pass; a2_fail_start=$fail
expect_allow "feat branch"      "git push origin feat/my-branch"
expect_allow "feat -u"          "git push -u origin feat/my-branch"
expect_allow "domain-fix"       "git push origin feat/domain-fix"
expect_allow "maintainers-docs" "git push origin maintainers-docs"
expect_allow "local main to remote feat" "git push origin main:feature-branch"
echo "  subtotal: $((pass - a2_start)) pass, $((fail - a2_fail_start)) fail"

# ── 3: PR merge without --squash → deny ─────────────────────────────

echo ""
echo "=== 3: PR merge without --squash → deny ==="
a3_start=$pass; a3_fail_start=$fail
expect_deny "merge default" "gh pr merge 42"
expect_deny "merge --merge" "gh pr merge 42 --merge"
expect_deny "merge --admin" "gh pr merge 42 --admin"
expect_deny "merge --rebase" "gh pr merge 42 --rebase"
expect_deny "squash in body not flag" "gh pr merge 42 --merge --body 'please use --squash later'"
echo "  subtotal: $((pass - a3_start)) pass, $((fail - a3_fail_start)) fail"

# ── 4: PR merge with --squash → allow ───────────────────────────────

echo ""
echo "=== 4: PR merge with --squash → allow ==="
a4_start=$pass; a4_fail_start=$fail
expect_allow "squash merge" "gh pr merge 42 --squash"
echo "  subtotal: $((pass - a4_start)) pass, $((fail - a4_fail_start)) fail"

# ── 5: Other commands pass through ───────────────────────────────────

echo ""
echo "=== 5: Other commands pass through ==="
a5_start=$pass; a5_fail_start=$fail
expect_allow "git status"  "git status"
expect_allow "git log"     "git log --oneline -5"
expect_allow "gh pr view"  "gh pr view 42"
expect_allow "gh pr list"  "gh pr list"
expect_allow "cat"         "cat README.md"
expect_allow "ls"          "ls -la"
expect_allow "echo"        "echo hello"
echo "  subtotal: $((pass - a5_start)) pass, $((fail - a5_fail_start)) fail"

# ── Summary ──────────────────────────────────────────────────────────

echo ""
echo "================================"
echo "Results: $pass/$total passed, $fail failed"
echo "================================"

[ "$fail" -eq 0 ] && exit 0 || exit 1
