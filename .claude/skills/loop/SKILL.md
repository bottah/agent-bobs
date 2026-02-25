---
description: Iterative loop until a condition is met
---

# Loop Skill

Run an iterative fix-and-check loop until a success condition is satisfied.

## Inputs

The user provides a mode and optionally a task description:

| Mode | Syntax | Behavior |
|------|--------|----------|
| **tests** | `/loop tests` | Loop until the test suite passes |
| **custom** | `/loop <condition>` | Loop until a custom condition is met |

If no argument is given, ask the user what condition to loop on.

## Steps

1. Determine the loop mode and success condition from the user's input
2. Establish the iteration plan:
   - **tests mode**: identify the test command (same detection as `/test` skill), run it, read failures
   - **custom mode**: parse the user's condition as the success criterion
3. Execute the first iteration:
   - Analyze the current state (test failures, code issues, etc.)
   - Make targeted fixes to address the most likely root cause
   - Verify by re-checking the condition
4. After each iteration, evaluate:
   - **Condition met?** → Report success and stop
   - **Condition not met?** → Log what was tried, what changed, and why it didn't work, then start the next iteration
5. Repeat step 3-4 until the condition is satisfied or the iteration limit is reached
6. Produce a final summary:

```
## Loop Complete

**Condition**: [what was being checked]
**Result**: [met / not met]
**Iterations**: N

### Changes Made
- [file:line] description of change (iteration N)
- ...

### Iteration Log
1. Attempted X → result Y
2. Attempted X → result Y
...
```

## Rules

- **Iteration limit**: Stop after 10 iterations. If the condition is still not met, report what was tried and suggest next steps for the user.
- **No repeated attempts**: If the same fix fails twice, try a different approach. Never apply the exact same change again.
- **Minimize blast radius**: Make the smallest change that could fix the issue. Don't refactor surrounding code.
- **Show your work**: Before each fix, briefly state your hypothesis. After each check, state whether it moved closer to the goal.
- **Bail early on dead ends**: If after 3 iterations there is no measurable progress, stop and report the situation rather than burning through the remaining attempts.
- **Preserve user code intent**: Fix the condition, don't delete or disable the thing being checked (e.g., don't delete a failing test to make tests pass).
