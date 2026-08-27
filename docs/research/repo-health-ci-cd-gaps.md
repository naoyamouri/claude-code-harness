# Repo Health / CI-CD Gap Baseline

Date: 2026-05-22 JST
Scope: Phase 74.1.1 research / evidence only. No formatter, CI, or release behavior is changed by this document.

## Verdict

Phase 74 is not a request to rebuild release gates from scratch.

The repository already has useful release and adapter gates. Phase 74 should reuse and connect them more deliberately:

- Reuse existing release preflight and mirror drift gates.
- Add only missing repo-health gates where the current evidence shows a gap.
- Keep support tier claims below public support unless host runtime smoke exists.
- Treat static checks and skipped runtime smoke as evidence boundaries, not as runtime proof.
- Keep `not_observed != absent`.

## Harness-Mem Evidence

The following harness-mem observations were retrieved during the Phase 74 review pass:

| Observation | Evidence used | Phase 74 implication |
|-------------|---------------|----------------------|
| `obs_00mpgppz7f6f5a34497979547e` | Review result said implementation may start, but only from `74.1.1` evidence doc. | Do not start with `gofmt -w` or CI edits. Baseline first. |
| `obs_00mpgbnvdef40188747e0463c9` | Phase 73.1.3 prompt kept support tiers fixed and required `not_observed != absent`. | Phase 74 must not promote Codex app, Cursor, Copilot CLI, Antigravity, or OpenCode parity without runtime proof. |
| `obs_00mpgbny6q214e4d30a1718f50` | Review focus included README/onboarding wording, support claim boundary, and not rushing later adapter tasks. | Repo-health wording must avoid implying broader host support. |
| `obs_00mpfmwsg2ed41f1beb39b9ff4` | Prior handoff captured `validate-plugin` / `check-consistency` / skill mirror drift as distribution-quality risk. | Phase 74 must include mirror drift and consistency as existing risk surfaces, not rediscover them. |

Retrieval boundary: harness-mem was reachable in the prior review pass, but transient daemon timeouts were also observed. Future review evidence should use serial `safe_mode` search or direct observation IDs rather than broad parallel searches.

## Existing Gates To Reuse

### Release Preflight Already Exists

`scripts/release-preflight.sh` already checks core release safety:

- clean worktree: `scripts/release-preflight.sh:139`
- release version sync: `scripts/release-preflight.sh:168`
- adapter path detection: `scripts/release-preflight.sh:407`
- explicit / path / claim driven adapter gate selection: `scripts/release-preflight.sh:488`
- mirror build / OpenCode validation / skill mirror sync: `scripts/release-preflight.sh:548`
- mirror drift failure: `scripts/release-preflight.sh:578`
- Codex plugin adapter smoke and OpenCode bootstrap smoke: `scripts/release-preflight.sh:600`
- distribution archive gate: `scripts/release-preflight.sh:622`
- capability matrix and bootstrap routing gates: `scripts/release-preflight.sh:633`
- CI status boundary for detached HEAD: `scripts/release-preflight.sh:680`

Do not create a second release preflight system. Phase 74 should connect this existing gate to the tag / release flow and clarify when it is required.

### Prior Plans Already Covered Mirror Drift

Historical Plans evidence shows this is not new ground:

- Phase 66.1.4 added release preflight mirror drift checks before tags: `Plans.md:123`
- Phase 70.2.3 made adapter checks path-triggered, release-claim-triggered, or explicit-flag triggered: `Plans.md:179`
- Phase 70.4.1 required full regression closeout including release preflight: `Plans.md:182`

Phase 74 should not duplicate that architecture. It should verify whether the current tag-triggered workflow and PR/release closeout actually require those existing gates.

### CI Already Covers Several Quality Surfaces

Current CI gates observed:

