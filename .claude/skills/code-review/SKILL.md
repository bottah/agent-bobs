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
bd create --title "<issue title>" --body "<issue body>" --type feature --json
```
Then update metadata with `github_issue` and `repo`:
```bash
bd update <bead-id> --set-metadata '{"github_issue": <N>, "repo": "<repo>"}'
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

bd create \
  --title "Review PR #<pr_number> [$reviewer]" \
  --type review \
  --label "reviewer:$reviewer" \
  --set-metadata "{\"pr\": <pr_number>, \"repo\": \"$repo\", \"head_sha\": \"$head_sha\", \"base_ref\": \"$base_ref\", \"head_ref\": \"$head_ref\", \"reviewer\": \"$reviewer\", \"cycle\": 1, \"feature_bead\": \"<feature_bead_id>\"}" \
  --json
```

### 6. Post GitHub event comment

Post a marker comment on the PR for observability:

```bash
gh pr comment <pr_number> -R "$repo" --body "$(cat <<'EVEOF'
<!-- beads-event -->
Code review requested: <reviewer>
EVEOF
)"
```

### 7. Poll loop

Poll the review bead status until resolution or timeout:

```bash
start_time=$(date +%s)
cycle=1  # current cycle number
# review_bead_id is set from step 5 (the bead created there)

while true; do
  sleep $poll_interval_seconds

  # Check elapsed time
  elapsed=$(( $(date +%s) - start_time ))
  if [ $elapsed -ge $(( max_wait_minutes * 60 )) ]; then
    echo "Timeout: waited ${max_wait_minutes} minutes with no review resolution."
    echo "Resume with: /code-review <feature-bead-id>"
    # Do NOT modify any bead state on timeout
    break
  fi

  # Check review bead status (always poll the current cycle's bead)
  review_status=$(bd show "$review_bead_id" --json | jq -r '.status')

  case "$review_status" in
    closed)
      # Reviewer approved — proceed to merge
      break
      ;;
    blocked)
      # Reviewer requested changes
      feedback=$(bd show "$review_bead_id" --json | jq -r '.notes' | grep 'REQUEST_CHANGES:')

      # Check cycle limit
      if [ $((cycle + 1)) -gt $max_review_cycles ]; then
        # Limit reached — flag and stop
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
      review_bead_id=$(bd create \
        --title "Review PR #<pr_number> [$reviewer] (cycle $cycle)" \
        --type review \
        --label "reviewer:$reviewer" \
        --set-metadata "{\"pr\": <pr_number>, \"repo\": \"$repo\", \"head_sha\": \"$head_sha\", \"base_ref\": \"$base_ref\", \"head_ref\": \"$head_ref\", \"reviewer\": \"$reviewer\", \"cycle\": $cycle, \"feature_bead\": \"<feature_bead_id>\"}" \
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
# 1. Active review bead (highest cycle) must be closed
review_status=$(bd show <active-review-bead-id> --json | jq -r '.status')
if [ "$review_status" != "closed" ]; then
  echo "Merge gate failed: review bead is '$review_status', not 'closed'."
  bd update <feature-bead-id> --status blocked
  exit 1
fi

# 2. Review bead head_sha must match current PR head
review_sha=$(bd show <active-review-bead-id> --json | jq -r '.metadata.head_sha')
pr_head=$(gh pr view <pr_number> -R "$repo" --json headRefOid -q .headRefOid)
if [ "$review_sha" != "$pr_head" ]; then
  gh pr comment <pr_number> -R "$repo" --body "<!-- beads-event --> Merge blocked: reviewed SHA ($review_sha) doesn't match PR head ($pr_head). Manual investigation required."
  bd update <feature-bead-id> --status blocked
  echo "Merge gate failed: SHA mismatch."
  exit 1
fi

# 3. Cycle must be within allowed range
review_cycle=$(bd show <active-review-bead-id> --json | jq -r '.metadata.cycle')
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

Check for existing state at each step before creating new artifacts.

## Rules

- All `gh` commands must use `-R owner/repo` (SSH aliases prevent auto-detection)
- Claude never closes review beads — only the reviewer can set `closed` status
- On timeout: do not modify any bead state, just pause and instruct to resume
- On cycle limit: label PR, block feature bead, stop
- Use `--squash` for all PR merges to maintain linear history
- Every step should check existing state for idempotent resumability
