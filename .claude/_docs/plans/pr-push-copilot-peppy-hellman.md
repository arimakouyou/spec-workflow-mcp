# プロジェクトローカル `/pr-review-response` skill 新設プラン

## Context

PR レビューコメントへの対応は現状 `handle-pr-comments`（プラグイン配布版と `.claude/skills/` の同期コピー）で賄っているが、実装は単一ファイルのモノリシックで、Command が全ステップを直列処理している。ユーザーが求めるのは「コメントの妥当性検証」「同種問題の網羅スキャン」「push 前最終レビュー」「Copilot へのレビュー依頼」を **エージェント委譲 + 複数同時起動** で高速に回せるワークフロー。既存 skill は残し、このプロジェクト固有のオーケストレーター skill を新設することで用途分離とロールバック容易性を確保する。MEMORY の「修正プッシュ後に REST API で Copilot へレビュー依頼」をワークフローに恒久組み込みし、auditor/reviewer 系の fail-open 懸念を引き続き排除する。

## 成果物

- **新 skill**: `.claude/skills/pr-review-response/SKILL.md`（プロジェクトローカル、日本語）
- **新 agents**（プロジェクトローカル、3 体構成）
  - `.claude/agents/pr-triage-worker.md` — 1 コメントを独立評価する read-only triager（haiku、並列）
  - `.claude/agents/pr-pattern-scanner.md` — 1 パターンを repo 全域 grep する read-only scanner（haiku、並列）
  - `.claude/agents/pr-fix-worker.md` — ファイル単位で Edit するシンプル修正 worker（sonnet、並列）。`parallel-worker` は TDD 契約に縛られるため流用せず、単純な Read→Edit→format ワークフロー専用に新設
- **既存再利用**
  - skill `pre-push-review` — 最終セルフレビュー（skill ツール経由で呼ぶ）
  - skill `handle-pr-comments`（プラグイン版）— 直接は呼ばないが、検証原則・検索ルール・steering 照合ロジックを文面で引き継ぐ

## スキル呼び出し形式

```
/pr-review-response <pr-number>
```

- `<pr-number>` は `#123` / `123` / URL いずれも受理（既存 skill と同じ正規化ロジック）
- 引数未指定時はユーザーに確認

## エージェント構成

### 新設: `pr-triage-worker`（.claude/agents/）

| 項目 | 値 |
|------|-----|
| model | haiku |
| tools | Read, Grep, Glob, advisor |
| memory | なし（エフェメラル） |
| 役割 | PR コメント 1 件を受け取り、対象 `path:line` を読み、steering/rules と照合、5 分類 + validity 判定を返す |
| 並列度 | N = コメント件数（triage は read-only / 軽量なので `resource-aware-parallelism.md` の MAX_LIGHT_AGENTS で制限、デフォルト 5） |
| 返答形式 | 最終メッセージで YAML を返す（fire-and-forget、SendMessage 不使用） |
| 副作用 | なし（Edit/Write なし、commit なし）|

入力プロンプト（Command から渡す）— **品質非劣化原則を毎回明記**:

```
PR番号: {number}
担当コメントID: {comment.id}
path: {comment.path}
line: {comment.line}
body: {comment.body}
reviewer: {comment.user}
resolved: {isResolved}
steering docs: .spec-workflow/steering/{product,tech,structure}.md
rules: .claude-plugin/rules/{design-principles,security,*-style}.md

【品質非劣化原則（必須）】
- 機械レビュアーの指摘を鵜呑みにしない。一見妥当でも、既存の品質ゲート・整合性を下げる方向の提案は `invalid` と判定する
- steering / rules と矛盾する指摘は `invalid`（該当ドキュメントへの参照を reason に付ける）
- 判断に迷う場合は advisor() を呼んで second opinion を得る
```

戻り値（最終メッセージ本文に YAML として）:

```yaml
comment_id: {id}
category: code_fix | question | style | approval | suggestion
validity: valid | partial | invalid
reason: "{判定根拠 — どの rule/steering と整合/矛盾したか}"
proposed_action: "{妥当時の修正方針 1-2 行}"
```

矛盾検出は Command 単独で triage 結果を突合する（Phase 2.5）。haiku triager のコンテキストに他コメント body を流し込まないことで並列コストを抑える。

### 新設: `pr-pattern-scanner`（.claude/agents/）

| 項目 | 値 |
|------|-----|
| model | haiku |
| tools | Read, Grep, Glob |
| memory | なし |
| 役割 | 指摘 1 件の「パターン（正規表現・抽象化したアンチパターン）」を受け取り、repo 全域を grep して同種出現箇所を列挙 |
| 並列度 | N = 妥当指摘ユニーク数 |
| 返答形式 | 最終メッセージで YAML を返す（fire-and-forget、SendMessage 不使用） |
| 副作用 | なし |

