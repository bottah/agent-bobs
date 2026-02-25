# Hooks: Programmatic Guardrails & Lifecycle Automation

Hooks are shell scripts that run at specific points during a Claude Code session. They provide **programmatic enforcement** -- unlike agent permissions (which are instruction-based), hooks are guaranteed to execute regardless of what the agent decides to do.

## The Three Enforcement Layers

| Layer | Mechanism | Enforcement | Example |
|-------|-----------|-------------|---------|
| **Agents** | `allowed_tools` in YAML | Tool availability | Reader can't call Edit |
| **Skills** | Markdown instructions | Workflow guidance | Commit skill stages before committing |
| **Hooks** | Shell scripts | Programmatic guarantee | Block `rm -rf /` before execution |

Agents and skills rely on Claude following instructions. Hooks run as actual code -- they can block, modify, log, and inject context regardless of what the agent attempts.

## Hook Lifecycle Events

| Event | When | Can Block? | Use For |
|-------|------|-----------|---------|
| `SessionStart` | Session begins | No | Inject context (git status, env info) |
| `PreToolUse` | Before tool executes | Yes (deny) | Block dangerous ops, auto-approve safe ones |
| `PostToolUse` | After tool completes | No | Lint, test, log, feed context back |
| `PermissionRequest` | Permission prompt shown | Yes (allow/deny) | Auto-approve read-only tools |
| `Stop` | Session ending | Can delay | Final validation, cleanup |
| `SubagentStop` | Sub-agent ending | Can delay | Validate sub-agent output |
| `UserPromptSubmit` | User sends message | No | Preprocess user input |
| `Notification` | Notification shown | No | External alerting |

## Included Hook Scripts

### Universal (work for any project)

| Script | Event | Matcher | Purpose |
|--------|-------|---------|---------|
| `security-gate.sh` | `PreToolUse` | `Bash` | Blocks dangerous bash patterns (`rm -rf /`, `chmod 777`, fork bombs, force push to main) |
| `path-protector.sh` | `PreToolUse` | `Edit\|Write` | Denies writes to `.env*`, `*.secret`, `*.pem`, `*.key`, `credentials/*` |
| `audit-logger.sh` | `PostToolUse` | `*` | Appends structured JSON log to `.claude/audit.log` |
| `auto-allow-reads.sh` | `PermissionRequest` | -- | Auto-allows read-only tools and safe bash commands to reduce permission dialogs |
| `pre-compact-backup.sh` | `PreCompact` | -- | Backs up conversation transcript before context compression |
| `desktop-notify.sh` | `Notification` | -- | Sends a desktop notification when the agent is waiting for input |
| `session-cleanup.sh` | `Stop` | -- | Captures session memory to `.claude/last-session.json` and cleans up stale artifacts |
| `subagent-log.sh` | `SubagentStop` | -- | Logs subagent/teammate completion to `.claude/subagent.log` |

### Templates (customize for your project)

| Script | Event | Matcher | Purpose |
|--------|-------|---------|---------|
| `tool-policy.sh` | `PreToolUse` | `Bash` | Intercepts blocked commands and suggests alternatives. Config-driven via `tool-policy.json`. |
| `post-edit-lint.sh` | `PostToolUse` | `Edit\|Write` | Runs linter on edited file, feeds errors back to Claude. Supports JS/TS (eslint), Python (ruff/flake8), Go (golangci-lint). |
| `affected-tests.sh` | `PostToolUse` | `Edit\|Write` | Finds and runs tests related to edited file. Supports Jest/Vitest, pytest, go test. |
| `context-loader.sh` | `SessionStart` | -- | Injects git branch, uncommitted changes, recent commits, stash count. |

## Enabling Hooks

Hooks are configured in `.claude/settings.json`. The provided configuration enables all hooks. To disable specific hooks, remove their entry from the relevant event array.

### Enabling a subset

If you only want the universal guardrails without the project-specific hooks:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [{ "type": "command", "command": "./scripts/hooks/security-gate.sh" }]
      },
      {
        "matcher": "Edit|Write",
        "hooks": [{ "type": "command", "command": "./scripts/hooks/path-protector.sh" }]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "*",
        "hooks": [{ "type": "command", "command": "./scripts/hooks/audit-logger.sh" }]
      }
    ]
  }
}
```

## Customizing Hook Scripts

### Linter hook

Edit `scripts/hooks/post-edit-lint.sh`. The script detects file extension and runs the appropriate linter. To add a new language:

```bash
elif [[ "$file_path" =~ \.rb$ ]]; then
  if command -v rubocop &>/dev/null; then
    lint_output=$(rubocop "$file_path" 2>&1)
    lint_exit=$?
  fi
