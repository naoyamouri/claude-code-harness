#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="${ROOT_DIR}/scripts/harness-pr-post-create-review.sh"
grep -Fq '"additionalProperties": false' "$RUNNER" \
  || { echo "formal review schema must be strict" >&2; exit 1; }
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/pr-post-create-review.XXXXXX")"
trap 'find "$TMP_DIR" -depth -delete' EXIT

REMOTE="$TMP_DIR/origin.git"
REPO="$TMP_DIR/repo"
BIN="$TMP_DIR/bin"
mkdir -p "$BIN"
REAL_GIT_BIN="$(command -v git)"
git init -q --bare "$REMOTE"
git init -q "$REPO"
git -C "$REPO" config user.email test@example.com
git -C "$REPO" config user.name test
git -C "$REPO" checkout -qb main
printf 'base\n' >"$REPO/file.txt"
git -C "$REPO" add file.txt
git -C "$REPO" commit -qm seed
git -C "$REPO" remote add origin "$REMOTE"
git -C "$REPO" push -qu origin main
git -C "$REPO" checkout -qb feature/formal-review
printf 'change\n' >>"$REPO/file.txt"
git -C "$REPO" commit -qam change
git -C "$REPO" push -qu origin feature/formal-review

cat >"$BIN/gh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "pr" ] && [ "${2:-}" = "view" ]; then
  printf '{"number":42,"headRefOid":"%s","baseRefOid":"%s","baseRefName":"main","isDraft":false,"mergeStateStatus":"CLEAN","mergeable":"MERGEABLE"}\n' "$FAKE_HEAD" "$FAKE_BASE"
  exit 0
fi
if [ "${1:-}" = "pr" ] && [ "${2:-}" = "create" ]; then
  [ "${FAKE_GH_CREATE_FAIL:-0}" = "0" ] || exit 1
  printf '%s\n' 'https://github.com/example/repo/pull/42'
  exit 0
fi
echo "unexpected gh command: $*" >&2
exit 1
SH
cat >"$BIN/git" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = "remote" ] && [ "${2:-}" = "get-url" ] && [ "${3:-}" = "origin" ]; then
  printf '%s\n' 'https://github.com/example/repo.git'
  exit 0
fi
if [ "${1:-}" = "fetch" ] && [ "${FAKE_GIT_FETCH_FAIL:-0}" = "1" ]; then exit 1; fi
exec "$REAL_GIT" "$@"
SH
cat >"$BIN/codex" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[ "${1:-}" = "exec" ] || exit 2
[ -n "${FAKE_CODEX_LOG:-}" ] && printf 'review\n' >>"$FAKE_CODEX_LOG"
[ "${FAKE_CODEX_FAIL:-0}" = "0" ] || exit 1
out=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o|--output-last-message) out="$2"; shift 2 ;;
    *) shift ;;
  esac
done
printf '{"report_markdown":"# Formal review","review":{"verdict":"%s","critical_issues":[],"major_issues":[]}}\n' "${FAKE_REVIEW_VERDICT:-APPROVE}" >"$out"
SH
chmod +x "$BIN/gh" "$BIN/git" "$BIN/codex"

run_runner() {
  run_runner_at "$RUNNER"
}

run_runner_at() {
  local runner="$1"
  shift
  PATH="$BIN:$PATH" \
  REAL_GIT="$REAL_GIT_BIN" \
  FAKE_HEAD="$(git -C "$REPO" rev-parse HEAD)" \
  FAKE_BASE="$(git -C "$REPO" rev-parse origin/main)" \
  bash "$runner" "$@"
}

(cd "$REPO" && run_runner)
receipt="$REPO/.git/harness/pr-review-receipts/42.json"
[ -f "$receipt" ] || { echo "expected APPROVE receipt" >&2; exit 1; }
[ -s "$REPO/.claude/state/pr-review-report.md" ] || { echo "expected Markdown report" >&2; exit 1; }

