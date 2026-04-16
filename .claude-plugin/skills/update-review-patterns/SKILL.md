---
name: update-review-patterns
description: "マージ済 PR のレビューコメントを分析し、`.claude/_docs/know-how/pr-review-patterns.md` のチェックリストを追記・更新する。新規カテゴリの検出、既存カテゴリへの代表例追加、カテゴリ別件数の再集計を行う。通常は PR マージ直後に手動起動。Triggers on: 'update review patterns', 'update checklist', 'pr-review-patterns を更新', 'refresh review patterns', '/update-review-patterns'."
user-invokable: true
argument-hint: "[--pr <N>[,<N>...]] [--since <YYYY-MM-DD>] [--auto] [--dry-run]"
---

# PR レビューパターン更新 — チェックリスト保守

マージされた PR のレビューコメントを取得・分析し、`.claude/_docs/know-how/pr-review-patterns.md` のチェックリストを更新する。新しい指摘パターンを既存 A-H カテゴリに追記、または新規カテゴリを追加する。

## 呼び出し形式

`/update-review-patterns [--pr <N>[,<N>...]] [--since <YYYY-MM-DD>] [--auto] [--dry-run]`

## 入力

| 引数 | 説明 |
|------|------|
| `--pr <N>` | 対象 PR 番号（カンマ区切り複数可、例: `54,56,58`）。指定時は該当 PR のみ分析 |
| `--since <date>` | 指定日以降にマージされた全 PR を対象（例: `2026-04-01`） |
| `--auto` | 対象を自動選定（pr-review-patterns.md の「生成日」以降にマージされた PR）|
| `--dry-run` | ファイルを更新せず、更新差分のみ表示 |

**呼び出し例**:
- `/update-review-patterns --pr 54` — PR #54 のコメントのみ分析して更新
- `/update-review-patterns --since 2026-04-01` — 4/1 以降の全マージ PR
- `/update-review-patterns --auto` — 前回更新以降の全 PR（最も一般的）
- `/update-review-patterns --auto --dry-run` — 更新内容を確認してから反映

いずれも未指定の場合はユーザーに `--auto` で良いか確認する。

## 実行コンテキスト

| コンテキスト | 使用タイミング |
|-------------|---------------|
| **マージ直後の手動起動** | 自分または他メンバーの PR がマージされた直後、次の PR を作る前に反映 |
| **週次・月次の定期更新** | `--since` で期間指定し、まとめて反映 |
| **SessionStart hook** (オプション) | セッション開始時に `--auto` を走らせ、前回以降の PR を自動反映。ただし確認プロンプトが出るため、デフォルト有効化は非推奨 |

## 前提条件チェック (MANDATORY)

1. **gh CLI 認証**
   ```bash
   gh auth status
   ```
2. **pr-review-patterns.md の有無を確認し、処理モードを分岐**
   ```bash
   if [ -f .claude/_docs/know-how/pr-review-patterns.md ]; then
     MODE=update
   else
     MODE=initial
   fi
   ```
   - `MODE=update`: 既存ファイルを追記・更新する通常フロー（以降の手順 1〜8）
   - `MODE=initial`: ユーザーに初回生成の可否を確認し、承認された場合のみ「pr-review-patterns.md 新規生成モード」節の手順に入る。拒否された場合は **STOP**
3. **リポジトリ情報の取得と変数定義**
   ```bash
   REPO=$(gh repo view --json nameWithOwner -q '.nameWithOwner')
   OWNER="${REPO%%/*}"
   REPO_NAME="${REPO##*/}"
   ```
   以降の API コール（`gh api repos/${OWNER}/${REPO_NAME}/...`）では `${OWNER}/${REPO_NAME}` を使用する。
4. **対象 PR リストの確定** — 引数から解決できない場合はユーザー確認

## 処理フロー

### 1. 対象 PR の取得

`--auto` の場合: pr-review-patterns.md の `生成日` を読み、それ以降に `merged` になった PR を列挙:
```bash
gh pr list --state merged --search "merged:>={date}" --limit 100 --json number,mergedAt
```

`--pr` / `--since` は指定どおりに列挙。

対象 0 件の場合は `[update-review-patterns] 新規対象 PR なし。pr-review-patterns.md は最新です` と報告して終了。

### 2. レビューコメント収集

各 PR について:
```bash
gh api --paginate "repos/${OWNER}/${REPO_NAME}/pulls/{N}/comments"
gh api --paginate "repos/${OWNER}/${REPO_NAME}/pulls/{N}/reviews"
gh api --paginate "repos/${OWNER}/${REPO_NAME}/issues/{N}/comments"
```

除外:
- bot の定型概要（Copilot "Pull request overview" / dependabot 通知等、**ただしレビュー指摘本体は含める**）
- 自分の返信コメント（user === 自分）
- 既に pr-review-patterns.md に代表例として収録されている PR のコメント（`PR #N` を grep）

