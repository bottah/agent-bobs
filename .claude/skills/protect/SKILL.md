---
description: Configure GitHub branch protection rulesets
---

# Protect Skill

Apply branch protection rulesets from the declarative config at `.github/ruleset.json`.

## Source of Truth

`.github/ruleset.json` defines both the branch ruleset and repo merge settings. This file is version-controlled. The `/protect` skill reads it and applies it via `gh api` — no interpretation, no drift.

To change protection rules, edit `.github/ruleset.json` and re-run `/protect`.

## Prerequisites

- `gh` CLI authenticated with **admin** access to the target repository
- Switch to `bottah` account if needed: `gh auth switch --user bottah`

## Steps

1. **Auto-detect repository**: Extract owner/repo from `git remote get-url origin`
   - Parse `user/repo.git` from the URL (handles SSH aliases like `github.com-bottah`)
   - Confirm with the user: "Apply ruleset to **owner/repo**?"
2. **Check authentication**: `gh api repos/{owner}/{repo} --jq '.permissions.admin'`
   - If not `true`, warn and exit with instructions
3. **Read config**: Read `.github/ruleset.json` from the repo root
   - If the file is missing, stop and tell the user to create it
4. **Check existing rulesets**: `gh api repos/{owner}/{repo}/rulesets`
   - If a ruleset with the same name exists, update it (PUT) instead of creating (POST)
   - If no match, create a new one
5. **Apply ruleset**:
   - Create: `gh api repos/{owner}/{repo}/rulesets -X POST --input <(jq '.ruleset' .github/ruleset.json)`
   - Update: `gh api repos/{owner}/{repo}/rulesets/{id} -X PUT --input <(jq '.ruleset' .github/ruleset.json)`
6. **Apply repo settings**: Read `.repo_settings` from the config and PATCH the repo:
   ```
   gh api repos/{owner}/{repo} -X PATCH --input <(jq '.repo_settings' .github/ruleset.json)
   ```
7. **Verify**: Fetch the ruleset back and diff against the config to confirm they match
8. **Show summary**: Print what was applied and any differences detected

## Rules

- Never hardcode repository names — always auto-detect from git remote
- The ONLY source of truth is `.github/ruleset.json` — do not invent rules from prose
- Always confirm with the user before applying
- If authentication is insufficient, exit gracefully with instructions
- Idempotent — safe to run multiple times (creates or updates as needed)
