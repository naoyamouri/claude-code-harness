#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="${ROOT_DIR}/.github/workflows/sync-chachamaru-upstream.yml"

[ -f "${WORKFLOW}" ] || { echo "missing upstream sync workflow" >&2; exit 1; }

required_patterns=(
  "name: Sync Chachamaru upstream"
  "schedule:"
  "workflow_dispatch:"
  "contents: write"
  "pull-requests: write"
  "https://github.com/Chachamaru127/claude-code-harness.git"
  "git fetch --no-tags upstream main"
  "git merge-base --is-ancestor"
  "git merge --no-ff --no-edit"
  "gh pr create"
  "harness-review code --base origin/main --no-commit"
)

for pattern in "${required_patterns[@]}"; do
  grep -Fq "${pattern}" "${WORKFLOW}" || {
    echo "upstream sync workflow missing: ${pattern}" >&2
    exit 1
  }
done

echo "test-upstream-sync-workflow: ok"
