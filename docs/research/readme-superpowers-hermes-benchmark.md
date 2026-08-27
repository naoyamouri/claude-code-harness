# README Benchmark: Superpowers + Hermes

Date: 2026-05-24
Scope: Phase 75.1.1 planning evidence for the `README.md` /
`README_ja.md` product front door and visual-asset refresh.

Status: Phase 75.1.1 research only. This document does not rewrite the README
and does not generate images.

## Decision

Phase 75 should adopt the product-front-door shape from Superpowers and Hermes,
but only after translating it through Harness' own support tiers and unknown
data contract. The current README has useful onboarding pieces, but the top
surface is still carrying release archaeology, `Hokage` code-name framing, and
old/dark visual assets. Those should be removed, relocated, or regenerated
before release.

## External Sources Checked

| Source | Evidence observed on 2026-05-24 | Harness use |
|--------|----------------------------------|-------------|
| Superpowers repo: https://github.com/obra/superpowers | README leads with short definition, Quickstart, How it works, installation by coding agent, basic workflow, skills library, philosophy, updating, community. It explicitly names Claude Code, Codex CLI, Codex App, Factory Droid, Gemini CLI, OpenCode, Cursor, and GitHub Copilot CLI as install surfaces. | Adopt the short front door, tool-first install map, workflow clarity, skill-trigger framing. Do not inherit the broad host support claim. |
| Hermes Agent repo: https://github.com/NousResearch/hermes-agent | README uses a visual hero, concise value proposition, Quick Install, Getting Started commands, CLI vs Messaging quick reference, documentation map, migration path, and contributor path. It also makes broad infrastructure/runtime claims that are specific to Hermes. | Adopt the "what can I run now?" shape, quick command reference, docs map, and migration clarity. Do not copy Hermes' runtime, gateway, model-provider, cloud, or memory claims. |

## Local Evidence Checked

| Local source | Evidence | Phase 75 implication |
|--------------|----------|----------------------|
| `spec.md` | Defines support tiers, onboarding contract, unknown data contract, PR/release boundary, README Product Surface Contract, and visual asset constraints. | README and visual claims must follow `spec.md`; `not_observed != absent` remains mandatory. |
| `Plans.md` Phase 73.1.11 | Lightweight README refresh was completed, but it did not require full benchmark, claim inventory, image regeneration, asset manifest, or GPT-image2.0 route proof. | Phase 75 is not redoing Phase 73 blindly; it closes the missing product-surface and asset evidence. |
| `docs/onboarding/index.md` | Tool-first onboarding with tiers: Claude Code `supported`, Codex CLI/OpenCode `internal-compatible`, Codex app/Cursor/GitHub Copilot CLI `candidate`, Antigravity CLI `future/unsupported`. | README can point users to their tool, but public wording must keep tier boundaries. |
| `docs/onboarding/install.md` | Candidate/unsupported hosts are boundary checks, not install promises. Codex direct plugin smoke is separate from `setup-codex`. | Install section must not make candidate hosts feel production-ready. |
| `docs/onboarding/migration.md` | Migration report is non-destructive and preserves harness-mem state. | Existing-user section should be concise and confidence-building, not a deep internal migration postmortem. |
| `docs/onboarding/skill-trigger-acceptance.md` | Skill-trigger acceptance differentiates Claude, Codex companion, and OpenCode; raw `codex exec` is not the Harness companion path. | README can say Harness validates skill/workflow triggers, but must avoid host parity claims. |
| `docs/tool-capability-matrix.md` | False parity forbidden; Codex/OpenCode are bounded; candidate hosts do not inherit safety/bootstrap claims. | Support table should be proof boundary, not marketing support matrix. |
| `README.md` / `README_ja.md` | Both already have Quickstart, How It Works, Install By Tool, First 15 Minutes, Existing User Migration, Advanced. Both also still include `v4.2-Hokage` badge, `docs/images/hokage/hokage-hero.jpg`, v4.2/v4.0 history blocks, and `Hokage Core Extraction Status` near the top. | Keep the useful navigation, then rewrite the top surface to lead with user pain, latest state, and verified route. Move or remove release archaeology and internal-code-name framing. |
| `CHANGELOG.md` | Contains user-facing changes but also records internal HTML/closeout artifacts and historical release context. | CHANGELOG should record release value, not operator-only HTML or internal background as product value. |

## Adopt / Adapt / Reject / Unknown

