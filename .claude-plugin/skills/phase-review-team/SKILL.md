---
name: phase-review-team
description: "Phase completion expert team review. Assembles a multi-disciplinary review team to perform comprehensive code review before Phase commit. Each expert independently analyzes the code from their specialty perspective, then a leader consolidates findings into a prioritized final report saved to file. Triggers on: Phase review tasks (_PhaseReview: true) in spec-implement workflow, or explicit '/phase-review-team' invocation."
---

# Phase Review — Expert Team Review

Phase 完了時にコミット前に実施する、専門家チームによる多角的コードレビュー。

## Overview

各 Phase の成果物に対して、5 名の専門家が独立して調査を行い、具体的な問題箇所と改善案を報告する。リーダーは各報告を統合し、優先度付きの最終レポートを作成してファイルに保存する。

## Inputs

- **spec-name**: スペック名（kebab-case）
- **phase-number**: 対象 Phase 番号
- **changed-files**: Phase で変更されたファイル一覧
- **project-path**: プロジェクトルートパス
- **integration-verification**: 統合検証結果（3.5.1.5 で取得。各ステップの PASS/FAIL/SKIP と詳細）

## Expert Team Composition

| Role | Perspective |
|------|-------------|
| **実装担当** | 仕様書にある機能を網羅しているか、仕様を逸脱していないか |
| **セキュリティ担当1** | 認証、認可、データ漏洩 |
| **セキュリティ担当2** | OWASP TOP 10、最新の CVE |
| **パフォーマンス担当** | ボトルネック、計算量、リソース効率 |
| **品質・保守性担当** | テストカバレッジ、読みやすさ、命名規則、DRY 原則 |

## Execution Steps

### 1. Assemble and Dispatch (Parallel)

5 名の専門家を **並列** で起動する。各専門家は Agent tool で起動し、独立して調査・報告を行う。

```javascript
// 実装担当
Agent({
  subagent_type: "general-purpose",
  description: "Phase review: spec compliance",
  prompt: `あなたは実装レビューの専門家です。Phase {phase-number} で変更されたコードを、仕様書の観点からレビューしてください。

    プロジェクトパス: {project-path}
    スペック名: {spec-name}
    変更ファイル: {changed-files}

    統合検証結果:
    - ビルド: {integration-verification.build}
    - 統合テスト: {integration-verification.integration-tests}
    - スモークテスト: {integration-verification.smoke-test}

    レビュー観点:
    - 仕様書（requirements.md, design.md）にある機能をすべて網羅しているか
    - 仕様を逸脱した実装がないか
    - design.md のAPI定義（パス、メソッド、リクエスト/レスポンス型）との整合性
    - tasks.md の各タスクの Success 基準がすべて満たされているか

    参照ファイル:
    - {project-path}/.spec-workflow/specs/{spec-name}/requirements.md
    - {project-path}/.spec-workflow/specs/{spec-name}/design.md
    - {project-path}/.spec-workflow/specs/{spec-name}/tasks.md

    レポート形式:
    ## 実装担当レビュー
    ### 発見事項
    各発見事項について以下を記載:
    - ファイル: (パスと行番号)
    - 深刻度: Critical / Major / Minor
    - 問題: (具体的な説明)
    - 改善案: (具体的な修正方法)
    ### 総合評価
    - 仕様カバレッジ: X/Y (実装済み/仕様数)
    - 仕様逸脱: あり/なし`
})

// セキュリティ担当1
Agent({
  subagent_type: "general-purpose",
  description: "Phase review: auth & data security",
  prompt: `あなたはセキュリティレビューの専門家（認証・認可・データ保護）です。Phase {phase-number} で変更されたコードをレビューしてください。

    プロジェクトパス: {project-path}
    変更ファイル: {changed-files}

    統合検証結果:
    - ビルド: {integration-verification.build}
    - 統合テスト: {integration-verification.integration-tests}
    - スモークテスト: {integration-verification.smoke-test}

    ★重要: 最新のセキュリティ情報に基づいてレビューすること★
    レビュー開始前に、以下の情報を取得してください:

    【WebSearch が利用可能な場合】
    1. 使用しているフレームワーク・ライブラリの最新セキュリティアドバイザリ
       - 検索例: "{framework名} security advisory {current year}"
       - 検索例: "{framework名} CVE {current year}"
    2. 認証・認可に関する最新のベストプラクティス
       - 検索例: "authentication best practices {current year}"
       - 検索例: "JWT security vulnerabilities {current year}"

    【WebSearch が利用できない場合のオフラインフォールバック】
    1. `cargo audit` を実行して既知の脆弱性を検出（RustSec Advisory DB ベース）
    2. Cargo.toml の依存クレートバージョンを確認し、明らかに古いバージョンを検出
    3. 自身の学習データに基づくセキュリティベストプラクティスでレビュー
    4. レポートに「オフラインレビュー: WebSearch 未使用」と明記

    取得した情報をレビューの判断基準に反映させること。

    レビュー観点:
    - 認証: 認証が必要なエンドポイントにミドルウェアが適用されているか、トークン生成・検証は安全か
    - 認可: リソースへのアクセス制御、権限チェックの欠落、IDOR 脆弱性
    - データ漏洩: レスポンスにパスワードハッシュ・内部ID・スタックトレースが含まれていないか、ログへの機密情報出力
    - セッション管理: セッション固定、セッションハイジャック対策
    - 暗号: 適切なハッシュアルゴリズム、ソルトの使用、鍵管理

    レポート形式:
    ## セキュリティレビュー（認証・認可・データ保護）
    ### 参照した最新セキュリティ情報
    - (WebSearch で取得した情報のサマリとソース URL)
    ### 発見事項
    各発見事項について以下を記載:
    - ファイル: (パスと行番号)
    - 深刻度: Critical / Major / Minor
    - カテゴリ: 認証 / 認可 / データ漏洩 / セッション / 暗号
    - 根拠: (最新のベストプラクティスや Advisory との照合結果)
    - 問題: (具体的な説明)
    - 改善案: (具体的な修正方法)
    ### 総合評価`
})

