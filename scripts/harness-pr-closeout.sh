#!/bin/bash
# harness-pr-closeout.sh
# Build PR title/body from an evidence pack. Default path is dry-run preview only.
#
# Subcommands:
#   build   --base REF --head REF --evidence evidence.json --out pr-payload.json
#   dry-run --payload pr-payload.json
#   push    --payload pr-payload.json [--yes]
#   ready   --pr N [--timeout SEC]

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 2
fi

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/harness-pr-closeout.sh build --base REF --head REF --evidence FILE --out FILE
  bash scripts/harness-pr-closeout.sh dry-run --payload FILE
  bash scripts/harness-pr-closeout.sh push --payload FILE [--yes]
  bash scripts/harness-pr-closeout.sh ready --pr N [--timeout SEC]

Notes:
  - build writes pr-payload.json from an evidence pack (no git/gh side effects)
  - dry-run previews payload on stdout (no git/gh side effects)
  - push calls gh pr create --draft only after confirmation or --yes
  - ready marks a draft PR ready and waits until workflows that re-run on
    ready_for_review complete a new run for the head SHA (exit 1 on timeout
    or when a workflow file cannot be read; the PR then stays draft)
USAGE
}

json_get() {
  local file="$1"
  local filter="$2"
  jq -r "$filter" "$file"
}

truncate_title() {
  local title="$1"
  local max_len=70
  if [ "${#title}" -le "${max_len}" ]; then
    printf '%s' "$title"
    return
  fi
  printf '%s' "${title:0:$((max_len - 1))}…"
}

