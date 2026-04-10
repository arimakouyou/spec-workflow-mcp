# ハイブリッド検査モデル

決定論的ルール（リンター/CI ツール）と LLM ベースの意味的検査を組み合わせた
品質保証アーキテクチャを定義する。

## 検査アーキテクチャ概要

```
ソースコード変更
    │
    ├─── 決定論的検査（parallel-worker / CI）
    │    ├── rustfmt: フォーマット統一
    │    ├── clippy: Lint 警告検出
    │    ├── cargo test: テスト実行
    │    ├── cargo audit: 脆弱性検出
    │    └── architecture tests: 構造的不変条件
    │
    └─── LLM ベース検査（review-worker）
         ├── A: Style — 命名の意図・一貫性
         ├── B: Design — SoC、依存方向、YAGNI
         ├── C: Security — OWASP、認証/認可
         ├── D: Spec — 仕様準拠
         ├── E: Tests — テスト品質、TDD 準拠
         ├── F: Design Conformance — 設計適合
         └── G: API Docs — OpenAPI 更新確認
```

## 検査マトリクス

各品質観点について、決定論的検査と LLM 検査のどちらが担当するかを定義する。

| 品質観点 | 決定論的検査 | LLM 検査 | 担当エージェント |
|---------|-------------|---------|---------------|
| コードフォーマット | `cargo fmt --check` | — | parallel-worker |
| Lint 警告 | `cargo clippy -D warnings` | A: Style 確認 | parallel-worker + review-worker |
| ユニットテスト | `cargo test` | E: テスト品質評価 | parallel-worker + review-worker |
| セキュリティ脆弱性 | `cargo audit` | C: OWASP 分析 | parallel-worker + review-worker |
| 依存方向 | `tests/architecture.rs` | B: Design 評価 | テスト + review-worker |
| 命名の適切さ | — | A: Style 評価 | review-worker のみ |
| 単一責任原則 | — | B: Design 評価 | review-worker のみ |
| 仕様準拠 | — | D: Spec 確認 | review-worker のみ |
| TDD プロセス | — | E2: TDD 準拠評価 | review-worker のみ |
| 設計適合 | — | F: 設計逸脱検出 | review-worker のみ |
| API ドキュメント | — | G: openapi.yaml 確認 | review-worker のみ |

## 各検査が捕捉する問題の分類

### 決定論的検査のみで検出可能

- フォーマット違反（空白、インデント、末尾改行）
- コンパイラ警告（未使用変数、到達不能コード）
- 既知の脆弱性パターン（CVE データベースとの照合）
- 依存方向違反（`use crate::` の機械的解析）
- テストの PASS/FAIL 結果

### LLM 検査のみで検出可能

- 命名が意図を正確に表現しているか（意味的判断）
- 関数が単一責任を持っているか（設計判断）
- エラーメッセージがユーザーにとって有用か（UX 判断）
- 仕様書の Success 基準を満たしているか（仕様解釈）
- コードが「なぜそう書いたか」の設計意図に沿っているか

### 両方が協調して検出

- セキュリティ: `cargo audit` で既知 CVE + C: OWASP でロジックの脆弱性
- テスト品質: `cargo test` で PASS/FAIL + E: テストが意味のあるアサーションか
- スタイル: `clippy` で機械的パターン + A: プロジェクト固有の命名規約

## 主観的品質基準（Taste Invariants）

LLM 検査で適用する主観的品質基準は `.claude-plugin/rules/design-principles.md` に定義されている。

### design-principles.md との対応

| Taste Invariant | design-principles.md | review-worker カテゴリ |
|----------------|---------------------|---------------------|
| 責務分離 | D1: Separation of Concerns | B: Design |
| 依存方向 | D2: Direction of Dependencies | B: Design |
| 最小公開 API | D3: Minimizing Public API | B: Design |
| エラー一貫性 | D4: Consistent Error Handling | B: Design |
| 命名の適切さ | D5: Naming Appropriateness | A: Style |
| DRY 原則 | D6: DRY | B: Design |
| YAGNI 原則 | D7: YAGNI | B: Design |

これらの基準は AI コードレビュー（review-worker）のプロンプトで直接参照される。
review-worker は `design-principles.md` を読み取り、各原則に基づいてコードを評価する。

## ワークフロー内の実行タイミング

| タイミング | 決定論的検査 | LLM 検査 |
|-----------|-------------|---------|
| TDD 実装中（step 4） | parallel-worker が rustfmt + clippy + test 実行 | — |
| UT 品質検証（step 5） | — | test-engineer がテスト品質を評価 |
| コードレビュー（step 6） | review-worker が rustfmt + clippy + test 実行 | review-worker が A-G カテゴリレビュー |
| Phase Review（step 3.5） | cargo test + 統合検証 + CVE audit | Expert Team Review（5名並列） |

## 品質の二重確認原則

parallel-worker（実装者）と review-worker（レビュアー）は異なるエージェントであり、
review-worker は **Anti-Bias Protocol** に基づき、parallel-worker の結果を鵜呑みにしない:

> コードには問題がある。あなたの仕事はそれを見つけること。
> 「3段階通過しているから大丈夫」という推論は禁止。

この分離により、決定論的チェックの通過が LLM レビューの品質を劣化させないことを保証する。
