# Code Review Checklist

## Correctness
- [ ] Logic handles all expected inputs correctly
- [ ] Edge cases are handled (empty, null, boundary values)
- [ ] Error paths return appropriate errors, don't silently fail
- [ ] State mutations are intentional and consistent
- [ ] Async operations handle race conditions

## Security
- [ ] No hardcoded secrets, keys, or credentials
- [ ] User input is validated and sanitized
- [ ] No SQL injection, XSS, command injection, or path traversal
- [ ] Authentication and authorization checks are present where needed
- [ ] Sensitive data is not logged or exposed in error messages

## Quality
- [ ] Code follows existing project patterns and conventions
- [ ] No unnecessary duplication (DRY where appropriate)
- [ ] Names are clear and descriptive
- [ ] Functions have single, clear responsibilities
- [ ] No dead code or commented-out blocks

## Testing
- [ ] New behavior has corresponding tests
- [ ] Tests cover both happy path and error cases
- [ ] Tests are deterministic (no flaky timing, ordering, or external dependencies)
- [ ] Existing tests still pass

## Performance
- [ ] No obvious N+1 queries or unnecessary loops
- [ ] Large data sets are paginated or streamed
- [ ] No blocking operations on hot paths
- [ ] Resources are properly cleaned up (connections, file handles, timers)