render_finding_lines() {
  local file="$1"
  local key="$2"
  local heading="$3"
  local count
  count="$(jq --arg key "$key" '(.[$key] // []) | length' "$file")"
  printf '## %s\n\n' "$heading"
  if [ "$count" -eq 0 ]; then
    printf '_None_\n\n'
    return
  fi
  jq -r --arg key "$key" '
    (.[$key] // [])[]
    | "- **\(.id // "finding")** (\(.severity // "unknown")): \(.summary // .issue // .message // "no summary")"
      + (if .reason then " — rejected because: \(.reason)" else "" end)
  ' "$file"
  printf '\n\n'
}

build_body() {
  local merged_file="$1"
  local body=""

  body+="## Summary\n\n"
  body+="Evidence-pack PR closeout for \`$(json_get "$merged_file" '.spec_path')\` (\`$(json_get "$merged_file" '.lane')\` / \`$(json_get "$merged_file" '.stage')\`).\n\n"

  body+="## Context\n\n"
  body+="- base_ref: \`$(json_get "$merged_file" '.base_ref')\`\n"
  body+="- head_ref: \`$(json_get "$merged_file" '.head_ref')\`\n"
  body+="- spec_path: \`$(json_get "$merged_file" '.spec_path')\`\n"
  body+="- lane: \`$(json_get "$merged_file" '.lane')\`\n"
  body+="- stage: \`$(json_get "$merged_file" '.stage')\`\n\n"

  body+="## Review command\n\n"
  body+="\`\`\`bash\n$(json_get "$merged_file" '.review_command')\n\`\`\`\n\n"

  body+="## Focused tests\n\n"
  local tests
  tests="$(jq -r '(.focused_tests // [])[] | "- `\(.)`"' "$merged_file")"
  if [ -z "$tests" ]; then
    body+="_None_\n\n"
  else
    body+="${tests}\n\n"
  fi

  body+="$(render_finding_lines "$merged_file" 'accepted_findings' 'Accepted findings')"
  body+="$(render_finding_lines "$merged_file" 'rejected_findings' 'Rejected findings')"

  body+="## Release preflight warnings\n\n"
  local warnings
  warnings="$(jq -r '(.release_preflight_warnings // [])[] | "- \(.)"' "$merged_file")"
  if [ -z "$warnings" ]; then
    body+="_None_\n\n"
  else
    body+="${warnings}\n\n"
  fi

  body+="## Residual risk\n\n"
  body+="$(json_get "$merged_file" '.residual_risk')\n"

  printf '%b' "$body"
}

validate_required_fields() {
  local file="$1"

  local required=(
    base_ref head_ref spec_path lane stage review_command
    focused_tests accepted_findings rejected_findings
    release_preflight_warnings residual_risk
  )
  local field
  for field in "${required[@]}"; do
    if ! jq -e --arg f "$field" 'has($f)' "$file" >/dev/null; then
      echo "missing required field: $field" >&2
      exit 2
    fi
  done
}

cmd_build() {
  local base_ref=""
  local head_ref=""
  local evidence_file=""
  local out_file=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --base)
        base_ref="${2:-}"
        shift 2
        ;;
      --base=*)
        base_ref="${1#*=}"
        shift
        ;;
      --head)
        head_ref="${2:-}"
        shift 2
        ;;
      --head=*)
        head_ref="${1#*=}"
        shift
        ;;
      --evidence)
        evidence_file="${2:-}"
        shift 2
        ;;
      --evidence=*)
        evidence_file="${1#*=}"
        shift
        ;;
      --out)
        out_file="${2:-}"
        shift 2
        ;;
      --out=*)
        out_file="${1#*=}"
        shift
        ;;
      *)
        echo "unknown build option: $1" >&2
        usage >&2
        exit 2
        ;;
    esac
  done

  if [ -z "$base_ref" ] || [ -z "$head_ref" ] || [ -z "$evidence_file" ] || [ -z "$out_file" ]; then
    echo "build requires --base, --head, --evidence, and --out" >&2
    exit 2
  fi
  if [ ! -f "$evidence_file" ]; then
    echo "evidence file not found: $evidence_file" >&2
    exit 2
  fi

  local merged_file
  merged_file="$(mktemp)"
  trap 'rm -f "$merged_file"' RETURN

  jq -s --arg base_ref "$base_ref" --arg head_ref "$head_ref" '
    .[0]
    | .base_ref = $base_ref
    | .head_ref = $head_ref
    | .focused_tests = (.focused_tests // [])
    | .accepted_findings = (.accepted_findings // [])
    | .rejected_findings = (.rejected_findings // [])
    | .release_preflight_warnings = (.release_preflight_warnings // [])
  ' "$evidence_file" >"$merged_file"

  validate_required_fields "$merged_file"

  local raw_title
  raw_title="[$(json_get "$merged_file" '.lane')/$(json_get "$merged_file" '.stage')] $(json_get "$merged_file" '.spec_path') — evidence-pack closeout"
  local title
  title="$(truncate_title "$raw_title")"
  local body
  body="$(build_body "$merged_file")"

  jq -n \
    --slurpfile src "$merged_file" \
    --arg title "$title" \
    --arg body "$body" \
    '
      $src[0]
      | .schema_version = "pr-payload.v1"
      | .title = $title
      | .body = $body
    ' >"$out_file"
}

cmd_dry_run() {
  local payload_file=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --payload)
        payload_file="${2:-}"
        shift 2
        ;;
      --payload=*)
        payload_file="${1#*=}"
        shift
        ;;
      *)
        echo "unknown dry-run option: $1" >&2
        usage >&2
        exit 2
        ;;
    esac
  done

  if [ -z "$payload_file" ] || [ ! -f "$payload_file" ]; then
    echo "dry-run requires --payload FILE" >&2
    exit 2
  fi

  validate_required_fields "$payload_file"

  echo "PR closeout preview (dry-run)"
  echo "title: $(json_get "$payload_file" '.title')"
  echo "base: $(json_get "$payload_file" '.base_ref')"
  echo "head: $(json_get "$payload_file" '.head_ref')"
  echo "lane: $(json_get "$payload_file" '.lane')"
  echo "stage: $(json_get "$payload_file" '.stage')"
  echo "spec_path: $(json_get "$payload_file" '.spec_path')"
  echo "--- body ---"
  json_get "$payload_file" '.body'
  echo "--- end body ---"
  echo "note: no git push or gh pr create executed"
}

ensure_attached_head() {
  if ! git symbolic-ref -q HEAD >/dev/null 2>&1; then
    echo "detached HEAD: create or checkout a branch before PR closeout push" >&2
    exit 1
  fi
}

confirm_push() {
  if [ "${YES:-0}" -eq 1 ]; then
    return 0
  fi
  if [ ! -t 0 ]; then
    echo "confirmation required: re-run with --yes or attach a TTY" >&2
    exit 1
  fi
  printf 'Create PR with gh? [y/N] ' >&2
  local answer
  read -r answer
  case "$answer" in
    y|Y|yes|YES) ;;
    *)
      echo "aborted" >&2
      exit 1
      ;;
  esac
}

cmd_push() {
  local payload_file=""
  YES=0

  while [ $# -gt 0 ]; do
    case "$1" in
      --payload)
        payload_file="${2:-}"
        shift 2
        ;;
      --payload=*)
        payload_file="${1#*=}"
        shift
        ;;
      --yes)
        YES=1
        shift
        ;;
      *)
        echo "unknown push option: $1" >&2
        usage >&2
        exit 2
        ;;
    esac
  done

  if [ -z "$payload_file" ] || [ ! -f "$payload_file" ]; then
    echo "push requires --payload FILE" >&2
    exit 2
  fi

  validate_required_fields "$payload_file"
  ensure_attached_head
  confirm_push

  if ! command -v gh >/dev/null 2>&1; then
    echo "gh CLI is required for push" >&2
    exit 2
  fi

  local title base_ref head_ref body
  title="$(json_get "$payload_file" '.title')"
  base_ref="$(json_get "$payload_file" '.base_ref')"
  head_ref="$(json_get "$payload_file" '.head_ref')"
  body="$(json_get "$payload_file" '.body')"

  # draft で作る。CI が draft 中は軽い検証だけを回し、merge 直前の `ready` で full を1回通す。
  gh pr create \
    --draft \
    --base "$base_ref" \
    --head "$head_ref" \
    --title "$title" \
    --body "$body"
}

