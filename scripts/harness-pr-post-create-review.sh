#!/usr/bin/env bash
# Run the formal Codex review and record its receipt for the current PR.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
helper_path() {
  local name="$1"
  if [ -x "${ROOT_DIR}/scripts/${name}" ]; then
    printf '%s\n' "${ROOT_DIR}/scripts/${name}"
  else
    printf '%s\n' "${SCRIPT_DIR}/${name}"
  fi
}
GATE="$(helper_path harness-pr-review-gate.sh)"
WRITER="$(helper_path write-review-result.sh)"
STATE_DIR=".claude/state"
REPORT="${STATE_DIR}/pr-review-report.md"
OUTPUT="${STATE_DIR}/pr-review-output.json"
RESULT="${STATE_DIR}/review-result.json"

die() { echo "pr-post-create-review: $*" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || die "jq is required"
command -v codex >/dev/null 2>&1 || die "codex is required"

context="$($GATE context)"
base_ref="$(jq -er '.base_ref' <<<"$context")"
pr_base="$(jq -er '.base_oid' <<<"$context")"
"$GATE" invalidate >/dev/null
git fetch origin "$base_ref" >/dev/null
base="$(git merge-base "origin/$base_ref" HEAD)"
mkdir -p "$STATE_DIR"

schema="$(mktemp "${TMPDIR:-/tmp}/harness-pr-review-schema.XXXXXX")"
raw="$(mktemp "${TMPDIR:-/tmp}/harness-pr-review-output.XXXXXX")"
trap 'rm -f "$schema" "$raw"' EXIT
cat >"$schema" <<'JSON'
{
  "type": "object",
  "additionalProperties": false,
  "required": ["report_markdown", "review"],
  "properties": {
    "report_markdown": {"type": "string", "minLength": 1},
    "review": {
      "type": "object",
      "additionalProperties": false,
      "required": ["verdict"],
      "properties": {"verdict": {"enum": ["APPROVE", "REQUEST_CHANGES"]}}
    }
  }
}
JSON

prompt="Execute the Harness formal code-review workflow for the current PR diff ${base}..HEAD. Read the relevant spec and Plans task contract, inspect the diff, and assess security, regression safety, tests, and TDD evidence. Return report_markdown with the complete human report and review with verdict APPROVE only when no critical/major issue remains; otherwise REQUEST_CHANGES."
if ! codex exec --ephemeral --sandbox read-only --output-schema "$schema" -o "$raw" "$prompt" >/dev/null; then
  die "Codex formal review failed; receipt was invalidated"
fi
if ! jq -e '.report_markdown | type == "string" and length > 0' "$raw" >/dev/null \
  || ! jq -e '.review | type == "object" and (.verdict == "APPROVE" or .verdict == "REQUEST_CHANGES")' "$raw" >/dev/null; then
  die "Codex review output did not satisfy the formal review contract; receipt was invalidated"
fi

jq -r '.report_markdown' "$raw" >"$REPORT"
jq '.review' "$raw" >"$OUTPUT"
"$WRITER" "$OUTPUT" "$(git rev-parse HEAD)" "$RESULT" \
  --base-ref "$base" --pr-base "$pr_base" --pr-base-ref "$base_ref" \
  --review-workflow harness-review --review-mode code --review-report "$REPORT"
"$GATE" record --base "$base"

verdict="$(jq -er '.verdict' "$RESULT")"
if [ "$verdict" != "APPROVE" ]; then
  die "formal review returned $verdict; no APPROVE receipt was recorded"
fi
printf 'Formal review approved and receipt recorded for the current PR\n'
