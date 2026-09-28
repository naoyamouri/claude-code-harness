#!/usr/bin/env bash
# test-pr-closeout.sh
# Evidence-pack-driven PR closeout helper contract tests (Phase 72.1.5).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLOSEOUT="${PROJECT_ROOT}/scripts/harness-pr-closeout.sh"
EVIDENCE="${SCRIPT_DIR}/fixtures/pr-closeout-evidence.json"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

command -v jq >/dev/null 2>&1 || fail "jq is required"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/pr-closeout-test.XXXXXX")"
MOCK_BIN_DIR="${TMP_DIR}/bin"
MOCK_GH="${MOCK_BIN_DIR}/gh"
MOCK_GIT="${MOCK_BIN_DIR}/git"
GH_CALLS="${TMP_DIR}/gh-calls.log"
GIT_CALLS="${TMP_DIR}/git-calls.log"

cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

mkdir -p "${MOCK_BIN_DIR}"

make_blocking_mock() {
  local target="$1"
  local log_file="$2"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'echo "$0 $*" >> %s\n' "${log_file}"
    printf 'echo "mock blocked: $0" >&2\n'
    printf 'exit 99\n'
  } >"${target}"
  chmod +x "${target}"
}

make_recording_mock_gh() {
  {
    printf '#!/usr/bin/env bash\n'
    printf 'echo "$*" >> %s\n' "${GH_CALLS}"
    printf 'if [ "$1" = "pr" ] && [ "$2" = "create" ]; then\n'
    printf '  echo "https://github.com/example/repo/pull/1"\n'
    printf '  exit 0\n'
    printf 'fi\n'
    printf 'echo "unexpected gh invocation: $*" >&2\n'
    printf 'exit 1\n'
  } >"${MOCK_GH}"
  chmod +x "${MOCK_GH}"
}

run_closeout() {
  PATH="${MOCK_BIN_DIR}:${PATH}" bash "${CLOSEOUT}" "$@"
}

required_payload_fields=(
  base_ref
  head_ref
  spec_path
  lane
  stage
  review_command
  focused_tests
  accepted_findings
  rejected_findings
  release_preflight_warnings
  residual_risk
  title
  body
)

[ -f "${CLOSEOUT}" ] || fail "missing script: ${CLOSEOUT}"
[ -f "${EVIDENCE}" ] || fail "missing evidence fixture: ${EVIDENCE}"

# (a) build writes pr-payload.json with required fields
PAYLOAD_A="${TMP_DIR}/payload-a.json"
run_closeout build \
  --base origin/main \
  --head task/72.1.5 \
  --evidence "${EVIDENCE}" \
  --out "${PAYLOAD_A}"

[ -f "${PAYLOAD_A}" ] || fail "(a) build must write --out payload"

for field in "${required_payload_fields[@]}"; do
  jq -e --arg f "${field}" 'has($f)' "${PAYLOAD_A}" >/dev/null \
    || fail "(a) missing required field in payload: ${field}"
done

[ "$(jq -r '.base_ref' "${PAYLOAD_A}")" = "origin/main" ] \
  || fail "(a) base_ref must come from --base"
[ "$(jq -r '.head_ref' "${PAYLOAD_A}")" = "task/72.1.5" ] \
  || fail "(a) head_ref must come from --head"

# (b) dry-run must not invoke gh or git
make_blocking_mock "${MOCK_GH}" "${GH_CALLS}"
make_blocking_mock "${MOCK_GIT}" "${GIT_CALLS}"
: >"${GH_CALLS}"
: >"${GIT_CALLS}"

set +e
dry_out="$(run_closeout dry-run --payload "${PAYLOAD_A}" 2>&1)"
dry_rc=$?
set -e

[ "${dry_rc}" -eq 0 ] || fail "(b) dry-run should exit 0, got ${dry_rc}"
[ "${#dry_out}" -gt 0 ] || fail "(b) dry-run should print preview output"
[ ! -s "${GH_CALLS}" ] || fail "(b) dry-run must not call gh (calls: $(cat "${GH_CALLS}"))"
[ ! -s "${GIT_CALLS}" ] || fail "(b) dry-run must not call git (calls: $(cat "${GIT_CALLS}"))"

