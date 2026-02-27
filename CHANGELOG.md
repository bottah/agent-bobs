# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

## Unreleased

### Added

- Default `permissions.allow` and `permissions.deny` rules in `settings.json` to reduce prompt friction
- `/branch` skill for creating properly-named feature branches from `origin/main`
- `/protect` skill for applying GitHub branch protection rulesets from `.github/ruleset.json`
- `.github/workflows/ci.yml` scaffold with placeholder lint, test, and build jobs
- `.github/ruleset.json` declarative branch protection config (squash-only, linear history, status checks)
- `.github/pull_request_template.md` with Summary, Changes, Test Plan, and Notes sections
- Git-Ops Workflow section in `CLAUDE.md` documenting multi-layer enforcement of feature-branch development
- Auto-post review findings as PR comment via `gh pr comment` in `/review` skill
- Main-branch warning in `context-loader.sh` at session start
- `tool-policy.json` rules blocking direct push to main/master

### Changed

- Enhanced `/commit` skill with branch guard (refuses commit on main/master)
- Enhanced `/pr` skill with branch guard, rebase freshness check, SSH alias workaround, and self-review suggestion
- Improved Go linting in `post-edit-lint.sh` with go.mod directory discovery
- Updated reviewer agent to include `gh pr comment` in allowed tools

### Fixed

- Fixed `audit-logger.sh` jq string slicing syntax (`tostring[:500]` → `tostring | .[0:500]`) and added stderr suppression
- Fixed macOS-incompatible non-greedy regex in `/pr` skill sed command (`[^/]+?` → `[^/.]+`)

## [0.1.0] - 2026-02-06

### Security

- Restricted builder agent from web access (WebSearch/WebFetch) to prevent prompt injection via untrusted content
- Fixed auto-allow hook bypassing pipe commands (`ls | tee malicious_file` was silently auto-allowed)
- Moved curl/wget pipe-to-shell patterns to regex matching in `security-gate.sh` (substring matching silently failed)

### Fixed

- Added required `hookEventName` to all hook output JSON -- without it, Claude Code silently ignored every hook response
- Fixed `grep -P` (Perl regex) usage across hooks -- not available on macOS
- Fixed `git -C <path>` commands not recognized by auto-allow hook
- Fixed broken JSON string concatenation in `post-edit-lint.sh` and `affected-tests.sh`
- Fixed `timeout` command in `affected-tests.sh` for macOS compatibility (falls back to `gtimeout`)
- Fixed `audit-logger.sh` JSON truncation that could produce malformed log entries
- Removed `> /dev/null` false positive from `security-gate.sh`

### Added

- `README.md` with project overview, quick start, and reference tables
- Hook output format reference in `docs/HOOKS.md` with correct JSON for all event types

### Changed

- Streamlined `/commit` skill from 9 steps to 3 (single prompt for related changes)
