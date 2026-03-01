# Beads Code Review Workflow — v1

## Context

A **cross-platform code review workflow** where:
- **Claude** writes code, creates PRs
- **An external reviewer** (e.g., Codex, Gemini) reviews PRs by polling for beads review tasks
- **Beads** is the coordination bus — agents communicate through bead state changes
- **GitHub** hosts review artifacts (formal GH reviews, PR comments, labels)
- **Git-ops** enforces the review gate (branch protection, required reviews)

This workflow is **completely isolated** from Claude's native TaskCreate/TaskList/team system. Those continue to work independently for in-session coordination.

**v1 scope**: One reviewer end to end. The reviewer is determined by the first entry in `code-review-workflow.yml` (default: codex). Multi-reviewer coordination is deferred to v2.

## Architecture

```
  Claude (tmux pane 1)          Reviewer (tmux pane 2)
  ┌──────────────────┐          ┌──────────────────┐
  │ Implements code  │          │ Polls bd ready   │
  │ Creates PR       │          │ Claims review    │
  │ Creates review   │──beads──>│ Fetches PR diff  │
  │   bead           │          │ Posts GH review  │
  │ Polls for review │<─beads──│ Closes/blocks    │
  │   completion     │          │   review bead    │
  │ Fixes if needed  │          └──────────────────┘
  │ Merges when      │
  │   review passes  │
  └──────────────────┘
           │
     ┌─────▼─────┐
     │  GitHub    │
     │  PR + API  │  ← formal review, comments, labels, branch protection
     └───────────┘
```

**Communication flow**: Agents never talk directly. All coordination goes through:
1. **Beads** — state machine (create → claim → review → close/request-changes)
2. **GitHub** — review artifacts (formal GH review, PR comments)

## Beads Issue Graph

```
bd-001: "Add user search" (type=feature, status=in_progress, assignee=claude, github_issue=#7)
  └── bd-002: "Review PR #42 [codex]" (type=review, label=reviewer:codex, blocks bd-001)
```

The feature bead links back to the GitHub issue it was created from via `github_issue` in metadata.

---

## State Machine

### Feature Bead Lifecycle

| State | Actor | Transition | Next State |
|-------|-------|------------|------------|
| `open` | — | Claude claims | `in_progress` |
| `in_progress` | Claude | Review bead approved + merge gate passes | merge, then `closed` |
| `in_progress` | Claude | Review bead approved + merge gate fails | `blocked` |
| `in_progress` | Claude | `max_review_cycles` reached | `blocked` |
| `blocked` | Human | Re-opens | `open` |
| `closed` | — | Terminal | — |

### Review Bead Lifecycle

| State | Actor | Transition | Next State |
|-------|-------|------------|------------|
| `open` | — | Created by Claude | `open` (ready for pickup) |
| `open` | Reviewer | Claims | `in_progress` |
| `in_progress` | Reviewer | APPROVE | `closed` |
| `in_progress` | Reviewer | REQUEST_CHANGES | `blocked` |
| `closed` | — | Terminal (approved) | — |

On a new cycle, Claude creates a fresh review bead with an incremented `cycle`. The previous bead is left as-is — only the highest `cycle` is considered active.

### Ownership Rules

- Only the reviewer: `open` → `in_progress`, `in_progress` → `closed`/`blocked`.
- Only Claude: creates review beads and manages `cycle`/`head_sha`.
- Claude never sets a review bead to `closed`. That state is reserved for reviewer approval.

---

## Bead Metadata

### Feature Bead Metadata

```json
{
  "github_issue": 7,
  "repo": "owner/repo"
}
```

`github_issue` is set when the feature bead is created from a GitHub issue (`/code-review #7`). Omitted when created from a description or picked from ready queue.

### Review Bead Metadata

```json
{
  "pr": 42,
  "repo": "owner/repo",
  "head_sha": "abc1234def5678",
  "base_ref": "main",
  "head_ref": "feat/user-search",
  "reviewer": "codex",
  "cycle": 1,
  "feature_bead": "bd-001"
}
```

Only Claude manages `head_sha` and `cycle`.

---

## Review Cycle Semantics

### Re-Review After Fixes

When the reviewer posts REQUEST_CHANGES and Claude pushes fixes:
1. Claude creates a new review bead with the new `head_sha` and `cycle: N+1`.
2. The previous review bead remains in `blocked` state — it is ignored because only the highest `cycle` is active.

### Cycle Counting

- Cycles are 1-indexed. The first review bead has `cycle: 1`.
- `max_review_cycles: 3` allows cycles 1, 2, and 3.
- Claude stops when `cycle + 1 > max_review_cycles`.

---

## Merge Gate

Merge is permitted only when **all** of the following are true:

