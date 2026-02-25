---
description: "Spawn a review team: lead + 3 specialized reviewers"
---

# Team: Multi-Perspective Code Review

Spawn a team of reviewers to examine code from different angles.

## Input

$ARGUMENTS

## Team Composition

Create a team with `TeamCreate` using the name `review-<short-name>`, then spawn these teammates:

| Role | Agent | Subagent Type | Focus |
|------|-------|---------------|-------|
| **Lead** (you) | -- | -- | Coordinate and synthesize findings |
| **Security Reviewer** | `reviewer` | `general-purpose` | Vulnerabilities, auth, input validation, secrets |
| **Quality Reviewer** | `reviewer` | `general-purpose` | Code quality, patterns, maintainability, DRY |
| **Coverage Reviewer** | `reviewer` | `general-purpose` | Test coverage, edge cases, error handling |

## Workflow

### 1. Scope Determination
- Identify what to review (PR, diff range, file set)
- Prepare the scope description for all reviewers

### 2. Parallel Review
- Create a review task for each reviewer with their specific focus area
- Each reviewer works independently on the same code from their perspective
- Provide each reviewer with clear instructions about their focus

### 3. Synthesis
- Collect findings from all three reviewers
- Deduplicate and categorize findings
- Produce a consolidated review report:

```
## Consolidated Review

**Scope**: [what was reviewed]
**Verdict**: [approve / request changes]

### Critical (must fix)
- ...

### Warnings (should fix)
- ...

### Suggestions (nice to have)
- ...

### By Category
| Category | Findings | Severity |
|----------|----------|----------|
| Security | ... | ... |
| Quality | ... | ... |
| Coverage | ... | ... |
```

### 4. Completion
- Present the consolidated report to the user
- Shut down the team

## Rules

- All three reviews should run in parallel for speed
- De-duplicate findings -- if two reviewers flag the same issue, consolidate
- Prioritize by severity: critical > warning > suggestion
