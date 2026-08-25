# Phase 425 TDD RED evidence

Before the Phase 425 guard was implemented, the focused gate test contained the
new Free-private merge case and failed against the prior helper:

```text
FAIL: Free private fallback must require an explicit user merge instruction
```

The current fixture expands that case to require a post-review, current-HEAD
approval comment from the repository owner and keeps the negative cases for
missing approval, wrong author, stale approval, pending or failed CI, dirty PR,
non-private repository, and unrelated 403 responses.
