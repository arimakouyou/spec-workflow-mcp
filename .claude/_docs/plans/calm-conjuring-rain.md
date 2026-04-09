# Plan: ライブラリバージョンの最新化と Phase Review での CVE 検査

## Context

公開ワークフローの Phase 2 (設計) で Key Design Decisions や Required Build Tools テーブルに記載するライブラリバージョンが、AI の学習データに基づくため古いことが多い。

**目的**:
1. Phase 2 で最新ライブラリバージョンを WebSearch で検索して採用する
2. 最終レビュー (Phase Review) でライブラリに CVE がないかを検査する

**対象外**: 実装中 (Phase 5 Step 0) のバージョン検査は不要。実装中に新バージョンがリリースされても採用不要。

---

## 現状分析

### Phase 2 (設計) — バージョン指定の現状
- `spec-design/SKILL.md` Wave 1 step 5「Key Design Decisions」で技術選定・バージョンを記述
- Wave 2「Required Build Tools」テーブルに Min Version を記載
- **問題**: バージョンは AI の学習データ由来で検証されていない

### Phase Review — CVE検査の現状
- `phase-review-team/SKILL.md` のセキュリティ担当2が既に:
  - Cargo.toml の依存クレート＋バージョンを一覧化
  - WebSearch で各クレートの CVE を検索
  - `cargo audit` をフォールバックとして実行
  - OWASP A06「脆弱で古くなったコンポーネント」を確認
- **問題**: `cargo audit` の実行が専門家の裁量に委ねられ、必須ステップとして強制されていない

---

## 変更対象ファイル

| # | ファイル | 操作 | 内容 |
|---|---------|------|------|
| 1 | `.claude-plugin/skills/spec-design/SKILL.md` | 編集 | Wave 1 にバージョン検証ステップ追加 |
| 2 | `.claude-plugin/skills/spec-test-design/SKILL.md` | 編集 | Section 3.3 にバージョン検証追加 |
| 3 | `.claude-plugin/skills/spec-implement/SKILL.md` | 編集 | Phase Review (3.5.1.5) に CVE 監査ステップ追加 |
| 4 | `src/markdown/templates/design-template.md` | 編集 | Notes にバージョン検証注記追加 |
| 5 | `src/markdown/templates/test-design-template.md` | 編集 | Notes にバージョン検証注記追加 |

---

## Step 1: spec-design SKILL.md — バージョン検証ステップ追加

**ファイル**: `.claude-plugin/skills/spec-design/SKILL.md`

Wave 1 の step 3 で「5. Key Design Decisions」を記述した後、step 4「Architecture Confirmation」の前（L105 付近）に新ステップを挿入:

```markdown
### 3.5 Version Freshness Verification (MANDATORY)

Key Design Decisions の記述後、記載した全てのライブラリ・フレームワークのバージョンが最新安定版であることを検証する。AI の学習データに基づくバージョンは古い可能性がある。

#### 3.5.1 バージョン情報の抽出

Key Design Decisions セクションから技術名＋バージョンのペアを全て収集する（例: 「Leptos 0.7」「Diesel 2.2」「Axum 0.8」）。

#### 3.5.2 最新安定版の確認

収集した各ライブラリについて、以下の優先順で最新安定版を確認する:

1. **WebSearch**（推奨）:
   - 検索: "{ライブラリ名} latest stable release"
   - 検索: "{ライブラリ名} crates.io"（Rust）/ "{パッケージ名} npm"（Node.js）

2. **context7 MCP**（補助）:
   - resolve-library-id でライブラリを特定
   - query-docs で最新バージョンやチェンジログを確認

3. **レジストリ CLI フォールバック**（Web ツール利用不可時）:
   ```bash
   # Rust
   cargo search {crate_name} --limit 1
   # Node.js
   npm view {package_name} version
   ```

#### 3.5.3 バージョン更新

検証結果をテーブルにまとめ、Key Design Decisions を更新する:

| Library | Design Version | Latest Stable | Action |
|---------|---------------|---------------|--------|
| {name} | {old} | {new} | Updated / Kept (理由) |

- Key Design Decisions のバージョンを最新安定版に更新
- **例外**: steering ドキュメント（tech.md 等）が互換性のため特定バージョンを指定している場合は維持し理由を注記
- **メジャーバージョン変更**: 設計版と最新版のメジャーバージョンが異なる場合、Architecture Confirmation (step 4) でユーザーに報告
```

また、Wave 2 の Required Build Tools 導出ルール（L226-231）の後に追加:

```markdown
6. Min Version は step 3.5 で検証した最新安定版を反映すること。AI の学習データのデフォルト値を使用しない
```

