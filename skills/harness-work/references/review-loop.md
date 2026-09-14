# Review Loop

The review loop is shared by Solo, Parallel, and Breezing. Parallel runs it once
per Worker; Breezing runs it from the Lead (see below).

## Order

1. Prefer the persistent Codex review session under `codex-companion.sh` when available.
2. Fall back to the internal `reviewer` agent (when `command -v codex` fails or
   the companion times out at 120s).
3. Run AI Residuals in parallel with either:

```bash
bash "${HARNESS_PLUGIN_ROOT}/scripts/review-ai-residuals.sh" --base-ref "${BASE_REF}" --include-untracked
```

4. Normalize the review artifact with `write-review-result.sh`.

## Verdict Threshold

Give the reviewer only this threshold; it must judge verdict from it alone.
Below-threshold suggestions become `recommendations` and never flip the verdict.

Provide the original request, outcome and DoD, selected plan/spec/contract,
owned scope and authorization source, actual target diff, and existing
validation evidence to the reviewer. Start in fresh read-only context; the author's
report is a claim to check. Recover missing evidence through allowed reads
before requesting material input. Findings need a location, failure condition,
and checkable reason, not private reasoning transcripts.

| Severity | Definition | Verdict effect |
|---|---|---|
| `critical` | Security vulnerability, data loss risk, possible production outage | Any finding means `REQUEST_CHANGES` |
| `major` | Breaks an existing feature, clearly contradicts spec, failing test | Any finding means `REQUEST_CHANGES` |
| `minor` | Naming, missing comment, style inconsistency | Does not change verdict |
| `recommendation` | Best-practice suggestion, future improvement | Does not change verdict |

Minor-only and recommendation-only reviews must approve. "Would be nice to have" is never a reason for `REQUEST_CHANGES`.

## Codex Companion Review

Capture `BASE_REF=$(git rev-parse HEAD)` before implementation starts. Derive
`TARGET_FINGERPRINT` from the base ref plus the selected spec, DoD, and owned
scope; source changes made to satisfy findings do not change this fingerprint.
Then run the persistent review entrypoint:

```bash
BASE_REF=$(git rev-parse HEAD)
# ... implementation complete ...
TARGET_FINGERPRINT=sha256(canonical_json(BASE_REF, spec_digest, DoD, owned_scope))
bash "${HARNESS_PLUGIN_ROOT}/scripts/codex-companion.sh" review-session \
  --project-root "${PROJECT_ROOT}" --task-id "${TASK_ID}" \
  --target-fingerprint "${TARGET_FINGERPRINT}" --base-ref "${BASE_REF}" \
  --output "${REVIEW_OUTPUT}" --prompt "${REVIEW_PROMPT}"
REVIEW_EXIT=$?
```

The first call starts a persistent read-only Codex review and stores its thread
handle in `.claude/state/repair-loop/<task>.json`. A later call with the same
target fingerprint resumes that handle. A changed fingerprint starts fresh with
`material-target-change`; a failed resume starts fresh with
`reviewer-unavailable`. Both replacement reasons remain in the same state file.
Start and resume both use the bundled official review-output schema. Missing,
empty, malformed, or shape-invalid output fails before verdict normalization or
repair-loop recording. Each successful call emits one prompt-free, countable
`review-session` orchestration-ledger entry.

Verdict mapping (official plugin → Harness):

| Official plugin | Harness | Verdict effect |
|---|---|---|
| `approve` | `APPROVE` | - |
| `needs-attention` | `REQUEST_CHANGES` | - |
| `findings[].severity: critical` | `critical_issues[]` | Any → `REQUEST_CHANGES` |
| `findings[].severity: high` | `major_issues[]` | Any → `REQUEST_CHANGES` |
| `findings[].severity: medium/low` | `recommendations[]` | Does not change verdict |

## Internal Reviewer Agent Fallback

When Codex exec is unavailable:

```
Agent tool: subagent_type="reviewer"
prompt: "Review the original request and DoD against the actual diff in fresh read-only context. Request/why/owned scope/authorization source: {task_request}. Plan/spec/contract: {paths}. Validation evidence: {evidence}. Verdict rule: critical/major -> REQUEST_CHANGES, minor/recommendation only -> APPROVE. Report locations, failure conditions, evidence, and unverified items. diff: {git diff ${BASE_REF}}"
```

