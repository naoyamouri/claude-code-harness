---
name: cursor-do
description: "Delegate a single write task to Cursor Composer in an isolated worktree, then Lead-review and submit a topic-branch PR. Use when user invokes cursor:do, says delegate to cursor, have composer write it, refactor with cursor, hand a file edit to Composer. Do NOT load for: planning, code review only, read-only investigation, or multi-task team runs (use breezing --cursor or cursor:ask instead)."
---

# cursor:do — Single-Task Write Delegate to Cursor Composer

1 件の実装タスクを Cursor Composer (`composer-2.5-fast`) に専用 worktree 内で委譲し、Lead が diff をレビューして topic branch の PR を作成する skill。**topic branch → PR → formal review → CI → GitHub merge** を必ず通し、待機は `cc:blocked [reason]`、merge receipt 後の `cc:完了 [merge-sha]` は `harness-sync` の別 marker PR だけが記録する。

封じ込めは Cursor 側にはない ([references/cursor-cli-only.md](${CLAUDE_SKILL_DIR}/references/cursor-cli-only.md))。**専用 `.git` を持つ worktree + Lead diff review + topic-branch PR** の 3 点だけが実効的な境界。cursor の出力は Lead レビューまで untrusted として扱う。

## Step 0 — NARRATION RULES (UX Contract)

敵は **冗長さ** であって進捗報告ではない。breezing と同じ契約。**起動時に banner + 実行計画を簡潔に明示してから実行する**。見やすい進捗報告は歓迎、冗長な繰り返しのみ禁止。

### 起動時に必ず出すもの (banner + plan、合計 5 行以内)

```
🚀 cursor / composer-2.5-fast / feat/foo-bar / Add login form validation
これから:
1. pre-check (branch / cursor-agent) → 専用 worktree 作成
2. composer に実装委譲 (--write)
3. diff レビュー → topic branch を push → PR 作成
```

banner 1 行 (`🚀 cursor / composer-2.5-fast / <branch> / <task>`) + 計画 2-4 行。1 秒以内に出し、即 Step 1 へ。

### 進捗報告は出してよい (見やすい範囲で)

- 各ステップの開始・完了を 1 行ステータスで (`✓ worktree 作成: .claude/worktrees/cursor-do-...`)
- pre-check / resolve の要点、作成した PR
- なぜこの分岐を取るかの理由を 1 行で

### 禁止 (= 冗長さ)

- **同じ事実の 2 回言い換え**: pre-check 結果を後段で再説明しない
- **中身のない前置き**: tool call で自明な宣言だけの行
- **3 行以上の経緯振り返り**: 必要なら 1 行に圧縮
- **起動シーケンス中の ★ Insight ブロック**: Insight は最終 report で 1 回のみ

違反例 (冗長):
```
× 「composer 2.5 で実装する流れですね、まず確認します」（中身のない前置き）
× 「Cursor を呼ぶ前に branch を見ます」 → bash → 「branch を確認しました」（言い換え）
× ★ Insight ──── Cursor の強みは…
```

正常例 (簡潔 + 計画明示):
```
🚀 cursor / composer-2.5-fast / feat/foo-bar / Add login form validation
これから: worktree 作成 → composer に実装委譲 → diff レビュー → PR 作成
```

## Step 1 — banner + plan を出し切る (1 秒以内)

引数 `$ARGUMENTS` をタスク説明として受ける。引数が空なら以下のマーカーを出力してユーザーに 1 行タスクを要求し、入力後に Step 2 へ進む:

```
CURSOR_DO_AWAITING_TASK: provide a one-line task description as $ARGUMENTS
```

引数があれば、即 1 行 echo:

```
🚀 cursor / composer-2.5-fast / <current-branch> / <task-first-60-chars>
```

`<current-branch>` は Step 2 で取得する値だが、Step 1 では未取得のため `…` でも可。Step 2 直後に確定値を 1 行で再出力する。Step 0 の banner + 実行計画 (5 行以内) はここで出し切り、以降は各ステップの 1 行ステータスで進捗を見せる。冗長な繰り返しのみ避ける。

## Step 2 — 並列 pre-check (1 bash)