# push tests need real git for attached-head detection; drop the blocking git mock.
rm -f "${MOCK_GIT}"

# (c) push --yes invokes gh pr create with expected argv
make_recording_mock_gh
: >"${GH_CALLS}"

DETACHED_REPO="${TMP_DIR}/detached-repo"
mkdir -p "${DETACHED_REPO}"
git -C "${DETACHED_REPO}" init -q
git -C "${DETACHED_REPO}" config user.email "test@example.com"
git -C "${DETACHED_REPO}" config user.name "Test User"
printf 'seed\n' >"${DETACHED_REPO}/README.md"
git -C "${DETACHED_REPO}" add README.md
git -C "${DETACHED_REPO}" commit -q -m "seed"
git -C "${DETACHED_REPO}" checkout -q -b task/72.1.5

PAYLOAD_C="${TMP_DIR}/payload-c.json"
(
  cd "${DETACHED_REPO}"
  PATH="${MOCK_BIN_DIR}:${PATH}" bash "${CLOSEOUT}" build \
    --base main \
    --head task/72.1.5 \
    --evidence "${EVIDENCE}" \
    --out "${PAYLOAD_C}"
)

set +e
(
  cd "${DETACHED_REPO}"
  PATH="${MOCK_BIN_DIR}:${PATH}" bash "${CLOSEOUT}" push --payload "${PAYLOAD_C}" --yes
) >/dev/null 2>&1
push_rc=$?
set -e

[ "${push_rc}" -eq 0 ] || fail "(c) push --yes should exit 0 on attached branch, got ${push_rc}"
grep -Fq 'pr create' "${GH_CALLS}" || fail "(c) push --yes must call gh pr create"
grep -Fq -- '--base main' "${GH_CALLS}" || fail "(c) gh pr create must pass --base"
grep -Fq -- '--head task/72.1.5' "${GH_CALLS}" || fail "(c) gh pr create must pass --head"
grep -Fq -- '--title' "${GH_CALLS}" || fail "(c) gh pr create must pass --title"
grep -Fq -- '--body' "${GH_CALLS}" || fail "(c) gh pr create must pass --body"
grep -Fq -- '--draft' "${GH_CALLS}" || fail "(c) gh pr create must pass --draft (CI runs the full suite only after ready)"

# (d) push without --yes and non-tty stdin must exit 1
make_recording_mock_gh
: >"${GH_CALLS}"

set +e
(
  cd "${DETACHED_REPO}"
  PATH="${MOCK_BIN_DIR}:${PATH}" bash "${CLOSEOUT}" push --payload "${PAYLOAD_C}" </dev/null
) >/dev/null 2>&1
no_confirm_rc=$?
set -e

[ "${no_confirm_rc}" -eq 1 ] || fail "(d) push without --yes on non-tty stdin must exit 1, got ${no_confirm_rc}"
[ ! -s "${GH_CALLS}" ] || fail "(d) push without confirmation must not call gh"

# (e) detached HEAD must fail fast
DETACHED_ONLY="${TMP_DIR}/detached-only"
mkdir -p "${DETACHED_ONLY}"
git -C "${DETACHED_ONLY}" init -q
git -C "${DETACHED_ONLY}" config user.email "test@example.com"
git -C "${DETACHED_ONLY}" config user.name "Test User"
printf 'solo\n' >"${DETACHED_ONLY}/README.md"
git -C "${DETACHED_ONLY}" add README.md
git -C "${DETACHED_ONLY}" commit -q -m "solo"
DETACHED_SHA="$(git -C "${DETACHED_ONLY}" rev-parse HEAD)"
git -C "${DETACHED_ONLY}" checkout -q "${DETACHED_SHA}"