- actionlint install and execution: `.github/workflows/validate-plugin.yml:35`
- plugin validation: `.github/workflows/validate-plugin.yml:81`
- consistency checks: `.github/workflows/validate-plugin.yml:85`
- Codex package validation: `.github/workflows/validate-plugin.yml:89`
- Go build/test/vet: `.github/workflows/validate-plugin.yml:108`
- multi-OS build / validate / doctor smoke: `.github/workflows/smoke-install.yml:42`
- OpenCode mirror build / validation / setup contract / mirror sync: `.github/workflows/opencode-compat.yml:81`

Phase 74 must preserve these gates and add missing checks around them, not replace them.

## Current Gaps

### Go Format Gate

Observed command:

```text
gofmt -l go
```

Observed files: 28.

```text
go/internal/breezing/deps.go
go/internal/event/event.go
go/internal/event/post_compact.go
go/internal/guardrail/cc2110_regression_test.go
go/internal/hookhandler/auto_test_runner.go
go/internal/hookhandler/ci_status_checker.go
go/internal/hookhandler/emit_agent_trace.go
go/internal/hookhandler/emit_agent_trace_test.go
go/internal/hookhandler/fix_proposal_injector_test.go
go/internal/hookhandler/instructions_loaded_test.go
go/internal/hookhandler/permission_denied_handler.go
go/internal/hookhandler/permission_denied_handler_test.go
go/internal/hookhandler/posttooluse_log_toolname_test.go
go/internal/hookhandler/posttooluse_quality_pack_test.go
go/internal/hookhandler/pre_compact_save.go
go/internal/hookhandler/pre_compact_save_test.go
go/internal/hookhandler/task_completed.go
go/internal/hookhandler/task_completed_test.go
go/internal/hookhandler/todo_sync_test.go
go/internal/hookhandler/track_changes.go
go/internal/hookhandler/userprompt_inject_policy_test.go
go/internal/session/init.go
go/internal/session/monitor.go
go/internal/session/monitor_test.go
go/internal/session/summary.go
go/internal/session/summary_test.go
go/internal/state/schema.go
go/internal/state/store.go
```

Existing Go tests and vet are present, but no `gofmt -l go` fail gate was observed in `.github/workflows/validate-plugin.yml`.

Recommended Phase 74 handling:

- First apply format-only diff separately from functional changes.
- Add a small format/lint test or CI step.
- Keep `go test ./...` and `go vet ./...` as existing behavior gates.

### Phase 74.1.2 Format Gate Closeout

Date: 2026-05-22 JST

Implementation:

- Ran `gofmt -w` on the 28 files listed in the Phase 74.1.1 baseline.
- Added `tests/test-format-lint.sh` as the repo-local fail gate for `gofmt -l go`.
- Added the same gate to `.github/workflows/validate-plugin.yml` in the `test-go` job before Go build/test/vet.

Separation note:

- This task is a format gate and CI gate change only.
- The worktree already contained other Go changes before this task, including `go/cmd/harness/doctor.go`, `go/cmd/harness/main.go`, and untracked migration report files.
- Those existing functional diffs are not part of the Phase 74.1.2 format-only change. Review and commit separation should keep mechanical gofmt output separate from functional Go changes.

Validation:

- `bash tests/test-format-lint.sh`: PASS
- `gofmt -l go`: PASS, empty output
- `go test ./...` from `go/`: PASS
- `go vet ./...` from `go/`: PASS

### Shell Lint / Format

Observed local tool availability:

- `shellcheck`: available locally at `/opt/homebrew/bin/shellcheck`
- `shfmt`: not observed in PATH

Observed CI gap:

- No `shellcheck` / `shfmt` gate was observed in the root workflows reviewed.

This means shell lint is not "unnecessary"; it is currently unconfigured as a repo gate.

Recommended Phase 74 handling:

- Start with high-risk subset: `scripts/release-preflight.sh`, setup scripts, `scripts/ci/*.sh`, and `tests/test-*.sh`.
- Use `shellcheck` as a targeted fail gate.
- Decide whether `shfmt -d` starts as fail gate or advisory after baseline evidence.