1. The active review bead (highest `cycle`) is `closed`.
2. The active review bead's `head_sha` matches the current PR head.
3. `cycle + 1 > max_review_cycles` has not triggered.

"Active" = the review bead with the highest `cycle` value. Previous-cycle beads are ignored.

**If the merge gate fails** (e.g., `head_sha` mismatch because the PR head changed outside the normal fix cycle), Claude posts an event comment explaining the mismatch, sets the feature bead to `blocked`, and stops. The human must investigate and re-open the feature bead to resume. Automatic stale-head recovery is deferred to v2.

---

## Review Feedback Format

### REQUEST_CHANGES

```
## Summary
<1-2 sentence overview>

## Blocking Issues
- [ ] <file:line> <description>

## Nits (non-blocking)
- <file:line> <suggestion>
```

At least one blocking issue required. Nits-only = APPROVE with comments.

### APPROVE

```
## Summary
<1-2 sentence overview>

## Notes (optional)
- <observations>
```

### Bead Notes Prefix

Claude identifies review feedback by `REQUEST_CHANGES:` prefix in bead notes.

---

## Observability (GitHub)

v1 uses minimal GitHub mirroring. The formal GH review from the reviewer is the primary artifact.

| Event | GitHub Action |
|-------|---------------|
| Review bead created | PR comment: `<!-- beads-event --> Code review requested: <reviewer>` |
| Review approved | PR comment: `<!-- beads-event --> <reviewer> approved at <sha>. Merging.` |
| Limit reached | PR comment: `<!-- beads-event --> Review cycle limit reached (N/N). PR flagged for human review.` + PR label |

Reviewers post formal GH reviews (not comments). Only Claude posts PR comments.

---

## `code-review-workflow.yml`

```yaml
# .claude/code-review-workflow.yml
#
# Cross-platform code review workflow.
# Claude implements. External reviewer reviews. Beads coordinates.
#
# v1 uses only the first reviewer listed below.
# Additional entries are accepted but ignored until v2.

reviewers:
  codex:
    focus: "security, correctness, edge cases, error handling"

limits:
  max_review_cycles: 3          # max fix/re-review loops before flagging
  poll_interval_seconds: 60     # how often Claude checks review status
  max_wait_minutes: 30          # max time Claude waits before pausing

on_limit_reached:
  pr_label: "needs-human-review"
```

**Required**: `reviewers` with at least one entry. v1 uses only the first reviewer; additional entries are accepted but ignored until v2.

---

## `/code-review` Skill

**Entry points**:
- `/code-review #42` — create feature bead from GitHub issue #42, then work on it
- `/code-review bd-abc` — work on existing feature bead
- `/code-review "add user search"` — create feature bead from description, work on it
- `/code-review` — pick from `bd ready --json`

**Execution**:

1. **Prerequisite check**: `bd`, `gh`, `gh auth status`, beads db.
2. **Resolve issue**:
   - If GitHub issue (`#N`): extract repo from `git remote get-url origin`, fetch via `gh issue view <N> -R <repo> --json title,body,labels`, create feature bead with title/body, store `"github_issue": N` and `"repo": "<repo>"` in bead metadata.
   - If bead ID (`bd-abc`): use existing bead.
   - If description string: create feature bead with that description.
   - If nothing: pick from `bd ready --json`.
   - Claim the feature bead.
3. **Branch**: `<type>/<bead-id>-<slugified-title>`. Reuse if exists.
4. **Implement**: Claude implements the feature.
5. **Commit + PR**: commit, push, create PR. Include `Resolves <bead-id>` in body. If created from a GitHub issue, also include `Closes #<N>`.
6. **Create review bead**: one bead for the configured reviewer with full metadata.
7. **Post GH event comment**: "Code review requested: `<reviewer>`".
8. **Poll** every `poll_interval_seconds`:
   - `closed` → reviewer approved. Proceed to merge.
   - `blocked` → read `REQUEST_CHANGES:` feedback.
     - If `cycle + 1 > max_review_cycles`: flag PR, block feature bead, stop.
     - Else: fix code, commit, push, create new review bead with `cycle: N+1`.
   - Elapsed `>= max_wait_minutes` with no changes → pause.
9. **Merge**: verify merge gate. `gh pr merge --squash --delete-branch`.
10. **Close feature bead**: `bd close <id> --reason "Merged via PR #<N>"`.

**Resumability**: re-invocation detects existing state and resumes from the appropriate step.

---

## Reviewer Agent Interface (Pseudocode)

