#!/usr/bin/env bash
# Phase 148 — persistent reviewer session contract (no provider calls).

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WRAPPER="${ROOT_DIR}/scripts/codex-companion.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

fail() {
  echo "test-codex-review-session: FAIL: $1" >&2
  exit 1
}

rg -q 'review-session' "${ROOT_DIR}/skills/harness-work/references/review-loop.md" \
  || fail "shared Claude-side review loop is not wired to the persistent session"
rg -q 'followup_task' "${ROOT_DIR}/skills-codex/harness-work/references/review-loop.md" \
  || fail "Codex reviewer fallback does not retain its target"
rg -q 'same reviewer thread' "${ROOT_DIR}/docs/spec/workflow-review-and-release.md" \
  || fail "detailed Review Contract does not require same-thread repair review"

PROJECT="${TMP_DIR}/project"
FAKE_BIN="${TMP_DIR}/bin"
CALLS="${TMP_DIR}/calls.jsonl"
LEDGER="${TMP_DIR}/orchestration-ledger.jsonl"
mkdir -p "${PROJECT}" "${FAKE_BIN}"
git -C "${PROJECT}" init -q
git -C "${PROJECT}" config user.name test
git -C "${PROJECT}" config user.email test@example.com
printf 'base\n' > "${PROJECT}/tracked.txt"
git -C "${PROJECT}" add tracked.txt
git -C "${PROJECT}" commit -qm base

cat > "${FAKE_BIN}/codex" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$(printf '%s\0' "$@" | jq -Rs 'split("\u0000")[:-1]')" >> "${FAKE_CODEX_CALLS}"
output=""
schema=""
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  case "${args[$i]}" in
    -o|--output-last-message) output="${args[$((i + 1))]:-}" ;;
    --output-schema) schema="${args[$((i + 1))]:-}" ;;
  esac
done
if [ "${FAKE_CODEX_FAIL_RESUME:-0}" = 1 ] && [ "${1:-}" = exec ] && [ "${2:-}" = resume ]; then
  exit 9
fi
if [ "${1:-}" = exec ] && [ "${2:-}" = resume ]; then
  printf '{"type":"thread.started","thread_id":"%s"}\n' "${3}"
else
  printf '{"type":"thread.started","thread_id":"thread-%s"}\n' "${FAKE_CODEX_THREAD:-one}"
fi
[ -n "${output}" ] || exit 8
[ -f "${schema}" ] || exit 7
case "${FAKE_CODEX_OUTPUT_MODE:-valid}" in
  valid)
    printf '{"verdict":"approve","summary":"No blocking findings.","findings":[],"next_steps":[]}\n' > "${output}"
    ;;
  missing) rm -f "${output}" ;;
  malformed) printf 'not-json\n' > "${output}" ;;
esac
SH
chmod +x "${FAKE_BIN}/codex"

run_review() {
  local fingerprint="$1"
  local task_id="${TEST_TASK_ID:-148.1}"
  PATH="${FAKE_BIN}:${PATH}" \
    FAKE_CODEX_CALLS="${CALLS}" \
    FAKE_CODEX_OUTPUT_MODE="${FAKE_CODEX_OUTPUT_MODE:-valid}" \
    FAKE_CODEX_THREAD="${FAKE_CODEX_THREAD:-one}" \
    FAKE_CODEX_FAIL_RESUME="${FAKE_CODEX_FAIL_RESUME:-0}" \
    HARNESS_ORCHESTRATION_LEDGER="${LEDGER}" \
    CLAUDE_SESSION_ID="phase-148-test" \
    HARNESS_DISABLE_MODEL_ROUTING=1 \
    bash "${WRAPPER}" review-session \
      --project-root "${PROJECT}" \
      --task-id "${task_id}" \
      --target-fingerprint "${fingerprint}" \
      --base-ref HEAD \
      --output "${TMP_DIR}/review-${task_id}.json" \
      --prompt "Review the current diff"
}

