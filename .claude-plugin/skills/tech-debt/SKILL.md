---
name: tech-debt
description: >
  技術的負債を .claude/_docs/tech-debt/ にレジスタ形式で記録・管理する。
  ID 付きエントリ (TD-NNNN) で優先度・工数・ステータスを追跡し、
  定期的なレビューで解消計画を維持する。
  ADR（決定記録）とは別管理: ADR は「意思決定」、tech-debt は「既知の問題と改善計画」。
  Triggers: 'record tech debt', 'tech debt', '技術的負債', 'add debt', '/tech-debt'.
argument-hint: "[add|list|update <TD-ID> --status <status>|audit]"
user-invokable: true
---

# Tech Debt Register

技術的負債を `.claude/_docs/tech-debt/` にレジスタ形式で記録・管理するスキル。
P5-02（技術的負債がrepo内で一覧管理されている）に対応する。

## ディレクトリ構造

```
.claude/_docs/tech-debt/
  INDEX.md              # 一覧（優先度順テーブル）
  TD-0001-slug.md       # 個別エントリ
  TD-0002-slug.md
```

## 引数パース

| サブコマンド | 引数 | 説明 |
|------------|------|------|
| `add` | (なし — 対話的に収集) | 新規エントリ作成 |
| `list` | (なし) | INDEX.md を読み取って一覧表示 |
| `update` | `<TD-ID> --status <status>` | ステータス更新 |
| `audit` | (なし) | コードベース走査で潜在的 tech debt を検出 |

## 操作: add

### Step 1: 情報収集

ユーザーから以下の情報を収集する（省略された場合は対話で確認）:

| フィールド | 必須 | 説明 |
|-----------|------|------|
| タイトル | Yes | 負債の簡潔な説明 |
| 概要 | Yes | 負債の内容と所在 |
| 影響 | Yes | この負債が引き起こす問題 |
| 優先度 | Yes | Critical / High / Medium / Low |
| 工数見積 | Yes | S(1-2h) / M(half-day) / L(1-3d) / XL(1w+) |
| 改善計画 | No | 修正方法（後で追記可） |
| 関連 ADR | No | 関連する ADR の ID（例: ADR-0003） |

### Step 2: ID 採番

`.claude/_docs/tech-debt/` 内の既存ファイルを走査し、最大 ID + 1 を採番する:

```bash
# 既存の最大 ID を取得
MAX_ID=$(ls .claude/_docs/tech-debt/TD-*.md 2>/dev/null | \
  grep -oP 'TD-\K\d+' | sort -n | tail -1)
NEXT_ID=$(printf "%04d" $((${MAX_ID:-0} + 1)))
```

### Step 3: ファイル作成

`.claude-plugin/skills/tech-debt/references/tech-debt-template.md` のテンプレートに従い、
`.claude/_docs/tech-debt/TD-{NEXT_ID}-{slug}.md` を作成する。

slug はタイトルを kebab-case に変換して生成する（例: "古い認証ミドルウェア" → `legacy-auth-middleware`）。

### Step 4: INDEX.md 更新

`.claude/_docs/tech-debt/INDEX.md` に行を追加する。INDEX.md が存在しない場合は新規作成:

```markdown
# Tech Debt Register

| ID | タイトル | ステータス | 優先度 | 工数 | 作成日 | 関連 ADR |
|----|---------|----------|--------|------|--------|---------|
| TD-0001 | [タイトル] | Open | High | M | 2026-04-08 | — |
```

テーブルは優先度順（Critical > High > Medium > Low）でソートする。

## 操作: list

INDEX.md を読み取り、ステータスでフィルタリングして表示する:

```
Tech Debt Register:
  Open: 3 件 (Critical: 1, High: 1, Medium: 1)
  In-Progress: 1 件
  Resolved: 2 件
  Accepted: 0 件

[INDEX.md のテーブルを表示]
```

## 操作: update

指定された TD-ID のエントリファイルの frontmatter を更新する:

| ステータス遷移 | 許可 | 備考 |
|--------------|------|------|
| Open → In-Progress | Yes | 作業開始 |
| Open → Accepted | Yes | 負債を許容する判断（意図的に修正しない） |
| In-Progress → Resolved | Yes | `resolved` フィールドに日付を記入 |
| In-Progress → Open | Yes | 作業中断 |
| Resolved → Open | Yes | 再発した場合 |

INDEX.md のステータス列も同時に更新する。

## 操作: audit

コードベースを走査して潜在的な技術的負債を検出する。

### 検出シグナル

```bash
# TODO/FIXME/HACK コメントの検出
grep -rn 'TODO\|FIXME\|HACK\|XXX\|WORKAROUND' src/ --include='*.rs' --include='*.ts' --include='*.js' 2>/dev/null

# 300行超の大きなファイル（複雑性の兆候）
find src/ -name '*.rs' -o -name '*.ts' -o -name '*.js' 2>/dev/null | while read f; do
  lines=$(wc -l < "$f")
  [ "$lines" -gt 300 ] && echo "LARGE_FILE ($lines lines): $f"
done

# 古い依存関係（Rust）
cargo outdated --depth 1 2>/dev/null | grep -v "Up to date"

# 古い依存関係（Node.js）
npx npm-check-updates 2>/dev/null | grep -v "All dependencies"
```

### レポート

```markdown
## Tech Debt Audit Report — {DATE}

### 検出された潜在的負債

| # | シグナル | ファイル/箇所 | 既存エントリ | 推奨アクション |
|---|---------|-------------|------------|--------------|
| 1 | TODO コメント (5件) | src/handlers/auth.rs | なし | `/tech-debt add` |
| 2 | 大規模ファイル (450行) | src/services/payment.rs | TD-0003 | 既存エントリで管理中 |
| 3 | 古い依存 (3件) | Cargo.toml | なし | `/tech-debt add` |
```

各項目について、ユーザーに `/tech-debt add` で登録するか確認する。
既存の tech-debt エントリでカバーされている場合はスキップする。

## ADR との関係

| 記録対象 | 使用先 | 例 |
|---------|--------|-----|
| 意思決定とその根拠 | ADR (`/adr`) | "PostgreSQL を選定、DynamoDB は却下" |
| 既知の問題と改善計画 | Tech Debt (`/tech-debt`) | "認証ミドルウェアが古く、セッショントークンの保存方法がコンプライアンス要件を満たしていない" |

ADR の結果として生じた tech debt は `related-adr` フィールドでリンクする。

## Know-how からの昇格

`/knowhow-capture` で記録された know-how のうち、個別の tips ではなく構造的・慢性的な問題であるものは
`/tech-debt add` に昇格させる。feedback-loop.md FL4 の昇格パスを参照。

## Notes

- ファイル作成後の staging/commit はユーザーが明示的に要求した場合のみ実行する
- Accepted ステータスは「修正しない」という意図的な判断。理由を概要セクションに記載すること
- doc-freshness.md により、90日以上 Open のエントリはレビュー対象となる