### Phase 74.1.3 Shell Lint Baseline Closeout

Date: 2026-05-22 JST

Implementation:

- Added `tests/test-shell-lint.sh`.
- Added `shellcheck` installation and `bash ./tests/test-shell-lint.sh` to `.github/workflows/validate-plugin.yml`.
- The first fail gate uses `shellcheck --severity=error` for a high-risk subset:
  - `scripts/release-preflight.sh`
  - `scripts/setup-codex.sh`
  - `scripts/setup-opencode.sh`
  - `scripts/ci/*.sh`
  - `tests/test-distribution-archive.sh`
  - `tests/test-release-preflight.sh`
  - `tests/test-format-lint.sh`
  - `tests/test-shell-lint.sh`

Why this is the first gate:

- A normal `shellcheck` run on the same high-risk subset has existing warning/info debt, but no error-level findings.
- The error-level gate still catches shell parse failures and high-risk command issues on the release/setup/CI path.
- `shfmt` remains advisory for now because it was not observed in PATH locally and is not yet installed in CI.

Observed warning/info debt to classify before expanding the gate:

- `scripts/release-preflight.sh`: unused color variables (`SC2034`).
- `scripts/setup-opencode.sh`: ASCII-art single quotes (`SC2016`), pattern substitution quoting (`SC2295`), inline local assignment (`SC2155`).
- `scripts/ci/*.sh`: inline local assignment (`SC2155`), pattern substitution quoting (`SC2295`), single-run loop style (`SC2043`), and similar style/info findings.

Exploratory broader run:

- `shellcheck --severity=error scripts/release-preflight.sh scripts/setup-codex.sh scripts/setup-opencode.sh scripts/ci/*.sh tests/test-*.sh` found error-level findings outside the first subset:
  - `tests/test-hooks-sync.sh`: `SC1087`
  - `tests/test-project-detection.sh`: `SC2045`
  - `tests/test-render-html.sh`: `SC1072` / `SC1073`
- These are real expansion blockers, but they are outside the initial release/setup/CI/distribution subset and should be cleaned before moving ShellCheck to all test scripts.

Validation:

- `bash tests/test-shell-lint.sh`: PASS
- Direct high-risk subset `shellcheck --severity=error`: PASS
- `shfmt`: not observed in PATH; no fail gate added.

### Release Workflow Is Not Preflight-Gated

The tag-triggered release workflow builds and uploads binaries:

- tag trigger: `.github/workflows/release.yml:3`
- build binaries: `.github/workflows/release.yml:71`
- create release / upload assets: `.github/workflows/release.yml:78`

No step requiring `scripts/release-preflight.sh --check-adapters` was observed before asset upload.

Recommended Phase 74 handling:

- Do not rewrite release preflight.
- Require the existing preflight before release claim, tag, or asset upload.
- Make CI unavailable / detached HEAD a warning or release-block boundary, not a release-ready signal.

### Phase 74.1.4 Release Preflight Hardening Closeout

Date: 2026-05-22 JST

Implementation:

- Added `bash ./scripts/release-preflight.sh --check-adapters` to `.github/workflows/release.yml` before GitHub Release creation and existing release asset upload.
- Added release workflow dependencies for `jq` and `ripgrep`, which the existing preflight path may need.
- Updated `docs/release-preflight.md` to state that the tag-triggered release workflow runs preflight before publishing assets.
- Added `tests/test-release-preflight.sh` coverage that asserts release preflight appears before both `Create GitHub Release` and `Upload Go binaries to existing release`.

Boundary:

- This does not create a second release preflight system. It wires the existing `scripts/release-preflight.sh --check-adapters` gate into the publishing path.
- `tests/test-distribution-archive.sh` still verifies `git archive HEAD`, so it proves committed artifact shape only. Dirty and untracked local files are covered by the clean-tree preflight gate, not by the archive test itself.
- In a tag-triggered detached HEAD workflow, CI status may be unavailable and remains a warning boundary. Release-ready claims should not treat that warning as proof that PR/main CI passed.

