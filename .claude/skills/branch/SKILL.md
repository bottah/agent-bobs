---
description: Create a feature branch from main
---

# Branch Skill

Create a properly-named feature branch from `origin/main`.

## Inputs

The user may provide:
- A branch name (e.g., `feat/document-search`)
- A description (e.g., "add document search") — auto-converted to `type/kebab-name`
- Nothing — prompt for a name

## Steps

1. Check the current branch: `git branch --show-current`
   - If already on a feature branch, confirm with the user before switching
2. Validate or generate the branch name:
   - Must match: `type/short-kebab-description`
   - Valid types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`, `ci`
   - If the user gave a description, infer the type and convert to kebab-case
   - If ambiguous, ask the user to choose
3. Fetch the latest main: `git fetch origin main`
4. Check for uncommitted changes: `git status --porcelain`
   - If changes exist, offer to stash them: `git stash push -m "auto-stash before branch <name>"`
5. Create the branch from `origin/main` (not local main — avoids stale bases):
   ```
   git checkout -b <branch-name> origin/main
   ```
6. Confirm creation and remind the user of next steps:
   ```
   Created branch: <branch-name> (from origin/main)
   Next: make changes → /commit → /pr
   ```

## Rules

- Never branch from local main — always use `origin/main` to avoid stale bases
- Enforce the naming convention — reject names that don't match `type/kebab-name`
- If the user is already on the target branch, do nothing
- Do not create branches that already exist (check with `git branch --list`)
