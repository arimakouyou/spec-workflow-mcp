# 段階的執行モデルとルール昇格基準

ルールの成熟度に応じた段階的執行モデルを定義する。ルールは最初はドキュメントとして始まり、
違反の蓄積に応じて自動的に執行レベルが昇格される。

## 執行レベル定義

| Level | 名称 | 執行方法 | 違反時の動作 |
|-------|------|---------|-------------|
| L1 | ドキュメント | ルールファイル（`.claude-plugin/rules/`）に記載 | エージェントが参照するが強制なし |
| L2 | AI レビュー | review-worker のレビューカテゴリ（A-G）で検査 | findings として報告、rework/escalate |
| L3 | CI ツール | GitHub Actions の CI ジョブで機械的に検査 | CI 失敗でマージブロック |
| L4 | 構造テスト | `tests/architecture.rs` 等のテストコードで検証 | `cargo test` 失敗でビルドブロック |
| L5 | コンパイラ/型システム | 言語の型システムやコンパイラエラーで強制 | コンパイル不可 |

## 現在のルール配置

| ルール | L1 Doc | L2 AI Review | L3 CI | L4 構造テスト | L5 型 |
|--------|--------|-------------|-------|-------------|-------|
| コードフォーマット（rustfmt） | rust-style.md | A: Style | `cargo fmt --check` | — | — |
| Lint 警告（clippy） | rust-style.md | A: Style | `cargo clippy -D warnings` | — | — |
| 依存方向ルール | design-principles.md D2 | B: Design | — | `/generate-arch-tests` | — |
| セキュリティ（OWASP） | security.md | C: Security | `cargo audit` | — | — |
| 仕様準拠 | — | D: Spec | — | — | — |
| テスト品質 | — | E: Tests, E2: TDD | `cargo test` | — | — |
| 設計適合 | design-conformance.md | F: Design Conformance | — | — | — |
| API ドキュメント | — | G: API Docs | — | — | — |
| 循環依存禁止 | design-principles.md D2 | B: Design | — | `/generate-arch-tests` | — |
| 型安全性 | type-safety.md | B: Design | `cargo clippy` | — | コンパイラ |
| API バリデーション | api-validation.md | C: Security | — | — | serde 型 |
| SAST（セキュリティ解析） | — | C: Security | clippy security / CodeQL | — | — |
| エラーメッセージ品質 | error-message-guidelines.md | E: Tests | — | — | — |
| Flaky Test 管理 | flaky-test-management.md | E: Tests | リトライ設定 / 隔離ジョブ | — | — |
| VRT（Visual Regression） | test-design-template.md | E: Tests | Playwright VRT (Advisory) | — | — |
| 品質 Issue 自動修正 | enforcement-levels.md | — | `auto-fix-quality.yml` | — | — |

## ルール昇格基準

ルールの執行レベルを上げる条件と手順を定義する。

### 昇格条件

| 昇格パス | 条件 | 判断者 |
|---------|------|--------|
| L1 → L2 | ルールが確立し、レビューで繰り返し指摘される | チームリード |
| L2 → L3 | AI レビューで 3回以上同一ルール違反が検出された | チームリード + CI 担当 |
| L3 → L4 | CI チェックでは検出できない構造的な違反がある | アーキテクト |
| L4 → L5 | 型システムで表現可能な不変条件である | アーキテクト |

### 昇格手順

1. **提案**: 違反ログを収集し、昇格の妥当性を評価
2. **ADR 作成**: `/adr` スキルで昇格決定の ADR を記録
3. **実装**: 昇格先レベルのツール設定/テストコードを追加
4. **検証**: 既存コードが新しい執行レベルに適合するか確認
5. **適用**: CI / テストに組み込み、違反を検出する状態にする

### 自動昇格提案（P3-04 対応）

週次定期品質チェック（`--with-scheduled`）で違反を蓄積し、閾値を超えた場合に昇格を自動提案する。

**蓄積方法**: 週次 CI の Issue に `[Quality]` ラベルを付与。同一ルール ID の Issue が一定数蓄積されたら昇格対象。