戻り値:

```yaml
pattern: "{検索パターン}"
additional_occurrences:
  - path: {path}
    line: {line}
    context: "{該当行抜粋}"
missing_from_fix_queue: [{path:line}, ...]  # Phase 4 に追加すべき修正対象
```

### 新設: `pr-fix-worker`（.claude/agents/）

`parallel-worker` は TDD 専用契約（worktree + test-design doc + Red→Green→Refactor）に縛られており、単純な指摘修正には不向き。専用 worker を新設する。

| 項目 | 値 |
|------|-----|
| model | sonnet |
| tools | Read, Edit, Write, Bash, Grep, Glob, advisor |
| memory | なし |
| 役割 | 1 ファイル分の修正指摘（複数行にまたがる可能性あり）を受け取り、Read→Edit→format で修正、必要なら該当ファイルの既存テストを走らせる |
| 並列度 | N = 影響ファイル数（MAX_HEAVY_AGENTS 制約） |
| 同時実行時の排他 | 同一ファイルへの指摘は必ず 1 worker に集約（edit conflict 回避） |
| 副作用 | Edit/Write あり、commit は **行わない**（commit は Command の責務）|

入力プロンプト雛形:

```
file: {path}
修正対象コメント:
- L{line1}: {body1}
- L{line2}: {body2}
...

【原則】
- 品質低下禁止。既存テストが通る状態を保つ
- 修正範囲は指摘された path に限定（他ファイルは触らない）
- 指摘の意図が曖昧な箇所は Edit せずに Command へ「skip」で返す
- format（rustfmt / dotnet format / prettier）を最後に実行して戻す
```

戻り値（最終メッセージで YAML）:

```yaml
file: {path}
changed_lines: [{start-end}, ...]
skipped_comments: [{id}, ...]   # 判断保留したコメント ID
summary: "{1-2 行}"
```

### 再利用: skill `pre-push-review`

- Skill ツール経由で `/pre-push-review --base origin/{baseRefName}` を呼び出す
- 判定 `push_ok` / `push_after_fix` / `fix_required` により分岐
- Critical / Moderate 検出時は Phase 4 に差し戻す（再 triage は不要、修正だけ）

## ワークフロー

全体構造: **Command → Triage 並列 → 矛盾検出 → 承認 → 修正 並列 → Scan 並列 → 必要なら再修正 → commit → pre-push-review → push → 返信+Copilot依頼**

> **重要な順序制約**: `pre-push-review` は `git diff base..HEAD` を見るため、Phase 5 終了時点で未コミットの差分があると検査対象から漏れる。そのため **Phase 5 の直後にまず commit**（Phase 5.5）、続いて pre-push-review（Phase 6）、最後に push（Phase 7）の順序にする。review の結果 `fix_required` なら **reset/amend は使わず、追加修正コミットを積む**（履歴を残すことで何が問題だったか追跡可能）。

### Phase 0: 前提条件チェック

既存 `handle-pr-comments` 相当を踏襲。`gh auth status` / リポジトリ確認 / PR 状態 / ワーキングツリー / `gh pr checkout`。いずれも失敗時は STOP。

### Phase 1: コメント取得

既存と同様、以下 3 種を取得:

1. `gh api repos/${OWNER}/${REPO_NAME}/pulls/{number}/comments --paginate` — inline レビューコメント
2. `gh api repos/${OWNER}/${REPO_NAME}/pulls/{number}/reviews --paginate` — レビューサマリ
3. `gh pr view {number} --json reviewThreads` — resolved 状態

resolved コメントは triage から除外。

### Phase 2: 並列トリアージ

`pr-triage-worker` を件数ぶん同時起動。triage は read-only / 軽量なので `resource-aware-parallelism.md` の `MAX_LIGHT_AGENTS` で上限制御。

```
Agent(subagent_type: "pr-triage-worker", prompt: <comment #1 context>)
Agent(subagent_type: "pr-triage-worker", prompt: <comment #2 context>)
...
```

単一メッセージ内で複数 Agent tool use を並べて同時発火させる。各 worker の戻り値を集約し、以下 4 バケットに分配:

| バケット | 条件 |
|---------|------|
| `auto_fix` | validity `valid` かつ category `code_fix` / `style` |
| `reply_only` | category `question` |
| `user_decision` | validity `partial` or category `suggestion` |
| `invalid_reject` | validity `invalid`（対応せず理由付きで返信） |

### Phase 2.5: 矛盾フィードバック検出（ユーザー承認の前段）

Phase 2 で集約した triage 結果について、以下を検査:

