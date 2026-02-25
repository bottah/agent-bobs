# Architecture: Four Layers

This template uses four layers that build on each other. Each layer works independently; together they provide governed multi-agent orchestration.

```
Teams    (optional — multi-session coordination)
  └── reuses Agents, Skills, and Hooks
Skills   (reusable workflows — /commit, /review, /test)
  └── can specify an Agent for permission scoping
Agents   (permission boundaries — reader, builder, reviewer)
Hooks    (programmatic guardrails — always-on, all sessions)
```

## Layer 1: Agents

Agents define **what tools are available**. An agent definition (`.claude/agents/reader.md`) declares `allowed_tools` in YAML frontmatter. When a skill or team command specifies that agent, Claude Code enforces tool restrictions at the platform level — the agent literally cannot call tools outside its allowed set.

```yaml
# .claude/agents/reader.md
---
allowed_tools:
  - "Read"
  - "Glob"
  - "Grep"
---
```

Permission patterns support globs for shell commands:
- `"Bash(git diff*)"` — allows `git diff` but not `git push`
- `"Bash(npm test*)"` — allows `npm test` but not `npm install`

**Enforcement**: Platform-level. Cannot be bypassed by the agent.

## Layer 2: Skills

Skills define **reusable workflows**. A skill (`.claude/skills/review/SKILL.md`) contains automation logic in markdown, invoked via `/skill-name`.

YAML frontmatter controls execution:
- **`context: fork`** — runs in a sub-agent, keeping large outputs out of the main context window
- **`agent: reviewer`** — applies the named agent's permission restrictions
- No `context`/`agent` — runs inline in the main session

Skills work in both single-session and team contexts. A teammate can invoke `/review` the same way the lead can.

**Enforcement**: Instruction-based. The agent follows the workflow but has discretion.

## Layer 3: Hooks

Hooks are shell scripts that fire at lifecycle events. Unlike agents (declaration-based) and skills (instruction-based), hooks are **code that runs regardless of what the agent decides to do**.

| Event | Timing | Power |
|-------|--------|-------|
| `PreToolUse` | Before tool executes | Can **block** or **modify** the action |
| `PostToolUse` | After tool completes | Can **react**: lint, test, log, inject context |
| `PermissionRequest` | Permission prompt | Can **auto-approve** or **auto-deny** |
| `SessionStart` | Session begins | Can **inject context** |

Hooks fire for **all sessions**, including teammates in a team. This is the key advantage over instruction-based guardrails — every agent gets the same programmatic enforcement.

See `docs/HOOKS.md` for full details.

**Enforcement**: Programmatic. Runs as actual code, cannot be bypassed.

## Layer 4: Team Commands

Team commands (`.claude/commands/team-*.md`) orchestrate **multi-session coordination**. Each teammate is a full Claude Code instance with its own context window.

| Tool | Purpose |
|------|---------|
| `TeamCreate` | Create a team with shared task list |
| `TaskCreate` / `TaskUpdate` / `TaskList` | Shared task management |
| `SendMessage` | Direct messaging between teammates |
| `Task` (with `team_name`) | Spawn new teammates into the team |

### Team lifecycle

```
TeamCreate("feature-auth")
  → Task(spawn "explorer", team_name="feature-auth")
  → Task(spawn "implementer", team_name="feature-auth")
  → TaskCreate("Research auth patterns")
  → TaskUpdate(assign to explorer)
  → ... teammates work, message, update tasks ...
  → SendMessage(shutdown_request to each)
  → TeamDelete()
```

Team commands reuse agents for permission scoping. An explorer teammate spawned with the `reader` agent gets read-only tools. Hooks fire for every teammate.

**Enforcement**: Platform-level (team infrastructure) + agent-level (permission scoping).

## The Enforcement Spectrum

| Layer | What It Controls | How It's Enforced | Can Be Bypassed? |
|-------|-----------------|-------------------|-------------------|
| **Agents** | What tools are available | `allowed_tools` declaration | No (platform-enforced) |
| **Skills** | What workflow to follow | Markdown instructions | Yes (agent discretion) |
| **Hooks** | How tools are used | Shell scripts | No (runs before/after tools) |
| **Teams** | Who works on what | Task list + messaging | No (platform-enforced) |

## When to Use What

| Need | Layer | Example |
|------|-------|---------|
| Restrict tool access | Agent | `reader` can't call Edit |
| Reusable workflow | Skill | `/commit` stages and commits |
| Block dangerous ops | Hook | `security-gate.sh` blocks `rm -rf /` |
| Auto-lint on edit | Hook | `post-edit-lint.sh` feeds errors back |
| Parallel investigation | Team | `/team-research` with parallel explorers |
| Multi-perspective review | Team | `/team-review` with 3 specialists |
| Complex feature | Team | `/team-feature` with coordinated roles |

### Rule of Thumb

- **One task, needs permission control** → Agent (+ optional Skill)
- **One task, reusable workflow** → Skill
- **Multiple tasks, parallel work** → Team command
- **Enforcement for everyone, always** → Hook
