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
PR_VIEW_LOG="$TMP_DIR/pr-view.log"
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
PR_BASE_REF="main"

cat > "$BIN/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
  [ "${NO_PR:-0}" = "1" ] && exit 1
  [ -z "${PR_VIEW_LOG:-}" ] || printf '%s\n' "$*" >> "$PR_VIEW_LOG"
  if [ "${REQUIRE_ORIGIN_REPO:-0}" = "1" ] && [[ "$*" != *"--repo test-owner/test-repo"* ]]; then
    exit 1
  fi
  if [[ "$*" == *"state,mergeStateStatus,mergedAt,mergeCommit"* ]]; then
    if [ "${PR_MERGED:-true}" = "true" ]; then
      printf '{"state":"MERGED","mergeStateStatus":"CLEAN","mergedAt":"2026-01-01T00:00:00Z","mergeCommit":{"oid":"merged-sha"}}\n'
    elif [ "${PR_MERGE_QUEUED:-false}" = "true" ]; then
      printf '{"state":"OPEN","mergeStateStatus":"QUEUED","mergedAt":null,"mergeCommit":null}\n'
    else
      printf '{"state":"OPEN","mergeStateStatus":"CLEAN","mergedAt":null,"mergeCommit":null}\n'
    fi
    exit 0
  fi
  printf '{"number":42,"headRefOid":"%s","baseRefOid":"%s","baseRefName":"%s"}\n' "$PR_HEAD_SHA" "$PR_BASE_SHA" "$MOCK_PR_BASE_REF"
  exit 0
fi
if [ "$1" = "api" ]; then
  expected_endpoint="repos/test-owner/test-repo/branches/$MOCK_PR_BASE_REF/protection/required_status_checks"
  [[ "$*" == *"$expected_endpoint"* ]] || exit 1
  if [ "${PR_BASE_PROTECTION_AVAILABLE:-true}" != "true" ]; then
    echo 'HTTP/2.0 403 Forbidden' >&2
    echo '{"message":"Upgrade to GitHub Pro or make this repository public to enable this feature."}' >&2
    exit 1
  fi
  if [ "${PR_BASE_PROTECTION_STRICT:-true}" = "true" ]; then
    printf '{"strict":true}\n'
  else
    printf '{"strict":false}\n'
  fi
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
REVIEW_REPORT="$REPO/.claude/state/pr-review-report.md"
mkdir -p "$(dirname "$REVIEW_REPORT")"
printf '# PR review\n' > "$REVIEW_REPORT"

write_result() {
  (cd "$REPO" && bash "$ROOT_DIR/scripts/write-review-result.sh" "$REVIEW_INPUT" "$HEAD_SHA" "$REVIEW_RESULT" --base-ref "$BASE" --pr-base "$PR_BASE_SHA" --pr-base-ref "$PR_BASE_REF" --review-workflow harness-review --review-mode code --review-report "$REVIEW_REPORT")
}

write_unprovenanced_result() {
  (cd "$REPO" && bash "$ROOT_DIR/scripts/write-review-result.sh" "$REVIEW_INPUT" "$HEAD_SHA" "$REVIEW_RESULT" --base-ref "$BASE" --pr-base "$PR_BASE_SHA" --pr-base-ref "$PR_BASE_REF")
}

run_gate() {
  PATH="$BIN:$PATH" MERGE_LOG="$MERGE_LOG" PR_VIEW_LOG="$PR_VIEW_LOG" PR_HEAD_SHA="$PR_HEAD_SHA" PR_BASE_SHA="$PR_BASE_SHA" MOCK_PR_BASE_REF="$PR_BASE_REF" PR_BASE_PROTECTION_AVAILABLE="${PR_BASE_PROTECTION_AVAILABLE:-true}" PR_BASE_PROTECTION_STRICT="${PR_BASE_PROTECTION_STRICT:-true}" PR_MERGED="${PR_MERGED:-true}" PR_MERGE_QUEUED="${PR_MERGE_QUEUED:-false}" bash "$GATE" "$@"
}

[ -x "$GATE" ] || fail "missing executable gate: $GATE"

context="$(cd "$REPO" && run_gate context)"
jq -e --argjson pr_number 42 --arg head "$HEAD_SHA" --arg base_ref "$PR_BASE_REF" --arg base_oid "$PR_BASE_SHA" '
  .pr_number == $pr_number
  and .head == $head
  and .base_ref == $base_ref
  and .base_oid == $base_oid
