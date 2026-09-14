# Phase 144: reproducible RED evidence

The initial worktree base was `b01273afc3321de7ada30132243966a59581c9b0`.
The commands below inspect immutable pre-change Git objects, so the failing
condition can be rerun even though the fix is now in the working tree.

| Task | Pre-change command | Exit | Failed condition |
| --- | --- | --- | --- |
| 144.1 | `git show b01273af:skills/cursor-do/references/cursor-cli-only.md \| grep -Fq 'cherry-pick'` | 0 | Canonical Cursor reference still prescribed direct integration. |
| 144.1 | `git show b01273af:skills/breezing/references/lean-path-detail.md \| grep -Fq 'main に cherry-pick'` | 0 | Canonical Breezing dependency flow still prescribed main integration. |
| 144.2 | `git show 49a0698a:scripts/setup-codex.sh \| grep -Fq 'harness-pr-closeout.sh'` | 1 | The user installer did not ship the closeout helper. |

The Phase 144 contract test is the corresponding GREEN check:

```bash
bash tests/test-pr-first-core-skill-contract.sh
```
