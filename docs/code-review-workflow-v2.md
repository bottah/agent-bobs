# Beads Code Review Workflow — v2

Hardening, resilience, and advanced features layered on top of v1. All items here assume the v1 workflow is working end-to-end with a single configured reviewer.

See `code-review-workflow-v1.md` for the baseline.

---

## Multiple Concurrent Reviewers

v1 supports one configured reviewer. v2 enables multiple reviewers active at once (e.g., codex + gemini).

### Changes from v1

- Config: multiple entries under `reviewers:` are all exercised (not just the first).
- Claude creates one review bead per reviewer.
- **Re-review policy**: when Claude pushes fixes, ALL reviewers must re-review. A fix for one reviewer's feedback can introduce issues in another reviewer's domain. All reviewers must approve the same `head_sha`.
- **Merge gate**: all reviewers' active review beads must be `closed` (not just one).
- **Polling**: Claude tracks each reviewer independently. Some may be `closed` while others are still `in_progress`.

### Cross-Reviewer Synchronization

When any reviewer posts REQUEST_CHANGES:
1. Claude waits until no review beads are `in_progress` (all active reviewers have finished their current review).
2. Claude supersedes ALL current-cycle beads (see `superseded` state below).
3. Claude creates fresh `open` beads for ALL reviewers with the new `head_sha` and incremented `cycle`.

This prevents reviewing stale code and ensures all reviewers evaluate the same commit.

### Updated Issue Graph

```
bd-001: "Add user search" (type=feature, status=in_progress, assignee=claude)
  ├── bd-002: "Review PR #42 [codex]" (type=review, label=reviewer:codex, blocks bd-001)
  └── bd-003: "Review PR #42 [gemini]" (type=review, label=reviewer:gemini, blocks bd-001)
```

### Updated Merge Gate

Merge is permitted only when **all** of the following are true:

1. For every configured reviewer, the active review bead (highest `cycle`) is `closed`.
2. No active review bead is in `open`, `in_progress`, or `blocked`.
3. Every active closed bead's `head_sha` matches the current PR head.
4. `cycle <= max_review_cycles` (the current cycle is within the allowed range).

---

## `superseded` State

v1 leaves old-cycle beads in their terminal state and ignores them by cycle number. v2 introduces an explicit `superseded` state for cleaner bookkeeping.

### Additional Review Bead Transitions

| State | Actor | Transition | Next State |
|-------|-------|------------|------------|
| `blocked` | Claude | New cycle started | `superseded` |
| `closed` | Claude | New cycle started (stale approval) | `superseded` |
| `open` | Claude | New cycle started (unclaimed) | `superseded` |
| `open` | Claude | Stale SHA detected, full cycle reset | `superseded` |
| `superseded` | — | Terminal (historical record) | — |

### Cycle Rotation

When Claude pushes fixes and starts a new cycle:
1. Claude waits until no beads are `in_progress`.
2. Claude supersedes ALL current-cycle beads (any state except `in_progress`).
3. Claude creates fresh `open` beads for ALL reviewers with new `head_sha` and incremented `cycle`.

`superseded` beads are historical records — excluded from merge gate evaluation and reviewer polling.

**Command**: `bd update <id> --status superseded --append-notes "Superseded by cycle <N+1>" --json`

### Ownership Invariant

Claude never transitions a review bead to `closed`. That state is reserved exclusively for reviewer approval. When Claude needs to retire review beads (stale state, new cycle, PR merged/closed), it uses `superseded`.

---

## Updatable Status Comment

v1 uses simple append-only event comments. v2 adds a live-updating status table on the PR.

Claude maintains a **single status comment** on the PR, identified by a marker:

```markdown
<!-- beads-workflow-status -->
## Code Review Status

| Reviewer | Status | Cycle | SHA |
|----------|--------|-------|-----|
| codex | reviewing | 1/3 | abc1234 |
| gemini | waiting | 1/3 | abc1234 |

Last updated: 2026-03-01T10:30:00Z
```

