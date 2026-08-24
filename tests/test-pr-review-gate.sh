#!/usr/bin/env bash
# PR review receipt: current PR / base / HEAD / verdict must agree before merge.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="$ROOT_DIR/scripts/harness-pr-review-gate.sh"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/pr-review-gate-test.XXXXXX")"

cleanup() {
  [ -d "$TMP_DIR" ] && find "$TMP_DIR" -depth -delete
}
trap cleanup EXIT

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

REPO="$TMP_DIR/repo"
BIN="$TMP_DIR/bin"
MERGE_LOG="$TMP_DIR/merge.log"
mkdir -p "$REPO" "$BIN"

git -C "$REPO" init -q
git -C "$REPO" config user.email test@example.com
git -C "$REPO" config user.name Test
printf 'seed\n' > "$REPO/file.txt"
git -C "$REPO" add file.txt
git -C "$REPO" commit -q -m seed
BASE="$(git -C "$REPO" rev-parse HEAD)"
git -C "$REPO" checkout -qb feature/pr-review
printf 'change\n' >> "$REPO/file.txt"
git -C "$REPO" commit -qam change
HEAD_SHA="$(git -C "$REPO" rev-parse HEAD)"

cat > "$BIN/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
  [ "${NO_PR:-0}" = "1" ] && exit 1
  printf '{"number":42}\n'
  exit 0
fi
if [ "$1" = "pr" ] && [ "$2" = "merge" ]; then
  printf '%s\n' "$*" >> "$MERGE_LOG"
  exit 0
fi
echo "unexpected gh invocation: $*" >&2
exit 2
EOF
chmod +x "$BIN/gh"

REVIEW_INPUT="$REPO/review-output.json"
REVIEW_RESULT="$REPO/review-result.json"

write_result() {
  (cd "$REPO" && bash "$ROOT_DIR/scripts/write-review-result.sh" "$REVIEW_INPUT" "$HEAD_SHA" "$REVIEW_RESULT" --base-ref "$BASE")
}

run_gate() {
  PATH="$BIN:$PATH" MERGE_LOG="$MERGE_LOG" bash "$GATE" "$@"
}

[ -x "$GATE" ] || fail "missing executable gate: $GATE"

for workflow_file in \
  "$ROOT_DIR/skills/harness-work/references/sprint-contract.md" \
  "$ROOT_DIR/opencode/skills/harness-work/references/sprint-contract.md" \
  "$ROOT_DIR/skills-codex/harness-work/SKILL.md" \
  "$ROOT_DIR/codex/.codex/skills/harness-work/SKILL.md"; do
  grep -Fq 'harness-pr-review-gate.sh' "$workflow_file" \
    || fail "workflow does not route PR merge through the gate: $workflow_file"
done

for workflow_file in \
  "$ROOT_DIR/skills/harness-work/references/sprint-contract.md" \
  "$ROOT_DIR/opencode/skills/harness-work/references/sprint-contract.md" \
  "$ROOT_DIR/skills-codex/harness-work/SKILL.md" \
  "$ROOT_DIR/codex/.codex/skills/harness-work/SKILL.md"; do
  grep -Fq 'write-review-result.sh' "$workflow_file" \
    || fail "workflow does not normalize the PR review result: $workflow_file"
  grep -Fq -- '--base-ref "$BASE_REF"' "$workflow_file" \
    || fail "workflow does not bind the PR review to its base: $workflow_file"
done

# PRなしではreceiptを発行しない。
printf '{"verdict":"APPROVE"}\n' > "$REVIEW_INPUT"
write_result
set +e
(cd "$REPO" && NO_PR=1 run_gate record --base "$BASE" --review-result "$REVIEW_RESULT") >/dev/null 2>&1
no_pr_rc=$?
set -e
[ "$no_pr_rc" -ne 0 ] || fail "record must fail without a PR"