// セキュリティ担当2
Agent({
  subagent_type: "general-purpose",
  description: "Phase review: OWASP & CVE",
  prompt: `あなたはセキュリティレビューの専門家（OWASP・脆弱性）です。Phase {phase-number} で変更されたコードをレビューしてください。

    プロジェクトパス: {project-path}
    変更ファイル: {changed-files}

    統合検証結果:
    - ビルド: {integration-verification.build}
    - 統合テスト: {integration-verification.integration-tests}
    - スモークテスト: {integration-verification.smoke-test}

    ★重要: 最新の脆弱性情報に基づいてレビューすること★
    レビュー開始前に、以下の手順を実行してください:

    手順1: プロジェクトの依存クレートを特定
    - Cargo.toml を読み、依存クレート名とバージョンを一覧化する

    手順2: 依存クレートの脆弱性を確認
    【WebSearch が利用可能な場合】
    - 各クレートの最新 CVE を検索:
      - 検索例: "{crate名} CVE" (例: "axum CVE", "diesel CVE", "tokio CVE")
      - 検索例: "{crate名} security advisory {current year}"
      - 検索例: "RustSec advisory {crate名}"
      - RustSec Advisory Database (https://rustsec.org/advisories/) も参照
    - 見つかった CVE について、使用中のバージョンが影響を受けるか確認
    【WebSearch が利用できない場合のオフラインフォールバック】
    - `cargo audit` を実行して RustSec Advisory DB から既知の脆弱性を検出
    - Cargo.toml のバージョンを確認し、明らかに古いバージョンをフラグ
    - レポートに「オフラインレビュー: WebSearch 未使用、cargo audit ベース」と明記

    手順3: OWASP の最新動向を確認
    【WebSearch が利用可能な場合】
    - 検索例: "OWASP TOP 10 latest update"
    - 検索例: "OWASP {使用フレームワーク} cheat sheet"
    【WebSearch が利用できない場合】
    - 自身の学習データに基づく OWASP TOP 10 知識でレビュー

    手順4: 上記の情報を踏まえてコードをレビュー

    レビュー観点:
    OWASP TOP 10 の各項目について確認:
    - A01: アクセス制御の不備
    - A02: 暗号化の失敗
    - A03: インジェクション（SQL, コマンド, XSS）
    - A04: 安全でない設計
    - A05: セキュリティ設定の不備
    - A06: 脆弱で古くなったコンポーネント
    - A07: 識別と認証の失敗
    - A08: ソフトウェアとデータの整合性の不備
    - A09: セキュリティログとモニタリングの不備
    - A10: サーバーサイドリクエストフォージェリ (SSRF)

    追加確認:
    - 手順2 で発見した CVE に該当する使用箇所がないか
    - cargo audit 相当のチェック（既知の脆弱性を持つバージョンを使用していないか）
    - 入力バリデーションの漏れ
    - エラーメッセージによる情報漏洩

    レポート形式:
    ## セキュリティレビュー（OWASP・CVE）
    ### 検索した脆弱性情報
    - (依存クレートごとに検索結果をサマリ、ソース URL を記載)
    - (該当 CVE があればCVE番号、影響バージョン、対処状況を記載)
    ### 発見事項
    各発見事項について以下を記載:
    - ファイル: (パスと行番号)
    - 深刻度: Critical / Major / Minor
    - OWASP カテゴリ: A01-A10 / CVE番号
    - 根拠: (検索で見つけた CVE/Advisory への参照)
    - 問題: (具体的な説明)
    - 改善案: (具体的な修正方法、パッチバージョンがあればそのバージョン番号)
    ### 総合評価`
})

