#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="${ROOT_DIR}/.github/workflows/sync-chachamaru-upstream.yml"
VALIDATE_WORKFLOW="${ROOT_DIR}/.github/workflows/validate-plugin.yml"

[ -f "${WORKFLOW}" ] || { echo "missing upstream sync workflow" >&2; exit 1; }
[ -f "${VALIDATE_WORKFLOW}" ] || { echo "missing validate-plugin workflow" >&2; exit 1; }

grep -Fq "workflow_dispatch:" "${VALIDATE_WORKFLOW}" || {
  echo "validate-plugin must allow workflow_dispatch" >&2
  exit 1
}

required_patterns=(
  "name: Sync Chachamaru upstream"
  "schedule:"
  "workflow_dispatch:"
  "actions: write"
  "contents: write"
  "pull-requests: write"
  "https://github.com/Chachamaru127/claude-code-harness.git"
  "git fetch --no-tags upstream main"
  "git merge-base --is-ancestor"
  "git merge --no-ff --no-edit"
  "gh pr create"
  "gh workflow run validate-plugin.yml"
  "harness-review code --base origin/main --no-commit"
)

for pattern in "${required_patterns[@]}"; do
  grep -Fq "${pattern}" "${WORKFLOW}" || {
    echo "upstream sync workflow missing: ${pattern}" >&2
    exit 1
  }
done

echo "test-upstream-sync-workflow: ok"
