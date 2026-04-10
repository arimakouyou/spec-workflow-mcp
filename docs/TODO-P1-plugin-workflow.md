# P1-06, P1-08: プラグインワークフロー拡張 TODO

ハーネス成熟度チェック P1 の改善で、プロジェクト側（A部分）は対応済み。
プラグイン側（B/C部分）のワークフロー拡張が残っている。

## P1-06: APIスキーマ自然言語説明のワークフロー組み込み

### B. 新規スキル `/generate-api-docs`

**目的:** API実装後にOpenAPIドキュメントを自動生成するスキル

**スキル定義場所:** `.claude-plugin/skills/generate-api-docs/SKILL.md`

**想定フロー:**
1. ソースコードからAPIルート定義を解析（Axum Router, Express routes等）
2. ハンドラのシグネチャ・Rustdoc・型定義を収集
3. OpenAPI 3.1 YAML を `docs/openapi.yaml` に生成
4. 共有型定義のdoc commentが不足していれば補完を提案

**トリガー:** `/generate-api-docs` または spec-implementのPhase完了時

### C. 既存ワークフロー拡張

- **spec-implement** (`SKILL.md`):
  - 全Phaseの実装完了後のreview-workerチェック項目に追加:
    「API変更がある場合は `docs/openapi.yaml` の更新確認」
- **spec-design** (`SKILL.md`):
  - API Designセクション作成時のガイダンスに追加:
    「OpenAPIスキーマ生成のためdoc commentをフィールドレベルで記述すること」

---

## P1-08: CIフィードバックのワークフロー組み込み

### B. `/setup-ci` スキル拡張

**目的:** setup-ciで生成するci.ymlにPRコメントフィードバックを標準搭載

**変更対象:**
- `.claude-plugin/skills/setup-ci/references/ci-rust.yml` — テスト結果PRコメント投稿ステップ追加
- `.claude-plugin/skills/setup-ci/references/ci-nodejs.yml` — 同上
- `.claude-plugin/skills/setup-ci/references/ci-leptos.yml` — 同上
- `.claude-plugin/skills/setup-ci/SKILL.md` — `--no-pr-comments` オプションでオプトアウト可能に

**PRコメント方式:**
- `actions/github-script@v7` によるsticky comment方式（既存コメントを更新、スパム防止）
- checkジョブ: テスト結果サマリーを投稿
- e2eジョブ（`--with-e2e` 時）: E2E結果を投稿
- セキュリティ: untrusted inputをrun:で実行しない。テスト出力ファイルの読み取りのみ

### C. 既存ワークフロー拡張

- **spec-implement** (`SKILL.md`):
  - Phase Review時に「CI結果がPRコメントに投稿されるため、PRコメントから結果を確認可能」のガイダンスを追加
- **create-pr** (`SKILL.md`):
  - PR作成時にPR bodyへ「CIフィードバックがPRコメントに自動投稿されます」の記載を追加

---

## 実装済み（参考: rust-image-viewer-2 での対応）

| 項目 | ファイル | 内容 |
|------|---------|------|
| P1-06A | `docs/openapi.yaml` | OpenAPI 3.1仕様（4エンドポイント、3スキーマ、全description付き） |
| P1-06A | `shared/src/lib.rs` | DirectoryNode/ImageInfoの各フィールドにRustdoc追加 |
| P1-06A | `server/src/lib.rs` | build_routerにOpenAPI参照追記 |
| P1-08A | `.github/workflows/ci.yml` | checkジョブ: テスト結果PRコメント、e2eジョブ: E2E結果PRコメント |
