#!/usr/bin/env bash
# gh-review.sh — Submit formal GitHub PR reviews as the dedicated reviewer.
#
# Usage:
#   ./scripts/hooks/gh-review.sh \
#     --repo owner/repo --pr 42 --event APPROVE \
#     --body "Review body" --commit-id abc123 [--dry-run]
#
# Reads `github_login` from .claude/code-review-workflow.yml to determine the
# expected reviewer identity. Gets the reviewer token via `gh auth token -u`.
# Validates identity before posting (fail-closed).

set -euo pipefail

# --- Argument parsing ---
REPO="" PR="" EVENT="" BODY="" COMMIT_ID="" DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)      REPO="$2";      shift 2 ;;
    --pr)        PR="$2";        shift 2 ;;
    --event)     EVENT="$2";     shift 2 ;;
    --body)      BODY="$2";      shift 2 ;;
    --commit-id) COMMIT_ID="$2"; shift 2 ;;
    --dry-run)   DRY_RUN=true;   shift   ;;
    *)
      echo "gh-review.sh: unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

# --- Validate required args ---
missing=()
[[ -z "$REPO" ]]      && missing+=(--repo)
[[ -z "$PR" ]]        && missing+=(--pr)
[[ -z "$EVENT" ]]     && missing+=(--event)
[[ -z "$BODY" ]]      && missing+=(--body)
[[ -z "$COMMIT_ID" ]] && missing+=(--commit-id)

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "gh-review.sh: missing required arguments: ${missing[*]}" >&2
  exit 1
fi

# Validate event type
if [[ "$EVENT" != "APPROVE" && "$EVENT" != "REQUEST_CHANGES" ]]; then
  echo "gh-review.sh: --event must be APPROVE or REQUEST_CHANGES, got: $EVENT" >&2
  exit 1
fi

# --- Read reviewer GitHub login from config ---
CONFIG_FILE=".claude/code-review-workflow.yml"
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "gh-review.sh: config not found: $CONFIG_FILE" >&2
  exit 1
fi

REVIEWER_GH_USER=$(sed -n 's/^[[:space:]]*github_login:[[:space:]]*"\{0,1\}\([^"]*\)"\{0,1\}[[:space:]]*$/\1/p' "$CONFIG_FILE" | head -1)
if [[ -z "$REVIEWER_GH_USER" ]]; then
  echo "gh-review.sh: github_login not found in $CONFIG_FILE" >&2
  exit 1
fi

# --- Get reviewer token ---
REVIEWER_TOKEN=$(gh auth token -u "$REVIEWER_GH_USER" 2>/dev/null) || true
if [[ -z "$REVIEWER_TOKEN" ]]; then
  echo "gh-review.sh: no token found for user '$REVIEWER_GH_USER'. Add the account with: gh auth login (select $REVIEWER_GH_USER when prompted)" >&2
  exit 1
fi

# --- Validate identity (fail-closed) ---
ACTUAL_LOGIN=$(GH_TOKEN="$REVIEWER_TOKEN" gh api user -q .login 2>/dev/null) || true
if [[ "$ACTUAL_LOGIN" != "$REVIEWER_GH_USER" ]]; then
  echo "gh-review.sh: identity mismatch — expected '$REVIEWER_GH_USER', got '$ACTUAL_LOGIN'" >&2
  exit 1
fi

# --- Dry run ---
if [[ "$DRY_RUN" == true ]]; then
  echo "gh-review.sh [dry-run]: would post review to $REPO PR #$PR"
  echo "  event:     $EVENT"
  echo "  commit_id: $COMMIT_ID"
  echo "  body:      $BODY"
  echo "  as:        $REVIEWER_GH_USER"
  exit 0
fi

# --- Post formal review ---
GH_TOKEN="$REVIEWER_TOKEN" gh api "repos/$REPO/pulls/$PR/reviews" \
  -f event="$EVENT" \
  -f body="$BODY" \
  -f commit_id="$COMMIT_ID"

echo "gh-review.sh: posted $EVENT review on $REPO PR #$PR as $REVIEWER_GH_USER"
