---
description: Run tests and summarize results
context: fork
agent: builder
---

# Test Skill

Run the project's test suite and produce a clear summary.

## Steps

1. Determine the test command:
   - Check `package.json` for `scripts.test`
   - Check for `pytest.ini`, `pyproject.toml`, or `setup.cfg` for pytest config
   - Check for `Cargo.toml` (cargo test)
   - Check for `go.mod` (go test)
   - Check for `Makefile` with a test target
   - If nothing is found, ask the user for the test command
2. Run the test command
3. Parse the output and produce a summary:

```
## Test Results

**Status**: [pass / fail]
**Total**: X | **Passed**: X | **Failed**: X | **Skipped**: X

### Failures
- `test_name` (file:line): brief description of failure

### Summary
[One-line assessment of test health]
```

## Rules

- Always show the full test output before the summary
- If tests fail, include the relevant error messages and stack traces
- If no test suite exists, say so clearly rather than guessing
