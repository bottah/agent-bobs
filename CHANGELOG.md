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
- `tool-policy.json` rules blocking direct push to main/master and `--admin` bypass on `gh pr merge`
- Governance gate job in CI — single required check that aggregates all upstream jobs, decoupling CI additions from `ruleset.json` (#20)
- `customize_once` mechanism in `install.sh` — skip project-specific files (`README.md`, `CHANGELOG.md`, `CLAUDE.md`, `ci.yml`, `ruleset.json`) on re-install (#23, #27, #32)
- `/code-review` skill for beads-coordinated cross-platform code review workflow
- `beads-logger.sh` PostToolUse hook for `bd` command audit trail
- `.claude/code-review-workflow.yml` default config for reviewer, limits, and on-limit behavior
- `docs/BEADS.md` setup guide with configuration reference, reviewer interface, and troubleshooting
- Auto-allow for `bd` read commands (`ready`, `show`, `list`) in `auto-allow-reads.sh`
- Beads status display (active reviews, in-progress features) in `context-loader.sh` session start
- `pcre` mode for `tool-policy.sh` enabling negative lookahead patterns
- Merge-gate rule in `tool-policy.json` requiring `--squash` on `gh pr merge`

### Changed

- `install.sh` excludes `.beads` directory, adds `code-review-workflow.yml` to customize_once, optionally runs `bd init`

- Enhanced `/commit` skill with branch guard (refuses commit on main/master)
- Enhanced `/pr` skill with branch guard, rebase freshness check, SSH alias workaround, and self-review suggestion
- Improved Go linting in `post-edit-lint.sh` with go.mod directory discovery
- Updated reviewer agent to include `gh pr comment` in allowed tools
- `/review` skill extracts repo conditionally — only when interacting with GitHub, so local-only reviews work without a remote (#34, #37)

### Fixed

- Fixed `audit-logger.sh` jq string slicing syntax (`tostring[:500]` → `tostring | .[0:500]`) and added stderr suppression
- Fixed macOS-incompatible non-greedy regex in `/pr` skill sed command (`[^/]+?` → `[^/.]+`)
- `auto-allow-reads.sh` extracted only one word for `gh` subcommands, so no `gh` read commands were actually auto-allowed; added `pr checks` and `pr diff` (#25)
- Removed `env`/`printenv` from auto-allow-reads safe list — conflicted with `security-gate.sh` secret leakage protection (#31)
- Removed `.claude/settings.json` from `path-protector.sh` protected patterns — file is intentionally committed as repo config (#21)
- Repo extraction regex rejected dots in repo names (e.g., `owner/my.project.git`) (#30)
- `install.sh` copied session artifacts (transcript backups, session state, subagent logs, handoff docs) into target repos (#22)
- `install.sh` printed stale `agent-teams` project name instead of `agent-bobs` (#33)

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