| 昇格パス | 自動提案トリガー | 提案内容 |
|---------|---------------|---------|
| L1 → L2 | 同一パターンの指摘が Issue 2件以上 | review-worker のチェック項目に追加を提案 |
| L2 → L3 | review-worker findings で同一ルール ID が 3回以上 | CI ジョブへのチェック追加を提案 |
| L3 → L4 | CI で検出できない構造違反が 2回以上 | `/generate-arch-tests` のテスト追加を提案 |

**提案フォーマット**: Issue のコメントまたは新規 Issue で以下を出力:

```
## 昇格提案

- ルール: {rule-id} ({rule-name})
- 現在の執行レベル: L{N}
- 提案する昇格先: L{N+1}
- 根拠: {直近M回の違反サマリー}
- 推奨アクション: {具体的な実装手順}
```

### 降格条件

| 条件 | アクション |
|------|----------|
| ルールが実情に合わなくなった | L3/L4 → L2 に降格し、AI レビューのみに戻す |
| 誤検出が多い | 一時的に L1 に降格し、ルール自体を見直す |
| プロジェクト方針の変更 | ADR で廃止を記録し、該当レベルから除去 |

## review-worker との連携

review-worker は L2（AI レビュー）の主要な執行者である。各カテゴリ（A-G）の findings は以下の severity に分類される:

| Severity | 対象カテゴリ | アクション | 昇格候補 |
|----------|------------|----------|---------|
| Minor | A (Style), G (API Docs) | auto-fix | L3 昇格候補（機械的に修正可能） |
| Moderate | B (Design), C (Security), E (Tests), E2 (TDD) | parallel-worker に差し戻し | L4 昇格候補（構造テスト化可能） |
| Critical | D (Spec), F (Design Conformance) | ユーザーエスカレート | L5 昇格候補（型で表現可能か検討） |

## 自動修正 PR 生成（P3-10 対応）

週次定期チェックで検出された品質問題に対して、エージェントが自動修正 PR を作成する仕組み。

### 自動修正可能な問題

| 問題種別 | 修正方法 | PR タイトル例 |
|---------|---------|-------------|
| フォーマット違反 | `cargo fmt` / `prettier --write` | `fix: auto-format code` |
| 未使用依存 | `Cargo.toml` から削除 | `chore: remove unused dependencies` |
| doc comment 不足 | `/generate-api-docs` の提案を適用 | `docs: add missing doc comments` |
| Stale ドキュメント | 内容を現状に合わせて更新 | `docs: update stale documentation` |

### 自動修正フロー

1. 週次 CI (`scheduled-quality.yml`) が違反を検出し `[quality]` + `[automated]` ラベル付き Issue を作成
2. `auto-fix-quality.yml` が Issue 作成イベントで Claude Code を起動し、`/handle-issue` を自動実行
3. 修正をブランチに実装
4. `/create-pr --closes {issue-number}` で PR 作成
5. CI + review-worker による品質検証
6. 承認後マージ（`--with-auto-merge` 有効時は自動マージ）

> **CI ワークフロー設定**: `/setup-ci --with-auto-fix` で `auto-fix-quality.yml` を生成する。
> 前提条件: `ANTHROPIC_API_KEY` シークレットが設定されていること。

### Issue のみの場合（PARTIAL 対応）

自動修正 PR の仕組みが未構築の場合（`--with-auto-fix` 未適用）でも、Issue 作成のみで P3-10 / P8-07 の PARTIAL 判定を得られる。
完全な自動修正 PR 生成には `/setup-ci --with-auto-fix` で CI ワークフローを追加し、`ANTHROPIC_API_KEY` シークレットを設定する必要がある。

## spec-implement との連携

Phase Review（step 3.5）では以下の執行レベルが適用される:

1. **L4 構造テスト**: step 3.5.1 `cargo test` でアーキテクチャテストを自動実行
2. **L3 CI**: step 3.5.1.5 統合検証で CI 相当のチェックを実行
3. **L2 AI レビュー**: step 3.5.2 Expert Team Review で多角的レビュー
4. **L3 CI**: step 3.5.1.6 CVE Audit で脆弱性を機械的に検査