# REQUEST_CHANGESはreceiptにできない。
printf '{"verdict":"REQUEST_CHANGES"}\n' > "$REVIEW_INPUT"
write_result
set +e
(cd "$REPO" && run_gate record --base "$BASE" --review-result "$REVIEW_RESULT") >/dev/null 2>&1
request_changes_rc=$?
set -e
[ "$request_changes_rc" -ne 0 ] || fail "record must reject REQUEST_CHANGES"

# APPROVEのcurrent HEADだけをrecordし、必要な値を残す。
printf '{"verdict":"APPROVE"}\n' > "$REVIEW_INPUT"
write_result
(cd "$REPO" && run_gate record --base "$BASE" --review-result "$REVIEW_RESULT")
RECEIPT="$REPO/.git/harness/pr-review-receipts/42.json"
[ -f "$RECEIPT" ] || fail "record must write a PR receipt"
jq -e --arg base "$BASE" --arg head "$HEAD_SHA" '
  .schema_version == "pr-review-receipt.v1"
  and .base_ref == $base
  and .head == $head
  and .verdict == "APPROVE"
  and (.reviewed_at | type == "string")
' "$RECEIPT" >/dev/null || fail "receipt fields are incomplete"

(cd "$REPO" && run_gate verify --base "$BASE")

# review-result.v1 でない手製のAPPROVEはreceiptにできない。
printf '{"verdict":"APPROVE","commit_hash":"%s"}\n' "$HEAD_SHA" > "$REVIEW_RESULT"
set +e
(cd "$REPO" && run_gate record --base "$BASE" --review-result "$REVIEW_RESULT") >/dev/null 2>&1
handmade_rc=$?
set -e
[ "$handmade_rc" -ne 0 ] || fail "record must require a normalized review result"

# review対象baseが違えば、同じHEADでもreceiptにできない。
printf '{"verdict":"APPROVE"}\n' > "$REVIEW_INPUT"
write_result
jq '.base_ref = "wrong-base"' "$REVIEW_RESULT" > "$REVIEW_RESULT.tmp"
mv "$REVIEW_RESULT.tmp" "$REVIEW_RESULT"
set +e
(cd "$REPO" && run_gate record --base "$BASE" --review-result "$REVIEW_RESULT") >/dev/null 2>&1
wrong_base_rc=$?
set -e
[ "$wrong_base_rc" -ne 0 ] || fail "record must require a review of the requested base"

# receiptなしではmerge helperもfail closedにする。
rm "$RECEIPT"
set +e
(cd "$REPO" && run_gate merge --base "$BASE" --dry-run) >/dev/null 2>&1
missing_receipt_rc=$?
set -e
[ "$missing_receipt_rc" -ne 0 ] || fail "merge must fail without a receipt"
[ ! -s "$MERGE_LOG" ] || fail "missing receipt must not invoke gh pr merge"

# record後はmerge helperが検証済みPRだけを実行できる。
(printf '{"verdict":"APPROVE"}\n' > "$REVIEW_INPUT")
write_result
(cd "$REPO" && run_gate record --base "$BASE" --review-result "$REVIEW_RESULT")
(cd "$REPO" && run_gate merge --base "$BASE" --dry-run) | grep -Fq 'gh pr merge 42 --squash' \
  || fail "dry-run must show the guarded merge command"
(cd "$REPO" && run_gate merge --base "$BASE")
grep -Fq 'pr merge 42 --squash' "$MERGE_LOG" || fail "guarded merge must call gh pr merge --squash"

# pushでHEADが変われば以前のreceiptは無効。
printf 'next\n' >> "$REPO/file.txt"
git -C "$REPO" commit -qam next
set +e
(cd "$REPO" && run_gate verify --base "$BASE") >/dev/null 2>&1
stale_rc=$?
set -e
[ "$stale_rc" -ne 0 ] || fail "verify must reject a stale receipt after a new commit"

echo "test-pr-review-gate: ok"
