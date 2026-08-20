#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="${ROOT_DIR}/.github/workflows/sync-chachamaru-upstream.yml"
VALIDATE_WORKFLOW="${ROOT_DIR}/.github/workflows/validate-plugin.yml"
SMOKE_WORKFLOW="${ROOT_DIR}/.github/workflows/smoke-install.yml"
CODEQL_WORKFLOW="${ROOT_DIR}/.github/workflows/codeql.yml"

[ -f "${WORKFLOW}" ] || { echo "missing upstream sync workflow" >&2; exit 1; }
for workflow in "${VALIDATE_WORKFLOW}" "${SMOKE_WORKFLOW}" "${CODEQL_WORKFLOW}"; do
  [ -f "${workflow}" ] || { echo "missing CI workflow: ${workflow}" >&2; exit 1; }
  grep -Fq "workflow_dispatch:" "${workflow}" || {
    echo "CI workflow must allow workflow_dispatch: ${workflow}" >&2
    exit 1
  }
done

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
  "gh workflow run smoke-install.yml"
  "gh workflow run codeql.yml"
  "harness-review code --base origin/main --no-commit"
)

for pattern in "${required_patterns[@]}"; do
  grep -Fq "${pattern}" "${WORKFLOW}" || {
    echo "upstream sync workflow missing: ${pattern}" >&2
    exit 1
  }
done

echo "test-upstream-sync-workflow: ok"
