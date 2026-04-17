---
name: pr-review-response
description: "PR レビューコメントを取得し、並列トリアージ → 矛盾検出 → ユーザー承認 → 並列修正 → 同種問題スキャン → pre-push セルフレビュー → push → Copilot レビュー依頼を、複数エージェントの同時起動で回す。Triggers on: 'pr-review-response', 'PR レビュー対応（並列）', 'pr review parallel', '/pr-review-response'."
user-invokable: true
argument-hint: "<pr-number>"
---

# pr-review-response — 並列エージェント駆動の PR レビュー対応ワークフロー

PR レビューコメントへの対応を **Command + 3 種のローカル worker + 既存 pre-push-review skill** で多段オーケストレーションする、このプロジェクト専用の skill。既存 `/handle-pr-comments` が単一ファイル逐次実装なのに対し、本スキルは Triage / Fix / Scan を複数エージェントで同時起動し、最終レビューは `/pre-push-review` に委譲、push 後に Copilot レビュー依頼まで実施する。

## なぜ新スキルを作るか

- 既存 `/handle-pr-comments` はそのまま残す（ロールバック容易性、spec-implement 文脈での利用継続）
- 並列化と agent 委譲で分類・修正・パターンスキャンを高速化
- MEMORY `feedback_copilot_review_request.md` の「修正 push 後に REST API で Copilot へレビュー依頼」をワークフローに恒久組み込み

## 呼び出し形式

```
/pr-review-response <pr-number>
```

`<pr-number>` は `#123` / `123` / `https://github.com/.../pull/123` いずれも受理。引数未指定時はユーザーに確認。

## 使用エージェント

| エージェント | 役割 | 並列度 | 副作用 |
|-------------|-----|-------|--------|
| `pr-triage-worker`（haiku）| 1 コメントを分類 + 妥当性判定 | N コメント数 | なし（read-only）|
| `pr-fix-worker`（sonnet）| 1 ファイル分の修正を適用 | N 影響ファイル数 | Edit あり、commit なし |
| `pr-pattern-scanner`（haiku）| 1 パターンを repo 全域 grep | N 妥当指摘ユニーク数 | なし（read-only）|

並列度は `.claude-plugin/rules/resource-aware-parallelism.md` に従いエージェント種別で分ける。`pr-triage-worker` と `pr-pattern-scanner` は read-only / 軽量なので `MAX_LIGHT_AGENTS`（デフォルト 5）、`pr-fix-worker` は Edit 実行の重量エージェントなので `MAX_HEAVY_AGENTS`（デフォルト 4）で上限制御する。

## 全体ワークフロー

```
Phase 0  前提条件チェック
  ↓
Phase 1  PR コメント取得（REST + GraphQL reviewThreads）
  ↓
Phase 2  並列トリアージ（pr-triage-worker × N）
  ↓
Phase 2.5 矛盾フィードバック検出
  ↓
Phase 3  対応計画をユーザーに提示 → 承認待ち
  ↓
Phase 4  並列修正（pr-fix-worker × ファイル数）
  ↓
Phase 5  並列同種問題スキャン（pr-pattern-scanner × パターン数）
  ↓（追加修正が必要なら Phase 4 に戻る、上限 3 回）
Phase 5.5 Command が一括 commit
  ↓
Phase 6  pre-push セルフレビュー（/pre-push-review）
  ↓（fix_required → Phase 4 へ、Phase 5 は skip、4→5.5→6 ループ、上限 2 回）
Phase 7  push
  ↓
Phase 8  レビュアー返信 + Copilot レビュー依頼
  ↓
Phase 9  完了レポート
```

> **重要な順序制約**: `pre-push-review` は `git diff base..HEAD` を見るため、Phase 5.5 で先に commit しておかないと fix が検査対象から漏れる。再修正時は **reset/amend せず追加コミットを積む**。

---

## Phase 0: 前提条件チェック（MANDATORY）

既存 `/handle-pr-comments` を踏襲（`.claude-plugin/skills/handle-pr-comments/SKILL.md:31-79` 参照）。いずれかが失敗した場合は **STOP** し、対処方法を案内する。

1. **gh CLI 認証**: `gh auth status` — 失敗時は `gh auth login` を案内
2. **リポジトリ取得**:
   ```bash
   REPO=$(gh repo view --json nameWithOwner -q '.nameWithOwner')
   OWNER="${REPO%%/*}"
   REPO_NAME="${REPO##*/}"
   ```
3. **PR 状態確認**: `gh pr view {number} --json state` — `MERGED`/`CLOSED` の場合は続行確認
4. **ワーキングツリー**: `git status --porcelain` — 未コミット変更があれば STOP
5. **PR ブランチへの切り替え**: `gh pr checkout {number}`