# ready 化後、head SHA の draft 時代の run（緑でも focused のみ）を full gate と数えないよう、
# ready_for_review で再起動する workflow の新しい run が完了するまで待つ。登録だけでは
# job の check がまだ無く、`gh pr checks` に古い SUCCESS だけが見える瞬間がある。
cmd_ready() {
  local pr="" timeout=1800
  while [ $# -gt 0 ]; do
    case "$1" in
      --pr) pr="${2:-}"; shift 2 ;;
      --timeout) timeout="${2:-}"; shift 2 ;;
      *) echo "unknown ready option: $1" >&2; usage >&2; exit 2 ;;
    esac
  done
  [ -n "$pr" ] || { echo "ready requires --pr N" >&2; exit 2; }
  [[ "$timeout" =~ ^[0-9]+$ ]] || { echo "ready --timeout must be whole seconds: $timeout" >&2; exit 2; }
  command -v gh >/dev/null 2>&1 || { echo "gh CLI is required for ready" >&2; exit 2; }

  local view is_draft sha
  view="$(gh pr view "$pr" --json isDraft,headRefOid)"
  is_draft="$(jq -r '.isDraft' <<<"$view")"
  sha="$(jq -r '.headRefOid' <<<"$view")"
  if [ "$is_draft" != "true" ]; then
    echo "PR #$pr is already ready for review"
    return 0
  fi

  local runs_url="repos/{owner}/{repo}/actions/runs?head_sha=${sha}&event=pull_request&per_page=100"
  local before expected="" path workflow
  before="$(gh api "$runs_url" | jq -c '[.workflow_runs[] | {id, path}]')" \
    || { echo "could not list runs for $sha; PR #$pr left as draft" >&2; exit 1; }
  # 判定できない workflow を「再起動しない」と扱うと draft 時代の緑で merge されるため、
  # 取得失敗は ready 化の前に止める（PR は draft のままなので再実行できる）。
  # ponytail: ready_for_review を文字列で探す。コメント内の一致は待ち過ぎて timeout で止まる側に倒れる。
  for path in $(jq -r '[.[].path] | unique[]' <<<"$before"); do
    workflow="$(gh api -H 'Accept: application/vnd.github.raw' "repos/{owner}/{repo}/contents/${path}?ref=${sha}")" \
      || { echo "could not read $path at $sha; PR #$pr left as draft" >&2; exit 1; }
    if [[ "$workflow" == *ready_for_review* ]]; then
      expected="$expected $path"
    fi
  done

  gh pr ready "$pr"
  if [ -z "$expected" ]; then
    echo "PR #$pr is ready; no workflow re-runs on ready_for_review"
    return 0
  fi

  local interval="${HARNESS_READY_POLL_INTERVAL:-5}" start now pending
  start="$(date +%s)"
  while :; do
    pending=""
    for path in $expected; do
      if ! gh api "$runs_url" | jq -e --argjson before "$before" --arg path "$path" \
        '[.workflow_runs[] | select(.path == $path and .status == "completed") | .id] - [$before[].id] | length > 0' >/dev/null; then
        pending="$pending $path"
      fi
    done
    if [ -z "$pending" ]; then
      echo "PR #$pr is ready; ready_for_review runs completed for:$expected"
      return 0
    fi
    now="$(date +%s)"
    if [ $((now - start)) -ge "$timeout" ]; then
      echo "PR #$pr is ready but ready_for_review runs did not complete within ${timeout}s for:$pending" >&2
      exit 1
    fi
    sleep "$interval"
  done
}

SUBCOMMAND="${1:-}"
shift || true

case "$SUBCOMMAND" in
  build)
    cmd_build "$@"
    ;;
  dry-run)
    cmd_dry_run "$@"
    ;;
  push)
    cmd_push "$@"
    ;;
  ready)
    cmd_ready "$@"
    ;;
  -h|--help|"")
    usage
    [ -z "$SUBCOMMAND" ] && exit 2
    ;;
  *)
    echo "unknown subcommand: $SUBCOMMAND" >&2
    usage >&2
    exit 2
    ;;
esac
