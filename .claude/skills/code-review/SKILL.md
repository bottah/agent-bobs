---
description: Beads-coordinated code review workflow
---

# Code Review Skill

Orchestrate the full code review lifecycle: implement a feature, create a PR, request external review via beads, handle feedback cycles, and merge on approval.

## Inputs

The user may provide:
- `#N` — a GitHub issue number (e.g., `/code-review #42`)
- `bd-xxx` — an existing feature bead ID (e.g., `/code-review bd-abc`)
- `"text"` — a description to create a feature bead from (e.g., `/code-review "add user search"`)
- Nothing — pick from `bd ready --json`

## Steps

### 0. Prerequisite check

Verify all required tools and state are available before proceeding:

```bash
# Required CLIs
command -v bd || { echo "Error: bd CLI not found. Install beads first."; exit 1; }
command -v gh || { echo "Error: gh CLI not found. Install GitHub CLI first."; exit 1; }
gh auth status
```

- Verify beads database exists: `bd list --json` should succeed
- Read config: `.claude/code-review-workflow.yml`
- Extract from config:
  - `reviewer` — first key under `reviewers:` (v1 uses only the first)
  - `reviewer_login` — the `github_login:` value for that reviewer (used to filter poll results)
  - `reviewer_focus` — the `focus:` value for that reviewer
  - `max_review_cycles` — from `limits:`
  - `poll_interval_seconds` — from `limits:`
  - `max_wait_minutes` — from `limits:`
  - `pr_label` — from `on_limit_reached:`
- Extract repo for `gh` commands (SSH aliases prevent auto-detection):
  ```bash
  repo=$(git remote get-url origin | sed -E 's|(\.git)$||; s|.*[:/]([^/]+/[^/]+)$|\1|')
  ```

### 1. Resolve issue

Determine the feature bead based on the entry point:

**GitHub issue (`#N`)**:
```bash
gh issue view <N> -R "$repo" --json title,body,labels
```
Create a feature bead with the issue title and body. Store metadata:
```bash
bd create --title "<issue title>" --description "<issue body>" --type feature \
  --metadata '{"github_issue": <N>, "repo": "<repo>"}' --json
```
Claim the bead:
```bash
bd update <bead-id> --claim
```

**Existing bead (`bd-xxx`)**:
```bash
bd show <bead-id> --json
```
Verify it's a feature bead and in a workable state (`open` or `in_progress`). Claim if not already claimed.

**Description string**:
```bash
bd create --title "<description>" --type feature --json
```
Claim the bead.

**Nothing (pick from ready queue)**:
```bash
bd ready --json
```
Present the list to the user for selection. Claim the selected bead.

### 2. Branch

Create or reuse a feature branch:
- Branch name: `feat/<bead-id>-<slugified-title>` (e.g., `feat/bd-abc-add-user-search`)
- If the branch already exists (resuming), check it out
- If creating new: `git checkout -b <branch-name>`

### 3. Implement

This is the interactive implementation step. Claude implements the feature based on:
- The bead title and body/description
- The GitHub issue details (if created from an issue)
- User guidance during implementation

Pause here and implement the feature with the user. Continue to step 4 when the user confirms the implementation is ready.

### 4. Commit + push + PR

Create a conventional commit, push, and open a PR:

```bash
# Commit (use /commit skill conventions)
git add <files>
git commit -m "<type>(scope): <description>"

# Push
git push -u origin <branch-name>

# Create PR (always target main explicitly)
gh pr create --title "<type>(scope): <description>" --base main --body "$(cat <<'PREOF'
## Summary
<summary of changes>

Resolves <bead-id>
<if from github issue: Closes #N>
PREOF
)" -R "$repo"
```

Store the PR number for subsequent steps.

### 5. Create review bead

Create a review bead with full metadata for the configured reviewer:

