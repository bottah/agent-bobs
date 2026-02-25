---
description: Update CHANGELOG.md with unreleased changes
---

# Changelog Skill

Update the project changelog with notable changes since the last release.

## Inputs

The user may provide:
- A baseline version or tag (e.g., `v1.2.0`)
- Nothing (defaults to the most recent git tag)

## Steps

1. Determine the baseline version:
   - If provided by the user, use that
   - Otherwise: `git describe --tags --abbrev=0`
   - If no tags exist, use the initial commit
2. Gather commits since the baseline:
   ```bash
   git log <baseline>..HEAD --pretty=format:"%h %s"
   ```
3. Read the existing `CHANGELOG.md` (or `CHANGELOG` if no `.md` variant exists)
4. Categorize the notable commits and draft new entries for the **Unreleased** section
5. Show the draft entries to the user for confirmation or edits
6. Update the changelog file

## Content Rules

- **Include**: features, fixes, breaking changes, deprecations, security patches
- **Exclude**: typo fixes, internal refactoring, CI tweaks, dependency bumps (unless security-related)
- Reference pull requests (`#NUMBER`) when available; never include raw commit hashes
- Group related changes into a single entry when appropriate
- Order by importance: breaking changes → features → fixes

## Style Rules

- Match the existing changelog's formatting (heading style, bullet character, spacing)
- Start each entry with a past-tense verb or descriptive phrase
- Keep entries concise but specific enough to understand the change
- Format code references with backticks
- If no Unreleased section exists, add one at the top in the same style as existing sections

### Good Examples

- `Added multi-key support to the sort filter. #827`
- `Fixed an issue where config parsing failed on Windows paths.`
- `Improved error reporting when task claim expires.`

### Bad Examples

- `Fixed bug` — too vague
- `Updated dependencies` — insignificant unless security-related
- `Refactored internal code structure` — not user-facing
- `Various improvements` — meaningless

## Notes

- If an Unreleased section already has content, append to it rather than replacing it
- If the repo has no changelog file, create `CHANGELOG.md` with a standard header
- When unsure whether a change is notable, err on the side of including it
- This skill pairs well with `/commit` — run `/changelog` before tagging a release
