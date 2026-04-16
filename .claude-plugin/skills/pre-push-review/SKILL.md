---
name: pre-push-review
description: "PUSH 前のセルフレビュー。未 push コミットの diff を .claude/_docs/know-how/pr-review-patterns.md のチェックリストで A-H カテゴリに分けて観察し、`codex` プラグイン導入時は `/codex:review` も併用。Critical / Moderate / Minor を報告する。PUSH 前・PR 作成前に使用。Triggers on: 'pre-push review', 'PUSH 前レビュー', 'セルフレビュー', 'review before push', 'checklist review', '/pre-push-review'."
user-invokable: true
argument-hint: "[--base <ref>] [--target <ref>] [--focus <category>] [--save] [--auto-fix]"
---

# PUSH 前セルフレビュー — チェックリスト駆動レビュー

未 push のコミット（またはユーザー指定の ref 範囲）に対して、`.claude/_docs/know-how/pr-review-patterns.md` のチェックリストで **A〜H 全カテゴリ** のセルフレビューを行い、push 前に修正すべき問題を検出する。

`codex` プラグインが導入されている場合は `/codex:review` も併用して観点を重層化する。

## 呼び出し形式

`/pre-push-review [--base <ref>] [--target <ref>] [--focus <category>]`

## 入力

| 引数 | デフォルト | 説明 |
|------|-----------|------|
| `--base <ref>` | `origin/main` | 比較対象の base ref。`origin/develop`、`HEAD~3`、タグなども可 |
| `--target <ref>` | `HEAD` | レビュー対象の上限 ref。通常は `HEAD`（カレントブランチの最新） |
| `--focus <category>` | なし | 観点をカテゴリに絞る（A〜H のいずれか、カンマ区切り複数可）。省略時は A-H 全カテゴリ |
| `--save` | なし | レビュー結果を `.claude/_docs/reviews/pre-push-{YYYY-MM-DD-HHMM}.md` に保存 |
| `--auto-fix` | なし | Minor 指摘のみが検出された場合に修正を提案（ユーザー確認必須、勝手に適用しない）|

**呼び出し例**:
- `/pre-push-review` — `origin/main..HEAD` を A-H 全カテゴリでレビュー
- `/pre-push-review --base origin/develop` — 別 base で比較
- `/pre-push-review --focus A,C` — 整合性 + ドキュメント乖離のみ
- `/pre-push-review --target HEAD~2` — 最新 2 コミット除外

## 実行コンテキスト

| コンテキスト | 使用タイミング |
|-------------|---------------|
| **スタンドアロン実行** (`/pre-push-review` を直接呼ぶ) | 手動セルフレビュー。`git push` または `/create-pr` の直前 |
| **`/handle-pr-comments` から内部参照** | PR レビュー対応で修正を加えた後、同スキルから自動的に呼ばれる |
| **spec-implement / wave-harness から内部参照** | review-worker が最終コミット前に呼ぶ（オプション）|

## 前提条件チェック (MANDATORY)

前提条件の Bash 例は `set -euo pipefail` 相当の堅牢性で記述する。外部コマンド依存は `command -v` ガードを置く（本スキル自身が pr-review-patterns.md のカテゴリ B「シェル堅牢性」の基準を自己適用する）。以下を順番に確認し、失敗時は **STOP** して案内する。

0. **依存コマンドの存在確認**
   ```bash
   command -v git >/dev/null 2>&1 || { echo "git が見つかりません"; exit 127; }
   # gh は codex プラグイン検出や `/codex:review` 連携時にのみ必要。未導入でも本スキルは動く
   ```
1. **現在位置が git リポジトリのルート**
   ```bash
   git rev-parse --show-toplevel >/dev/null 2>&1 || { echo "git リポジトリ内で実行してください"; exit 1; }
   ```
2. **`--base` ref の存在確認**
   ```bash
   git rev-parse --verify "<base>" >/dev/null 2>&1 || { echo "'<base>' ref が存在しません"; exit 1; }
   ```
3. **`--target` ref の存在確認**（同上）
4. **base..target の差分が空でない**
   ```bash
   count=$(git rev-list --count "<base>..<target>")
   [ "$count" -eq 0 ] && { echo "レビュー対象の差分がありません"; exit 0; }
   ```
5. **チェックリストファイル存在確認**
   ```bash
   if [ ! -f .claude/_docs/know-how/pr-review-patterns.md ]; then
     echo "[pre-push-review] WARNING: pr-review-patterns.md が未作成です。generic チェックリスト（A-H のヘッダーのみ）で続行します"
   fi
   ```
   存在しない場合は警告のみで続行（know-how 未整備プロジェクトでも動く）。

## 処理フロー

### 1. 対象コミット・ファイル把握

```bash
git log --oneline "<base>..<target>"
git diff --stat "<base>..<target>"
```

ログ出力:
```
[pre-push-review] Base: <base>, Target: <target>
[pre-push-review] Commits: N, Files: M, +A -D lines
```

### 2. チェックリスト読込

`.claude/_docs/know-how/pr-review-patterns.md` を Read し、A-H カテゴリ各々の「PUSH 前チェック」箇条書きを抽出する。`--focus` が指定されていれば該当カテゴリのみ使用。