' <<<"$context" >/dev/null || fail "context must expose the current origin PR base"

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
  grep -Fq 'PR_CONTEXT=' "$workflow_file" \
    || fail "workflow does not resolve the live PR base: $workflow_file"
  grep -Fq 'pr-review-report.md' "$workflow_file" \
    || fail "workflow does not preserve the human-readable PR review report: $workflow_file"
  grep -Fq -- '--report .claude/state/pr-review-report.md' "$workflow_file" \
    || fail "workflow does not direct the reviewer to write the human-readable report: $workflow_file"
  grep -Fq -- '--review-workflow harness-review --review-mode code' "$workflow_file" \
    || fail "workflow does not record harness-review provenance: $workflow_file"
  grep -Fq -- '--review-report .claude/state/pr-review-report.md' "$workflow_file" \
    || fail "workflow does not bind the receipt to the human-readable report: $workflow_file"
  grep -Fq -- '--pr-base "$PR_BASE" --pr-base-ref "$PR_BASE_REF"' "$workflow_file" \
    || fail "workflow does not record the live PR base in its review artifact: $workflow_file"
done

# PRなしではreceiptを発行しない。
printf '{"verdict":"APPROVE"}\n' > "$REVIEW_INPUT"
write_result
set +e
(cd "$REPO" && NO_PR=1 run_gate record --base "$BASE" --review-result "$REVIEW_RESULT") >/dev/null 2>&1
no_pr_rc=$?
set -e
[ "$no_pr_rc" -ne 0 ] || fail "record must fail without a PR"

# REQUEST_CHANGESはreceiptを発行せず、成功として既存receiptを無効化する。
printf '{"verdict":"REQUEST_CHANGES"}\n' > "$REVIEW_INPUT"
write_result
(cd "$REPO" && run_gate record --base "$BASE" --review-result "$REVIEW_RESULT")
[ ! -f "$REPO/.git/harness/pr-review-receipts/42.json" ] \
  || fail "REQUEST_CHANGES must not leave a receipt"

# workflow を指定しない generic reviewer 出力ではreceiptを発行しない。
printf '{"verdict":"APPROVE"}\n' > "$REVIEW_INPUT"
write_unprovenanced_result
set +e
(cd "$REPO" && run_gate record --base "$BASE" --review-result "$REVIEW_RESULT") >/dev/null 2>&1
unprovenanced_rc=$?
set -e
[ "$unprovenanced_rc" -ne 0 ] || fail "record must reject a review result without harness-review provenance"

# report と正規化時のdigestが一致しなければreceiptを発行しない。
write_result
printf 'tampered\n' >> "$REVIEW_REPORT"
set +e
(cd "$REPO" && run_gate record --base "$BASE" --review-result "$REVIEW_RESULT") >/dev/null 2>&1
tampered_report_rc=$?
set -e
[ "$tampered_report_rc" -ne 0 ] || fail "record must reject a changed review report"
printf '# PR review\n' > "$REVIEW_REPORT"

# APPROVEのcurrent HEADだけをrecordし、必要な値を残す。
printf '{"verdict":"APPROVE"}\n' > "$REVIEW_INPUT"
write_result
(cd "$REPO" && run_gate record --base "$BASE" --review-result "$REVIEW_RESULT")
RECEIPT="$REPO/.git/harness/pr-review-receipts/42.json"
[ -f "$RECEIPT" ] || fail "record must write a PR receipt"
jq -e --arg base "$BASE" --arg pr_base "$PR_BASE_SHA" --arg pr_base_ref "$PR_BASE_REF" --arg head "$HEAD_SHA" '
  .schema_version == "pr-review-receipt.v1"
  and .base_ref == $base
  and .pr_base == $pr_base
  and .pr_base_ref == $pr_base_ref
  and .head == $head
  and .verdict == "APPROVE"
  and .review_workflow == "harness-review"
  and .review_mode == "code"
  and (.review_report_sha256 | type == "string" and test("^[0-9a-f]{64}$"))
  and (.reviewed_at | type == "string")
' "$RECEIPT" >/dev/null || fail "receipt fields are incomplete"

(cd "$REPO" && run_gate verify --base "$BASE")

# 同一HEADの後続REQUEST_CHANGESは、古いAPPROVE receiptを無効化する。
printf '{"verdict":"REQUEST_CHANGES"}\n' > "$REVIEW_INPUT"
write_result
(cd "$REPO" && run_gate record --base "$BASE" --review-result "$REVIEW_RESULT")
[ ! -f "$RECEIPT" ] || fail "REQUEST_CHANGES must invalidate an existing APPROVE receipt"
set +e
(cd "$REPO" && run_gate verify --base "$BASE") >/dev/null 2>&1
invalidated_rc=$?
set -e
[ "$invalidated_rc" -ne 0 ] || fail "verify must reject an invalidated receipt"

# 後続のAPPROVEでのみreceiptを再発行できる。
printf '{"verdict":"APPROVE"}\n' > "$REVIEW_INPUT"
write_result
(cd "$REPO" && run_gate record --base "$BASE" --review-result "$REVIEW_RESULT")

