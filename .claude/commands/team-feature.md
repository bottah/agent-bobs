---
description: "Spawn a feature team: lead + builder(s) + reader + reviewer"
---

# Team: Feature Implementation

Spawn a multi-agent team to implement a feature end-to-end.

## Input

$ARGUMENTS

## Team Composition

Create a team with `TeamCreate` using the name `feature-<short-name>`, then spawn these teammates:

| Role | Agent | Subagent Type | Purpose |
|------|-------|---------------|---------|
| **Lead** (you) | -- | -- | Coordinate, break down tasks, synthesize |
| **Explorer** | `reader` | `general-purpose` | Research codebase, find patterns, map dependencies |
| **Implementer** | `builder` | `general-purpose` | Write code, run tests, fix issues |
| **Reviewer** | `reviewer` | `general-purpose` | Review implementation before completion |

## Workflow

### 1. Research Phase
- Create a task for the Explorer to research the codebase and understand relevant patterns, files, and constraints
- Wait for research findings before proceeding

### 2. Planning Phase
- Based on research, break the feature into discrete implementation tasks
- Create tasks for each piece of work using `TaskCreate`
- Assign tasks to the Implementer

### 3. Implementation Phase
- The Implementer works through tasks sequentially
- For each task: implement, test, mark complete
- If the Implementer needs context, ask the Explorer to research

### 4. Review Phase
- When implementation is complete, assign a review task to the Reviewer
- The Reviewer examines all changes and provides feedback
- If changes are needed, create follow-up tasks for the Implementer

### 5. Completion
- Ensure all tests pass
- Summarize what was built and any remaining follow-ups
- Shut down the team

## Rules

- Always research before implementing -- don't guess at patterns
- Keep tasks small and focused (one logical change each)
- Run tests after each implementation task
- The Reviewer must approve before marking the feature complete
