---
description: "Spawn a research team: lead + 2-4 parallel researchers"
---

# Team: Parallel Research

Spawn a team of researchers to explore a topic from multiple angles simultaneously.

## Input

$ARGUMENTS

## Team Composition

Create a team with `TeamCreate` using the name `research-<short-name>`, then spawn teammates based on the research scope:

| Role | Agent | Subagent Type | Purpose |
|------|-------|---------------|---------|
| **Lead** (you) | -- | -- | Define angles, synthesize findings |
| **Codebase Explorer 1** | `reader` | `general-purpose` | Explore angle A of the codebase |
| **Codebase Explorer 2** | `reader` | `general-purpose` | Explore angle B of the codebase |
| **Web Researcher** | `researcher` | `general-purpose` | Research external docs, libraries, best practices |

Adjust the number of teammates (2-4) based on the breadth of the research topic. For narrow topics, 2 is sufficient. For broad architectural questions, use 4.

## Workflow

### 1. Decompose the Question
- Break the research question into 2-4 independent angles
- Each angle should be explorable without depending on others
- Examples:
  - "How does auth work?" → existing auth code, auth library docs, auth best practices
  - "Should we use X or Y?" → how X works, how Y works, project constraints, community recommendations

### 2. Parallel Exploration
- Create a research task for each teammate with their specific angle
- Provide clear, focused instructions for each angle
- All researchers work simultaneously

### 3. Synthesis
- Collect findings from all researchers
- Cross-reference and validate findings
- Produce a synthesis document:

```
## Research: [Topic]

### Key Findings
1. [Most important finding]
2. ...

### By Angle
#### [Angle A]
- [findings]

#### [Angle B]
- [findings]

### Recommendations
- [Actionable recommendation based on combined findings]

### Open Questions
- [Things that need further investigation]
```

### 4. Completion
- Present the synthesis to the user
- Shut down the team

## Rules

- Define non-overlapping research angles to avoid duplicate work
- Each researcher should be given enough context to work independently
- Prioritize findings by relevance and actionability