```

### Test runner hook

Edit `scripts/hooks/affected-tests.sh`. The script finds co-located test files by naming convention (`*.test.ts`, `test_*.py`, `*_test.go`). Customize the discovery patterns for your project structure.

### Context loader hook

Edit `scripts/hooks/context-loader.sh`. Add project-specific context:

```bash
# Example: show current TODO count
todo_count=$(grep -r "TODO" src/ 2>/dev/null | wc -l | tr -d ' ')
context+="Open TODOs: $todo_count\n"
```

### Tool policy (intercepted commands)

Edit `scripts/hooks/tool-policy.json` to define commands that should be blocked with helpful alternatives. Ships with an empty rules array — add your own project-specific policies.

Each rule has:
- `match` — string to match against the command
- `message` — what the agent sees when blocked (include the preferred alternative)
- `mode` — `"substring"` (default) or `"regex"`

**Example: Redirect pip to uv**
```json
{
  "rules": [
    {
      "match": "pip install",
      "message": "pip is disabled. Use: uv add PACKAGE",
      "mode": "substring"
    },
    {
      "match": "pip3 install",
      "message": "pip3 is disabled. Use: uv add PACKAGE",
      "mode": "substring"
    },
    {
      "match": "python -m venv",
      "message": "venv is disabled. Use: uv venv",
      "mode": "substring"
    },
    {
      "match": "^poetry ",
      "message": "poetry is disabled. Use uv instead (uv init, uv add, uv sync, uv run)",
      "mode": "regex"
    }
  ]
}
```

**Example: Enforce pnpm over npm/yarn**
```json
{
  "rules": [
    {
      "match": "^npm (install|add|remove|ci)",
      "message": "Use pnpm instead of npm: pnpm install, pnpm add, pnpm remove",
      "mode": "regex"
    },
    {
      "match": "^yarn ",
      "message": "Use pnpm instead of yarn: pnpm install, pnpm add, pnpm remove",
      "mode": "regex"
    }
  ]
}
```

Rules are checked in order; the first match wins. The agent receives the denial reason as feedback and will typically retry with the suggested alternative.

### Auto-allow reads

Edit `scripts/hooks/auto-allow-reads.sh` to adjust which operations skip the permission dialog. By default it auto-allows:

- **Tools**: `Read`, `Glob`, `Grep`, `WebSearch`, `WebFetch`
- **Bash commands**: `ls`, `cat`, `head`, `tail`, `wc`, `file`, `which`, `pwd`, `date`, `uname`, `env`
- **Git read commands**: `git status`, `git log`, `git diff`, `git show`, `git branch`, `git tag`, `git blame`
- **Version checks**: `node --version`, `python --version`
- **GitHub CLI reads**: `gh pr view`, `gh issue list`, `gh api`, etc.

Any command containing output redirection (`>`, `>>`) is never auto-allowed. Everything not explicitly listed falls through to the normal permission dialog.

To add a safe command:

```bash
    your_cmd)
      echo '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}'
      exit 0
      ;;