```bash
head_sha=$(git rev-parse HEAD)
base_ref=$(gh pr view <pr_number> -R "$repo" --json baseRefName -q .baseRefName)
head_ref=$(git branch --show-current)

review_bead_id=$(bd create \
  --title "Review PR #<pr_number> [$reviewer]" \
  --type task \
  --labels "type:review,reviewer:$reviewer" \
  --metadata "{\"pr\": <pr_number>, \"repo\": \"$repo\", \"head_sha\": \"$head_sha\", \"base_ref\": \"$base_ref\", \"head_ref\": \"$head_ref\", \"reviewer\": \"$reviewer\", \"cycle\": 1, \"feature_bead\": \"<feature_bead_id>\"}" \
  --json | jq -r '.id')
cycle=1
```

### 6. Request review + post GitHub event comment

Request a review from the configured reviewer and post a marker comment:

```bash
gh pr edit <pr_number> -R "$repo" --add-reviewer "$reviewer_login"
gh pr comment <pr_number> -R "$repo" --body "$(cat <<'EVEOF'
<!-- beads-event -->
Code review requested: <reviewer>
EVEOF
)"
```

### 7. Poll loop

Poll GitHub review status until resolution or timeout. The authoring session
polls GitHub directly and maps verdicts into local bead state.

```bash
start_time=$(date +%s)
# review_bead_id and cycle are set from step 5, or reloaded from
# bead metadata when resuming (see Resumability section below).
reviewed_sha=$(bd show "$review_bead_id" --json | jq -r '.[0].metadata.head_sha')

while true; do
  sleep $poll_interval_seconds

  # Check elapsed time
  elapsed=$(( $(date +%s) - start_time ))
  if [ $elapsed -ge $(( max_wait_minutes * 60 )) ]; then
    echo "Timeout: waited ${max_wait_minutes} minutes with no review resolution."
    echo "Resume with: /code-review <feature-bead-id>"
    # Do NOT modify any bead state on timeout — stop the workflow entirely
    exit 0
  fi

  # Poll GitHub for the latest review on this PR from the configured reviewer
  latest_review=$(gh api repos/$repo/pulls/<pr_number>/reviews --paginate \
    --jq "[.[] | select(.commit_id == \"$reviewed_sha\" and .user.login == \"$reviewer_login\")] | sort_by(.submitted_at) | last")

  if [ -z "$latest_review" ] || [ "$latest_review" = "null" ]; then
    continue  # No review yet
  fi

  review_state=$(echo "$latest_review" | jq -r '.state')
  review_id=$(echo "$latest_review" | jq -r '.id')

  case "$review_state" in
    APPROVED)
      # Map GitHub approval into local bead state and proceed to merge
      bd close "$review_bead_id" --reason "Approved at $reviewed_sha (GH review $review_id)"
      break
      ;;
    CHANGES_REQUESTED)
      # Fetch the review body for feedback
      feedback=$(echo "$latest_review" | jq -r '.body')
      bd update "$review_bead_id" --status blocked \
        --append-notes "REQUEST_CHANGES: $feedback"

      # Check cycle limit
      if [ $((cycle + 1)) -gt $max_review_cycles ]; then
        gh pr comment <pr_number> -R "$repo" --body "<!-- beads-event --> Review cycle limit reached ($cycle/$max_review_cycles). PR flagged for human review."
        gh pr edit <pr_number> -R "$repo" --add-label "$pr_label"
        bd update <feature-bead-id> --status blocked
        echo "Review cycle limit reached. PR labeled '$pr_label'. Human intervention required."
        exit 0
      fi

      # Fix the issues based on reviewer feedback
      echo "Reviewer requested changes (cycle $cycle/$max_review_cycles):"
      echo "$feedback"
      # <Claude fixes the code based on feedback>

      # Commit and push fixes
      git add <files>
      git commit -m "fix: address review feedback (cycle $((cycle + 1)))"
      git push

      # Create new review bead for next cycle and update the tracked bead ID
      cycle=$((cycle + 1))
      head_sha=$(git rev-parse HEAD)
      reviewed_sha="$head_sha"
      review_bead_id=$(bd create \
        --title "Review PR #<pr_number> [$reviewer] (cycle $cycle)" \
        --type task \
        --labels "type:review,reviewer:$reviewer" \
        --metadata "{\"pr\": <pr_number>, \"repo\": \"$repo\", \"head_sha\": \"$head_sha\", \"base_ref\": \"$base_ref\", \"head_ref\": \"$head_ref\", \"reviewer\": \"$reviewer\", \"cycle\": $cycle, \"feature_bead\": \"<feature_bead_id>\"}" \
        --json | jq -r '.id')

      # Post event comment
      gh pr comment <pr_number> -R "$repo" --body "<!-- beads-event --> Re-review requested: $reviewer (cycle $cycle/$max_review_cycles)"

      # Reset poll timer for new cycle
      start_time=$(date +%s)
      ;;
  esac
done
```