Validation:

- `bash tests/test-release-preflight.sh`: PASS
- `bash tests/test-distribution-archive.sh`: PASS

### Distribution Archive Uses HEAD

`tests/test-distribution-archive.sh` lists the distribution archive from `git archive HEAD`: `tests/test-distribution-archive.sh:8`.

Implication:

- Dirty and untracked local files are not represented in the archive.
- Passing this test does not prove uncommitted Phase 73/74 files are included in the shipped artifact.

Recommended Phase 74 handling:

- Keep this as an archive-shape gate.
- Pair it with clean-tree preflight before release-ready claims.

### Host Runtime Smoke Boundary

Codex plugin adapter test:

- static manifest/app proof checks: `tests/test-codex-plugin-adapter.sh:24`
- real Codex CLI smoke only if `codex` exists: `tests/test-codex-plugin-adapter.sh:55`
- otherwise prints static checks passed and smoke skipped: `tests/test-codex-plugin-adapter.sh:100`

OpenCode bootstrap:

- plugin injects bootstrap content and skill path registration: `opencode/plugins/harness-bootstrap.mjs:29`
- it explicitly keeps OpenCode at `internal-compatible` without runtime smoke: `opencode/plugins/harness-bootstrap.mjs:45`

Recommended Phase 74 handling:

- If CI can install real Codex/OpenCode binaries, run real runtime smoke.
- If not, preserve support tiers and emit evidence that static or Node-level checks are not runtime proof.

### Phase 74.1.5 Host Runtime Smoke Closeout

Date: 2026-05-22 JST

Official docs checked:

- Codex CLI official docs: <https://developers.openai.com/codex/cli> documents npm install via `npm i -g @openai/codex`.
- OpenCode CLI official docs: <https://opencode.ai/docs/cli/> documents CLI commands including `opencode plugin <module>` and config-related environment variables, but this task did not establish a CI-safe OpenCode binary install route.

Implementation:

- Added `HARNESS_CODEX_PLUGIN_SMOKE_REQUIRED=1` to `tests/test-codex-plugin-adapter.sh` so CI cannot silently pass if the Codex CLI is missing.
- Added `.github/workflows/validate-plugin.yml` steps to install a pinned Codex CLI package (`@openai/codex@0.133.0`) and run `bash ./tests/test-codex-plugin-adapter.sh` with runtime smoke required.
- Kept Codex CLI at `internal-compatible`: the new proof covers direct CLI marketplace/install/cache behavior in isolated `HOME` / `CODEX_HOME`, not Codex app behavior or Claude hook parity.
- Updated `tests/test-opencode-bootstrap-plugin.sh` to make OpenCode real-binary runtime absence explicit. Node-level bootstrap checks still pass, but the test now prints a warning when no executable OpenCode runtime is available.
- Updated `docs/tool-capability-matrix.md` to reflect Codex CLI runtime smoke and OpenCode's remaining Node-level boundary.
- Updated `docs/research/codex-app-smoke.md` so Codex app remains `candidate` even after Codex CLI runtime smoke is CI-gated.

Validation:

- `bash tests/test-codex-plugin-adapter.sh`: PASS
- `HARNESS_CODEX_PLUGIN_SMOKE_REQUIRED=1 bash tests/test-codex-plugin-adapter.sh`: PASS
- `bash tests/test-opencode-bootstrap-plugin.sh`: PASS with explicit runtime-skipped warning
- `bash tests/test-tool-capability-matrix.sh`: PASS

Support claim boundary:

- Codex CLI direct plugin smoke is stronger than static proof, but does not raise Codex CLI above `internal-compatible`.
- OpenCode remains `internal-compatible`; runtime bootstrap parity is still not observed.
- Codex app remains `candidate`; CLI proof is not app proof.