// パフォーマンス担当
Agent({
  subagent_type: "general-purpose",
  description: "Phase review: performance",
  prompt: `あなたはパフォーマンスレビューの専門家です。Phase {phase-number} で変更されたコードをレビューしてください。

    プロジェクトパス: {project-path}
    変更ファイル: {changed-files}

    統合検証結果:
    - ビルド: {integration-verification.build}
    - 統合テスト: {integration-verification.integration-tests}
    - スモークテスト: {integration-verification.smoke-test}

    レビュー観点:
    - ボトルネック: N+1 クエリ、不要なループ内 DB アクセス、ブロッキング I/O
    - 計算量: O(n²) 以上のアルゴリズムがないか、大量データでの挙動
    - リソース効率: 不要な clone()、メモリ割り当ての最適化、コネクションプール活用
    - 非同期処理: async/await の適切な使用、不要な .await の連鎖
    - キャッシュ: キャッシュすべきデータがキャッシュされているか、キャッシュ無効化戦略
    - DB: インデックスの活用、クエリ最適化、不要なカラムの SELECT

    レポート形式:
    ## パフォーマンスレビュー
    ### 発見事項
    各発見事項について以下を記載:
    - ファイル: (パスと行番号)
    - 深刻度: Critical / Major / Minor
    - カテゴリ: ボトルネック / 計算量 / リソース / 非同期 / キャッシュ / DB
    - 影響: (推定されるパフォーマンス影響)
    - 改善案: (具体的な修正方法)
    ### 総合評価`
})

