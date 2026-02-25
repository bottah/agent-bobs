# Customizing the Template

Step-by-step guide to adapting this template to your project.

## Quick Start

1. Copy the `.claude/` directory and `CLAUDE.md` into your project root
2. Update `CLAUDE.md` with your project's dev commands
3. You're ready to use `/commit`, `/review`, `/test`, `/plan`, `/pr`, `/handoff`, and the team commands

## Step 1: Update Dev Commands

Edit the "Dev Commands" section in `CLAUDE.md` with your actual project commands:

```markdown
## Dev Commands

\```bash
# Testing
npm test

# Linting
npm run lint

# Building
npm run build

# Running
npm run dev
\```
```

The test skill reads these to know how to run your tests.

## Step 2: Adjust Agent Permissions

The default agents cover the common permission spectrum. To customize:

### Add a new agent

Create `.claude/agents/your-agent.md`:

```yaml
---
allowed_tools:
  - "Read"
  - "Bash(your-specific-command*)"
---

# Your Agent

Description of what this agent does and its guidelines.
```

### Modify an existing agent

Edit the `allowed_tools` list in any agent file. Use glob patterns for shell commands:

```yaml
allowed_tools:
  - "Bash(docker build*)"     # Allow docker build but not docker rm
  - "Bash(kubectl get*)"      # Allow kubectl get but not kubectl delete
  - "Bash(terraform plan*)"   # Allow plan but not apply
```

### Remove an agent

Delete the file from `.claude/agents/`. Update any skills or commands that reference it.

## Step 3: Customize Skills

### Modify a skill

Edit the `SKILL.md` file. The key sections:

- **Frontmatter**: controls `context` (fork/inline) and `agent` binding
- **Steps**: the workflow the skill follows
- **Rules**: constraints on behavior

### Add a new skill

1. Create `.claude/skills/your-skill/SKILL.md`
2. Add frontmatter:
   ```yaml
   ---
   description: What this skill does
   context: fork        # optional: run in sub-agent
   agent: builder       # optional: apply agent permissions
   ---
   ```
3. Write the skill instructions in markdown
4. Add any supporting files (templates, checklists) in the same directory
5. Update the skill inventory in `CLAUDE.md`

### Remove a skill

Delete the skill directory. Update `CLAUDE.md` inventory.

## Step 4: Customize Team Commands

### Modify team composition

Edit the team command file in `.claude/commands/`. Adjust the team composition table and workflow to match your needs.

### Add a new team command

1. Create `.claude/commands/team-your-name.md`
2. Add frontmatter:
   ```yaml
   ---
   description: "Short description of this team template"
   ---
   ```
3. Define the team composition, workflow, and rules
4. Reference agents for permission control
5. Update the team template table in `CLAUDE.md`

### Common customizations

**Add a dedicated tester to the feature team:**
```markdown
| **Tester** | `builder` | `general-purpose` | Run tests, write missing tests |
```

**Add a docs writer to the feature team:**
```markdown
| **Docs Writer** | `builder` | `general-purpose` | Update documentation |
```

**Specialize the debug team for your stack:**
- Hypothesis angles specific to your architecture (DB, cache, API, frontend)
- Custom investigation procedures for your monitoring/logging stack

## Step 5: Update Git Conventions

Edit the "Git Conventions" section in `CLAUDE.md` to match your team's practices:

- Commit message format (conventional commits, ticket prefixes, etc.)
- Branch naming conventions
- PR template expectations

## Step 6: Add Project Constraints

Add project-specific constraints to the "Constraints" section in `CLAUDE.md`:

```markdown
## Constraints

- All API changes must include OpenAPI spec updates
- Database migrations must be reversible
- New dependencies require team lead approval
- Frontend changes must support IE11
```

## Tips

- **Start minimal**: use the defaults first, then customize as you hit friction
- **Least privilege**: prefer the most restricted agent that can do the job
- **Fork heavy work**: use `context: fork` for skills that produce large output
- **Name things clearly**: team names, task subjects, and agent names should be self-explanatory
- **Keep CLAUDE.md concise**: it's loaded into every session, so every line costs context
