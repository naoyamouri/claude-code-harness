#!/usr/bin/env bash
# Persistent, read-only Codex review session used by the Harness repair loop.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_SCRIPT="${SCRIPT_DIR}/repair-loop-state.sh"
MODEL_ROUTER="${SCRIPT_DIR}/model-routing.sh"

usage() {
  echo "Usage: codex-review-session.sh --project-root DIR --task-id ID --target-fingerprint HASH --base-ref REF --output FILE --prompt TEXT" >&2
}

PROJECT_ROOT=""
TASK_ID=""
TARGET_FINGERPRINT=""
BASE_REF=""
OUTPUT=""
PROMPT=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --project-root) PROJECT_ROOT="${2:-}"; shift 2 ;;
    --task-id) TASK_ID="${2:-}"; shift 2 ;;
    --target-fingerprint) TARGET_FINGERPRINT="${2:-}"; shift 2 ;;
    --base-ref) BASE_REF="${2:-}"; shift 2 ;;
    --output) OUTPUT="${2:-}"; shift 2 ;;
    --prompt) PROMPT="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

for value in PROJECT_ROOT TASK_ID TARGET_FINGERPRINT BASE_REF OUTPUT PROMPT; do
  [ -n "${!value}" ] || { echo "Missing --$(printf '%s' "${value}" | tr '[:upper:]_' '[:lower:]-')" >&2; usage; exit 2; }
done
command -v codex >/dev/null 2>&1 || { echo "codex-review-session: codex is required" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "codex-review-session: jq is required" >&2; exit 2; }
[ -d "${PROJECT_ROOT}" ] || { echo "codex-review-session: project root not found: ${PROJECT_ROOT}" >&2; exit 1; }
[[ "${TASK_ID}" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || { echo "codex-review-session: invalid task id: ${TASK_ID}" >&2; exit 2; }
git -C "${PROJECT_ROOT}" rev-parse --verify "${BASE_REF}^{commit}" >/dev/null 2>&1 || { echo "codex-review-session: invalid base ref: ${BASE_REF}" >&2; exit 2; }

STATE_PATH="${PROJECT_ROOT}/.claude/state/repair-loop/${TASK_ID}.json"
if [ ! -f "${STATE_PATH}" ]; then
  bash "${STATE_SCRIPT}" init "${PROJECT_ROOT}" "${TASK_ID}" "${MAX_REVIEWS:-3}" >/dev/null
fi

MODEL_ARGS=()
if [ "${HARNESS_DISABLE_MODEL_ROUTING:-0}" != 1 ]; then
  REVIEW_MODEL="$(bash "${MODEL_ROUTER}" --host codex --role reviewer --field model)"
  REVIEW_EFFORT="$(bash "${MODEL_ROUTER}" --host codex --role reviewer --field effort)"
  MODEL_ARGS=(-m "${REVIEW_MODEL}" -c "model_reasoning_effort=\"${REVIEW_EFFORT}\"")
fi

run_start() {
  local log_file="$1"
  (cd "${PROJECT_ROOT}" && codex exec --sandbox read-only review --base "${BASE_REF}" "${MODEL_ARGS[@]}" --json -o "${OUTPUT}" "${PROMPT}") > "${log_file}"
}

run_resume() {
  local handle="$1"
  local log_file="$2"
  (cd "${PROJECT_ROOT}" && codex exec resume -c 'sandbox_mode="read-only"' "${MODEL_ARGS[@]}" --json -o "${OUTPUT}" "${handle}" "${PROMPT}") > "${log_file}"
}

extract_handle() {
  jq -r 'select(.type == "thread.started") | .thread_id // .threadId // empty' "$1" | tail -1
}

CURRENT_HANDLE="$(jq -r '.reviewer.handle // empty' "${STATE_PATH}")"
CURRENT_FINGERPRINT="$(jq -r '.reviewer.target_fingerprint // empty' "${STATE_PATH}")"
LOG_FILE="$(mktemp)"
trap 'rm -f "${LOG_FILE}"' EXIT
FRESH_REASON=""

if [ -n "${CURRENT_HANDLE}" ] && [ "${CURRENT_FINGERPRINT}" = "${TARGET_FINGERPRINT}" ]; then
  if run_resume "${CURRENT_HANDLE}" "${LOG_FILE}"; then
    printf '%s\n' "${CURRENT_HANDLE}"
    exit 0
  fi
  FRESH_REASON="reviewer-unavailable"
elif [ -n "${CURRENT_HANDLE}" ]; then
  FRESH_REASON="material-target-change"
else
  FRESH_REASON="initial"
fi

: > "${LOG_FILE}"
run_start "${LOG_FILE}"
NEW_HANDLE="$(extract_handle "${LOG_FILE}")"
[ -n "${NEW_HANDLE}" ] || { echo "codex-review-session: review did not report a thread id" >&2; exit 1; }
bash "${STATE_SCRIPT}" reviewer-bind "${PROJECT_ROOT}" "${TASK_ID}" codex-exec "${NEW_HANDLE}" "${TARGET_FINGERPRINT}" "${FRESH_REASON}" >/dev/null
printf '%s\n' "${NEW_HANDLE}"