PR 番号の正規化（`#` 除去、URL から数値抽出）は `.claude-plugin/skills/handle-pr-comments/SKILL.md:29` と同じロジックで `{number}` 変数に入れる。

---

## Phase 1: PR コメント取得

以下の 3 種を取得する:

```bash
# inline レビューコメント
gh api repos/${OWNER}/${REPO_NAME}/pulls/{number}/comments --paginate

# レビューサマリ
gh api repos/${OWNER}/${REPO_NAME}/pulls/{number}/reviews --paginate

# resolved 状態（GraphQL 経由、REST では取れない）
gh pr view {number} --json reviewThreads -q '.reviewThreads[] | {id: .id, isResolved: .isResolved, comments: [.comments[] | {id: .id, databaseId: .databaseId, createdAt: .createdAt, path: .path, line: .line}]}'
```

resolved 済みコメントは Phase 2 の triage 対象から除外（`reply_only` に分類して完了レポートに記録）。

REST コメントと GraphQL の resolved 状態は `databaseId` を最優先で突合。なければ `createdAt + path + line` の複合キーでマッピング（body だけの突合は禁止 — 同文面で誤マッピングが起きる）。

---

## Phase 2: 並列トリアージ

resolved 除外後の全コメントについて `pr-triage-worker` を **単一メッセージ内で複数 Agent tool call を並べて同時発火** する。

```javascript
// 例: 5 コメントの場合
Agent({
  subagent_type: "pr-triage-worker",
  description: "Triage: {path}:{line}",
  prompt: buildTriagePrompt(comment_1, sibling_comments)
})
Agent({
  subagent_type: "pr-triage-worker",
  description: "Triage: {path}:{line}",
  prompt: buildTriagePrompt(comment_2, sibling_comments)
})
// ...
```

- 矛盾検出は **Command 側で一本化** する（Phase 2.5 で triage 結果を集約してから突合）。triager には他コメント情報を渡さない — haiku のコンテキストを無駄遣いしないため
- プロンプト雛形は `.claude/agents/pr-triage-worker.md` の「入力形式」セクションを参照
- 同時実行数が `MAX_LIGHT_AGENTS` を超える場合はバッチ分割する（最初のバッチが完了してから次を起動）

### Triage 結果の集約

各 worker が返す YAML ブロックをパースし、以下の 4 バケットに分類する:

| バケット | 条件 |
|---------|------|
| `auto_fix` | `validity: valid` かつ `category: code_fix` or `style` |
| `reply_only` | `category: question` |
| `user_decision` | `validity: partial` or `category: suggestion` |
| `invalid_reject` | `validity: invalid`（対応せず理由付き返信） |

---

## Phase 2.5: 矛盾フィードバック検出（Command 単独）

Phase 2 で集約した triage 結果を Command がクロス検査する。検出基準:

- `validity` が `valid` / `partial` のコメントを `path` + `line`（±3 行）でグルーピング
- 同一グループ内で `proposed_action` または `reason` が相反する方向を指している（「分割しろ」vs「このまま」、「削除しろ」vs「そのまま」など）
- 原文 `body` の語彙ベースで簡易判定すればよい（LLM 再呼び出し不要）

矛盾を検出した場合:

1. 矛盾ペアをユーザーに提示
2. 各レビュアーのレビューステータス（`APPROVED` / `CHANGES_REQUESTED`）を参考情報として表示
3. どちらを優先するかユーザーに確認（独断で判断しない）
4. 却下された側は Phase 3 計画で `invalid_reject` バケットに移し、理由付き返信を作成

矛盾なし → Phase 3 へ。

---

## Phase 3: 対応計画の提示（ユーザー承認）

以下の形式でユーザーに提示し、**承認を得るまで STOP**。

```
## PR #{number} レビューコメント対応計画（並列版）

### 自動対応（auto_fix + 承認済み user_decision）: {N}件
| # | ファイル | 行 | reviewer | 内容要約 | 対応方針 | 並列 fix-worker に含まれるか |
|---|---------|-----|----------|---------|---------|---------------------------|
| 1 | {path} | {line} | {user} | {summary} | {plan} | yes |
| ... |

### 質問への回答: {N}件
| # | ファイル | 行 | reviewer | 質問 | 回答案 |
|---|---------|-----|----------|------|--------|

### 不採用（invalid）: {N}件
| # | 対象 | 理由 | 返信内容（予定） |
|---|------|------|----------------|

### ユーザー判断待ち（suggestion / partial）: {N}件
| # | 対象 | 内容 | 承認/却下 |
|---|------|------|----------|

### 矛盾していたペア: {N}件（解消済みなら省略）
- {comment_id_A} vs {comment_id_B} → {user choice}

### スキップ（resolved / approval）: {N}件

**上記の計画で進めてよいですか？**
```

---

## Phase 4: 並列修正