PAYLOAD_E="${TMP_DIR}/payload-e.json"
(
  cd "${DETACHED_ONLY}"
  PATH="${MOCK_BIN_DIR}:${PATH}" bash "${CLOSEOUT}" build \
    --base main \
    --head "${DETACHED_SHA}" \
    --evidence "${EVIDENCE}" \
    --out "${PAYLOAD_E}"
)

set +e
(
  cd "${DETACHED_ONLY}"
  PATH="${MOCK_BIN_DIR}:${PATH}" bash "${CLOSEOUT}" push --payload "${PAYLOAD_E}" --yes
) >/dev/null 2>&1
detached_rc=$?
set -e

[ "${detached_rc}" -eq 1 ] || fail "(e) detached HEAD push must exit 1, got ${detached_rc}"

# (f) title <= 70 chars; body includes accepted and rejected findings
title_len="$(jq -r '.title' "${PAYLOAD_A}" | wc -m | tr -d ' ')"
[ "${title_len}" -le 70 ] || fail "(f) title must be <= 70 chars, got ${title_len}"

body_text="$(jq -r '.body' "${PAYLOAD_A}")"
grep -Fq 'acc-1' <<<"${body_text}" || fail "(f) body must include accepted finding id"
grep -Fq 'rej-1' <<<"${body_text}" || fail "(f) body must include rejected finding id"
grep -Fq 'Accepted findings' <<<"${body_text}" || fail "(f) body must sectionize accepted findings"
grep -Fq 'Rejected findings' <<<"${body_text}" || fail "(f) body must sectionize rejected findings"

# (g) harness-review path must not auto push / create PR
review_hits="$(rg -n 'gh pr create|git push' "${PROJECT_ROOT}/skills/harness-review" 2>/dev/null || true)"
[ -z "${review_hits}" ] || fail "(g) harness-review must not reference gh pr create or git push:\n${review_hits}"

# (h) ready: marks a draft PR ready and waits for the ready_for_review re-runs
# Mock state: draft flag, the runs visible for the head SHA, and workflow files.
READY_STATE="${TMP_DIR}/ready-state"
make_ready_mock_gh() {
  # $1 = runs appended by `gh pr ready` (JSON array of {id,path})
  mkdir -p "${READY_STATE}"
  printf '%s' "$1" >"${READY_STATE}/runs-after-ready.json"
  cat >"${MOCK_GH}" <<MOCK
#!/usr/bin/env bash
echo "\$*" >> "${GH_CALLS}"
S="${READY_STATE}"
case "\$*" in
  "pr view 7 --json isDraft,headRefOid")
    printf '{"isDraft":%s,"headRefOid":"abc123"}' "\$(cat "\$S/draft")" ;;
  "pr ready 7")
    jq -s 'add' "\$S/runs.json" "\$S/runs-after-ready.json" >"\$S/runs.next" && mv "\$S/runs.next" "\$S/runs.json"
    echo false >"\$S/draft" ;;
  *"actions/runs?head_sha=abc123&event=pull_request"*)
    jq '{workflow_runs: .}' "\$S/runs.json" ;;
  *"contents/.github/workflows/"*)
    f="\${*##*contents/}"; f="\${f%%\?*}"; cat "\$S/files/\$(basename "\$f")" 2>/dev/null || { echo "HTTP 502" >&2; exit 1; } ;;
  *) echo "unexpected gh invocation: \$*" >&2; exit 1 ;;
esac
MOCK
  chmod +x "${MOCK_GH}"
}
reset_ready_state() {
  rm -rf "${READY_STATE}"; mkdir -p "${READY_STATE}/files"
  echo "$1" >"${READY_STATE}/draft"
  printf '[{"id":1,"path":".github/workflows/tests.yml","status":"completed"},{"id":2,"path":".github/workflows/lint.yml","status":"completed"}]' >"${READY_STATE}/runs.json"
  printf 'on:\n  pull_request:\n    types: [opened, synchronize, ready_for_review]\n' >"${READY_STATE}/files/tests.yml"
  printf 'on:\n  pull_request:\n' >"${READY_STATE}/files/lint.yml"
  : >"${GH_CALLS}"
}
run_ready() {
  HARNESS_READY_POLL_INTERVAL=0 PATH="${MOCK_BIN_DIR}:${PATH}" bash "${CLOSEOUT}" ready --pr 7 "$@"
}