### 3. カテゴリ別レビュー

各カテゴリについて以下を実行:

| カテゴリ | レビュー手法 |
|---------|-------------|
| **A. 整合性 / 重複** | 新規 ID 規約（FC/DR/SD 等）を grep で全参照洗い出し、キー名・用語・コマンド揺れを検出。INDEX.md の件数計算検算 |
| **B. シェル堅牢性** | `.sh` / `.yml` / hook 系の `pipefail` / `command -v` / `|| true` / `$1`-`$9` 未検証 / BSD 移植性 |
| **C. ドキュメント乖離** | README / TOOLS-REFERENCE / guides 内の旧名・旧パス・存在しないツール、ネストフェンス |
| **D. プロセス / CI** | `.github/workflows/` の `permissions` / fork PR / listComments pagination / `{{TOOLCHAIN}}` プレースホルダ |
| **E. 設計適合 / スキーマ** | 既存パーサ（`task-parser.ts` / `ImplementationLogManager` 等）と出力形式の一致、dashboard silent drop のリスク |
| **F. セキュリティ** | path 境界（`safeJoin`）、JSON escape、permissive glob、fork PR secrets |
| **G. ID / 命名揺れ** | 同一概念が複数名で登場していないか |
| **H. テスト品質** | テスト追加があればアサーションの質、hook/shell script の未テスト |

実施:
1. Read で該当ファイルを確認
2. Grep で同種問題の網羅調査
3. `--focus` で絞られていない限り全カテゴリを順次実施

### 4. codex プラグインの併用検出

`/codex:review` が使える環境かを検出:

- Claude Code 起動時に `codex` プラグインの Skills がロードされている場合、Skill 一覧に `codex:review`（または類似名）が含まれる
- 存在する場合は Skill ツールで `/codex:review` を同一 diff に対して実行し、結果を本レビューの findings と重ね合わせる
- 存在しない場合は「codex プラグイン未導入のためスキップ」とログに明記

codex と本スキルの findings が競合した場合:
- **本スキル findings が prior**（know-how は本プロジェクト固有の実害パターンで、codex は一般的な静的観点）
- ただし codex が独自に検出した新規観点は Findings セクションに `source: codex` を付けて併記

### 5. Review Observation Log

`review-worker.md` の Anti-Bias Protocol と同じ形式（同 protocol は A-G、本スキルは A-H に拡張）で、A-H 各カテゴリに `checked-ok` / `finding` / `auto-fixable` のいずれかを記録する。**「問題なし」だけは不可、具体的に何を確認したか書く**:

```markdown
## 観察ログ
- **A（整合性）**: checked-ok — XxxPlan の FC ID は INDEX.md 合計 N ルールと一致、grep で key 名 unified 確認
- **B（shell）**: checked-ok: 該当なし — shell 変更なし
- **C（ドキュメント）**: finding — `XXX.md:L` で旧名 `old_skill` が残存
- ...
```

### 6. Findings 出力

pr-review-patterns.md の Severity（Critical / Moderate / Minor）で分類:

```markdown
## Findings

### Critical
（なければ「なし」）

### Moderate
1. **カテゴリ / 具体パターン名**
   - ファイル:行
   - 内容: 何が問題か
   - 期待: どうあるべきか
   - 提案: 具体的修正案
   - source: self | codex

### Minor
...

## 総合判定

- **PUSH 可** / **軽微修正後 PUSH 可** / **重要修正必要** のいずれか
- 修正候補件数: Critical N, Moderate M, Minor K
- codex 併用: 使用 / 未導入でスキップ
```

### 7. 自動修正の提案（任意）

`--auto-fix` が指定されており、Minor 指摘のみが検出された場合は修正を提案（ユーザー確認必須、勝手に適用しない）。

## 呼び出し元への返却値

```yaml
status: ok | warn | fail
commits_reviewed: <number>
files_reviewed: <number>
findings:
  critical: <number>
  moderate: <number>
  minor: <number>
codex_used: true | false
verdict: push_ok | push_after_fix | fix_required
findings_file: <path if saved — optional>
```

## 成果物の保存（任意）

`--save` が指定されていれば、レビュー結果を
`.claude/_docs/reviews/pre-push-{YYYY-MM-DD-HHMM}.md` に保存（ディレクトリが無ければ作成）。PR description に貼り付けたり、履歴として保持したりする用途。

## Rules

- **Read-only 原則**: このスキル自体はコード/ドキュメントを改変しない（`--auto-fix` が明示された場合を除き、ユーザー承認なしに修正しない）
- **Severity 整合**: findings の severity は `failure-taxonomy.md` FC3 の Minor/Moderate/Critical に揃える（`low/medium/high/critical` は使わない）
- **Anti-Bias**: 「全カテゴリ問題なし」の結論が出た場合、もう一度 diff を読み直して見落としがないか確認（review-worker の Anti-Bias Protocol と同方針）
- **Self-contained**: pr-review-patterns.md が未整備の環境でも、A-H のヘッダーのみで動作する（generic モード）
- **codex 優先順位**: codex 併用時は **本スキル findings を prior** とする（プロジェクト固有の実害パターンを優先）