### 3. 分類・追記候補の抽出

各コメントを pr-review-patterns.md の既存カテゴリ（A〜H）に分類:

- **既存カテゴリにマッチ** → そのカテゴリの「代表例」セクションに追加候補
- **どのカテゴリにも該当しない** → 新規カテゴリ候補として別リストに集積（ユーザー承認後に新規セクション追加）
- **既存の代表例と同種** → カウントのみ増分（代表例は追加せず、メタ情報の件数だけ更新）

分類観点（既存 A-H）:
1. A: 整合性 / 重複
2. B: シェル堅牢性
3. C: ドキュメント乖離
4. D: プロセス / CI
5. E: 設計適合 / スキーマ
6. F: セキュリティ
7. G: ID / 命名揺れ
8. H: テスト品質

### 4. 差分プレビュー

以下を組み立てて表示（`--dry-run` 時はこれで終了）:

```markdown
## 更新プレビュー

### メタ情報の更新
- 対象 PR 数: +M 件（{list of PR numbers}）
- 追加コメント数: +N 件
- 生成日: {old} → {new}

### カテゴリ件数の更新
| カテゴリ | 旧件数 | 新件数 | 差分 |
|---------|-------|-------|------|
| A | 158 | 167 | +9 |
...

### 追加される代表例
**A. 整合性 / 重複**
- PR #N: 指摘要約（新規代表例）

**C. ドキュメント乖離**
- PR #N: ...

### 新規カテゴリ候補（ユーザー承認必要）
- なし / あれば詳細
```

### 5. ユーザー承認

`--dry-run` 以外の場合は以下のいずれかを選ばせる:

1. **全部適用**: プレビュー通り全部反映
2. **部分適用**: 追加する代表例と新規カテゴリを個別に yes/no
3. **キャンセル**: 更新しない

### 6. ファイル更新

承認された変更を pr-review-patterns.md に反映:

- メタ情報の「生成日」「対象 PR 数」「総レビューコメント数」「カテゴリ別件数」を更新
- 各カテゴリの「代表例」セクションに新規指摘を追記（PR 番号とファイル:行 付き）
- 新規カテゴリが承認されている場合、H の後に追加（ID は新たに振る、例: I, J...）
- 「生成方法」セクションの実行例も更新

### 7. `.claude/_docs/know-how/INDEX.md` の更新（必要時）

カテゴリが増えた場合は `.claude/_docs/know-how/INDEX.md` の要約も更新する。

### 8. 完了レポート

```markdown
## 更新完了

- 対象 PR: {N 件、番号リスト}
- 追加コメント: {件数}
- 新規代表例: {件数}
- 新規カテゴリ: {件数または「なし」}
- ファイル: `.claude/_docs/know-how/pr-review-patterns.md` 更新済み
- 推奨アクション: このファイル単独でコミット（他の機能変更と混ぜない）
```

## hook への統合（オプション、デフォルト無効）

SessionStart や PR マージ後の自動実行を希望する場合、`.claude/settings.local.json` に以下を追加:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "type": "prompt",
        "prompt": "If there are merged PRs since the last update of pr-review-patterns.md, run /update-review-patterns --auto --dry-run and ask the user whether to apply."
      }
    ]
  }
}
```

ただし確認プロンプトが出るため、毎回の session start で邪魔に感じる場合は有効化しない。

## pr-review-patterns.md 新規生成モード

pr-review-patterns.md が存在しない場合、本スキルで初回生成も可能:

1. ユーザーに初回生成の確認
2. `gh pr list --state merged --limit 100` で全 merged PR を対象に分析
3. A-H カテゴリの初期値と件数を集計
4. ひな型（メタ情報 / 各カテゴリのチェック箇条書き / 代表例）を生成
5. `.claude/_docs/know-how/INDEX.md` にも登録

初期生成時は analysis が重いので、3 Agent に分割する（既存 pr-review-patterns.md の「生成方法」節参照）。

## Rules

- **承認必須**: `--dry-run` 以外の場合、書き出し前に必ずユーザー承認を取る
- **既存の Structure 尊重**: 追記で pr-review-patterns.md の章構造を壊さない（メタ情報 / A-H / 単発指摘 / 歴史的指摘 / 生成方法）
- **重複排除**: 同一の指摘を複数回記録しない（PR 番号 + 該当ファイル:行で同一性判定）
- **Scope 限定**: 本スキルは **`.claude/_docs/know-how/pr-review-patterns.md` と `.claude/_docs/know-how/INDEX.md` のみ** を更新する。他ファイルは一切触らない
- **PR 単独コミット推奨**: 更新後は `.claude/_docs/know-how/pr-review-patterns.md` と `.claude/_docs/know-how/INDEX.md` のみを含む独立コミットにする（機能変更とミックスしない）