# upstream remote が gh の既定になっていても、origin のPRだけを操作する。
(cd "$REPO" && REQUIRE_ORIGIN_REPO=1 run_gate verify --base "$BASE")

# review artifactに記録したPR baseとlive PR baseが違えばreceiptを発行しない。
printf '{"verdict":"APPROVE"}\n' > "$REVIEW_INPUT"
write_result
jq '.pr_base = "unreviewed-artifact-base"' "$REVIEW_RESULT" > "$REVIEW_RESULT.tmp"
mv "$REVIEW_RESULT.tmp" "$REVIEW_RESULT"
set +e
(cd "$REPO" && run_gate record --base "$BASE" --review-result "$REVIEW_RESULT") >/dev/null 2>&1
artifact_base_rc=$?
set -e
[ "$artifact_base_rc" -ne 0 ] || fail "record must reject an unreviewed review artifact base"

# base branchのretargetは同じSHAでもreceiptを無効にする。
PR_BASE_REF="release/v2"
set +e
(cd "$REPO" && run_gate verify --base "$BASE") >/dev/null 2>&1
retarget_rc=$?
set -e
[ "$retarget_rc" -ne 0 ] || fail "verify must reject a retargeted PR base branch"
PR_BASE_REF="main"

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

# private Free の既知403では、live PRを直前照合した縮退経路でmergeする。
PR_BASE_PROTECTION_AVAILABLE=false
: > "$MERGE_LOG"
: > "$PR_VIEW_LOG"
free_private_dry_run="$(cd "$REPO" && run_gate merge --base "$BASE" --dry-run)"
[[ "$free_private_dry_run" == *"--match-head-commit $HEAD_SHA"* ]] \
  || fail "Free private fallback must retain the reviewed head pin"
[ "$(wc -l < "$PR_VIEW_LOG" | tr -d ' ')" = 2 ] \
  || fail "Free private fallback must revalidate the live PR immediately before merge"
PR_BASE_PROTECTION_AVAILABLE=true

PR_BASE_PROTECTION_STRICT=false
: > "$MERGE_LOG"
set +e
(cd "$REPO" && run_gate merge --base "$BASE" --dry-run) >/dev/null 2>&1
unprotected_merge_rc=$?
set -e
[ "$unprotected_merge_rc" -ne 0 ] || fail "merge must require strict base protection"
[ ! -s "$MERGE_LOG" ] || fail "unprotected base must not invoke gh pr merge"
PR_BASE_PROTECTION_STRICT=true

# mergeはoriginのapproved headに固定する。
dry_run="$(cd "$REPO" && REQUIRE_ORIGIN_REPO=1 run_gate merge --base "$BASE" --dry-run)"
expected_merge="gh pr merge 42 --repo test-owner/test-repo --squash --match-head-commit $HEAD_SHA"
[[ "$dry_run" == *"$expected_merge"* ]] || fail "dry-run must show the guarded merge command"
(cd "$REPO" && REQUIRE_ORIGIN_REPO=1 run_gate merge --base "$BASE")
grep -Fq -- "--repo test-owner/test-repo" "$MERGE_LOG" || fail "guarded merge must target origin"
grep -Fq -- "--match-head-commit $HEAD_SHA" "$MERGE_LOG" || fail "guarded merge must pin the approved head"

# mergeが実際に完了していないなら成功扱いにしない。
PR_MERGED=false
: > "$MERGE_LOG"
set +e
(cd "$REPO" && run_gate merge --base "$BASE") >/dev/null 2>&1
unmerged_rc=$?
set -e
[ "$unmerged_rc" -ne 0 ] || fail "merge must verify that GitHub reports MERGED"
grep -Fq -- "--match-head-commit $HEAD_SHA" "$MERGE_LOG" || fail "failed post-merge verification must follow a head-pinned merge"
PR_MERGED=true

# merge queue に受理された状態は失敗ではなく、queue中であることを明示する。
PR_MERGED=false
PR_MERGE_QUEUED=true
queued_output="$(cd "$REPO" && run_gate merge --base "$BASE")"
[[ "$queued_output" == *"merge is queued"* ]] \
  || fail "merge queue submission must be reported as queued"
PR_MERGED=true
PR_MERGE_QUEUED=false

# pushでHEADが変われば以前のreceiptは無効。
printf 'next\n' >> "$REPO/file.txt"
git -C "$REPO" commit -qam next
set +e
(cd "$REPO" && run_gate verify --base "$BASE") >/dev/null 2>&1
stale_rc=$?
set -e
[ "$stale_rc" -ne 0 ] || fail "verify must reject a stale receipt after a new commit"

echo "test-pr-review-gate: ok"
