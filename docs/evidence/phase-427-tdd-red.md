# Phase 427 TDD RED evidence

Before the output-contract exception was added, the focused governance test
failed for every distributed `harness-review` skill:

```text
missing required term in skills/harness-review/SKILL.md: `code --no-commit --report FILE` では stdout に P35 フッターを付けない
missing required term in codex/.codex/skills/harness-review/SKILL.md: `code --no-commit --report FILE` では stdout に P35 フッターを付けない
missing required term in opencode/skills/harness-review/SKILL.md: `code --no-commit --report FILE` では stdout に P35 フッターを付けない
```

The final focused test requires the exception in all three distributed skills.