1 つの bash 呼び出しで以下を並列に取り、結果だけを 1 ブロックで受ける。個別の説明は出さない。

```bash
bash -c '
  set +e
  echo "==BRANCH=="; git branch --show-current
  echo "==VERSION=="; cat VERSION 2>/dev/null
  echo "==PLANS_TAIL=="; tail -n 12 Plans.md 2>/dev/null
  echo "==CURSOR_AGENT=="
  CURSOR_AGENT_BIN="${CURSOR_AGENT_BIN:-}"
  if [ -z "$CURSOR_AGENT_BIN" ]; then
    # `agent`（公式の新表記）→ `cursor-agent`（legacy alias）の順に探す。
    # `agent` は汎用的な名前なので、symlink 解決後の実パスの「成分」に
    # cursor-agent が完全一致で現れる場合だけ採用する（部分文字列一致だと
    # /x/cursor-agent-not-really/agent のようなディレクトリ名で突破される）。
    for _c in agent cursor-agent; do
      _p="$(command -v "$_c" 2>/dev/null)" || continue
      [ -n "$_p" ] || continue
      _r="$(realpath "$_p" 2>/dev/null || readlink -f "$_p" 2>/dev/null || echo "$_p")"
      case "/$_r/" in */cursor-agent/*) CURSOR_AGENT_BIN="$_p"; break ;; esac
    done
    if [ -z "$CURSOR_AGENT_BIN" ] && [ -x "$HOME/.local/bin/cursor-agent" ]; then
      CURSOR_AGENT_BIN="$HOME/.local/bin/cursor-agent"
    fi
  fi
  if [ -z "$CURSOR_AGENT_BIN" ]; then
    echo "NOT_INSTALLED"
  else
    "$CURSOR_AGENT_BIN" --version 2>/dev/null || echo "NOT_INSTALLED"
  fi
'
```

判定:
- `CURSOR_AGENT=NOT_INSTALLED` → `ERROR: cursor-agent not found (exit 3 expected from companion). Install via setup-cursor.sh.` を出し終了。
- `BRANCH` が `main` / `master` → `ERROR: protected branch cannot be a Cursor worker target. Create an isolated topic worktree.` を出して終了。

## Step 3 — plugin root + backend + model resolve (1 bash)

