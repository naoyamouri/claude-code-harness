#!/usr/bin/env bash
# Verify that core execution skills keep all default-branch writes behind a PR.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for skill in \
  skills/harness-work/SKILL.md \
  skills/breezing/SKILL.md \
  skills/cursor-do/SKILL.md \
  skills/harness-loop/SKILL.md \
  skills-codex/harness-work/SKILL.md \
  skills-codex/breezing/SKILL.md \
  skills-codex/harness-loop/SKILL.md; do
  grep -Fq 'topic branch → PR → formal review → CI → GitHub merge' "$ROOT/$skill"
  grep -Fq 'cc:blocked' "$ROOT/$skill"
done

for skill in skills/harness-sync/SKILL.md skills/harness-plan/SKILL.md; do
  grep -Fq 'marker PR' "$ROOT/$skill"
  grep -Fq 'cc:blocked' "$ROOT/$skill"
done

grep -Fq 'GitHub merge receipt' "$ROOT/skills/harness-sync/SKILL.md"
grep -Fq 'cc:blocked' "$ROOT/skills/harness-plan/SKILL.md"
grep -Fq 'neither a worker nor a Lead cherry-picks to a default branch' "$ROOT/docs/spec/workflow-review-and-release.md"
grep -Fq 'cc:blocked` with an explicit resume condition' "$ROOT/docs/spec/workflow-review-and-release.md"
grep -Fq '`cc:done` は GitHub merge と `harness-sync` が成功した後' "$ROOT/Plans.md"

for reference in \
  skills/cursor-do/SKILL.md \
  skills/cursor-do/references/cursor-cli-only.md \
  skills/breezing/references/lean-path-detail.md; do
  ! grep -Fq 'cherry-pick' "$ROOT/$reference"
done

echo 'pr-first core skill contract ok'
