#!/usr/bin/env bash
# Record an APPROVE review for the current PR and require it before agent merge.

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/harness-pr-review-gate.sh record --base REF [--review-result FILE]
  scripts/harness-pr-review-gate.sh verify --base REF
  scripts/harness-pr-review-gate.sh merge --base REF [--dry-run]
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
DRY_RUN=0

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
    --dry-run)
      DRY_RUN=1
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

[ -n "$BASE_REF" ] || die "--base REF is required"
BASE_SHA="$(git rev-parse --verify "${BASE_REF}^{commit}" 2>/dev/null)" \
  || die "invalid base ref: $BASE_REF"
HEAD_SHA="$(git rev-parse --verify HEAD)" || die "HEAD is unavailable"
PR_REPO=""
PR_NUMBER=""
PR_HEAD=""

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
  pr_json="$(gh pr view "$branch" --repo "$PR_REPO" --json number,headRefOid 2>/dev/null)" \
    || die "no PR found for the current origin branch"
  PR_NUMBER="$(jq -er '.number | tonumber' <<<"$pr_json")" \
    || die "could not read PR number"
  PR_HEAD="$(jq -er '.headRefOid' <<<"$pr_json")" \
    || die "could not read PR head"
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

record() {
  [ -f "$REVIEW_RESULT" ] || die "review result not found: $REVIEW_RESULT"

  local schema_version verdict reviewed_base reviewed_head receipt receipt_dir temp
  schema_version="$(jq -er '.schema_version' "$REVIEW_RESULT" 2>/dev/null)" \
    || die "review result has no schema_version"
  [ "$schema_version" = "review-result.v1" ] \
    || die "review result must use review-result.v1 (got: $schema_version)"
  verdict="$(jq -er '.verdict' "$REVIEW_RESULT" 2>/dev/null)" \
    || die "review result has no verdict"
  [ "$verdict" = "APPROVE" ] || die "review verdict must be APPROVE (got: $verdict)"
  reviewed_base="$(jq -er '.base_ref' "$REVIEW_RESULT" 2>/dev/null)" \
    || die "review result has no base_ref"
  [ "$reviewed_base" = "$BASE_SHA" ] \
    || die "review result is for $reviewed_base, but requested base is $BASE_SHA"
  reviewed_head="$(jq -er '.commit_hash' "$REVIEW_RESULT" 2>/dev/null)" \
    || die "review result has no commit_hash"
  [ "$reviewed_head" = "$HEAD_SHA" ] \
    || die "review result is for $reviewed_head, but HEAD is $HEAD_SHA"

  load_pr_context
  receipt="$(receipt_path "$PR_NUMBER")"
  receipt_dir="$(dirname "$receipt")"
  mkdir -p "$receipt_dir"
  temp="${receipt}.tmp.$$"
  jq -n \
    --arg schema_version "pr-review-receipt.v1" \
    --argjson pr_number "$PR_NUMBER" \
    --arg base_ref "$BASE_SHA" \
    --arg head "$HEAD_SHA" \
    --arg verdict "$verdict" \
    --arg reviewed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{schema_version: $schema_version, pr_number: $pr_number, base_ref: $base_ref, head: $head, verdict: $verdict, reviewed_at: $reviewed_at}' \
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
    --arg head "$PR_HEAD" \
    '.schema_version == "pr-review-receipt.v1"
      and .pr_number == $pr_number
      and .base_ref == $base_ref
      and .head == $head
      and .verdict == "APPROVE"
      and (.reviewed_at | type == "string")' \
    "$receipt" >/dev/null \
    || die "receipt does not match current PR, base, or live HEAD"
}

case "$ACTION" in
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
    if [ "$DRY_RUN" -eq 1 ]; then
      echo "gh pr merge $PR_NUMBER --repo $PR_REPO --squash --match-head-commit $HEAD_SHA"
    else
      gh pr merge "$PR_NUMBER" --repo "$PR_REPO" --squash --match-head-commit "$HEAD_SHA"
    fi
    ;;
  *)
    die "unknown action: $ACTION"
    ;;
esac