## Step 2: spec-test-design SKILL.md — テストツールバージョン検証追加

**ファイル**: `.claude-plugin/skills/spec-test-design/SKILL.md`

Section 3.3（L104-123）の末尾に追加:

```markdown
#### 3.3.1 テストツールバージョン検証

Required Test Tools テーブルの各ツールについて、Min Version が最新安定版であることを確認する:

1. WebSearch またはレジストリ CLI で最新安定版を確認
   - 検索: "{ツール名} latest version"
   - CLI: `cargo search {crate}` / `npm view {pkg} version`
2. Min Version を検証済みの最新安定版に更新

Phase 2 step 3.5 と同様、AI の学習データのデフォルト値を使用しない。
```

## Step 3: spec-implement SKILL.md — Phase Review に CVE 監査ステップ追加

**ファイル**: `.claude-plugin/skills/spec-implement/SKILL.md`

Phase Review の統合検証 (3.5.1.5) の後、Expert Team Review (3.5.2) の前（L268-270 の間）に新ステップを挿入:

```markdown
#### 3.5.1.6 CVE Audit (依存脆弱性監査)

Expert Team Review の前に、依存ライブラリの脆弱性を機械的に検査する。

**Step A: 監査ツール実行**

| プロジェクトタイプ | 検出条件 | 監査コマンド |
|----------------|----------|------------|
| Rust | `Cargo.lock` 存在 | `cargo audit` |
| Node.js | `package-lock.json` / `yarn.lock` 存在 | `npm audit` |
| 両方 | 両ファイル存在 | 両方実行 |

ロックファイルが存在しない場合は SKIP（新規プロジェクトで依存未解決）。

`cargo audit` 未インストールの場合:
```bash
cargo audit --version 2>&1 || echo "NOT_INSTALLED"
```
未インストールなら `cargo install cargo-audit` をユーザーに提案（Step 0.3 のユーザー承認ルールに従う）。インストールを拒否された場合は SKIP とし、Expert Team Review のセキュリティ担当に委ねる。

**Step B: 結果分類**

| 重大度 | アクション |
|-------|----------|
| Critical / High | CVE_FOUND リストに追加 |
| Medium / Low | 警告ログに記録 |

**Step C: 結果の引き渡し**

CVE 監査結果を Expert Team Review の入力に追加する:

```
CVE Audit Results:
- cargo audit: {PASS / N件の脆弱性検出 / SKIP}
- npm audit: {PASS / N件の脆弱性検出 / SKIP / N/A}
- Critical/High CVEs: {CVE_FOUND リスト or なし}
```

Expert Team Review のセキュリティ担当がこの結果を踏まえてレビューし、Verdict（PASS / NEEDS_REWORK / BLOCK）を判定する。CVE の深刻度と対応方針の最終判断はセキュリティ担当に委ねる。
```

## Step 4: design-template.md — バージョン検証注記追加

**ファイル**: `src/markdown/templates/design-template.md` (L118-121 の Notes 後)

追加:
```markdown
- **Version Verification**: Min Version は AI の学習データのデフォルト値を使用しない。WebSearch またはレジストリ CLI（`cargo search` / `npm view`）で最新安定版を確認し反映すること（Phase 2 step 3.5 参照）
```

## Step 5: test-design-template.md — バージョン検証注記追加

**ファイル**: `src/markdown/templates/test-design-template.md` (L40-43 の Notes 後)

追加:
```markdown
- **Version Verification**: Min Version は AI の学習データのデフォルト値を使用しない。WebSearch またはレジストリ CLI で最新安定版を確認し反映すること
```

---

## 実装順序

```
Step 4 (design-template.md)       ─┐
Step 5 (test-design-template.md)   ─┤── テンプレート注記（並列可）
Step 1 (spec-design SKILL.md)      ── Phase 2 バージョン検証
Step 2 (spec-test-design SKILL.md) ── Phase 3 テストツールバージョン検証
Step 3 (spec-implement SKILL.md)   ── Phase Review CVE監査
```

## 後方互換性

- Phase 5 Step 0 (ツール検証) は一切変更なし
- Phase Review の Expert Team 構成・Verdict 判定ロジックは変更なし（CVE 監査結果を入力として追加するのみ）
- 既存の Phase 2/3 承認済みドキュメントへの影響なし（新規作成時のみ適用）

## 検証方法

1. **Phase 2 検証**: `/spec-design` を実行し、Key Design Decisions 記述後に step 3.5 のバージョン検証テーブルが WebSearch 結果に基づいて生成されることを確認
2. **Phase Review 検証**: Phase Review タスク実行時に step 3.5.1.6 で `cargo audit` が実行され、結果が Expert Team Review に渡されることを確認