```

### Transcript backup

`scripts/hooks/pre-compact-backup.sh` runs automatically before context compression. Transcripts are saved to `.claude/transcript-backups/` with session ID and timestamp. Backups older than 7 days are pruned automatically.

To change the retention period, edit the `find -mtime` value in the script:

```bash
# Keep backups for 30 days instead of 7
find "$backup_dir" -name "*.jsonl" -mtime +30 -delete 2>/dev/null
```

### Desktop notifications

`scripts/hooks/desktop-notify.sh` sends a native OS notification when the agent is waiting for input. Uses `osascript` on macOS, `notify-send` on Linux. No configuration needed.

To notify on additional events, edit the grep filter in the script:

```bash
# Also notify on errors or completion
if ! echo "$message" | grep -qi "waiting\|input\|needs your\|error\|complete"; then
```

To disable without removing the hook, just comment out the entry in `.claude/settings.json`.

### Session cleanup & memory capture

`scripts/hooks/session-cleanup.sh` runs when a session ends. It does two things:

**Memory capture**: Writes `.claude/last-session.json` with a snapshot of the session's final state — branch, uncommitted file count, dirty files list, last commit, stop reason. The `context-loader.sh` hook can read this on the next session start to provide continuity.

Example `last-session.json`:
```json
{
  "session_id": "abc123",
  "ended_at": "2026-02-06T18:30:00Z",
  "stop_reason": "user_stopped",
  "branch": "feat/auth",
  "uncommitted_files": 3,
  "dirty_files": [" M src/auth.ts", " M src/auth.test.ts", "?? src/middleware.ts"],
  "last_commit": "a1b2c3d feat(auth): add JWT validation"
}
```

**Cleanup**: Removes empty log files and prunes stale transcript backups.

### Subagent log

`scripts/hooks/subagent-log.sh` appends a JSON entry to `.claude/subagent.log` when any subagent or teammate finishes. Useful for debugging team workflows and understanding which agents ran during a session.

Each entry records: timestamp, session ID, agent ID, agent type, and stop reason.

### Path protector

Edit `scripts/hooks/path-protector.sh`. Add project-specific protected paths:

```bash
protected_patterns=(
  # ... existing patterns ...
  "infrastructure/terraform/*"
  "k8s/production/*"
  "database/migrations/applied/*"
)
```

## Hook Output Formats

Every hook that returns JSON must include `hookEventName` in `hookSpecificOutput`. Without it, Claude Code silently ignores the response.

### PreToolUse (block dangerous operations)

```json
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Blocked: reason"}}
```

- `permissionDecision`: `"allow"` | `"deny"` | `"ask"`
- `permissionDecisionReason`: required when allow or deny

### PostToolUse (feed context back to Claude)

```json
{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"Lint errors:\n..."}}
```

- `additionalContext`: string injected into Claude's context

### PermissionRequest (auto-allow safe operations)

```json
{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}
```

- `decision.behavior`: `"allow"` | `"deny"`
- Note: `decision` is an **object** here, unlike PreToolUse where `permissionDecision` is a string

### SessionStart (inject startup context)

```json
{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"Branch: main\n..."}}
```

### Hooks that don't return decisions

`Stop`, `SubagentStop`, `Notification`, and `PreCompact` hooks perform side effects only (logging, backups, notifications). They don't need to return `hookSpecificOutput` -- just `exit 0`.

## Gotchas

### 1. hookEventName is required
The most common mistake. If your hook returns JSON but has no effect, check that `hookEventName` matches the event type exactly (`"PreToolUse"`, `"PostToolUse"`, `"PermissionRequest"`, `"SessionStart"`).

### 2. Matchers are case-sensitive
`"bash"` does NOT match `"Bash"`. Tool names are PascalCase: `Bash`, `Edit`, `Write`, `Read`, `Glob`, `Grep`, `WebFetch`, `WebSearch`.

### 3. Timeout defaults to 60 seconds
Hooks that take longer fail **silently**. Set explicit timeouts for anything slow:
```json
{ "type": "command", "command": "./scripts/hooks/slow-hook.sh", "timeout": 300 }
```

### 4. Multiple tools use pipe syntax
```json
{ "matcher": "Edit|Write" }
```
NOT `"Edit, Write"` or `["Edit", "Write"]`.

### 5. PostToolUse can't undo actions
It can only react. Use `PreToolUse` to block, `PostToolUse` to lint/test/log.

### 6. Hook output must be valid JSON
Malformed JSON causes silent failures. Always test scripts standalone:
```bash
echo '{"tool_name":"Bash","tool_input":{"command":"ls"}}' | ./scripts/hooks/security-gate.sh
```

### 7. grep -P doesn't work on macOS
Use `sed` + `awk` instead of `grep -oP` for portable argument extraction. macOS ships with BSD grep which lacks Perl regex support.

### 8. Keep hooks fast
Target under 5 seconds per hook. The article reports ~1.5s average per tool call with 8 hooks. Slow hooks degrade the interactive experience.

## Audit Log

When audit logging is enabled, entries are written to `.claude/audit.log`:

```json
{"ts":"2026-02-06T12:00:00Z","session":"abc123","tool":"Edit","input":{"file_path":"src/index.ts",...}}
```

Add `.claude/audit.log` to `.gitignore` -- it's per-developer, not shared.

## Hooks and Teams

Hooks fire for **all sessions**, including teammates in a team. This means:
- The security gate protects every teammate, not just the lead
- Audit logging captures activity across the entire team
- Lint/test hooks give every builder immediate feedback

This is the key advantage over instruction-based guardrails — a builder teammate gets the same programmatic enforcement as the lead session.
