# Plan: cargo-udeps / cargo-audit / cargo-mutants ワークフロー統合

## Context

プラグインの品質チェックワークフローに3つの cargo ツールを追加する。現在 `quality-checks.md` には `cargo fmt` / `cargo clippy` / `cargo test` / `cargo leptos build` の4段階があるが、依存関係の衛生管理（未使用・脆弱性）とテスト品質の検証（ミューテーション）が欠けている。

- **cargo-udeps**: 未使用依存の検出（nightly 必要）
- **cargo-audit**: 既知脆弱性の監査（高速・安定版）
- **cargo-mutants**: ミューテーションテスト（長時間実行・独立起動）

## 設計方針

| ツール | 配置先 | 理由 |
|--------|--------|------|
| cargo-audit | `quality-checks.md` に新セクション追加 | 高速で品質チェックパイプラインに自然に統合できる |
| cargo-udeps | `quality-checks.md` に新セクション追加 | 同上。ただし advisory（警告のみ、ブロックしない） |
| cargo-mutants | 新スキル `cargo-mutants/SKILL.md` | 長時間実行のため自動適用は不適切。ユーザー明示起動が正しい |

### チェック順序（更新後）

```
1. cargo fmt --all -- --check
2. cargo clippy --quiet --all-targets -- -D warnings
3. cargo test --quiet
4. cargo audit                            (インストール済みの場合 — 脆弱性発見時ブロック)
5. cargo +nightly udeps --quiet           (インストール済みの場合 — 警告のみ)
6. cargo leptos build OR WASM clippy      (Leptos プロジェクトのみ)
```

### 失敗セマンティクス

- **cargo-audit**: blocking — 既知脆弱性はセキュリティリスクのため commit をブロック
- **cargo-udeps**: advisory — nightly 依存で偽陽性もあるため警告のみ（ブロックしない）
- **cargo-mutants**: 独立起動のため既存パイプラインに影響なし

---

## 変更ファイル一覧

### 1. `.claude-plugin/rules/quality-checks.md`（修正）

**場所**: `## test` セクション（L36-41）の後、`## Leptos Full-Stack` セクション（L42）の前に新セクション追加

**追加内容**: `## Dependency Analysis (Optional Tools)` セクション

- `### cargo-audit (Security — blocking)` — コマンド、検出ロジック、失敗時の動作
- `### cargo-udeps (Unused dependencies — advisory)` — コマンド、nightly 要件、警告動作
- `### Detection and availability check` — `command -v` による可用性検出テーブル
- sccache は cargo-audit（コンパイル不要）と cargo-udeps（nightly 指定で互換性不安定）には**適用しない**旨を明記

**更新**: L84-89 のフルチェック順序サマリを6ステップに更新

### 2. `.claude-plugin/rules/security.md`（修正）

**場所**: A9 セクション（L59-61）を拡張

**変更内容**:
- `cargo audit` の詳細な運用手順を追加（脆弱性発見時のトリアージフロー）
- `cargo +nightly udeps` を攻撃面削減策として追記
- `quality-checks.md` の "Dependency Analysis" セクションへのクロスリファレンス
- `Cargo.lock` レビューの注意事項

### 3. `.claude-plugin/rules/cargo-toml.md`（修正）

**場所**: ファイル末尾（L63 の後）

**追加内容**: `## Dependency Hygiene` セクション（2-3行）
- `cargo +nightly udeps` による未使用依存検出への参照
- `cargo audit` によるメンテナンス状態の確認

### 4. `.claude-plugin/skills/cargo-mutants/SKILL.md`（新規作成）

**構成**:
- frontmatter: `name`, `description`, `argument-hint`, `user-invokable: true`
- Prerequisites: インストール確認
- Arguments: `--package`, `--file`, `--in-diff`, `--timeout`, `--jobs`
- 実行ステップ:
  1. 引数パースと環境検出
  2. ベースラインテスト実行（`cargo test` が通ることを確認）
  3. ミューテーションテスト実行（sccache 統合）
  4. 結果パースと構造化レポート
- 出力サマリ: killed/survived/timeout/unviable の集計 + survived mutants の詳細テーブル
- 他ワークフローとの統合ガイド（TDD 完了後の使い方等）

### 5. `.claude-plugin/agents/review-worker.md`（修正）

**場所**: Quality Checks セクション（L28-56）

**変更内容**:
- L34-38 のコマンドブロックに依存分析コマンドを追加:
  ```bash
  cargo fmt --all -- --check
  cargo clippy --quiet --all-targets -- -D warnings
  cargo test --quiet
  # Dependency Analysis (run if tools are available)
  command -v cargo-audit >/dev/null 2>&1 && cargo audit
  if command -v cargo-udeps >/dev/null 2>&1 && rustup run nightly rustc --version >/dev/null 2>&1; then
    cargo +nightly udeps --quiet || true
  fi
  ```
- Completion Report Format に `cargo_audit: pass|fail|skip` と `cargo_udeps: pass|warn|skip` を追加
- Retry Policy テーブルに cargo-audit（リトライ不要・fail は即停止）を追記

**注意**: `parallel-worker.md` は変更しない。TDD 反復サイクル中に依存分析を実行する意味は薄く、レビュー段階（review-worker）で十分。

### 6. `.claude-plugin/agents/parallel-worker.md`（変更なし）

TDD 実装ワーカーの高速フィードバックループを維持するため、依存分析は追加しない。`quality-checks.md` を参照する旨の記述はそのままで、実行コマンドは fmt + clippy + test に留める。

---

## 実装順序

```
Step 1: quality-checks.md          ← 基盤（他ファイルがこれを参照）
Step 2: security.md + cargo-toml.md ← 並列可能（クロスリファレンス追加）
Step 3: cargo-mutants/SKILL.md      ← 独立（新規ファイル作成）
Step 4: review-worker.md            ← quality-checks.md 反映
```

Step 2 と Step 3 は並列実行可能。

---

## 検証方法

1. **構文チェック**: 全変更ファイルの Markdown 構文が崩れていないことを確認
2. **クロスリファレンス整合性**: security.md → quality-checks.md、cargo-toml.md → quality-checks.md のリンクが正しいセクション名を指していることを確認
3. **チェック順序の一貫性**: quality-checks.md のサマリ（6ステップ）、review-worker.md のインラインコマンド、security.md の記述が矛盾しないことを確認
4. **スキル一覧**: `ls .claude-plugin/skills/cargo-mutants/SKILL.md` で新スキルファイルが存在することを確認
5. **既存テストへの影響**: `npm test` でプロジェクト自体のテストが pass することを確認（Markdown ルール変更はランタイムに影響しない）