**Idempotency**: Claude searches for existing comments containing `<!-- beads-workflow-status -->` before posting. If found, Claude updates via `gh api PATCH`. If not found, Claude creates a new comment.

### Extended Event Comments

v2 adds richer event taxonomy beyond v1's three events:

| Event | Comment |
|-------|---------|
| Review beads created | `<!-- beads-event --> Code review requested: codex, gemini` |
| Fix cycle started | `<!-- beads-event --> Review cycle 2/3: addressing codex feedback` |
| Limit reached | `<!-- beads-event --> Review cycle limit reached (3/3). PR flagged for human review.` |
| All reviews pass | `<!-- beads-event --> All reviewers approved at <sha>. Merging.` |

---

## Claim-Race Handling

Multiple agents may poll `bd ready` simultaneously. Claims are optimistic.

**Reviewer behavior on claim**:
1. Run `bd update <id> --claim --json`.
2. If the command fails (bead already claimed), exit cleanly and continue polling. Do not retry the same bead.
3. If the command succeeds, immediately re-read the bead (`bd show <id> --json`) and confirm:
   - `assignee` matches the reviewer's identity.
   - `status` is `in_progress`.
   - `head_sha` in metadata is present and valid.
4. If confirmation fails, release the bead (`bd update <id> --status open --assignee "" --json`) and continue polling.

**Duplicate session prevention**: Each reviewer should verify its `reviewer:<id>` label matches the bead's label before claiming. A codex instance must not claim a bead labeled `reviewer:gemini`.

---

## Reviewer Release Path

v1 treats `in_progress` as a one-way gate to `closed` or `blocked`. v2 adds a release path back to `open` for recoverable failures.

### Additional Review Bead Transitions

| State | Actor | Transition | Next State |
|-------|-------|------------|------------|
| `in_progress` | Reviewer | Claim verification failed | `open` |
| `in_progress` | Reviewer | `STALE_SHA` detected | `open` |
| `in_progress` | Reviewer | `INFRA_FAILURE` after retries | `open` |
| `in_progress` | Human | Abandoned claim (reviewer died) | `open` |

**Release command**: `bd update <id> --status open --assignee "" --append-notes "<REASON>: <details>" --json`

**Rules**:
- Reviewer release back to `open` is permitted only for: claim verification failure, `STALE_SHA` detection, or `INFRA_FAILURE` after retries.
- These are recovery paths, not errors. The bead returns to the pool for retry.
- A reviewer may only release a bead whose `--claim` it initiated. Claim verification failure counts — the reviewer ran `--claim`, so it is the claimer even if the post-claim state is unexpected.
- **Human override**: A human may release any abandoned `in_progress` bead regardless of who claimed it. This is the only recovery path when a reviewer dies mid-review. Claude cannot release `in_progress` beads — only humans and the claiming reviewer can.

---

## Head SHA Verification

Every review bead carries `head_sha` in metadata — the PR commit the review targets. Only Claude manages `head_sha`.

**On claim**: Reviewer reads `head_sha` from bead metadata and verifies it matches `gh pr view <pr> -R <repo> --json headRefOid -q .headRefOid`. If mismatched, the reviewer must **release the bead** and continue polling:

```
bd update <bead_id> --status open --assignee "" \
  --append-notes "STALE_SHA: bead head_sha does not match PR head" --json
```

Only Claude reconciles stale beads by superseding them and creating fresh ones with the correct SHA.

---

## STALE_SHA Reconciliation

When Claude detects a `STALE_SHA:` note in bead notes during polling, the PR head has changed outside the normal fix cycle (e.g., rebase, external push).

**Claude's response**:
1. Wait for any `in_progress` beads to finish.
2. Supersede ALL active beads in the current cycle.
3. Create fresh beads for ALL reviewers at the current PR head.
4. This does **NOT** increment the review cycle counter (it is a SHA reconciliation, not a fix response).

---

## INFRA_FAILURE Separation

