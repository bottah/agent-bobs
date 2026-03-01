# Beads Code Review Workflow

Cross-platform code review workflow where Claude implements features, an external reviewer (e.g., Codex) reviews PRs, and beads coordinates the handoff.

## Prerequisites

- **[bd CLI](https://github.com/plasticine-island/beads)** — the beads coordination tool
- **[gh CLI](https://cli.github.com/)** — GitHub CLI, authenticated (`gh auth login`)
- A git repository with a GitHub remote

## Configuration

The workflow is configured via `.claude/code-review-workflow.yml`:

```yaml
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

| Key | Description | Default |
|-----|-------------|---------|
| `reviewers` | Map of reviewer names to config. v1 uses only the first entry. | `codex` |
| `reviewers.<name>.focus` | Review focus areas for the reviewer | — |
| `limits.max_review_cycles` | Max fix/re-review cycles before flagging for human review | `3` |
| `limits.poll_interval_seconds` | How often Claude polls review bead status | `60` |
| `limits.max_wait_minutes` | Max wait time before Claude pauses | `30` |
| `on_limit_reached.pr_label` | Label applied to PR when cycle limit is reached | `needs-human-review` |

## Usage

### Entry Points

```bash
/code-review #42              # From a GitHub issue
/code-review bd-abc           # Resume an existing feature bead
/code-review "add user search"  # From a description
/code-review                  # Pick from ready queue
```

### Workflow Steps

1. **Prerequisite check** — verify `bd`, `gh`, auth, beads DB, config
2. **Resolve issue** — create or find the feature bead
3. **Branch** — create `feat/<bead-id>-<slug>` (or reuse existing)
4. **Implement** — Claude implements the feature interactively
5. **Commit + PR** — conventional commit, push, open PR
6. **Create review bead** — full metadata for the configured reviewer
7. **Post GH event comment** — `<!-- beads-event -->` marker on PR
8. **Poll** — wait for reviewer verdict; handle approve/request-changes/timeout
9. **Merge** — verify merge gate, squash merge, delete branch
10. **Close feature bead** — mark as done with merge reason

### Resumability

Re-invoke `/code-review <bead-id>` at any point to resume from where the workflow left off. The skill detects existing state (branches, PRs, review beads) and skips completed steps.

## Reviewer Agent Interface

External reviewers poll for review beads and post GitHub reviews:

```
loop forever:
  ready = bd ready --json --label "reviewer:<id>"
  if ready is empty: sleep 60; continue

  bead_id = ready[0].id
  bd update <bead_id> --claim --json

  bead = bd show <bead_id> --json
  pr, repo, head_sha, feature_bead = bead.metadata

  # Fetch PR context
  gh pr view <pr> -R <repo> --json title,body,files
  gh pr diff <pr> -R <repo>
  bd show <feature_bead> --json

  verdict, review_body = perform_review(pr_diff, feature_context)

  if verdict is APPROVE:
    gh api repos/<repo>/pulls/<pr>/reviews \
      -f event=APPROVE -f body=<review_body> -f commit_id=<head_sha>
    bd close <bead_id> --reason "Approved at <head_sha>"

  if verdict is REQUEST_CHANGES:
    gh api repos/<repo>/pulls/<pr>/reviews \
      -f event=REQUEST_CHANGES -f body=<review_body> -f commit_id=<head_sha>
    bd update <bead_id> --status blocked \
      --append-notes "REQUEST_CHANGES: <review_body>"
```

**Reviewer requirements**: `bd` CLI, `gh` CLI, repo read access, review write access, no merge permission.

## Observability

### Audit Logs

`beads-logger.sh` logs all `bd` CLI invocations to `.claude/beads-audit.log` as structured JSON:

```json
{"ts":"2026-03-01T12:00:00Z","session":"abc","tool":"bd","subcmd":"create","command":"bd create --title ..."}
```

### PR Comments

The workflow posts `<!-- beads-event -->` marker comments on PRs at key lifecycle events:
- Review requested
- Review approved (with merge)
- Cycle limit reached

### PR Labels

When `max_review_cycles` is exhausted, the PR is labeled with the configured `on_limit_reached.pr_label` (default: `needs-human-review`).

## Troubleshooting

### `bd` CLI not found

Install the beads CLI. The workflow checks for `bd` at startup and in the session context loader.

### Review bead stuck in `open`

The reviewer agent hasn't claimed it yet. Check that the reviewer is running and polling with the correct label (`reviewer:<name>`).

### Review bead stuck in `in_progress`

The reviewer claimed it but hasn't posted a verdict. Check the reviewer agent logs. If the reviewer crashed, the bead may need manual intervention.

### Merge gate fails with SHA mismatch

The PR head changed after the review was submitted (e.g., someone pushed directly). The feature bead is set to `blocked`. Investigate the mismatch, then set the feature bead back to `open` and re-run `/code-review <bead-id>`.

### Cycle limit reached

The workflow exhausted `max_review_cycles` fix/re-review loops. The PR is labeled `needs-human-review` and the feature bead is `blocked`. A human should review the PR directly, then re-open the feature bead to resume.

### Timeout during polling

Claude waited `max_wait_minutes` without a review verdict. No bead state is modified. Resume with `/code-review <bead-id>`.

### Beads database not initialized

Run `bd init` in your project root, or re-run `install.sh` which will initialize it automatically if `bd` is available.
