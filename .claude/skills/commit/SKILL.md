---
description: Interactive staged git commit workflow
---

# Commit Skill

Create a well-formed git commit interactively.

## Steps

0. **Branch guard**: Run `git branch --show-current`. If on `main` or `master`, **STOP** and tell the user:
   > You're on the main branch. Use `/branch` to create a feature branch before committing.
   Do NOT proceed with the commit.
1. Run `git status`, `git diff`, and `git diff --cached` in parallel
2. Analyze the changes:
   - If all changes are clearly related: propose staging all files and a draft commit message in a single prompt
   - If changes are mixed or unrelated: ask which files to stage first, then draft the message
3. Stage, commit, and show `git log --oneline -3` to confirm

Draft messages use conventional commits: `type(scope): description`. Focus on *why*, not *what*.

## Rules

- Refuse to commit on `main` or `master` — redirect to `/branch`
- Never stage `.env`, credentials, or secret files
- Never use `--no-verify` unless the user explicitly requests it
- Always show the user what will be committed before committing
- Use `Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>` trailer
