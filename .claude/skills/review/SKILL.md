---
description: Code review with checklist
context: fork
agent: reviewer
---

# Review Skill

Perform a structured code review using the reviewer agent.

## Inputs

The user may provide:
- A file path or glob pattern to review
- A git ref range (e.g., `main..HEAD`)
- A PR number (e.g., `#123`)
- Nothing (defaults to uncommitted changes)

## Steps

1. Determine the scope of review:
   - If a PR number is given: extract repo first, then fetch the diff:
     ```bash
     repo=$(git remote get-url origin | sed -E 's|(\.git)$||; s|.*[:/]([^/]+/[^/]+)$|\1|')
     gh pr diff <number> -R "$repo"
     ```
   - If a git range is given: `git diff <range>`
   - If a file/glob is given: read those files
   - If nothing: `git diff` (staged + unstaged)
2. Read the checklist from `checklist.md`
3. Check for a `REVIEW_GUIDELINES.md` file in the repository root. If it exists, read it and apply its project-specific criteria **in addition to** the built-in checklist. Project guidelines take precedence when they conflict with the default checklist.
4. For each checklist category, evaluate the code and note findings
5. Produce a structured review report:

```
## Review Summary

**Scope**: [what was reviewed]
**Verdict**: [approve / request changes / comment]

### Critical Issues
- ...

### Warnings
- ...

### Suggestions
- ...

### Checklist Results
| Category | Status | Notes |
|----------|--------|-------|
| ... | pass/warn/fail | ... |
```

6. **Post to PR**: If the review is for a PR (PR number given, or the current branch has an open PR), post the review:
   - **Extract repo** if not already done in step 1 (SSH aliases prevent `gh` auto-detection):
     ```bash
     repo=$(git remote get-url origin | sed -E 's|(\.git)$||; s|.*[:/]([^/]+/[^/]+)$|\1|')
     ```
   - Detect open PR: `gh pr view --json number -q .number -R "$repo" 2>/dev/null`
   - Get PR head SHA: `gh pr view <number> -R "$repo" --json headRefOid -q .headRefOid`
   - **Approve or request changes** → post a formal review via the wrapper:
     ```bash
     ./scripts/hooks/gh-review.sh --repo "$repo" --pr <number> \
       --event APPROVE --body "<review>" --commit-id <head_sha>
     ```
     (use `--event REQUEST_CHANGES` for request-changes verdicts)
   - **Comment only** (no verdict) → `gh pr comment <number> -R "$repo" --body "<review>"` (use a HEREDOC for the body)
   - If no PR is associated or no remote is configured, just output the review to the terminal

## Rules

- Be specific: always include file paths and line numbers
- Prioritize correctness and security over style
- Acknowledge good patterns, not just problems
- When using any `gh` command, always extract the repo first and pass `-R owner/repo` (SSH aliases prevent auto-detection)

## Project-Specific Guidelines

Teams can customize reviews by creating a `REVIEW_GUIDELINES.md` in the repository root. This file can contain:

- Additional checklist items specific to the project
- Domain-specific review criteria (e.g., accessibility, i18n, API compatibility)
- Patterns to watch for or explicitly allow
- Severity overrides (e.g., treat a default "suggestion" category as "critical")

If the file is absent, only the built-in checklist is used.