// 品質・保守性担当
Agent({
  subagent_type: "general-purpose",
  description: "Phase review: quality & maintainability",
  prompt: `あなたは品質・保守性レビューの専門家です。Phase {phase-number} で変更されたコードをレビューしてください。

    プロジェクトパス: {project-path}
    変更ファイル: {changed-files}

    統合検証結果:
    - ビルド: {integration-verification.build}
    - 統合テスト: {integration-verification.integration-tests}
    - スモークテスト: {integration-verification.smoke-test}

    レビュー観点:
    - テストカバレッジ: 新規コードに対するテストの網羅性、ハッピーパス・異常系・境界値
    - 統合テストカバレッジ: Phase の主要機能に対する統合テストが存在するか。統合検証で SKIP された場合、統合テストの追加が必要か評価する
    - テスト粒度バランス: ユニットテストと統合テストの棲み分けが適切か。ユニットテストのみで統合テストが皆無の場合は指摘する
    - TDD 遵守: テストが実装を駆動しているか（形骸化の兆候がないか）
      - is_ok()/is_some() だけのアサーション → 形骸化
      - ハッピーパスのみ → 不十分
      - 実装の内部構造に依存したテスト → 設計品質の問題
    - 読みやすさ: 関数の長さ、ネストの深さ、コメントの適切さ
    - 命名規則: 型・関数・変数の命名がプロジェクト規約に沿っているか、意図が明確か
    - DRY 原則: 重複コード、共通化すべきロジック
    - SOLID 原則: 単一責任、依存性逆転、インターフェース分離
    - エラーハンドリング: 統一されたエラー型、unwrap() の不適切な使用

    レポート形式:
    ## 品質・保守性レビュー
    ### 発見事項
    各発見事項について以下を記載:
    - ファイル: (パスと行番号)
    - 深刻度: Critical / Major / Minor
    - カテゴリ: テスト / TDD / 可読性 / 命名 / DRY / SOLID / エラー処理
    - 問題: (具体的な説明)
    - 改善案: (具体的な修正方法)
    ### 総合評価`
})
```

### 2. Consolidate (Leader)

全専門家のレポートが返ってきたら、リーダー（オーケストレーター自身）が統合する。

#### 2.1 統合レポートの作成

全発見事項を以下の優先度で分類:

| Priority | Criteria | Action |
|----------|----------|--------|
| **P0 — Blocker** | Critical なセキュリティ脆弱性、仕様の重大な逸脱 | コミット不可。即座に修正が必要 |
| **P1 — Must Fix** | Major な問題（セキュリティ、設計、仕様準拠） | コミット前に修正が必要 |
| **P2 — Should Fix** | Minor な問題（パフォーマンス改善、コード品質向上） | このPhaseで修正推奨。次Phase送りも可 |
| **P3 — Nice to Have** | 提案レベル（命名改善、コメント追加等） | 改善推奨だがブロッカーではない |

#### 2.2 レポートファイルの保存

```
.spec-workflow/specs/{spec-name}/reviews/phase-{phase-number}-review.md
```

レポートフォーマット:

```markdown
# Phase {phase-number} Expert Team Review

**Date**: {date}
**Spec**: {spec-name}
**Phase**: {phase-number}
**Reviewers**: 実装担当, セキュリティ担当1, セキュリティ担当2, パフォーマンス担当, 品質・保守性担当

## Summary

| Priority | Count | Action Required |
|----------|-------|-----------------|
| P0 — Blocker | {n} | Must fix before commit |
| P1 — Must Fix | {n} | Must fix before commit |
| P2 — Should Fix | {n} | Fix recommended |
| P3 — Nice to Have | {n} | Optional |

## Verdict: {PASS / NEEDS_REWORK / BLOCK}

{1-2 sentence summary of overall assessment}

---

## P0 — Blocker

{findings sorted by priority, each with file, line, reviewer, problem, and suggested fix}

## P1 — Must Fix

{...}

## P2 — Should Fix

{...}

## P3 — Nice to Have

{...}

---

## Individual Reports

### 実装担当
{full report}

### セキュリティ担当1（認証・認可・データ保護）
{full report}

### セキュリティ担当2（OWASP・CVE）
{full report}

### パフォーマンス担当
{full report}

### 品質・保守性担当
{full report}
```

### 3. Verdict and Action

| Verdict | Condition | Action |
|---------|-----------|--------|
| **PASS** | P0 = 0, P1 = 0 | review-worker にコミットを委譲 |
| **NEEDS_REWORK** | P0 = 0, P1 > 0 | P1 の発見事項を parallel-worker に差し戻し。修正後に再度チームレビュー |
| **BLOCK** | P0 > 0 | ユーザーにエスカレート。Critical なセキュリティ問題や仕様の根本的な逸脱 |

### 4. Re-review Policy

- NEEDS_REWORK 後の再レビューは **変更された箇所のみ** を対象とする（全体の再レビューは不要）
- 再レビューは最大 2 回まで。解消しない場合はユーザーにエスカレート
- PASS 後は review-worker の通常フロー（コミット）に進む
