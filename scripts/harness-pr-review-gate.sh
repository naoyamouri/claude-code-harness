#!/usr/bin/env bash
# Record an APPROVE review for the current PR and require it before agent merge.

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/harness-pr-review-gate.sh context
  scripts/harness-pr-review-gate.sh record --base REF [--review-result FILE] [--review-report FILE]
  scripts/harness-pr-review-gate.sh verify --base REF
  scripts/harness-pr-review-gate.sh merge --base REF [--dry-run] [--user-merge-head SHA]
USAGE
}

die() {
  echo "pr-review-gate: $*" >&2
  exit 1
}

command -v jq >/dev/null 2>&1 || die "jq is required"

ACTION="${1:-}"
[ -n "$ACTION" ] || { usage >&2; exit 2; }
shift

BASE_REF=""
REVIEW_RESULT=".claude/state/review-result.json"
REVIEW_REPORT=".claude/state/pr-review-report.md"
DRY_RUN=0
USER_MERGE_HEAD=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --base)
      BASE_REF="${2:-}"
      shift 2
      ;;
    --base=*)
      BASE_REF="${1#*=}"
      shift
      ;;
    --review-result)
      REVIEW_RESULT="${2:-}"
      shift 2
      ;;
    --review-result=*)
      REVIEW_RESULT="${1#*=}"
      shift
      ;;
    --review-report)
      REVIEW_REPORT="${2:-}"
      shift 2
      ;;
    --review-report=*)
      REVIEW_REPORT="${1#*=}"
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --user-merge-head)
      USER_MERGE_HEAD="${2:-}"
      shift 2
      ;;
    --user-merge-head=*)
      USER_MERGE_HEAD="${1#*=}"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

HEAD_SHA="$(git rev-parse --verify HEAD)" || die "HEAD is unavailable"
BASE_SHA=""
if [ "$ACTION" != "context" ]; then
  [ -n "$BASE_REF" ] || die "--base REF is required"
  BASE_SHA="$(git rev-parse --verify "${BASE_REF}^{commit}" 2>/dev/null)" \
    || die "invalid base ref: $BASE_REF"
fi
PR_REPO=""
PR_NUMBER=""
PR_HEAD=""
PR_BASE=""
PR_BASE_REF=""
STRICT_BASE_PROTECTION=1
PR_IS_DRAFT=""
PR_MERGE_STATE=""
PR_MERGEABLE=""

origin_repo() {
  local url
  url="$(git remote get-url origin 2>/dev/null)" || return 1
  case "$url" in
    https://github.com/*|http://github.com/*)
      url="${url#*github.com/}"
      ;;
    git@github.com:*)
      url="${url#git@github.com:}"
      ;;
    ssh://git@github.com/*)
      url="${url#ssh://git@github.com/}"
      ;;
    *)
      return 1
      ;;
  esac
  printf '%s\n' "${url%.git}"
}

load_pr_context() {
  local branch pr_json
  branch="$(git branch --show-current)"
  [ -n "$branch" ] || die "current branch is unavailable"
  PR_REPO="$(origin_repo)" || die "origin must be a GitHub repository"
  pr_json="$(gh pr view "$branch" --repo "$PR_REPO" --json number,headRefOid,baseRefOid,baseRefName,isDraft,mergeStateStatus,mergeable 2>/dev/null)" \
    || die "no PR found for the current origin branch"
  PR_NUMBER="$(jq -er '.number | tonumber' <<<"$pr_json")" \
    || die "could not read PR number"
  PR_HEAD="$(jq -er '.headRefOid' <<<"$pr_json")" \
    || die "could not read PR head"
  PR_BASE="$(jq -er '.baseRefOid' <<<"$pr_json")" \
    || die "could not read PR base"
  PR_BASE_REF="$(jq -er '.baseRefName' <<<"$pr_json")" \
    || die "could not read PR base name"
  PR_IS_DRAFT="$(jq -r '.isDraft' <<<"$pr_json")" \
    || die "could not read PR draft state"
  [[ "$PR_IS_DRAFT" = "true" || "$PR_IS_DRAFT" = "false" ]] \
    || die "could not read PR draft state"
  PR_MERGE_STATE="$(jq -er '.mergeStateStatus' <<<"$pr_json")" \
    || die "could not read PR merge state"
  PR_MERGEABLE="$(jq -er '.mergeable' <<<"$pr_json")" \
    || die "could not read PR mergeability"
  [ "$PR_HEAD" = "$HEAD_SHA" ] \
    || die "live PR head is $PR_HEAD, but local HEAD is $HEAD_SHA"
}