```
# <id> = the configured reviewer (e.g., "codex")
loop forever:
  ready = bd ready --json --label "reviewer:<id>"
  if ready is empty: sleep 60; continue

  bead_id = ready[0].id
  claim = bd update <bead_id> --claim --json
  if claim failed: continue

  bead = bd show <bead_id> --json
  pr, repo, head_sha, feature_bead = bead.metadata

  gh pr view <pr> -R <repo> --json title,body,files
  gh pr diff <pr> -R <repo>
  bd show <feature_bead> --json

  verdict, review_body = perform_review(pr_diff, feature_context)

  if verdict is APPROVE:
    gh api repos/<repo>/pulls/<pr>/reviews -f event=APPROVE -f body=<review_body> -f commit_id=<head_sha>
    bd close <bead_id> --reason "Approved at <head_sha>"

  if verdict is REQUEST_CHANGES:
    gh api repos/<repo>/pulls/<pr>/reviews -f event=REQUEST_CHANGES -f body=<review_body> -f commit_id=<head_sha>
    bd update <bead_id> --status blocked --append-notes "REQUEST_CHANGES: <review_body>"
```

**Requirements**: `bd` CLI, `gh` CLI, repo read access, review write access, no merge permission.

---

## Permissions Model

| Role | Repo | bd | gh | Merge |
|------|------|----|----|-------|
| Claude | read + write | all commands | PR create/merge/comment/edit, API | yes |
| Reviewer | read only | ready, show, list, update, close (own beads) | pr view, pr diff, API (post reviews only) | **no** |

---

## Timeout and Limit Behavior

### `max_review_cycles` Reached

1. Post event comment: "Review cycle limit reached (N/N). PR flagged for human review."
2. Apply PR label `needs-human-review`.
3. Set feature bead to `blocked`.
4. Leave review beads as-is. Stop.

**Resume**: human sets feature bead to `open`, Claude re-runs `/code-review <id>`.

### `max_wait_minutes` Reached

1. Output timeout message. Do not modify any bead state.
2. Session ends. Resume with `/code-review <id>`.

---

## New Files

| File | Purpose |
|------|---------|
| `.claude/code-review-workflow.yml` | Config |
| `.claude/skills/code-review/SKILL.md` | Orchestration skill |
| `scripts/hooks/beads-logger.sh` | Audit logging for bd commands |
| `docs/BEADS.md` | Setup + reviewer interface docs |

## Modified Files

| File | Change |
|------|--------|
| `install.sh` | `.beads` exclude, `code-review-workflow.yml` customize_once, optional `bd init` |
| `.claude/settings.json` | `Bash(bd *)` permission, beads-logger hook |
| `scripts/hooks/auto-allow-reads.sh` | Auto-allow `bd ready`, `bd show`, `bd list` |
| `scripts/hooks/context-loader.sh` | Beads status at session start |
| `scripts/hooks/tool-policy.json` | Merge-gate rule |
| `CLAUDE.md` | Code-review-workflow section |

## What This Does NOT Touch

Claude native TaskCreate/TaskList/TaskUpdate, TeamCreate/SendMessage, existing skills, existing team commands, existing agent definitions.

---

## Implementation Order

### PR 1: Foundation
- `beads-logger.sh`, auto-allow-reads, context-loader, settings.json, install.sh, tool-policy merge gate

### PR 2: Workflow + Skill
- `code-review-workflow.yml`, `skills/code-review/SKILL.md`

### PR 3: Docs
- `docs/BEADS.md`, CLAUDE.md updates

---

## v2 Considerations

The following are deferred to v2. See `code-review-workflow-v2.md` for full spec.

- **Multiple concurrent reviewers**: multi-reviewer coordination, cross-reviewer sync
- **`superseded` state**: historical bead bookkeeping, explicit cycle rotation across many beads
- **Updatable status comment**: live PR status table with `gh api PATCH`
- **Claim-race handling**: optimistic claim with verify-after-claim, duplicate session prevention
- **Reviewer release path**: `in_progress` → `open` for claim failure, STALE_SHA, INFRA_FAILURE
- **STALE_SHA reconciliation**: reviewer detects head mismatch, releases bead, Claude triggers full cycle reset
- **INFRA_FAILURE separation**: distinct notes prefix, reviewer releases to `open` (not `blocked`), Claude does not increment cycle
- **Head SHA verification**: reviewer verifies `head_sha` matches PR head before reviewing
- **Structured error handling**: prerequisite checks, transient retry with backoff, stale state detection (PR merged/closed)
- **Reviewer timeout alerts**: one-time `TIMEOUT_ALERTED` marker per bead per cycle
- **Configurable `on_limit_reached.notify`**: conditional event comment posting
- **Config validation**: schema enforcement, required vs optional fields, range checks
- **Linked issue discovery**: reviewer fetches `github_issue` from feature bead for richer context
- **Branch naming collision handling**: reuse existing branch on resume