### 8. Merge gate + squash merge

Before merging, verify all three merge gate conditions:

```bash
# Note: bd show --json returns an array; use .[0] to get the object

# 1. Active review bead (highest cycle) must be closed
review_status=$(bd show "$review_bead_id" --json | jq -r '.[0].status')
if [ "$review_status" != "closed" ]; then
  echo "Merge gate failed: review bead is '$review_status', not 'closed'."
  bd update <feature-bead-id> --status blocked
  exit 1
fi

# 2. Review bead head_sha must match current PR head
review_sha=$(bd show "$review_bead_id" --json | jq -r '.[0].metadata.head_sha')
pr_head=$(gh pr view <pr_number> -R "$repo" --json headRefOid -q .headRefOid)
if [ "$review_sha" != "$pr_head" ]; then
  gh pr comment <pr_number> -R "$repo" --body "<!-- beads-event --> Merge blocked: reviewed SHA ($review_sha) doesn't match PR head ($pr_head). Manual investigation required."
  bd update <feature-bead-id> --status blocked
  echo "Merge gate failed: SHA mismatch."
  exit 1
fi

# 3. Cycle must be within allowed range
review_cycle=$(bd show "$review_bead_id" --json | jq -r '.[0].metadata.cycle')
if [ "$review_cycle" -gt "$max_review_cycles" ]; then
  echo "Merge gate failed: cycle $review_cycle exceeds max $max_review_cycles."
  exit 1
fi
```

If all checks pass, post approval event and merge:

```bash
gh pr comment <pr_number> -R "$repo" --body "<!-- beads-event --> $reviewer approved at $review_sha. Merging."
gh pr merge <pr_number> -R "$repo" --squash --delete-branch
```

### 9. Close feature bead

```bash
bd close <feature-bead-id> --reason "Merged via PR #<pr_number>"
```

## Resumability

When re-invoked with a bead ID or on an existing branch, detect existing state and resume:

- If feature bead is `in_progress` and a PR exists → skip to step 5 or 7
- If a review bead already exists for the current cycle → skip to step 7 (poll)
- If the review bead is `closed` → skip to step 8 (merge)
- If the review bead is `blocked` and cycle limit not reached → resume fix cycle in step 7

On resume, first recover the PR number from the current branch (covers the case where the PR exists but no review bead has been created yet):
```bash
pr_number=$(gh pr view -R "$repo" --json number -q .number 2>/dev/null)
head_ref=$(git branch --show-current)
```

Then, if a review bead exists, reload cycle state from the highest-cycle review bead:
```bash
review_bead=$(bd list --json --label "type:review" | jq -r "[.[] | select(.metadata.feature_bead == \"<feature_bead_id>\")] | sort_by(.metadata.cycle) | last")
if [ "$review_bead" != "null" ] && [ -n "$review_bead" ]; then
  review_bead_id=$(echo "$review_bead" | jq -r '.id')
  cycle=$(echo "$review_bead" | jq -r '.metadata.cycle')
  pr_number=$(echo "$review_bead" | jq -r '.metadata.pr')
  base_ref=$(echo "$review_bead" | jq -r '.metadata.base_ref')
  head_ref=$(echo "$review_bead" | jq -r '.metadata.head_ref')
fi
```

Check for existing state at each step before creating new artifacts.

## Rules

- All `gh` commands must use `-R owner/repo` (SSH aliases prevent auto-detection)
- Claude maps GitHub review verdicts into local bead state (close on APPROVED, block on CHANGES_REQUESTED)
- On timeout: do not modify any bead state, just pause and instruct to resume
- On cycle limit: label PR, block feature bead, stop
- Use `--squash` for all PR merges to maintain linear history
- Every step should check existing state for idempotent resumability