v1 has no distinction between review verdicts and infrastructure errors. v2 adds the `INFRA_FAILURE:` notes prefix to separate them.

### Reviewer Behavior

| Failure | Behavior |
|---------|----------|
| `gh pr diff` fails | Retry up to 3 times with 5-second backoff. If all retries fail, release the bead with `INFRA_FAILURE:` note. |
| `bd update --claim` fails (network) | Retry up to 3 times with 5-second backoff. If all retries fail, continue polling. |
| `gh api` for posting review fails | Retry up to 3 times. If all fail, release the bead with `INFRA_FAILURE:` note. |

**Release command**: `bd update <id> --status open --assignee "" --append-notes "INFRA_FAILURE: <details>" --json`

### Claude's Polling Behavior

When Claude reads bead notes containing `INFRA_FAILURE:`, it:
- Logs the failure in the GH status comment.
- Does **not** treat it as `REQUEST_CHANGES`.
- Does **not** increment the review cycle counter.
- The bead remains `open` for the reviewer to retry on next poll cycle.

### Bead Notes Prefix Table

| Prefix | Meaning | Claude Action |
|--------|---------|---------------|
| `REQUEST_CHANGES:` | Reviewer posted REQUEST_CHANGES verdict | Increment cycle, fix code, supersede + re-queue |
| `INFRA_FAILURE:` | Transient infrastructure error | Log, do not increment cycle, wait for retry |
| `STALE_SHA:` | Reviewer detected head_sha mismatch | Full cycle reset (no cycle increment) |
| `TIMEOUT_ALERTED` | Unclaimed timeout alert already posted | Skip re-posting timeout alert |
| `REVIEW_STALLED` | In-progress stall alert already posted | Skip re-posting stall alert |

---

## Structured Error Handling

### Prerequisites

| Check | On Failure |
|-------|------------|
| `command -v bd` | Fail fast: "bd CLI not found. Install: `brew install beads` or `go install github.com/steveyegge/beads/cmd/bd@latest`" |
| `command -v gh` | Fail fast: "gh CLI not found. Install: `brew install gh`" |
| `gh auth status` | Fail fast: "gh not authenticated. Run `gh auth login`" |
| `bd ready --json` (test db access) | Fail fast: "beads not initialized. Run `bd init`" |

### Stale State Detection

| Condition | Behavior |
|-----------|----------|
| PR already merged | Claude detects via `gh pr view <pr> -R <repo> --json state -q .state`. Close feature bead: `bd close <id> --reason "PR already merged"`. Supersede remaining review beads. |
| PR closed (not merged) | Claude detects via `gh pr view <pr> -R <repo> --json state -q .state`, blocks feature bead: `bd update <id> --status blocked --append-notes "PR closed without merge"`. Supersede remaining review beads. |
| Feature bead already closed | Skill outputs "Issue already closed" and exits. |
| Review bead assigned to wrong reviewer | This is a post-claim verification failure (see Claim-Race Handling). The reviewer who ran `--claim` releases it (`--status open --assignee ""`) and continues polling. |

**Ownership invariant**: Claude never transitions a review bead to `closed`. That state is reserved exclusively for reviewer approval. When Claude needs to retire review beads (stale state, new cycle, PR merged/closed), it uses `superseded`.

---

## Reviewer Timeout Alerts

### Unclaimed Beads (`open`)

If a review bead has been `open` for longer than `max_wait_minutes` with no reviewer claiming it:

1. Claude posts an event comment: "Reviewer `<id>` has not claimed review bead after N minutes."
2. **This alert is emitted once per bead per cycle.** Claude records the alert by appending `TIMEOUT_ALERTED` to the bead notes, and checks for this marker before posting again.
3. Claude continues polling — does not auto-resolve or skip the reviewer.
4. The timeout is informational, not blocking. The workflow waits until the reviewer comes online or the human intervenes.

### Abandoned Reviews (`in_progress`)