- Command が triage 結果を `path:line (±3 行)` でグルーピングし、同一グループ内で `proposed_action` / `reason` / 原文 `body` の語彙から相反する指摘を検出する（LLM 再呼び出し不要）
- 検出例: 同じ関数に対して「分割すべき」と「このままで良い」が両方ある / 同じ型に対して相反する命名指摘
- 検出した場合は対応計画に進む前に矛盾ペアをユーザーに提示し、どちらを優先するか判断を仰ぐ（各レビュアーの `APPROVED` / `CHANGES_REQUESTED` を参考情報として併記）

矛盾なし → Phase 3 へ。

### Phase 3: 対応計画の提示（ユーザー承認）

既存 skill 相当のテーブル形式で提示。トリアージ結果と Phase 2.5 の矛盾解消結果を要約し、ユーザーが承認するまで STOP。

### Phase 4: 並列修正

`auto_fix` + ユーザー承認した `user_decision` をファイル単位にグループ化し、ファイルごとに 1 `pr-fix-worker` を起動。同時実行数は MAX_HEAVY_AGENTS 上限。

```
Agent(subagent_type: "pr-fix-worker", description: "Fix: {file}",
      prompt: "<pr-fix-worker 入力プロンプト雛形に沿って埋める>")
Agent(subagent_type: "pr-fix-worker", description: "Fix: {file2}", prompt: ...)
...
```

単一メッセージ内で複数 Agent tool use を並べて同時発火。同一ファイルへの指摘は必ず同一 worker に集約する（edit conflict 回避）。戻り値 `skipped_comments` が空でない場合はユーザーに提示して判断を仰ぐ。

### Phase 5: 並列同種問題スキャン

Phase 4 完了後、各妥当指摘についてパターンを抽象化し `pr-pattern-scanner` を並列起動。

```
Agent(subagent_type: "pr-pattern-scanner", prompt: "pattern: <regex>\nexclude: {fixed paths}")
```

検出された追加箇所は Command が受け取り、以下で分岐:

- 0 件 → Phase 5.5 へ
- 1 件以上 → ユーザーに提示し「同パターンの残存箇所を追加修正するか」を確認、承認時は Phase 4 に戻って `pr-fix-worker` を追加起動（ループ上限 3 回、それ以降は `Escalated` として最終レポートに含めユーザー判断）

### Phase 5.5: 初回コミット（pre-push-review のための履歴作成）

Command が一括で add + commit する。`pr-fix-worker` は commit しない契約なので、この段階ですべての修正がまだ working tree にある。

```bash
git add {全 fix-worker の changed_files + pattern-scanner の追加修正ファイル}
git commit -m "fix: PR #{number} レビューコメント対応

対応コメント:
- {comment1 summary}
- ...
"
```

品質チェック（`.claude-plugin/rules/quality-checks.md` QC1-QC3）は `pr-fix-worker` 内で完了している前提。commit 直前に Command が最終確認として rustfmt/clippy を軽く走らせる。

> **reset/amend 禁止**: Phase 6 で `fix_required` になっても、この commit は書き換えず追加コミットを積む。

### Phase 6: pre-push セルフレビュー

```
Skill("pre-push-review", "--base origin/{baseRefName}")
```

判定分岐:

| verdict | アクション |
|---------|----------|
| `push_ok` | Phase 7 へ |
| `push_after_fix` | Minor の内容をユーザーに提示し、同意があれば Phase 4 に戻す／同意がなければ warning のまま Phase 7 |
| `fix_required` | Critical/Moderate finding を Phase 4 にフィードバックして再修正。**再修正ループでは Phase 5（pattern scan）をスキップ**し、4 → 5.5 → 6 のみを回す（review が指摘した既知の修正を当てるだけで、新規パターン探索ではない）。再度 Phase 5.5 で **追加コミット**（amend ではなく積み重ね）→ Phase 6 を再実行。最大 2 回まで繰り返し、それ以降は **escalate**（PASS に格下げしない — Codex 指摘の fail-open 回避方針と整合） |

### Phase 7: push

```bash
git push
```

push 後は履歴に Phase 5.5 と必要に応じた再修正の追加コミットが並ぶ。どこでどう直したかが後で追跡可能。

### Phase 8: コメント返信 + Copilot レビュー依頼

1. 対応した各コメントに返信を投稿（既存 skill と同じ `gh api` パターン）
2. `invalid` 判定したコメントには理由付き返信（steering/rules へのリンク付き）
3. **Copilot レビュー依頼**（MEMORY `feedback_copilot_review_request.md` に完全準拠）:

