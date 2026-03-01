# Feedback: Current `-v1` / `-v2` Workflow Split

The split now mostly matches the intended layering. `code-review-workflow-v1.md` reads like a real single-reviewer baseline, and `code-review-workflow-v2.md` reads like additive hardening on top of that baseline.

## What Is Now Correctly Split

1. v1 is clearly single-reviewer.

- v1 explicitly scopes to one active reviewer end to end, selected from the first configured reviewer entry (default: `codex`).
- The v1 issue graph, merge gate, and reviewer loop all operate on one reviewer.
- Multi-reviewer coordination is explicitly deferred to v2.

2. `superseded` is correctly isolated to v2.

- v1 leaves older review beads in place and treats the highest `cycle` as active.
- v2 introduces `superseded` for explicit retirement and historical bookkeeping.

3. Rich GitHub observability is now mostly v2-only.

- v1 uses the formal GitHub review plus a small set of event comments.
- v2 adds the live-updating status comment and richer event taxonomy.

4. `on_limit_reached.notify` is now consistently v2-only.

- v1 always posts the limit-reached event comment.
- v2 introduces `on_limit_reached.notify` as the toggle for suppressing that comment.

## Remaining Notes

1. Reviewer identity is consistent at the rule level, and the remaining `codex` references are intentional examples/defaults.

- v1 consistently defines the active reviewer as the first configured reviewer (default: `codex`), and v2 matches that framing.
- The remaining `codex` references are limited to examples: the sample issue graph, sample metadata, sample config, and example reviewer IDs in v2.
- Per the current decision, that is intentional example/default language, not a contradiction and not a required spec change.

## Recommended Follow-Up

- Keep the v1/v2 split as it is now.
- No spec changes are required based on the current files.

This feedback is based only on `code-review-workflow-v1.md` and `code-review-workflow-v2.md`.