If a review bead has been `in_progress` for longer than `max_wait_minutes` with no verdict posted:

1. Claude posts an event comment: "Reviewer `<id>` claimed review bead but has not posted a verdict after N minutes. Bead may be abandoned."
2. **This alert is emitted once per bead per cycle.** Claude records the alert by appending `REVIEW_STALLED` to the bead notes, and checks for this marker before posting again.
3. Claude continues polling — does not auto-release the bead. Only the claiming reviewer or a human may release it (see human override in Reviewer Release Path).
4. If the reviewer has died, the human must manually release the bead back to `open` (`bd update <id> --status open --assignee ""`). This returns it to the pool for the reviewer to reclaim on next poll. Do not use `closed` (reserved for reviewer approval) or `superseded` (reserved for Claude cycle rotation).

---

## Configurable `on_limit_reached.notify`

v1 always posts a limit-reached event comment and has no `notify` key in the config. v2 adds a `notify` option:

```yaml
on_limit_reached:
  pr_label: "needs-human-review"
  notify: true   # Default: true. Set to false to skip event comment.
```

When `notify: false`, Claude still applies the PR label and blocks the feature bead, but omits the PR event comment.

---

## Config Validation

v2 enforces schema rules on `code-review-workflow.yml`:

```yaml
# --- Required ---
reviewers:                          # At least one reviewer must be defined
  <id>:                             # Reviewer ID — must match label `reviewer:<id>`
    focus: "<string>"               # Description of review focus area
    github_login: "<string>"        # GitHub username for formal reviews via gh-review.sh

# --- Optional (with defaults) ---
limits:
  max_review_cycles: 3              # Default: 3. Range: 1-10.
  poll_interval_seconds: 60         # Default: 60. Range: 10-300.
  max_wait_minutes: 30              # Default: 30. Range: 5-120.

on_limit_reached:
  pr_label: "needs-human-review"    # Default: "needs-human-review"
  notify: true                      # Default: true.

# --- Disabling a reviewer ---
# Comment out or remove the reviewer entry. Do not use `enabled: false`.
```

**Validation rules**:
- `reviewers` must contain at least one entry.
- Each reviewer `<id>` must be a valid label-safe string (alphanumeric, hyphens, underscores).
- `focus` is required for each reviewer.
- `github_login` is required for each reviewer (used by `gh-review.sh` for identity validation).
- All `limits` fields are optional; defaults apply if omitted.
- Range checks applied to numeric fields.
- Unknown keys are ignored (forward-compatible).

---

## Linked Issue Discovery

Review beads link to the feature bead via `feature_bead` in metadata. v2 adds richer discovery on top of v1's `github_issue` field:

1. **Bead metadata**: `feature_bead` field → `bd show <feature_bead> --json` for full description and acceptance criteria.
2. **GitHub issue**: If the feature bead has `github_issue` in metadata (set by v1 when created via `/code-review #N`), reviewers may fetch it via `gh issue view <N> --json` for additional context (acceptance criteria, discussion, labels).
3. **PR body**: Claude includes "Resolves bd-001" in the PR body. When the feature bead was created from a GitHub issue, Claude also includes "Closes #N". Reviewers can extract these references.

Reviewers are not required to fetch linked issues. The PR diff + feature bead description should be sufficient context.

---

## Branch Naming Collision Handling

Branch name is derived from the feature bead: `<type>/<bead-id>-<slugified-title>`.

**Collision handling**: If the branch already exists (resume scenario), reuse it. Check via `git rev-parse --verify <branch> 2>/dev/null`.

**Type mapping**: `feature` → `feat`, `bug` → `fix`, `task` → `chore`, `chore` → `chore`. Default: `feat`.

---

## Updated Reviewer Agent Interface (v2)

The v2 reviewer loop adds claim verification, head SHA checking, and infra failure handling:

```
loop forever:
  # 1. Poll for assigned work
  ready = bd ready --json --label "reviewer:<id>"

  # 2. If no work, sleep and retry
  if ready is empty:
    sleep 60 seconds
    continue

  # 3. Claim the first available bead
  bead_id = ready[0].id
  result = bd update <bead_id> --claim --json
  if claim failed: continue  # already claimed by another agent

  # 4. Verify claim (v2: claim-race handling)
  bead = bd show <bead_id> --json
  verify: assignee matches self, status is in_progress, head_sha is present
  if verification fails: release bead and continue

  # 5. Fetch PR context
  pr, repo, head_sha, feature_bead = extract from bead.metadata
  gh pr view <pr> -R <repo> --json title,body,files
  gh pr diff <pr> -R <repo>
  bd show <feature_bead> --json  # feature context

  # 6. Verify head_sha matches current PR head (v2: STALE_SHA handling)
  current_head = gh pr view <pr> -R <repo> --json headRefOid -q .headRefOid
  if head_sha != current_head:
    bd update <bead_id> --status open --assignee "" \
      --append-notes "STALE_SHA: bead head_sha does not match PR head"
    continue

  # 7. Review (agent-specific logic)
  verdict, review_body = perform_review(pr_diff, feature_context)

  # 8. Post verdict to GitHub + update bead
  if verdict is APPROVE:
    ./scripts/hooks/gh-review.sh --repo <repo> --pr <pr> \
      --event APPROVE --body <review_body> --commit-id <head_sha>
    bd close <bead_id> --reason "Approved at <head_sha>" --json

  if verdict is REQUEST_CHANGES:
    ./scripts/hooks/gh-review.sh --repo <repo> --pr <pr> \
      --event REQUEST_CHANGES --body <review_body> --commit-id <head_sha>
    bd update <bead_id> --status blocked \
      --append-notes "REQUEST_CHANGES: <review_body>" --json
```

### v2 Additions (marked inline above)
- **Step 4**: Claim verification — re-read bead after claim to confirm ownership.
- **Step 6**: Head SHA verification — detect stale beads before reviewing.
- **Retry logic**: Steps 5 and 8 should retry up to 3 times with 5-second backoff. On exhaustion, release the bead with `INFRA_FAILURE:` note.

---

## Implementation Order

v2 work is layered on top of v1 PRs:

### PR 4: Claim-Race + Release Path
- Claim verification in reviewer loop
- Release path (`in_progress` → `open`) for claim failure
- Head SHA verification before review

### PR 5: Error Handling + Resilience
- `STALE_SHA` reconciliation in Claude's polling loop
- `INFRA_FAILURE` separation (notes prefix, no cycle increment)
- Transient retry with backoff (reviewer side)
- Stale state detection (PR merged/closed)

### PR 6: Observability + Config Hardening
- Reviewer timeout alerts with `TIMEOUT_ALERTED` dedupe marker
- Configurable `on_limit_reached.notify`
- Config validation (schema enforcement, range checks)
- Linked issue discovery (reviewer fetches `github_issue` from feature bead)

---

## Verification (v2)

1. Two reviewers claim same bead simultaneously → loser skips cleanly, winner proceeds
2. Reviewer claims bead, re-read shows wrong assignee → releases and continues polling
3. Reviewer claims bead, head_sha doesn't match PR head → releases with `STALE_SHA` note
4. Claude sees `STALE_SHA` note → supersedes all active beads, creates fresh beads, no cycle increment
5. `gh pr diff` fails 3 times → reviewer releases bead with `INFRA_FAILURE` note, continues polling
6. Claude sees `INFRA_FAILURE` note → logs it, does not increment cycle, waits for retry
7. PR merged externally → Claude detects, closes feature bead, supersedes review beads
8. PR closed without merge → Claude blocks feature bead, supersedes review beads
9. Reviewer bead unclaimed for `max_wait_minutes` → single timeout alert posted, no duplicate
10. `on_limit_reached.notify: false` → label applied, no event comment posted
11. Invalid `code-review-workflow.yml` → fail fast with specific validation error