The `reviewer` agent is read-only (no Write/Edit/Bash) so it can review safely.
Retain the returned agent handle and bind it with `repair-loop-state.sh
reviewer-bind` using transport `native-agent`. On `REQUEST_CHANGES`, send the
updated review prompt to that same handle (`SendMessage` in Claude Code,
`followup_task` in Codex). If the handle is unavailable, bind the replacement
with reason `reviewer-unavailable`.

## Repair Loop

Iteration state is externalized to `.claude/state/repair-loop/<task>.json`
(schema: `templates/schemas/repair-loop.v1.json`) instead of living only in
conversation memory. This makes the `MAX_REVIEWS` ceiling machine-judged: the
same agent bounded by the ceiling cannot self-report an undercount, and a
long loop that loses earlier findings to context rot can still read them
back from the state file.

```
MAX_REVIEWS = read_contract(contract_path, ".review.max_iterations") or 3
bash scripts/repair-loop-state.sh init "${PROJECT_ROOT}" "${TASK_ID}" "${MAX_REVIEWS}"

while true:
    1. Run `review-session` (see above); get reviewer handle + verdict + findings
    2. bash scripts/repair-loop-state.sh record "${PROJECT_ROOT}" "${TASK_ID}" "${verdict}" "${findings_json}"
    3. if verdict == "APPROVE": break
    4. Parse the findings (critical / major only) and fix each one
    5. bash scripts/repair-loop-state.sh check "${PROJECT_ROOT}" "${TASK_ID}"
       - exit 0 -> below the ceiling (or already approved), loop continues
       - exit 1 -> ceiling reached without APPROVE
       - any other non-zero (2 = jq missing, 4 = cannot evaluate)
                -> the loop state could not be judged; this is NOT an escalation
    6. Re-run `review-session` with the same target fingerprint and a prompt that
       contains the updated full diff, each blocking finding's disposition, and
       current validation evidence

if `check` exited 1:
    -> escalate to the user with the remaining critical/major findings
       (read from the state file's iterations[], not from memory),
       wait for continue/abort

if `check` exited 2 or 4:
    -> report the tooling failure itself (missing `init`, wrong project root,
       corrupt state file, jq unavailable). Do NOT report it as "review limit
       reached" — that would blame the reviewer for a broken invocation.
```

> **Why exit 1 and exit 4 are separate**: this branch is taken by an autonomous
> agent that sees only the exit code. If "the ceiling was reached" and "the
> state could not be read" shared a code, a forgotten `init` or a wrong path
> would be reported to the operator as a genuine review escalation — the
> infrastructure would misreport in exactly the place this feature exists to
> stop the agent from misreporting.

Breezing repair instructions go back to the same Worker. In Codex, resume the
Worker and use `send_input`; in Claude Code, send the equivalent teammate
message (`SendMessage`).
Keep the original scope, DoD, and approval source in repair instructions; attach
the critical/major findings and relevant evidence. Re-review the changed output
in the same Reviewer thread within the same iteration limit. Start fresh only
when base/spec/DoD/scope materially changed or the stored Reviewer is unavailable;
record the reason in repair-loop state. Once DoD and required checks
pass, stop; optional improvements do not start another repair or test cycle.

## Breezing-Specific Application

In Breezing, the **Lead** runs the review loop:

1. Worker implements and commits inside its worktree, then returns the result to Lead.
2. Lead starts a persistent Codex review session (preferred) or a Reviewer agent (fallback) and retains its handle.
3. `REQUEST_CHANGES` → Lead sends fix instructions via `SendMessage`; Worker amends.
4. Re-review through the same handle after the fix (up to `MAX_REVIEWS`).
5. `APPROVE` → Lead pushes the topic branch and creates/updates a PR. Only formal review, required CI, and the GitHub merge receipt permit `harness-sync` to make a separate marker PR for `cc:完了 [merge-sha]`; waits are `cc:blocked [reason]`.