| Item | Decision | Why | Target files | Required tests/checks | Support claim boundary |
|------|----------|-----|--------------|-----------------------|------------------------|
| Short hero that says what Harness changes immediately | Adopt | Superpowers and Hermes both make the first screen do positioning work. Harness needs the same but grounded in its own workflow. | `README.md`, `README_ja.md`, visual manifest | `tests/test-readme-product-surface.sh`, render spot-check | Say Harness stabilizes plan/work/review/release. Do not say it supports every coding agent. |
| Quickstart before deep architecture | Adopt | New users need first runnable path before internal design. | `README.md`, `README_ja.md`, `docs/onboarding/index.md` | README product surface test | Quickstart can be Claude-first and link to bounded routes for other tools. |
| Tool-first install navigation | Adapt | Superpowers has direct install surfaces for many tools; Harness has tiered evidence instead. | `README.md`, `README_ja.md`, `docs/onboarding/install.md`, `docs/tool-capability-matrix.md` | support wording test, tool capability matrix test | Use `supported`, `internal-compatible`, `candidate`, `future/unsupported`; never upgrade a host from another project's proof. |
| How It Works that makes plan/spec automatic | Adopt | The user called out that earlier wording could sound manual. The section must show Harness drafts/updates `spec.md` and `Plans.md`; the user approves/corrects. | `README.md`, `README_ja.md`, `tests/test-readme-product-surface.sh` | README product surface test | Do not imply the user handwrites the plan/spec as the normal path. |
| Basic workflow as concrete stages | Adopt | Superpowers' workflow is legible; Harness already has setup -> plan/spec -> work/TDD -> review -> PR/release. | `README.md`, `README_ja.md`, `Plans.md`, `spec.md` | README product surface test, git diff check | Keep PR ready and release ready separate. |
| Command table with "what happens inside" | Adopt | This directly addresses the current README feedback and lowers cognitive load. | `README.md`, `README_ja.md` | README product surface test | Explain command behavior, not implementation lore. |
| Docs map and migration path | Adopt | Hermes makes deeper docs easy to find after the quick path. Existing users need migration impact/rollback clarity. | `README.md`, `README_ja.md`, `docs/onboarding/migration.md` | README surface test | Migration report is non-destructive; no purge/cleanup claim without explicit gate. |
| harness-mem as optional managed companion | Adapt | Harness has real harness-mem integration docs, but memory claims are easy to overstate. | `README.md`, `README_ja.md`, `spec.md`, `docs/onboarding/migration.md` | support wording test, any memory bridge tests already present | Say optional managed companion / cross-session search when configured. Avoid broad "only setup" competitor claims unless independently proven. |
| Big feature list before Quickstart | Reject | Users need operating path and proof boundary first; long lists slow the front door. | `README.md`, `README_ja.md` | README surface test | Feature detail can live later or in docs map. |
| Internal code-name/history framing at the top | Reject | The user explicitly asked to remove meta background and code-name explanation from the README surface. | `README.md`, `README_ja.md`, `CHANGELOG.md` | README surface test, manual claim scan | `Hokage` can remain in architecture/history docs where needed, not as first-screen product positioning. |
| Operator-only HTML as plugin distribution value | Reject | HTML explainers were useful for review, but are not a plugin value proposition. | `CHANGELOG.md`, README docs map if referenced | CHANGELOG review in 75.1.6 | Do not list internal confidence/merge HTML as public product value. |
| Broad cross-host support copied from Superpowers | Reject | Superpowers proof is not Harness proof. | `README.md`, `README_ja.md`, `docs/tool-capability-matrix.md` | support wording test, tool capability matrix test | Candidate/unsupported hosts stay candidate/unsupported. |
| Hermes runtime/infrastructure claims | Reject | Hermes has its own gateway, terminal backends, cloud, provider, and memory architecture. | `README.md`, `README_ja.md` | manual claim scan | Harness can borrow README shape, not Hermes capabilities. |
| GPT-image2.0 execution path | Unknown / Adapt | Official OpenAI API docs checked on 2026-05-24 expose `gpt-image-1.5`, `gpt-image-1`, and `gpt-image-1-mini`; `GPT-image2.0` remains unverified as an API model label in this repo. | `docs/research/readme-visual-asset-manifest.md` | 75.1.4 blocker check | No `GPT-image2.0` provenance claim until the user provides or approves a verified route. |

## Current README Claim Inventory