# (h1) draft PR: calls gh pr ready and exits 0 once tests.yml has a new run
reset_ready_state true
make_ready_mock_gh '[{"id":3,"path":".github/workflows/tests.yml","status":"completed"}]'
set +e; run_ready --timeout 5 >/dev/null 2>&1; rc=$?; set -e
[ "${rc}" -eq 0 ] || fail "(h1) ready should exit 0 after the re-run appears, got ${rc}"
grep -Fxq 'pr ready 7' "${GH_CALLS}" || fail "(h1) ready must call gh pr ready"

# (h2) no re-run ever appears: must time out non-zero instead of trusting the draft-era green
reset_ready_state true
make_ready_mock_gh '[]'
set +e; run_ready --timeout 1 >/dev/null 2>&1; rc=$?; set -e
[ "${rc}" -ne 0 ] || fail "(h2) ready must fail when the ready_for_review run never registers"

# (h3) no workflow reacts to ready_for_review: exit 0 without waiting
reset_ready_state true
printf 'on:\n  pull_request:\n' >"${READY_STATE}/files/tests.yml"
make_ready_mock_gh '[]'
set +e; run_ready --timeout 1 >/dev/null 2>&1; rc=$?; set -e
[ "${rc}" -eq 0 ] || fail "(h3) ready must not wait when no workflow lists ready_for_review, got ${rc}"
grep -Fxq 'pr ready 7' "${GH_CALLS}" || fail "(h3) ready must still call gh pr ready"

# (h4) already non-draft: no gh pr ready
reset_ready_state false
make_ready_mock_gh '[]'
set +e; run_ready --timeout 1 >/dev/null 2>&1; rc=$?; set -e
[ "${rc}" -eq 0 ] || fail "(h4) ready on a non-draft PR should exit 0, got ${rc}"
! grep -Fq 'pr ready' "${GH_CALLS}" || fail "(h4) ready must not call gh pr ready on a non-draft PR"

# (h5) a workflow file cannot be fetched: fail before gh pr ready (stay draft, fail closed)
reset_ready_state true
rm "${READY_STATE}/files/lint.yml"
make_ready_mock_gh '[{"id":3,"path":".github/workflows/tests.yml","status":"completed"}]'
set +e; run_ready --timeout 1 >/dev/null 2>&1; rc=$?; set -e
[ "${rc}" -ne 0 ] || fail "(h5) ready must fail when a workflow file cannot be fetched"
! grep -Fq 'pr ready' "${GH_CALLS}" || fail "(h5) ready must not mark the PR ready when detection failed"

# (h6) re-run registered but not completed: keep waiting (old SUCCESS checks are still visible)
reset_ready_state true
make_ready_mock_gh '[{"id":3,"path":".github/workflows/tests.yml","status":"in_progress"}]'
set +e; run_ready --timeout 1 >/dev/null 2>&1; rc=$?; set -e
[ "${rc}" -ne 0 ] || fail "(h6) ready must wait for the re-run to complete, not just register"

# (h7) non-numeric --timeout is rejected instead of looping forever
# (no workflow waits here, so a missing check returns 0 quickly instead of hanging the suite)
reset_ready_state true
printf 'on:\n  pull_request:\n' >"${READY_STATE}/files/tests.yml"
make_ready_mock_gh '[]'
set +e; run_ready --timeout abc >/dev/null 2>&1; rc=$?; set -e
[ "${rc}" -eq 2 ] || fail "(h7) non-numeric --timeout must exit 2, got ${rc}"
! grep -Fq 'pr ready' "${GH_CALLS}" || fail "(h7) invalid --timeout must not call gh pr ready"

echo "test-pr-closeout: ok"
