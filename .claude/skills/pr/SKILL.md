---
description: Create or update pull requests
---

# PR Skill

Create or update a pull request using the `gh` CLI.

## Steps

1. Check current branch and remote status:
   - `git branch --show-current`
   - `git status` (for uncommitted changes)
   - `git log main..HEAD --oneline` (or appropriate base branch)
2. If there are uncommitted changes, ask the user to commit first (or offer to run `/commit`)
3. Push the branch if needed: `git push -u origin <branch>`
4. Check if a PR already exists: `gh pr view --json number,title,state 2>/dev/null`
5. If PR exists, ask user if they want to update it
6. If creating a new PR:
   - Analyze all commits since divergence from base branch
   - Draft title (under 70 chars) and body
   - Use this format for the body:
     ```
     ## Summary
     - [bullet points describing changes]

     ## Test Plan
     - [ ] [how to verify the changes]

     Generated with Claude Code
     ```
   - Create with `gh pr create --title "..." --body "..."`
7. Show the PR URL to the user

## Rules

- Never force-push without explicit user confirmation
- Always show the PR content before creating
- Include all commits in the summary, not just the latest