```bash
gh api repos/${OWNER}/${REPO_NAME}/pulls/{number}/requested_reviewers \
  --method POST \
  -f 'reviewers[]=copilot-pull-request-reviewer[bot]'
```

- slug は `copilot-pull-request-reviewer[bot]` （末尾 `[bot]` 必須、MEMORY 既述）
- `gh pr edit --add-reviewer` は bot 名を解決できないので使わない
- 失敗時（既に依頼済 / 権限エラー / bot 未設定）は warning のみでワークフローは成功扱いにし、完了レポートに記載

### Phase 9: 完了レポート

```
## PR #{number} レビューコメント対応完了

### Triage 結果
- auto_fix: {N} / reply_only: {M} / user_decision: {K} / invalid_reject: {L}

### 修正サマリ
- 修正ファイル: {N} ({parallel workers})
- 同種問題の追加修正: {M}（scanner 検出）

### 品質チェック
- pre-push-review: {verdict}
- quality gate (QC1-QC3): PASS

### Push
- commit: {hash}
- branch: {headRefName} → origin

### Copilot レビュー依頼
- 結果: 成功 | warning ({reason})

### 未対応（ある場合）
- {理由付きリスト}
```

## 改変ファイル一覧

| パス | 操作 | 用途 |
|------|------|------|
| `.claude/skills/pr-review-response/SKILL.md` | 新規 | オーケストレーター |
| `.claude/agents/pr-triage-worker.md` | 新規 | read-only triage agent (haiku) |
| `.claude/agents/pr-pattern-scanner.md` | 新規 | read-only pattern scanner (haiku) |
| `.claude/agents/pr-fix-worker.md` | 新規 | ファイル単位の修正 worker (sonnet) |

既存ファイルは変更しない（`handle-pr-comments` は併存）。プラグイン側 `.claude-plugin/` には手を入れない。

## 参照する既存ロジック（コピーではなく引用）

| 引用元 | 持ち込む要素 |
|--------|--------------|
| `.claude-plugin/skills/handle-pr-comments/SKILL.md:29` | PR 番号正規化 |
| `同:80-108` | コメント取得 3 API（REST + GraphQL reviewThreads） |
| `同:127-166` | 妥当性検証原則（steering/rules prior、品質下げ禁止、3 段階判定） |
| `同:204-223` | 同種問題の grep パターン例 |
| `.claude-plugin/skills/pre-push-review/SKILL.md` | `/pre-push-review` 呼び出し・結果解釈 |
| `.claude-plugin/rules/resource-aware-parallelism.md` | `MAX_LIGHT_AGENTS` (triage / scanner) / `MAX_HEAVY_AGENTS` (fix-worker) 参照 |
| `.claude-plugin/rules/quality-checks.md` QC1-QC3 | 最終確認コマンド |

SKILL.md 本文でもこれらへの行番号リンクを明示し、挙動がズレた際の突合箇所をはっきりさせる。

## Verification

skill 作成後、以下で動作確認する。

1. **triage 単体**: テスト用 PR（コメント 3 件程度）で `/pr-review-response <N>` を起動し、Phase 2 のトリアージが並列に実行されることをログで確認（各 worker 起動タイムスタンプがほぼ同時刻）
2. **scanner 単体**: 既知の同種問題を仕込んだ PR で Phase 5 が追加検出を返すか確認
3. **pre-push-review 統合**: わざと Moderate 相当の問題を残したまま通し、Phase 6 が `fix_required` を返し Phase 4 にループ、追加コミットが積まれることを確認（amend されていないこと）
4. **Copilot 依頼**: push 後に `gh api repos/.../pulls/{N}` を叩き、`requested_reviewers` に `copilot-pull-request-reviewer[bot]` が含まれていることを確認
5. **project-local agent discovery**: 初回実行時に `subagent_type: "pr-triage-worker"` 等が解決できるか確認。失敗時は `/` プレフィクスやプラグイン prefix などの代替記法を試す
6. **矛盾検出**: 同一行に相反する指摘を含む PR で Phase 2.5 がユーザー確認を挟むことを確認
7. **rollback**: skill を削除しても既存 `/handle-pr-comments` が無影響で動くことを確認
8. **既存テスト**: プラグイン本体を触らないためフロントテストは省略（CLAUDE.md 規則通り）

## 非対応 / Non-Goals

- プラグイン (`.claude-plugin/`) への変更（将来別 PR で検討）
- `copilot` CLI（`wingrs-paas-front-api` の `copilot-review` skill）との連携 — 今回は REST API で Copilot bot をレビュアー指定するに留める
- review-worker の worktree ベースフローとの統合（spec-implement 文脈では既存 `handle-pr-comments` を使い続ける）
- triage worker の分類結果を ML で学習させる仕組み（将来検討）