`auto_fix` + ユーザー承認した `user_decision` の修正対象を **ファイル単位にグループ化** し、ファイルごとに 1 `pr-fix-worker` を起動する。同一ファイルへの指摘は必ず同一 worker に集約（edit conflict 回避）。

```javascript
// 例: 3 ファイルにまたがる場合
Agent({
  subagent_type: "pr-fix-worker",
  description: "Fix: src/foo.rs",
  prompt: buildFixPrompt("src/foo.rs", comments_for_foo_rs)
})
Agent({
  subagent_type: "pr-fix-worker",
  description: "Fix: src/bar.rs",
  prompt: buildFixPrompt("src/bar.rs", comments_for_bar_rs)
})
Agent({
  subagent_type: "pr-fix-worker",
  description: "Fix: tests/baz.rs",
  prompt: buildFixPrompt("tests/baz.rs", comments_for_baz_rs)
})
```

- 並列度上限: `MAX_HEAVY_AGENTS`
- プロンプト雛形は `.claude/agents/pr-fix-worker.md` の「入力形式」セクションを参照
- 各 worker の `skipped_comments` が空でない場合は、理由をユーザーに提示して判断を仰ぐ
- worker は commit しない（Command が Phase 5.5 で一括 commit）

---

## Phase 5: 並列同種問題スキャン

Phase 4 完了後、各妥当指摘について **パターンを抽象化** して `pr-pattern-scanner` を並列起動する。

### パターン抽象化の指針

- ID / キー名の誤り（例: `N-th` → `M-th`）→ `grep "N-th"` で残存検出
- 用語不統一（例: `-warnaserror` vs `--warnaserror`）→ 両形式で grep
- 配置位置の揺れ → 該当キー名で grep
- 型 / 関数名の typo → 正規表現で類似パターン検出

```javascript
Agent({
  subagent_type: "pr-pattern-scanner",
  description: "Scan: N-th 残存",
  prompt: `pattern: "N-th"
pattern_description: "指摘 #1 で指摘された N-th → M-th 誤記の残存箇所"
exclude_paths: ["src/foo.rs", "src/bar.rs"]   # Phase 4 で修正済み
include_globs: "**/*.md"
max_hits: 50`
})
Agent({
  subagent_type: "pr-pattern-scanner",
  description: "Scan: -warnaserror 揺れ",
  prompt: ...
})
```

### Phase 5 結果の分岐

| scanner 結果 | アクション |
|-------------|----------|
| 全 scanner で `additional_occurrences` が 0 件 | Phase 5.5 へ |
| いずれかで 1 件以上 | ユーザーに `missing_from_fix_queue` を提示し「同パターンの残存箇所を追加修正するか」を確認。承認時は Phase 4 に戻って `pr-fix-worker` を追加起動。ループ上限 3 回、それ以降は `Escalated` として最終レポートに含めユーザー判断 |

---

## Phase 5.5: 初回コミット

Phase 4 + Phase 5 追加修正がすべて working tree にある状態。Command が一括 add + commit する。

```bash
# 修正されたファイルのみ add（git add -A は使わない — 意図しないファイルを含めないため）
git add {全 fix-worker の file 一覧} {pattern-scanner 経由の追加修正ファイル}

# 軽量最終チェック（pre-push-review 前の念のための確認）
# プロジェクトタイプは存在するファイルで判定
if [ -f Cargo.toml ]; then
  cargo fmt --all -- --check && cargo clippy --quiet --all-targets -- -D warnings
elif find . -maxdepth 3 \( -name "*.csproj" -o -name "*.sln" \) -print -quit 2>/dev/null | grep -q .; then
  dotnet restore && dotnet format --verify-no-changes --no-restore && dotnet build --no-restore -warnaserror
elif [ -f package.json ]; then
  npm run lint --if-present && npm run typecheck --if-present
fi

git commit -m "$(cat <<'EOF'
fix: PR #{number} レビューコメント対応（並列対応）

対応コメント:
- {comment1 summary}
- {comment2 summary}
...

同種問題の追加修正:
- {scanner 検出箇所のサマリ}

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

- **reset / amend 禁止**: Phase 6 で `fix_required` になっても、この commit は書き換えず追加 commit を積む
- 品質チェックは `pr-fix-worker` 内で完了している前提だが、Command 側でも最終確認を軽量に走らせる

---

## Phase 6: pre-push セルフレビュー

```
Skill("pre-push-review", "--base origin/{baseRefName}")
```

判定分岐:

| verdict | アクション |
|---------|----------|
| `push_ok` | Phase 7 へ |
| `push_after_fix` (Minor のみ) | Minor の内容をユーザーに提示し、同意があれば Phase 4 に戻す／同意がなければ warning のまま Phase 7 |
| `fix_required` (Critical / Moderate あり) | Critical/Moderate finding を Phase 4 に戻して再修正。**再修正ループでは Phase 5（pattern scan）をスキップ**し、4 → 5.5 → 6 のみを回す。新しい修正を commit として積む（amend 禁止）→ Phase 6 再実行。最大 2 回繰り返し、それ以降は **escalate**（PASS に格下げせず、未対応 finding とともにユーザー判断に委ねる）|

> fail-open 禁止: Codex レビューで指摘された「3 回 FAIL で PASS 化」と同じ fail-open パターンに陥らないよう、escalate は必ず「未対応のまま通知」する設計とする。

---

## Phase 7: push

```bash
git push
```

push 失敗時（rebase 必要、hook 拒否など）は原因を報告してユーザー判断を仰ぐ。

---

## Phase 8: コメント返信 + Copilot レビュー依頼

### 8.1 各コメントへの返信

対応したコメントに返信を投稿:

```bash
# インラインコメントへの返信
gh api repos/${OWNER}/${REPO_NAME}/pulls/comments/{comment_id}/replies \
  -f body="対応しました。{変更内容の簡潔な説明}"