run_review target-a >/dev/null
STATE="${PROJECT}/.claude/state/repair-loop/148.1.json"
[ "$(jq -r '.reviewer.handle' "${STATE}")" = thread-one ] || fail "initial reviewer handle was not stored"
[ "$(jq -r '.reviewer.fresh_reason' "${STATE}")" = initial ] || fail "initial reason was not stored"
jq -e 'select(.[0] == "exec" and index("--sandbox") and index("read-only") and index("review"))' "${CALLS}" >/dev/null \
  || fail "initial review did not force the read-only sandbox"
jq -e 'select(.[0] == "exec" and index("--output-schema"))' "${CALLS}" >/dev/null \
  || fail "initial review did not enforce an output schema"
bash "${ROOT_DIR}/scripts/write-review-result.sh" "${TMP_DIR}/review-148.1.json" HEAD "${TMP_DIR}/normalized-review.json" >/dev/null
jq -e '.schema_version == "review-result.v1" and .verdict == "APPROVE"' "${TMP_DIR}/normalized-review.json" >/dev/null \
  || fail "structured review output did not normalize into review-result.v1"
[ "$(wc -l < "${LEDGER}" | tr -d ' ')" -eq 1 ] || fail "successful review-session did not emit exactly one ledger entry"
jq -e 'select(.backend == "codex" and .subcommand == "review-session" and .counts == true and .write == false)' "${LEDGER}" >/dev/null \
  || fail "review-session ledger entry is not countable and read-only"
grep -Fq 'Review the current diff' "${LEDGER}" && fail "review prompt leaked into the ledger"

run_review target-a >/dev/null
jq -e 'select(.[0] == "exec" and .[1] == "resume" and index("thread-one"))' "${CALLS}" >/dev/null \
  || fail "same target did not resume thread-one"
jq -e 'select(.[0] == "exec" and .[1] == "resume" and index("sandbox_mode=\"read-only\""))' "${CALLS}" >/dev/null \
  || fail "resumed review did not force the read-only sandbox"
[ "$(jq '.reviewer_replacements | length' "${STATE}")" -eq 0 ] || fail "same target replaced the reviewer"

FAKE_CODEX_THREAD=two run_review target-b >/dev/null
[ "$(jq -r '.reviewer.handle' "${STATE}")" = thread-two ] || fail "material target change did not start a fresh reviewer"
[ "$(jq -r '.reviewer.fresh_reason' "${STATE}")" = material-target-change ] || fail "target-change reason missing"

FAKE_CODEX_THREAD=three FAKE_CODEX_FAIL_RESUME=1 run_review target-b >/dev/null
[ "$(jq -r '.reviewer.handle' "${STATE}")" = thread-three ] || fail "unavailable reviewer did not fall back to a fresh reviewer"
[ "$(jq -r '.reviewer.fresh_reason' "${STATE}")" = reviewer-unavailable ] || fail "reviewer-unavailable reason missing"
[ "$(jq '.reviewer_replacements | length' "${STATE}")" -eq 2 ] || fail "reviewer replacement history is incomplete"

jq -e '.reviewer.transport == "codex-exec" and .reviewer.target_fingerprint == "target-b"' "${STATE}" >/dev/null \
  || fail "reviewer identity state is incomplete"

set +e
TEST_TASK_ID=148.missing FAKE_CODEX_OUTPUT_MODE=missing run_review missing-output >/dev/null 2>&1
missing_rc=$?
TEST_TASK_ID=148.malformed FAKE_CODEX_OUTPUT_MODE=malformed run_review malformed-output >/dev/null 2>&1
malformed_rc=$?
set -e
[ "${missing_rc}" -ne 0 ] || fail "missing review output was accepted"
[ "${malformed_rc}" -ne 0 ] || fail "malformed review output was accepted"
[ "$(wc -l < "${LEDGER}" | tr -d ' ')" -eq 4 ] || fail "failed review-session calls emitted ledger entries"

echo "test-codex-review-session: ok"