failing_bin="$TMP_DIR/failing/bin"
mkdir -p "$failing_bin"
cp "$ROOT_DIR/scripts/harness-pr-post-create-review.sh" \
  "$ROOT_DIR/scripts/harness-pr-review-gate.sh" "$failing_bin/"
printf '#!/usr/bin/env bash\nexit 1\n' >"$failing_bin/write-review-result.sh"
chmod +x "$failing_bin"/*
set +e
(cd "$REPO" && run_runner_at "$failing_bin/harness-pr-post-create-review.sh") >/dev/null 2>&1
writer_failure_rc=$?
set -e
[ "$writer_failure_rc" -ne 0 ] || { echo "writer failure must fail closeout" >&2; exit 1; }
[ ! -f "$receipt" ] || { echo "writer failure must invalidate a prior receipt" >&2; exit 1; }

installed_bin="$TMP_DIR/installed/bin"
mkdir -p "$installed_bin"
cp "$ROOT_DIR/scripts/harness-pr-post-create-review.sh" \
  "$ROOT_DIR/scripts/harness-pr-review-gate.sh" \
  "$ROOT_DIR/scripts/write-review-result.sh" \
  "$ROOT_DIR/scripts/harness-pr-create-and-review.sh" "$installed_bin/"
chmod +x "$installed_bin"/*
rm -f "$receipt"
(cd "$REPO" && run_runner_at "$installed_bin/harness-pr-create-and-review.sh" --base main --head feature/formal-review --fill)
[ -f "$receipt" ] || { echo "installed helpers must resolve sibling binaries" >&2; exit 1; }

set +e
(cd "$REPO" && FAKE_GIT_FETCH_FAIL=1 run_runner) >/dev/null 2>&1
fetch_failure_rc=$?
set -e
[ "$fetch_failure_rc" -ne 0 ] || { echo "fetch failure must fail closeout" >&2; exit 1; }
[ ! -f "$receipt" ] || { echo "fetch failure must invalidate a prior receipt" >&2; exit 1; }

(cd "$REPO" && run_runner)
set +e
(cd "$REPO" && FAKE_REVIEW_VERDICT=REQUEST_CHANGES run_runner) >/dev/null 2>&1
request_changes_rc=$?
set -e
[ "$request_changes_rc" -ne 0 ] || { echo "REQUEST_CHANGES must fail closeout" >&2; exit 1; }
[ ! -f "$receipt" ] || { echo "REQUEST_CHANGES must not leave a receipt" >&2; exit 1; }

set +e
(cd "$REPO" && FAKE_CODEX_FAIL=1 run_runner) >/dev/null 2>&1
review_failure_rc=$?
set -e
[ "$review_failure_rc" -ne 0 ] || { echo "review failure must fail closeout" >&2; exit 1; }
[ ! -f "$receipt" ] || { echo "review failure must invalidate a receipt" >&2; exit 1; }

payload="$REPO/payload.json"
cat >"$payload" <<'JSON'
{"base_ref":"main","head_ref":"feature/formal-review","spec_path":"spec.md","lane":"gate","stage":"implementation","review_command":"codex review","focused_tests":[],"accepted_findings":[],"rejected_findings":[],"release_preflight_warnings":[],"residual_risk":"none","title":"test","body":"test"}
JSON
codex_log="$TMP_DIR/codex.log"
set +e
(cd "$REPO" && PATH="$BIN:$PATH" REAL_GIT="$REAL_GIT_BIN" FAKE_GH_CREATE_FAIL=1 FAKE_CODEX_LOG="$codex_log" bash "$ROOT_DIR/scripts/harness-pr-closeout.sh" push --payload "$payload" --yes) >/dev/null 2>&1
create_failure_rc=$?
set -e
[ "$create_failure_rc" -ne 0 ] || { echo "PR create failure must fail closeout" >&2; exit 1; }
[ ! -e "$codex_log" ] || { echo "PR create failure must not start review" >&2; exit 1; }

echo "PASS: post-create formal review"