```

`invalid` 判定したコメントには理由付き返信（steering / rules へのリンク付き）:

```
この指摘は {.spec-workflow/steering/tech.md / .claude-plugin/rules/*.md} と矛盾するため不採用としました。
理由: {triage-worker の reason フィールド}
```

### 8.2 Copilot レビュー依頼

MEMORY `feedback_copilot_review_request.md` に完全準拠:

```bash
gh api repos/${OWNER}/${REPO_NAME}/pulls/{number}/requested_reviewers \
  --method POST \
  -f 'reviewers[]=copilot-pull-request-reviewer[bot]'
```

- slug は `copilot-pull-request-reviewer[bot]`（末尾 `[bot]` 必須）
- `gh pr edit --add-reviewer` は bot 名を解決できないので **使わない**
- 失敗時（既に依頼済 / 権限エラー / Copilot 未設定）は warning のみでワークフローは成功扱い、完了レポートに記載

---

## Phase 9: 完了レポート

```
## PR #{number} レビューコメント対応完了（並列版）

### Triage 結果
- auto_fix: {N}件 / reply_only: {M}件 / user_decision: {K}件 / invalid_reject: {L}件
- 矛盾ペア: {P}件（ユーザー解消済み）

### 修正サマリ
- 修正ファイル: {N} ({並列 fix-worker で処理})
- 同種問題の追加修正: {M}件（scanner 検出）
- pr-fix-worker が skip した指摘: {K}件（理由: ...）

### 品質チェック
- pre-push-review: {verdict}
  - Critical: {N} / Moderate: {M} / Minor: {K}
- Phase 5.5 軽量チェック: PASS

### Commit & Push
- commit 数: {N} 件（初回 + 再修正 {M} 回）
  - {hash1}: {message1}
  - ...
- branch: {headRefName} → origin

### Copilot レビュー依頼
- 結果: 成功 / warning ({reason})

### 未対応（ある場合）
- {escalated の内容と理由}
```

---

## ルール

- **対応計画は必ずユーザー承認を取る**（Phase 3）
- **矛盾フィードバックは独断判断しない**（Phase 2.5）
- **resolved コメントは再対応しない**
- **`APPROVED` レビューのコメントは優先度を下げる**
- **commit / push の前に pre-push-review が PASS していること**
- **reset / amend 禁止**（履歴を残す）
- **各コミットメッセージに対応コメントを記載**
- **Copilot 依頼は push 後・返信後に実施**
- **PR が MERGED / CLOSED の場合は原則対応しない**（ユーザー明示指示時のみ続行）
- **品質非劣化原則**: triage-worker / fix-worker のプロンプトに毎回明記する

## 参照

| 引用元 | 引用要素 |
|--------|---------|
| `.claude-plugin/skills/handle-pr-comments/SKILL.md:29` | PR 番号正規化 |
| `.claude-plugin/skills/handle-pr-comments/SKILL.md:80-108` | コメント取得 3 API |
| `.claude-plugin/skills/handle-pr-comments/SKILL.md:127-166` | 妥当性検証原則 |
| `.claude-plugin/skills/handle-pr-comments/SKILL.md:204-223` | 同種問題 grep パターン例 |
| `.claude-plugin/skills/pre-push-review/SKILL.md` | `/pre-push-review` 仕様 |
| `.claude-plugin/rules/resource-aware-parallelism.md` | `MAX_LIGHT_AGENTS` (triage / scanner), `MAX_HEAVY_AGENTS` (fix-worker) |
| `.claude-plugin/rules/quality-checks.md` QC1-QC3 | 最終確認コマンド |
| MEMORY `feedback_copilot_review_request.md` | Copilot 依頼 REST 仕様 |
