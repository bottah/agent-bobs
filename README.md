# Multi-Agent Template for Claude Code

Boilerplate for multi-agent orchestration in [Claude Code](https://docs.anthropic.com/en/docs/claude-code). Four composable layers that work together or independently:

- **Agents** -- permission boundaries that restrict which tools a session can use
- **Skills** -- reusable workflows invoked as slash commands
- **Hooks** -- shell-script guardrails that fire at lifecycle events (agents can't override them)
- **Teams** -- multi-session coordination templates that spawn parallel agents

Agents, skills, and hooks work in any single-session workflow. Teams add parallelism on top.

## Quick Start

```bash
# Install into an existing project
./install.sh /path/to/your/project

# Review what changed
cd /path/to/your/project
git diff

# Accept
git add -A && git commit -m "chore: install agent-boilerplate"

# Or reject
git checkout -- .
```

After installing, open `CLAUDE.md` in your project and fill in the dev commands section:

```bash
# test   = npm test
# lint   = npm run lint
# build  = npm run build
# run    = npm start
```

Hooks like `post-edit-lint.sh` and `affected-tests.sh` auto-detect common frameworks, but explicit commands here let Claude run them directly.

## Agents

| Agent | Tools | Purpose |
|-------|-------|---------|
| `reader` | Read, Glob, Grep | Read-only codebase exploration |
| `builder` | Read, Glob, Grep, Edit, Write, Bash, Task, NotebookEdit | Full implementation (no web access) |
| `reviewer` | Read, Glob, Grep, git read commands | Code review without write access |
| `researcher` | Read, Glob, Grep, WebSearch, WebFetch | Web + codebase research |

Agents are defined in `.claude/agents/*.md`. Each file declares an `allowed_tools` list that Claude Code enforces at the platform level.

## Skills

| Skill | Context | Description |
|-------|---------|-------------|
| `/changelog` | main | Update CHANGELOG.md with unreleased changes |
| `/commit` | main | Interactive staged git commit workflow |
| `/review` | fork &rarr; `reviewer` | Code review with checklist (reads `REVIEW_GUIDELINES.md` if present) |
| `/test` | fork &rarr; `builder` | Run tests and summarize results |
| `/plan` | main | Interactive implementation planning |
| `/pr` | main | Create or update pull requests via `gh` |
| `/loop` | main | Iterative fix-and-check until a condition is met |
| `/handoff` | main | Generate session handoff document |

Skills live in `.claude/skills/*/SKILL.md`. "Context: main" runs in the current session; "fork" spawns a sub-agent with the indicated role.

## Team Templates

| Command | Composition | Use Case |
|---------|-------------|----------|
| `/team-feature` | lead + builder(s) + reader + reviewer | End-to-end feature implementation |
| `/team-review` | lead + 3 reviewers (security, quality, coverage) | Multi-perspective code review |
| `/team-research` | lead + 2-4 readers | Parallel codebase/web exploration |
| `/team-debug` | lead + 3-5 investigators | Competing hypothesis debugging |

Team commands live in `.claude/commands/team-*.md`. They use Claude Code's native team coordination (TeamCreate, TaskCreate, SendMessage) to run multiple agents in parallel.

## Hooks

Hooks are shell scripts configured in `.claude/settings.json`. They fire at Claude Code lifecycle events and enforce rules that agents cannot override.

### Universal (apply to any project)

| Hook | Event | Purpose |
|------|-------|---------|
| `security-gate.sh` | PreToolUse &rarr; Bash | Block dangerous bash patterns |
| `path-protector.sh` | PreToolUse &rarr; Edit/Write | Protect `.env*`, credentials, secrets |
| `audit-logger.sh` | PostToolUse &rarr; all | Structured JSON audit trail |
| `auto-allow-reads.sh` | PermissionRequest | Auto-allow read-only tools and safe bash commands |
| `pre-compact-backup.sh` | PreCompact | Back up transcript before context compression |
| `desktop-notify.sh` | Notification | Desktop notification when agent waits for input |
| `session-cleanup.sh` | Stop | Capture session memory + clean up stale artifacts |
| `subagent-log.sh` | SubagentStop | Log subagent/teammate completion for audit |

### Template (customize per project)

| Hook | Event | Purpose |
|------|-------|---------|
| `tool-policy.sh` | PreToolUse &rarr; Bash | Intercept commands, suggest alternatives (config-driven via `tool-policy.json`) |
| `post-edit-lint.sh` | PostToolUse &rarr; Edit/Write | Run linter, feed errors back to Claude |
| `affected-tests.sh` | PostToolUse &rarr; Edit/Write | Run related tests, feed failures back to Claude |
| `context-loader.sh` | SessionStart | Inject git status and recent commits |

## Project Structure

```
.claude/
  agents/
    builder.md            # Full-access implementation agent
    reader.md             # Read-only exploration agent
    researcher.md         # Web + codebase research agent
    reviewer.md           # Code review agent (no writes)
  commands/
    team-debug.md         # Debug team template
    team-feature.md       # Feature team template
    team-research.md      # Research team template
    team-review.md        # Review team template
  skills/
    changelog/SKILL.md
    commit/SKILL.md
    handoff/SKILL.md      # + template.md
    loop/SKILL.md
    plan/SKILL.md         # + template.md
    pr/SKILL.md
    review/SKILL.md       # + checklist.md
    test/SKILL.md
  settings.json           # Hook configuration + permissions
scripts/hooks/
  affected-tests.sh       # 12 hook scripts covering all 8 lifecycle events
  audit-logger.sh
  auto-allow-reads.sh
  context-loader.sh
  desktop-notify.sh
  path-protector.sh
  post-edit-lint.sh
  pre-compact-backup.sh
  security-gate.sh
  session-cleanup.sh
  subagent-log.sh
  tool-policy.sh          # + tool-policy.json
docs/
  CUSTOMIZATION.md        # How to adapt the template
  HOOKS.md                # Hook configuration and gotchas
  PATTERNS.md             # Multi-agent patterns and recipes
CLAUDE.md                 # Project instructions (read by Claude Code)
install.sh                # Install into target project
```

## Documentation

- [docs/PATTERNS.md](docs/PATTERNS.md) -- Multi-agent patterns and recipes
- [docs/CUSTOMIZATION.md](docs/CUSTOMIZATION.md) -- How to adapt the template to your project
- [docs/HOOKS.md](docs/HOOKS.md) -- Hook configuration, customization, and gotchas

## License

MIT