| Claim / section | Current evidence | Decision | Target action |
|-----------------|------------------|----------|---------------|
| `Quickstart` | Already links onboarding and shows `/harness-plan`, `/harness-work`, `/harness-review`, `/harness-release`. | Keep and tighten | In 75.1.3, keep first-run path but make the "what changes after install" promise stronger. |
| `How It Works` | Already says Harness drafts `spec.md` / `Plans.md` and user approves/corrects. | Keep | Preserve the anti-manual-plan wording added before 75.1.1. |
| `Install By Tool` | Existing support table matches `spec.md` tier vocabulary. | Keep and simplify | Reduce cognitive load in Japanese; keep tier labels as code terms. |
| `Existing User Migration` | States migration report checks caches/symlinks/harness-mem without deletion. | Keep | Make this a short reassurance block with deeper link. |
| `Advanced` | Contains Breezing, Codex companion, OpenCode bootstrap, harness-mem. | Keep lower | Keep after basic workflow/proof boundary; avoid making advanced paths look required. |
| `v4.2-Hokage` badge | README first screen contains code-name badge. | Remove or relocate | Remove from top README. If needed, move historical code-name to release notes/docs. |
| `docs/images/hokage/hokage-hero.jpg` hero | Dark/obsolete/internal-code-name image; alt text says `Hokage v4.0`. | Replace / unreference | 75.1.5 should stop referencing this image from README/README_ja. New hero must be white-background and claim-bounded. |
| `v4.2 Update` / `v4.0 "Hokage"` blocks | Release-history detail appears before the main user-facing value path. | Relocate / compress | Move to CHANGELOG or deeper docs; top README should state latest state, not release archaeology. |
| `Hokage Core Extraction Status` | Internal architecture boundary appears near top. | Relocate | Keep in architecture docs and docs map; do not lead README with it. |
| Requirements with Opus/Node/Hokage details | Useful but currently mixed with release narrative. | Reframe | Put as concise requirements after Quickstart or docs map; remove code-name explanation. |
| `only setup where ... remembered across sessions` | Competitive claim depends on harness-mem and competitor proof. | Revise / verify | Reword to "With harness-mem configured, Harness can carry project context across sessions" unless independent competitor audit is added. |
| Session Memory section | Describes harness-mem managed companion and no DB reads. | Keep lower | Keep as Advanced or docs map content; link to setup/migration. |
| CHANGELOG internal HTML entries | Useful operator evidence, not user value. | Remove from release-facing copy | 75.1.6 should ensure CHANGELOG item is user-facing and not "HTML artifact shipped". |

## Asset Inventory / Action

| Asset | Used by | Text-bearing | Decision | Required action |
|-------|---------|--------------|----------|-----------------|
| `docs/images/claude-harness-logo-with-text.png` | README + README_ja | Yes, logo text | Keep as source tone | May remain as logo source; generated derivatives must match its white-background/brand tone. |
| Remote shields | README + README_ja | Short badge text | Keep with audit | They are not generated product diagrams, but remove the `v4.2-Hokage` shield from top README. |
| `docs/images/hokage/hokage-hero.jpg` | README + README_ja | Likely visual/title claim via alt | Replace / unreference | Obsolete/dark/internal-code-name hero. Do not ship as top README hero after Phase 75. |
| `assets/readme-visuals-en/generated/why-harness-pillars.svg` | README | Yes | Regenerate EN | Pair with Japanese version; verify alt text and claim boundary. |
| `assets/readme-visuals-ja/generated/why-harness-pillars.svg` | README_ja | Yes | Regenerate JA | Keep separate Japanese text, lower terminology load. |
| `assets/readme-visuals-en/generated/harness-feature-matrix.svg` | README | Yes | Regenerate EN after claim audit | Remove/soften competitor "only setup" style claims unless independently proven. |
| `assets/readme-visuals-ja/generated/harness-feature-matrix.svg` | README_ja | Yes | Regenerate JA after claim audit | Same claim boundary as English; reduce jargon. |
| `assets/readme-visuals-en/work-all-flow.svg` | README | Yes | Regenerate EN | Align with `/harness-work` and current stage gate wording. |
| `assets/readme-visuals-ja/work-all-flow.svg` | README_ja | Yes | Regenerate JA | Japanese copy should avoid unnecessary English labels. |
| `assets/readme-visuals-en/generated/core-loop.svg` | README | Yes | Regenerate EN | Use current setup/plan/work/review/release loop. |
| `assets/readme-visuals-ja/generated/core-loop.svg` | README_ja | Yes | Regenerate JA | Same claim, simpler Japanese. |
| `assets/readme-visuals-en/parallel-workers.svg` | README | Yes | Regenerate EN | Bound subagent/Breezing claims to Harness evidence. |
| `assets/readme-visuals-ja/parallel-workers.svg` | README_ja | Yes | Regenerate JA | Avoid implying hands-off autonomy without review gates. |
| `assets/readme-visuals-en/review-perspectives.svg` | README | Yes | Regenerate EN | Keep review perspective concept if current skill docs support it. |
| `assets/readme-visuals-ja/review-perspectives.svg` | README_ja | Yes | Regenerate JA | Keep readable language. |
| `assets/readme-visuals-en/generated/safety-guardrails.svg` | README | Yes | Regenerate EN | Avoid unsupported host/security absolutes. |
| `assets/readme-visuals-ja/generated/safety-guardrails.svg` | README_ja | Yes | Regenerate JA | Same support boundary. |
| `assets/readme-visuals-en/skills-ecosystem.svg` | README | Yes | Regenerate EN | Align with current command names and skill trigger acceptance. |
| `assets/readme-visuals-ja/skills-ecosystem.svg` | README_ja | Yes | Regenerate JA | Avoid excess jargon. |
| `assets/readme-visuals-en/breezing-agents.svg` | README | Yes | Regenerate EN | Keep as advanced/team mode, not required first-run flow. |
| `assets/readme-visuals-ja/breezing-agents.svg` | README_ja | Yes | Regenerate JA | Same. |
| `assets/readme-visuals-ja/safety-shield.svg` | README_ja only | Yes | Remove or pair | Either remove from README_ja or create a matching EN asset only if the section still needs it. Do not leave one-sided bilingual asset drift. |

