---
description: Create or update pull requests
---

# PR Skill

Create or update a pull request using the `gh` CLI.

## Steps

1. **Branch guard**: Run `git branch --show-current`. If on `main` or `master`, **STOP** and tell the user:
   > You're on the main branch. Use `/branch` to create a feature branch before opening a PR.
   Do NOT proceed.
2. Check remote status:
   - `git status` (for uncommitted changes)
   - `git log main..HEAD --oneline` (or appropriate base branch)
3. If there are uncommitted changes, ask the user to commit first (or offer to run `/commit`)
4. **Rebase freshness check**: Fetch origin and check if branch is behind main:
   ```
   git fetch origin main
   git rev-list --count HEAD..origin/main
   ```
   If behind, warn: "Your branch is N commits behind origin/main. Consider rebasing: `git rebase origin/main`"
5. Push the branch if needed: `git push -u origin <branch>`
6. Check if a PR already exists: `gh pr view --json number,title,state 2>/dev/null`
7. If PR exists, ask user if they want to update it
8. If creating a new PR:
   - Analyze all commits since divergence from base branch
   - Draft title (under 70 chars) and body
   - Use this format for the body (matches `.github/pull_request_template.md`):
     ```
     ## Summary
     - [brief description of what and why]

     ## Changes
     - [bullet list of specific changes]

     ## Test Plan
     - [ ] [how to verify the changes]

     ## Notes
     [optional: migration steps, deployment considerations, follow-up work]

     Generated with Claude Code
     ```
   - **gh CLI workaround**: The remote may use an SSH alias (e.g., `github.com-bottah`). Auto-detect the owner/repo from the remote URL and pass `-R owner/repo` to `gh pr create`:
     ```
     remote_url=$(git remote get-url origin)
     # Extract owner/repo from SSH or HTTPS URL
     repo=$(echo "$remote_url" | sed -E 's|.*[:/]([^/]+/[^/.]+)(\.git)?$|\1|')
     gh pr create -R "$repo" --title "..." --body "..."
     ```
9. Show the PR URL to the user
10. Suggest self-review: "Run `/review main..HEAD` to self-review before requesting reviewers."

## Rules

- Refuse to create a PR from `main` or `master` — redirect to `/branch`
- Never force-push without explicit user confirmation
- Always show the PR content before creating
- Include all commits in the summary, not just the latest
- Always use `-R owner/repo` with `gh` to handle SSH alias remotes
