# Multi-Agent Template for Claude Code

Boilerplate for multi-agent orchestration in Claude Code. Four layers: **agents** (permission boundaries), **skills** (reusable workflows), **hooks** (programmatic guardrails), and **team commands** (multi-session coordination).

## Agent Inventory

| Agent | Tools | Purpose |
|-------|-------|---------|
| `reader` | Read, Glob, Grep | Read-only codebase exploration |
| `builder` | Read, Glob, Grep, Edit, Write, Bash, Task, NotebookEdit | Full implementation (no web access) |
| `reviewer` | Read, Glob, Grep, git read commands | Code review without write access |
| `researcher` | Read, Glob, Grep, WebSearch, WebFetch | Web + codebase research |

## Skill Inventory

| Skill | Context | Description |
|-------|---------|-------------|
| `/changelog` | main | Update CHANGELOG.md with unreleased changes |
| `/commit` | main | Interactive staged git commit workflow |
| `/review` | fork → `reviewer` | Code review with checklist (reads `REVIEW_GUIDELINES.md` if present) |
| `/test` | fork → `builder` | Run tests and summarize results |
| `/plan` | main | Interactive implementation planning |
| `/pr` | main | Create or update pull requests via `gh` |
| `/loop` | main | Iterative fix-and-check until a condition is met |
| `/handoff` | main | Generate session handoff document |

## Team Templates

| Command | Composition | Use Case |
|---------|-------------|----------|
| `/team-feature` | lead + builder(s) + reader + reviewer | End-to-end feature implementation |
| `/team-review` | lead + 3 reviewers (security, quality, coverage) | Multi-perspective code review |
| `/team-research` | lead + 2-4 readers | Parallel codebase/web exploration |
| `/team-debug` | lead + 3-5 investigators | Competing hypothesis debugging |

## Dev Commands

Replace these placeholders with your project's actual commands. Hooks like `post-edit-lint.sh` and `affected-tests.sh` auto-detect frameworks, but explicit commands here let Claude run them directly.

```bash
# test   = <your test command>
# lint   = <your lint command>
# build  = <your build command>
# run    = <your start command>
```

## Git Conventions

- Use [conventional commits](https://www.conventionalcommits.org/): `type(scope): description`
- Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`, `ci`
- Keep commits atomic -- one logical change per commit
- Write commit messages that explain *why*, not just *what*

## Hooks (Programmatic Guardrails)

Hooks are shell scripts that fire at lifecycle events, enforcing rules that agents can't override. Configured in `.claude/settings.json`, scripts live in `scripts/hooks/`.

| Hook | Event | Scope | Purpose |
|------|-------|-------|---------|
| `security-gate.sh` | PreToolUse → Bash | Universal | Block dangerous bash patterns |
| `tool-policy.sh` | PreToolUse → Bash | Template | Intercept commands, suggest alternatives (config-driven) |
| `path-protector.sh` | PreToolUse → Edit\|Write | Universal | Protect `.env*`, credentials, secrets |
| `audit-logger.sh` | PostToolUse → all | Universal | Structured JSON audit trail |
| `auto-allow-reads.sh` | PermissionRequest | Universal | Auto-allow read-only tools and safe bash commands |
| `pre-compact-backup.sh` | PreCompact | Universal | Back up transcript before context compression |
| `desktop-notify.sh` | Notification | Universal | Desktop notification when agent waits for input |
| `session-cleanup.sh` | Stop | Universal | Capture session memory + clean up stale artifacts |
| `subagent-log.sh` | SubagentStop | Universal | Log subagent/teammate completion for audit |
| `post-edit-lint.sh` | PostToolUse → Edit\|Write | Template | Run linter, feed errors to Claude |
| `affected-tests.sh` | PostToolUse → Edit\|Write | Template | Run related tests, feed failures to Claude |
| `context-loader.sh` | SessionStart | Template | Inject git status and recent commits |

See `docs/HOOKS.md` for configuration, customization, and gotchas.

## Constraints

- Never commit secrets, credentials, or `.env` files
- Prefer editing existing files over creating new ones
- Run tests before marking implementation tasks complete
- Use the least-privileged agent for each task (reader > reviewer > builder)
- Keep skill outputs concise -- fork into sub-agents for large operations