## Bilingual Parity Gaps

- `README_ja.md` still uses many English section titles and specialized labels:
  `How It Works`, `Install By Tool`, `Existing User Migration`, `Advanced`,
  `candidate`, `internal-compatible`, `smoke`, `gate`, and
  `direct plugin smoke`.
- The tier labels themselves may remain as code terms because they are contract
  values, but Japanese prose around them should explain the meaning in plain
  language.
- Every text-bearing visual must have a separate EN and JA file. Do not reuse
  English diagrams in Japanese README.
- JA-only `assets/readme-visuals-ja/safety-shield.svg` is a parity gap unless
  the section is intentionally Japanese-only; current recommendation is to
  remove or merge it into the regenerated safety visual pair.

## Target Files For 75.1.2-75.1.6

| Phase | Target files | Purpose |
|-------|--------------|---------|
| 75.1.2 | `spec.md`, `Plans.md`, this research doc, `tests/test-readme-product-surface.sh` | Freeze README outline, wording rules, and test changes. |
| 75.1.3 | `README.md`, `README_ja.md`, `tests/test-readme-product-surface.sh`, `tests/test-support-claim-wording.sh` | Rewrite copy and command internals. |
| 75.1.4 | future asset manifest under `docs/research/` or `docs/readme-assets/`, image-generation prompt pack | Verify GPT-image2.0 path before generation. |
| 75.1.5 | README image references, `assets/readme-visuals-en/`, `assets/readme-visuals-ja/`, `docs/images/`, new asset parity test | Generate/integrate visuals and remove obsolete hero. |
| 75.1.6 | `CHANGELOG.md`, PR/release evidence docs, README tests | Close product-surface review and release suitability. |

## Required Tests / Checks

- `bash tests/test-readme-product-surface.sh`
- `bash tests/test-support-claim-wording.sh`
- `bash tests/test-tool-capability-matrix.sh`
- New or updated asset existence / bilingual parity check for local README image
  references, likely `tests/test-readme-image-assets.sh`.
- `git diff --check`
- If generated raster images are added: file size check and README render
  spot-check.
- If GPT-image2.0 path cannot be verified in 75.1.4: do not claim that model;
  use the official GPT Image path only after approval.

## Support Claim Boundary

The README can say:

- Harness is Claude-first.
- Claude Code is `supported`.
- Codex CLI and OpenCode are `internal-compatible` with bounded evidence.
- Codex app, Cursor, and GitHub Copilot CLI are `candidate`.
- Antigravity CLI is `future/unsupported`.
- harness-mem is an optional managed companion for cross-session memory when
  configured and healthy.

The README cannot say:

- Harness supports every Superpowers host.
- Candidate hosts are supported, production-ready, or parity-equivalent.
- Hermes-like gateway/cloud/provider/runtime capabilities exist in Harness.
- Generated images were made by GPT-image2.0 until that execution path is
  verified and approved.
- Missing runtime evidence means a host is absent or impossible. The contract is
  `not_observed != absent`.

## Unknowns / Blockers

- GPT-image2.0 local/official execution path: still unverified as an API model
  label. `docs/research/readme-visual-asset-manifest.md` records the official
  GPT Image API fallback and approval gate.
- Exact generated image dimensions and file sizes: `Unknown` until asset
  manifest is created.
- Whether to keep any legacy `Hokage` visual in docs outside README: not
  decided here. This task only decides README top-surface handling.
- harness-mem MCP health is available in this session, but no dedicated search
  tool was exposed in the current MCP tool list. This is process evidence only;
  it should not become a README product claim.
