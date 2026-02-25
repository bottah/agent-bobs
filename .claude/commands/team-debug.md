---
description: "Spawn a debug team: lead + 3-5 investigators with competing hypotheses"
---

# Team: Adversarial Debugging

Spawn a team of investigators that pursue competing hypotheses about a bug in parallel.

## Input

$ARGUMENTS

## Team Composition

Create a team with `TeamCreate` using the name `debug-<short-name>`, then spawn 3-5 investigators:

| Role | Agent | Subagent Type | Purpose |
|------|-------|---------------|---------|
| **Lead** (you) | -- | -- | Form hypotheses, assign, arbitrate |
| **Investigator 1** | `reader` | `general-purpose` | Pursue hypothesis A |
| **Investigator 2** | `reader` | `general-purpose` | Pursue hypothesis B |
| **Investigator 3** | `reader` | `general-purpose` | Pursue hypothesis C |
| **Fixer** (optional) | `builder` | `general-purpose` | Implement the fix once root cause is found |

## Workflow

### 1. Bug Analysis
- Understand the symptoms from the user's description
- Examine any error messages, stack traces, or reproduction steps
- Form 3-5 competing hypotheses about the root cause

### 2. Hypothesis Assignment
- Assign each investigator a different hypothesis to pursue
- Each investigator should:
  - Search for evidence supporting or refuting their hypothesis
  - Follow the code path relevant to their theory
  - Report their findings with confidence level (high/medium/low)

### 3. Evidence Collection
- All investigators work in parallel
- Each reports back with:
  - Evidence found (file paths, code snippets, log patterns)
  - Confidence level in their hypothesis
  - Alternative theories discovered during investigation

### 4. Arbitration
- Compare evidence from all investigators
- Identify the most likely root cause
- If no clear winner, form new hypotheses and reassign

### 5. Fix (if requested)
- Once root cause is identified, spawn or assign the Fixer
- Implement the fix
- Verify the fix addresses the original symptoms
- Run tests to check for regressions

### 6. Report

```
## Debug Report: [Bug Description]

### Symptoms
- [observed behavior]

### Root Cause
[explanation with evidence]

### Hypotheses Explored
| # | Hypothesis | Confidence | Verdict |
|---|-----------|------------|---------|
| 1 | ... | high/med/low | confirmed/refuted |
| 2 | ... | ... | ... |

### Fix Applied
[what was changed and why]

### Verification
[how the fix was verified]
```

### 7. Completion
- Present the debug report to the user
- Shut down the team

## Rules

- Hypotheses should be genuinely different, not variations of the same idea
- Investigators must report evidence honestly, even if it refutes their hypothesis
- The lead should remain neutral and follow the evidence, not commit to a hypothesis early
- If the first round of hypotheses all fail, form new ones based on what was learned
