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
git -C "$REPO" remote add origin https://github.com/test-owner/test-repo.git
printf 'seed\n' > "$REPO/file.txt"
git -C "$REPO" add file.txt
git -C "$REPO" commit -q -m seed
BASE="$(git -C "$REPO" rev-parse HEAD)"
git -C "$REPO" checkout -qb feature/pr-review
printf 'change\n' >> "$REPO/file.txt"
git -C "$REPO" commit -qam change
HEAD_SHA="$(git -C "$REPO" rev-parse HEAD)"
PR_HEAD_SHA="$HEAD_SHA"
PR_BASE_SHA="$BASE"

cat > "$BIN/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
  [ "${NO_PR:-0}" = "1" ] && exit 1
  if [ "${REQUIRE_ORIGIN_REPO:-0}" = "1" ] && [[ "$*" != *"--repo test-owner/test-repo"* ]]; then
    exit 1
  fi
  printf '{"number":42,"headRefOid":"%s","baseRefOid":"%s"}\n' "$PR_HEAD_SHA" "$PR_BASE_SHA"
  exit 0
fi
if [ "$1" = "pr" ] && [ "$2" = "merge" ]; then
  if [ "${REQUIRE_ORIGIN_REPO:-0}" = "1" ] && [[ "$*" != *"--repo test-owner/test-repo"* ]]; then
    exit 1
  fi
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
  PATH="$BIN:$PATH" MERGE_LOG="$MERGE_LOG" PR_HEAD_SHA="$PR_HEAD_SHA" PR_BASE_SHA="$PR_BASE_SHA" bash "$GATE" "$@"
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
jq -e --arg base "$BASE" --arg pr_base "$PR_BASE_SHA" --arg head "$HEAD_SHA" '
  .schema_version == "pr-review-receipt.v1"
  and .base_ref == $base
  and .pr_base == $pr_base
  and .head == $head
  and .verdict == "APPROVE"
  and (.reviewed_at | type == "string")
' "$RECEIPT" >/dev/null || fail "receipt fields are incomplete"

(cd "$REPO" && run_gate verify --base "$BASE")

# upstream remote が gh の既定になっていても、origin のPRだけを操作する。
(cd "$REPO" && REQUIRE_ORIGIN_REPO=1 run_gate verify --base "$BASE")

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

# 別sessionのremote pushでは、local HEADが古くてもreceiptを無効にする。
PR_HEAD_SHA="unreviewed-remote-head"
: > "$MERGE_LOG"
set +e
(cd "$REPO" && run_gate merge --base "$BASE" --dry-run) >/dev/null 2>&1
remote_head_rc=$?
set -e
[ "$remote_head_rc" -ne 0 ] || fail "merge must reject an unreviewed remote PR head"
[ ! -s "$MERGE_LOG" ] || fail "remote head mismatch must not invoke gh pr merge"
PR_HEAD_SHA="$HEAD_SHA"

# base branch が進んだPRは、headが同じでも再レビュー前にmergeできない。
PR_BASE_SHA="unreviewed-remote-base"
: > "$MERGE_LOG"
set +e
(cd "$REPO" && run_gate merge --base "$BASE" --dry-run) >/dev/null 2>&1
remote_base_rc=$?
set -e
[ "$remote_base_rc" -ne 0 ] || fail "merge must reject an unreviewed remote PR base"
[ ! -s "$MERGE_LOG" ] || fail "remote base mismatch must not invoke gh pr merge"
PR_BASE_SHA="$BASE"

# mergeはoriginのapproved headに固定する。
dry_run="$(cd "$REPO" && REQUIRE_ORIGIN_REPO=1 run_gate merge --base "$BASE" --dry-run)"
expected_merge="gh pr merge 42 --repo test-owner/test-repo --squash --match-head-commit $HEAD_SHA"
[[ "$dry_run" == *"$expected_merge"* ]] || fail "dry-run must show the guarded merge command"
(cd "$REPO" && REQUIRE_ORIGIN_REPO=1 run_gate merge --base "$BASE")
grep -Fq -- "--repo test-owner/test-repo" "$MERGE_LOG" || fail "guarded merge must target origin"
grep -Fq -- "--match-head-commit $HEAD_SHA" "$MERGE_LOG" || fail "guarded merge must pin the approved head"

# pushでHEADが変われば以前のreceiptは無効。
printf 'next\n' >> "$REPO/file.txt"
git -C "$REPO" commit -qam next
set +e
(cd "$REPO" && run_gate verify --base "$BASE") >/dev/null 2>&1
stale_rc=$?
set -e
[ "$stale_rc" -ne 0 ] || fail "verify must reject a stale receipt after a new commit"

echo "test-pr-review-gate: ok"
