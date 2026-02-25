# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

## Unreleased

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
