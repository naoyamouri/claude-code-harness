# Codex Review Loop

Codex review follows the same verdict contract as Claude-side `harness-work`.

Pass the original request and why, owned scope, authorization source, selected
plan/spec/contract paths, DoD, actual target diff, and validation evidence to a
fresh read-only reviewer for the initial pass. Recover missing evidence through allowed reads first.
Report locations, failure conditions, concise reasons, and unverified items;
the worker's self-report is not proof.

## Order

1. Run `codex-companion.sh review-session` when available. It starts a persistent
   read-only review thread on the first pass and resumes its stored handle later.
2. Run AI Residuals JSON scan:

```bash
bash "${HARNESS_PLUGIN_ROOT}/scripts/review-ai-residuals.sh" --base-ref "${BASE_REF}" --include-untracked
```

3. Fall back to a read-only reviewer agent only when companion review is not
   available. Retain its target handle and use `followup_task` for re-review;
   a replacement is allowed only when that handle is unavailable, with the
   reason recorded in repair-loop state.

## Verdict Threshold

`critical` or `major` means `REQUEST_CHANGES`. `minor` and `recommendation` do
not affect approval.

## Worker Repair

When a spawned Worker needs changes, resume it and use `send_input` with the
critical/major findings only. Then wait again and rerun review.
Preserve the original task constraints and DoD in that follow-up. Reuse the same
Reviewer handle for the updated full diff, finding dispositions, and current
validation evidence, and keep the contract's iteration limit. Derive the target
fingerprint from base/spec/DoD/scope. Only a changed fingerprint or unavailable
Reviewer starts fresh; `repair-loop.v1` records `material-target-change` or
`reviewer-unavailable` and retains replacement history.
Stop when DoD and required checks pass; repeat or broaden tests only for new
changes, evidence, or unresolved concerns.