## Regression Check From This Review

Commands run after the harness-mem catch-up:

```text
git diff --check -- spec.md Plans.md docs/phase-73-completion-confidence.html docs/research
bash tests/test-spec-ssot-workflow.sh
bash tests/test-tool-capability-matrix.sh
bash tests/test-bootstrap-routing-contract.sh
bash scripts/sync-skill-mirrors.sh --check
bash tests/test-codex-package.sh
node scripts/validate-opencode.js
```

Result:

- diff check: PASS
- spec SSOT workflow: PASS
- capability matrix: PASS
- bootstrap routing: PASS
- skill mirror sync: PASS when run serially
- Codex package: PASS when run serially
- OpenCode validation: PASS when run serially

Important concurrency note:

- Running mirror build / release preflight / Codex package checks in parallel can create misleading transient failures because generated mirror files may be rewritten while another check reads them.
- Phase 74 release evidence should run these checks serially or isolate generated outputs.

## Release Preflight Observation

`bash scripts/release-preflight.sh --check-adapters` was also run during this review.

Observed:

- It failed `working tree clean` because this Phase 73/74 worktree is dirty.
- It later reported `release mirror drift` when mirror build generated diffs under `opencode/AGENTS.md` / `opencode/README.md`.
- After the checks were rerun serially, `bash scripts/sync-skill-mirrors.sh --check`, `bash tests/test-codex-package.sh`, and `node scripts/validate-opencode.js` passed.

Interpretation:

- This does not mean release preflight is obsolete.
- It means release preflight must be run in a clean release context, and generated mirror drift must be treated as a release blocker or isolated from read-only review checks.

## Phase 74.1.6 Closeout Observation

Date: 2026-05-22 JST

Commands:

```text
bash tests/validate-plugin.sh
bash scripts/release-preflight.sh --check-adapters
```

Results:

- `bash tests/validate-plugin.sh`: PASS, 95 passed / 0 warnings / 0 failed.
- Pre-commit `bash scripts/release-preflight.sh --check-adapters`: expected FAIL in the dirty worktree.
- Post-commit `bash scripts/release-preflight.sh --check-adapters`: PASS with warnings.

Pre-commit release-preflight summary:

- 13 passed
- 5 warnings
- 2 failed

Failed gates:

- `working tree clean`: failed because Phase 73/74 changes are intentionally uncommitted in this worktree.
- `release mirror drift`: failed with generated diffs under `opencode/AGENTS.md` and `opencode/README.md`.

Post-commit release-preflight summary:

- 15 passed
- 5 warnings
- 0 failed

Warnings:

- `.env.example not found; env parity skipped`
- healthcheck command not configured
- runtime residual scan warnings
- sprint-contract schema scan skipped
- CI status unavailable because no GitHub Actions run had been observed for branch `codex/phase-73-74-harness-v2` immediately after first push

Interpretation:

- Phase 74 implementation gates are in place and local validation passed.
- Clean local release preflight now passes.
- This branch is PR-ready after normal review, but not release-ready until GitHub CI is green on the pushed branch / PR context.

## Support Claim Boundary

Current repo wording correctly keeps:

- Claude Code: `supported`
- Codex CLI: `internal-compatible`
- OpenCode: `internal-compatible`
- Codex app / Cursor / GitHub Copilot CLI: `candidate`
- Antigravity CLI: `future/unsupported`

Phase 74 must not raise any host tier solely because static tests pass.

## Phase 74 Implementation Guardrails

1. Start with this evidence baseline.
2. Do not add a second release-preflight script.
3. Reuse existing release preflight and mirror gates.
4. Keep formatter-only diffs separate from functional changes.
5. Run mirror-generation-related checks serially.
6. Treat skipped host runtime smoke as a support-claim boundary.
7. Require clean-tree release preflight before release-ready claims.