receipt_path() {
  local common_dir
  common_dir="$(git rev-parse --git-common-dir)" || die "not a git worktree"
  if [[ "$common_dir" != /* ]]; then
    common_dir="$(cd "$common_dir" && pwd)"
  fi
  printf '%s/harness/pr-review-receipts/%s.json' "$common_dir" "$1"
}

sha256_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    die "shasum or sha256sum is required"
  fi
}

record() {
  [ -f "$REVIEW_RESULT" ] || die "review result not found: $REVIEW_RESULT"
  [ -f "$REVIEW_REPORT" ] || die "review report not found: $REVIEW_REPORT"

  local schema_version verdict reviewed_base reviewed_head reviewed_pr_base reviewed_pr_base_ref review_workflow review_mode review_report_sha256 receipt receipt_dir temp
  schema_version="$(jq -er '.schema_version' "$REVIEW_RESULT" 2>/dev/null)" \
    || die "review result has no schema_version"
  [ "$schema_version" = "review-result.v1" ] \
    || die "review result must use review-result.v1 (got: $schema_version)"
  verdict="$(jq -er '.verdict' "$REVIEW_RESULT" 2>/dev/null)" \
    || die "review result has no verdict"
  case "$verdict" in
    APPROVE|REQUEST_CHANGES) ;;
    *) die "review verdict must be APPROVE or REQUEST_CHANGES (got: $verdict)" ;;
  esac
  reviewed_base="$(jq -er '.base_ref' "$REVIEW_RESULT" 2>/dev/null)" \
    || die "review result has no base_ref"
  [ "$reviewed_base" = "$BASE_SHA" ] \
    || die "review result is for $reviewed_base, but requested base is $BASE_SHA"
  reviewed_head="$(jq -er '.commit_hash' "$REVIEW_RESULT" 2>/dev/null)" \
    || die "review result has no commit_hash"
  [ "$reviewed_head" = "$HEAD_SHA" ] \
    || die "review result is for $reviewed_head, but HEAD is $HEAD_SHA"
  reviewed_pr_base="$(jq -er '.pr_base' "$REVIEW_RESULT" 2>/dev/null)" \
    || die "review result has no pr_base"
  reviewed_pr_base_ref="$(jq -er '.pr_base_ref' "$REVIEW_RESULT" 2>/dev/null)" \
    || die "review result has no pr_base_ref"
  review_workflow="$(jq -er '.review_provenance.workflow' "$REVIEW_RESULT" 2>/dev/null)" \
    || die "review result has no review provenance"
  [ "$review_workflow" = "harness-review" ] \
    || die "review result was not produced by harness-review"
  review_mode="$(jq -er '.review_provenance.mode' "$REVIEW_RESULT" 2>/dev/null)" \
    || die "review result has no review mode"
  [ "$review_mode" = "code" ] \
    || die "review result was not produced by harness-review code"
  review_report_sha256="$(jq -er '.review_provenance.report_sha256' "$REVIEW_RESULT" 2>/dev/null)" \
    || die "review result has no review report digest"
  [[ "$review_report_sha256" =~ ^[0-9a-f]{64}$ ]] \
    || die "review result has an invalid review report digest"
  [ "$(sha256_file "$REVIEW_REPORT")" = "$review_report_sha256" ] \
    || die "review report does not match the normalized review result"

  load_pr_context
  [ "$reviewed_pr_base" = "$PR_BASE" ] \
    || die "review result is for PR base $reviewed_pr_base, but live PR base is $PR_BASE"
  [ "$reviewed_pr_base_ref" = "$PR_BASE_REF" ] \
    || die "review result is for PR base branch $reviewed_pr_base_ref, but live PR base branch is $PR_BASE_REF"
  receipt="$(receipt_path "$PR_NUMBER")"
  if [ "$verdict" = "REQUEST_CHANGES" ]; then
    rm -f "$receipt"
    echo "Invalidated APPROVE receipt for PR #$PR_NUMBER after REQUEST_CHANGES"
    return
  fi
  receipt_dir="$(dirname "$receipt")"
  mkdir -p "$receipt_dir"
  temp="${receipt}.tmp.$$"
  jq -n \
    --arg schema_version "pr-review-receipt.v1" \
    --argjson pr_number "$PR_NUMBER" \
    --arg base_ref "$BASE_SHA" \
    --arg pr_base "$PR_BASE" \
    --arg pr_base_ref "$PR_BASE_REF" \
    --arg head "$HEAD_SHA" \
    --arg verdict "$verdict" \
    --arg review_workflow "$review_workflow" \
    --arg review_mode "$review_mode" \
    --arg review_report_sha256 "$review_report_sha256" \
    --arg reviewed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{schema_version: $schema_version, pr_number: $pr_number, base_ref: $base_ref, pr_base: $pr_base, pr_base_ref: $pr_base_ref, head: $head, verdict: $verdict, review_workflow: $review_workflow, review_mode: $review_mode, review_report_sha256: $review_report_sha256, reviewed_at: $reviewed_at}' \
    > "$temp"
  mv "$temp" "$receipt"
  echo "Recorded APPROVE receipt for PR #$PR_NUMBER"
}

verify() {
  local receipt
  load_pr_context
  receipt="$(receipt_path "$PR_NUMBER")"
  [ -f "$receipt" ] || die "no APPROVE receipt for PR #$PR_NUMBER"
  jq -e \
    --argjson pr_number "$PR_NUMBER" \
    --arg base_ref "$BASE_SHA" \
    --arg pr_base "$PR_BASE" \
    --arg pr_base_ref "$PR_BASE_REF" \
    --arg head "$PR_HEAD" \
    '.schema_version == "pr-review-receipt.v1"
      and .pr_number == $pr_number
      and .base_ref == $base_ref
      and .pr_base == $pr_base
      and .pr_base_ref == $pr_base_ref
      and .head == $head
      and .verdict == "APPROVE"
      and .review_workflow == "harness-review"
      and .review_mode == "code"
      and (.review_report_sha256 | type == "string" and test("^[0-9a-f]{64}$"))
      and (.reviewed_at | type == "string")' \
    "$receipt" >/dev/null \
    || die "receipt does not match current PR, base, or live HEAD"
}

require_strict_base_protection() {
  local encoded_base_ref protection strict private
  encoded_base_ref="$(jq -rn --arg value "$PR_BASE_REF" '$value | @uri')" \
    || die "could not encode PR base branch"
  if ! protection="$(gh api "repos/$PR_REPO/branches/$encoded_base_ref/protection/required_status_checks" --include 2>&1)"; then
    if [[ "$protection" == *"403 Forbidden"* ]] \
      && [[ "$protection" == *"Upgrade to GitHub Pro or make this repository public"* ]]; then
      private="$(gh api "repos/$PR_REPO" --jq .private 2>/dev/null)" \
        || die "could not verify whether $PR_REPO is private"
      [ "$private" = "true" ] \
        || die "strict protection fallback is only available for private GitHub Free repositories"
      echo "pr-review-gate: GitHub Free private repository; strict base protection is unavailable, using reviewed base/head checks" >&2
      STRICT_BASE_PROTECTION=0
      return
    fi
    die "agent merge requires required status checks with 'Require branches to be up to date before merging' on $PR_BASE_REF"
  fi
  protection="$(sed -n '/^{/,$p' <<<"$protection")"
  strict="$(jq -er '.strict' <<<"$protection" 2>/dev/null)" \
    || die "could not read base branch protection for $PR_BASE_REF"
  [ "$strict" = "true" ] \
    || die "agent merge requires 'Require branches to be up to date before merging' on $PR_BASE_REF"
}

require_free_private_merge_conditions() {
  local checks
  [ "$USER_MERGE_HEAD" = "$HEAD_SHA" ] \
    || die "private GitHub Free merge requires an explicit user instruction for current HEAD: --user-merge-head $HEAD_SHA"
  [ "$PR_IS_DRAFT" = "false" ] \
    || die "private GitHub Free merge requires a non-draft PR"
  [ "$PR_MERGE_STATE" = "CLEAN" ] && [ "$PR_MERGEABLE" = "MERGEABLE" ] \
    || die "private GitHub Free merge requires a CLEAN, mergeable PR (got $PR_MERGE_STATE/$PR_MERGEABLE)"
  checks="$(gh pr checks "$PR_NUMBER" --repo "$PR_REPO" --json name,state,workflow 2>/dev/null)" \
    || die "private GitHub Free merge requires all CI checks to complete successfully"
  jq -e 'type == "array" and length > 0 and all(.[]; .state == "SUCCESS")' <<<"$checks" >/dev/null \
    || die "private GitHub Free merge requires every reported CI check to be SUCCESS"
}

verify_merge_submission() {
  local pr_json state merge_state merge_commit
  pr_json="$(gh pr view "$PR_NUMBER" --repo "$PR_REPO" --json state,mergeStateStatus,mergedAt,mergeCommit 2>/dev/null)" \
    || die "could not verify merged PR #$PR_NUMBER"
  state="$(jq -er '.state' <<<"$pr_json")" \
    || die "could not read PR state after merge"
  merge_state="$(jq -er '.mergeStateStatus' <<<"$pr_json")" \
    || die "could not read PR merge state after merge"
  if [ "$state" = "OPEN" ] && [ "$merge_state" = "QUEUED" ]; then
    echo "PR #$PR_NUMBER merge is queued"
    return
  fi
  merge_commit="$(jq -er '.mergeCommit.oid' <<<"$pr_json")" \
    || die "could not read merge commit after merge"
  [ "$state" = "MERGED" ] && [ -n "$merge_commit" ] \
    || die "PR #$PR_NUMBER was not merged"
}

case "$ACTION" in
  context)
    [ "$DRY_RUN" -eq 0 ] || die "--dry-run is only valid with merge"
    load_pr_context
    jq -n \
      --argjson pr_number "$PR_NUMBER" \
      --arg head "$PR_HEAD" \
      --arg base_ref "$PR_BASE_REF" \
      --arg base_oid "$PR_BASE" \
      '{pr_number: $pr_number, head: $head, base_ref: $base_ref, base_oid: $base_oid}'
    ;;
  record)
    [ "$DRY_RUN" -eq 0 ] || die "--dry-run is only valid with merge"
    record
    ;;
  verify)
    [ "$DRY_RUN" -eq 0 ] || die "--dry-run is only valid with merge"
    verify >/dev/null
    echo "PR review receipt is valid"
    ;;
  merge)
    verify
    require_strict_base_protection
    if [ "$STRICT_BASE_PROTECTION" = 0 ]; then
      verify
      require_free_private_merge_conditions
    fi
    if [ "$DRY_RUN" -eq 1 ]; then
      echo "gh pr merge $PR_NUMBER --repo $PR_REPO --squash --match-head-commit $HEAD_SHA"
    else
      gh pr merge "$PR_NUMBER" --repo "$PR_REPO" --squash --match-head-commit "$HEAD_SHA"
      verify_merge_submission
    fi
    ;;
  *)
    die "unknown action: $ACTION"
    ;;
esac
