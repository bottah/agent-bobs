---
description: Generate session handoff document
---

# Handoff Skill

Create a handoff document that captures the current session's context for a future session or teammate.

## Steps

1. Review the conversation history for:
   - What was accomplished
   - What's still in progress
   - Decisions made and their rationale
   - Blockers or open questions
2. Examine current state:
   - `git status` and `git log --oneline -10`
   - Any failing tests or known issues
3. Draft a handoff document using `template.md`
4. Present to the user for review and edits
5. Save to the location the user specifies (default: `docs/handoff-<date>T<HHMM>.md`, e.g. `docs/handoff-2026-02-19T2100.md`)

## Rules

- Be comprehensive but concise -- the reader should be able to pick up exactly where you left off
- Include concrete file paths and code references, not vague descriptions
- Distinguish between "done", "in progress", and "not started"