`HARNESS_PLUGIN_ROOT` / `CLAUDE_PLUGIN_ROOT` が未設定だと `:-.` fallback が consumer repo の cwd に解決し、`scripts/cursor-companion.sh` が見えず起動不能になる (Issue #193 §2)。hooks.json と同じ `valid_root` パターンで堅牢に解決する。

```bash
bash -c '
  set -euo pipefail
  valid_root() {
    [ -n "${1:-}" ] && [ -f "$1/scripts/cursor-companion.sh" ] && { [ -f "$1/.claude-plugin/plugin.json" ] || [ -f "$1/.codex-plugin/plugin.json" ] || [ -f "$1/.cursor-plugin/plugin.json" ]; }
  }
  HARNESS_PLUGIN_ROOT="${HARNESS_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}"
  ROOT="$HARNESS_PLUGIN_ROOT"
  if ! valid_root "$ROOT"; then
    ROOT=""
    if [ -n "${CLAUDE_SKILL_DIR:-}" ]; then
      probe="$(cd "${CLAUDE_SKILL_DIR}" && pwd)"
      while [ "$probe" != "/" ] && ! valid_root "$probe"; do
        probe="$(cd "$probe/.." && pwd)"
      done
      valid_root "$probe" && ROOT="$probe"
    fi
  fi
  if ! valid_root "$ROOT"; then
    ROOT=""
    for c in "${CLAUDE_PROJECT_DIR:-}" "$PWD" \
             "$HOME/.claude/plugins/marketplaces/claude-code-harness-marketplace" \
             "$HOME/.claude/plugins/cache/claude-code-harness-marketplace/claude-code-harness/"*; do
      if valid_root "$c"; then ROOT="$c"; break; fi
    done
  fi
  if ! valid_root "$ROOT"; then
    echo "ERROR: claude-code-harness plugin root not found (no scripts/cursor-companion.sh)" >&2
    exit 2
  fi
  HARNESS_PLUGIN_ROOT="$ROOT"
  BACKEND=$(bash "${HARNESS_PLUGIN_ROOT}/scripts/resolve-impl-backend.sh" --backend cursor --role worker)
  MODEL=$(bash "${HARNESS_PLUGIN_ROOT}/scripts/model-routing.sh" --host cursor --role worker --field model)
  echo "PLUGIN_ROOT=${HARNESS_PLUGIN_ROOT}"
  echo "BACKEND=$BACKEND"
  echo "MODEL=$MODEL"
'
```

返却値: `PLUGIN_ROOT` (Step 5 で使う) / `BACKEND` (必ず `cursor`) / `MODEL` (通常 `composer-2.5-fast`)。`BACKEND` または `MODEL` が空なら `ERROR: backend/model resolution failed` を 1 行で出して終了。`PLUGIN_ROOT` 解決失敗は上記スクリプトが exit 2 で報告する。

## Step 4 — 専用 worktree 作成

衝突しない id を作って worktree を切る。**main tree や `$HOME` を指してはならない** (companion 側 guard で exit 2 になる)。`WT_DIR` は絶対パスで作る (Step 5 の `--workspace` は companion の `is not a directory` ガードで相対パスを exit 2 にすることがあるため、Issue #193 §4)。

```bash
bash -c '
  set -euo pipefail
  REPO_ROOT="$(git rev-parse --show-toplevel)"
  cd "$REPO_ROOT"
  ID="$(date +%Y%m%d-%H%M%S)-$$"
  WT_DIR="$REPO_ROOT/.claude/worktrees/cursor-do-${ID}"
  BASE_REF="$(git rev-parse HEAD)"
  BASE_BRANCH="$(git branch --show-current)"
  WT_BRANCH="cursor-do/${ID}"
  mkdir -p "$REPO_ROOT/.claude/worktrees"
  git worktree add -b "${WT_BRANCH}" "${WT_DIR}" "${BASE_REF}"
  echo "REPO_ROOT=${REPO_ROOT}"
  echo "WT_DIR=${WT_DIR}"
  echo "WT_BRANCH=${WT_BRANCH}"
  echo "BASE_REF=${BASE_REF}"
  echo "BASE_BRANCH=${BASE_BRANCH}"
'
```

返却された `WT_DIR` / `WT_BRANCH` / `BASE_REF` / `BASE_BRANCH` を以降の Step で使う。失敗時 (branch 名衝突等) は `ID` を作り直して 1 回だけ retry。2 回連続失敗で `ERROR: worktree creation failed` を出し終了。

## Step 5 — cursor-companion.sh task --write で委譲

Lead が直接 companion を呼ぶ ([references/cursor-cli-only.md](${CLAUDE_SKILL_DIR}/references/cursor-cli-only.md) Topology 節 — 非 claude backend では Worker 介在なし)。プロンプトは引数の task そのまま + 必要な追補のみ。冗長な前置きは付けない。

```bash
bash -c '
  set -euo pipefail
  valid_root() {
    [ -n "${1:-}" ] && [ -f "$1/scripts/cursor-companion.sh" ] && { [ -f "$1/.claude-plugin/plugin.json" ] || [ -f "$1/.codex-plugin/plugin.json" ] || [ -f "$1/.cursor-plugin/plugin.json" ]; }
  }
  HARNESS_PLUGIN_ROOT="${HARNESS_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}"
  ROOT="${PLUGIN_ROOT:-$HARNESS_PLUGIN_ROOT}"
  if ! valid_root "$ROOT"; then
    ROOT=""
    if [ -n "${CLAUDE_SKILL_DIR:-}" ]; then
      probe="$(cd "${CLAUDE_SKILL_DIR}" && pwd)"
      while [ "$probe" != "/" ] && ! valid_root "$probe"; do
        probe="$(cd "$probe/.." && pwd)"
      done
      valid_root "$probe" && ROOT="$probe"
    fi
  fi
  if ! valid_root "$ROOT"; then
    ROOT=""
    for c in "${CLAUDE_PROJECT_DIR:-}" "$PWD" \
             "$HOME/.claude/plugins/marketplaces/claude-code-harness-marketplace" \
             "$HOME/.claude/plugins/cache/claude-code-harness-marketplace/claude-code-harness/"*; do
      if valid_root "$c"; then ROOT="$c"; break; fi
    done
  fi
  if ! valid_root "$ROOT"; then
    echo "ERROR: claude-code-harness plugin root not found (no scripts/cursor-companion.sh)" >&2
    exit 2
  fi
  HARNESS_PLUGIN_ROOT="$ROOT"
  PROMPT="<task-description>

Constraints:
- Modify only files relevant to the task.
- Keep existing tests green. Add tests when the task is verifiable.
- Match existing code style and naming.
- Create exactly one git commit if your environment supports it; otherwise leave one dirty changeset for Lead auto-commit.
- Do not touch .claude-plugin/settings*, .claude/settings*, .eslintrc*, biome.json, tsconfig*.json."
  bash "${HARNESS_PLUGIN_ROOT}/scripts/cursor-companion.sh" task \
    --write \
    --workspace "${WT_DIR}" \
    "${PROMPT}"
' 2>&1
```

判定:
- exit 0 + result text → Step 6 へ
- exit 1 (result-error) → companion stderr を 1 行要約して `ERROR: cursor returned is_error/empty result` を出し終了。worktree は Step 8 のクリーンアップで削除
- exit 2 (bad-guard) → 設定不備。原因 (workspace 指定誤り等) を 1 行で示し終了
- exit 3 (not-found) → Step 2 で検出済みのはずだが、再度遭遇したら同様に終了

## Step 6 — Lead diff review

worktree 内で Composer が作成した変更を読み、目視レビュー + contract grep の二段ゲートを通す（topic branch PR の前段）。

**注意 (Issue #193 §1)**: Cursor Composer は `--write` でファイル編集を行うが **commit は作らない**ことがある。worktree が dirty のままだと Step 7 の PR に差分が載らない。本 Step 冒頭で dirty なら、既存 commit がある場合は amend、commit がない場合は Lead 側で 1 commit にまとめる。

```bash
bash -c '
  set -euo pipefail
  cd "${WT_DIR}"
  # Composer は dirty changeset を返すことがあるため、既存 commit に fold する
  if [ -n "$(git status --porcelain)" ]; then
    git add -A
    if [ "$(git rev-list --count "${BASE_REF}..HEAD")" -gt 0 ]; then
      git -c user.name="cursor-composer" -c user.email="cursor-composer@local" \
        commit --amend --no-edit --no-verify
      echo "==AUTO_AMENDED=="
    else
      git -c user.name="cursor-composer" -c user.email="cursor-composer@local" \
        commit --no-verify -m "cursor: ${TASK_SUMMARY:-cursor-do delegated change}"
      echo "==AUTO_COMMITTED=="
    fi
    git log -1 --oneline
  fi
  echo "==LOG=="
  git log --oneline "${BASE_REF}..HEAD"
  echo "==STAT=="
  git diff --stat "${BASE_REF}..HEAD"
  echo "==DIFF=="
  git diff "${BASE_REF}..HEAD"
'
```

`TASK_SUMMARY` は引数 task の先頭 60 文字以内に圧縮した文字列を Lead が事前に export しておく (例: `TASK_SUMMARY="Add login form validation"`)。未設定なら fallback メッセージ `cursor-do delegated change` を使う。`--no-verify` を付けるのは worktree 内の編集を「Lead レビュー前の中間 commit」として扱うため。topic branch の commit も通常の guardrail を通し、default branch への取り込みは PR merge だけにする。

Lead は diff 全文を Read し、以下を確認する:

- 変更が依頼タスクの範囲内か (関係ないファイルを触っていないか)
- protected path (`.claude-plugin/settings*`, `.eslintrc*`, etc.) を変更していないか
- secret / `.env` / 認証情報を含まないか
- 公開 support tier 表記を破壊していないか。contract gates は必ず candidate worktree (`WT_DIR`) 内で実行する:
  ```bash
  [ ! -f "${WT_DIR}/tests/test-support-claim-wording.sh" ] || (cd "${WT_DIR}" && bash tests/test-support-claim-wording.sh)
  [ ! -f "${WT_DIR}/scripts/ci/check-consistency.sh" ] || (cd "${WT_DIR}" && bash scripts/ci/check-consistency.sh)
  [ ! -f "${WT_DIR}/tests/validate-plugin.sh" ] || (cd "${WT_DIR}" && bash tests/validate-plugin.sh)
  ```

判定:
- 問題なし → Step 7 へ
- 範囲外変更あり → 該当 commit を `git reset` で巻き戻すか、Cursor に再委譲 (Step 5 を 1 回だけ retry)。2 回失敗で `REQUEST_CHANGES: <理由>` を出し、worktree を残したまま終了
- protected path / secret 検出 → 即 abort。`ABORT: protected path violation` を出し worktree 削除

## Step 7 — topic branch を push して PR を作成

Composer の commit は worker worktree に留める。Lead は default branch を直接操作せず、review 済み branch を push して PR を作る。PR を作成した時点ではタスクは `cc:WIP [PR #<number>: review/CI pending]` のままにする。

```bash
bash -c '
  set -euo pipefail
  COMMIT_COUNT="$(cd "${WT_DIR}" && git rev-list --count "${BASE_REF}..HEAD")"
  [ "${COMMIT_COUNT}" -gt 0 ] || { echo "ERROR: no commits for PR"; exit 1; }
  git -C "${WT_DIR}" push -u origin "${WT_BRANCH}"
  gh pr create --base "${BASE_BRANCH}" --head "${WT_BRANCH}" --fill
'
```

Formal review、required CI、GitHub merge が終わるまで main と completion marker を変更しない。CI・権限・人間判断の待機は `cc:blocked [reason]` とする。merge receipt 後に `harness-sync` を実行し、marker-only の別 PR で `cc:完了 [merge-sha]` を記録する。

## Step 8 — worktree cleanup + PR 報告 (1 ブロック)

PR 作成確認後にだけ worktree を cleanup する。PR 作成失敗時は worktree を残してユーザー判断に渡す。

```bash
bash -c '
  set -euo pipefail
  git worktree remove --force "${WT_DIR}"
  git branch -D "${WT_BRANCH}" 2>/dev/null || true
  echo "==CLEANUP=="
  git worktree list | grep -v "cursor-do-" || true
'
```

完了報告は **1 ブロック** で出す。中間ナレーションなし:

```
cursor:do PR created
   task: <task-first-60-chars>
   commits: <count>
   base: <BASE_REF> → PR #<number> into <BASE_BRANCH>
   plans: cc:WIP [PR pending]
   files: <changed-file-count> changed, +<inserts> -<deletes>
```

## Full Containment (write mode 必須)

| 層 | 役割 | skip 可否 |
|---|---|---|
| 専用 `.git` worktree | cursor の書込を main tree から隔離 | 不可（必須） |
| Lead diff review | untrusted cursor 出力の品質ゲート | 不可（必須） |
| contract-grep ゲート | docs / locale / matrix 固定文字列の保護 | 不可（必須） |
| topic branch → PR | default branch を GitHub merge gate の背後に置く唯一の経路 | 不可（必須） |
| merge 後の marker PR | `harness-sync` が `cc:完了 [merge-sha]` を記録 | 不可（必須） |

## Prohibited

- `--force` / `--yolo` を companion に渡す（Cursor 公式 "Never use"）
- cursor 出力を Lead レビュー前に main へ直接 commit する
- protected path (`.claude-plugin/settings*`, `.eslintrc*`, `tsconfig*.json`, etc.) を Step 5 の prompt で許可する
- `$HOME` / `/` / main tree を `--workspace` に指定する
- Plans.md の `cc:*` マーカーを task と無関係に書き換える

## Related Skills / Rules

- `cursor:ask` — 読取専用の質問・調査・敵対的視点 (worktree 不要)
- `breezing --cursor` — 複数タスクを team フローで cursor 委譲する場合
- `harness-work` — claude backend の default フロー (Worker agent 経由)
- `references/cursor-cli-only.md` — Cursor backend governance + Topology (旧 `.claude/rules/cursor-cli-only.md` の全文がここに移設済み)
