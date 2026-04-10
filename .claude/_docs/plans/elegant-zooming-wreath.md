# ハーネス成熟度チェック対応 — 全実装完了

## Status: DONE

本セッションで以下の全対応を完了。新たな計画タスクなし。

## 完了済み作業

### 1. P1-06/P1-08（TODO-P1-plugin-workflow.md 対応）
- `/generate-api-docs` スキル新規作成
- CI テンプレート sticky comment 追加
- `--no-pr-comments` オプション
- review-worker カテゴリ G 追加

### 2. アーキテクチャ不変条件テスト
- `/generate-arch-tests` スキル新規作成
- `spec-design` に Module Boundaries セクション追加
- 循環依存検出テスト追加

### 3. P2 チェックリスト対応（12項目）
- `enforcement-levels.md`, `type-safety.md`, `api-validation.md`, `hybrid-inspection.md` 新規作成
- `hooks.json` に PostToolUse(Edit/Write) フック追加
- `design-principles.md` に Taste Invariants 宣言

### 4. P1 チェックリスト対応（9項目）
- `rules/INDEX.md` 新規作成（60ルール一覧）
- `spec-design` に steering doc チェック追加
- `steering-doc` に CLAUDE.md ガイダンス追加
- `quality-checks.md` に QC3.5 doc comment カバレッジ追加

### 5. P3 チェックリスト対応（11項目）
- `job-scheduled-quality.yml` 定期 CI テンプレート新規作成
- `doc-freshness.md`, `doc-crossref.md` 新規作成
- `setup-ci --with-scheduled` オプション追加
- `quality-checks.md` に QC8 コード重複検出、npm audit 追加
- `cargo-mutants` にミューテーション閾値設定追加
- `enforcement-levels.md` に自動昇格提案・自動修正 PR ガイダンス追加

### 決定事項
- Node.js/TS ルール（type-safety.md TS-T1/T2, npm audit, knip 等）はそのまま残す（将来拡張用）

---

## 変更一覧

| # | 区分 | 対象ファイル | 変更内容 |
|---|------|-------------|---------|
| 1 | P1-06B | `skills/generate-api-docs/SKILL.md` | **新規作成** — OpenAPI 3.1 YAML 自動生成スキル |
| 2 | P1-06C | `skills/spec-design/SKILL.md` | API Design セクションに doc comment ガイダンス追加 |
| 3 | P1-06C | `skills/spec-implement/SKILL.md` | review-worker チェックリストにカテゴリ G（API Documentation）追加 |
| 4 | P1-06C | `agents/review-worker.md` | セクション G（API Documentation Conformance）追加 |
| 5 | P1-08B | `skills/setup-ci/references/ci-rust.yml` | テスト出力キャプチャ + PR コメント投稿ステップ追加 |
| 6 | P1-08B | `skills/setup-ci/references/ci-nodejs.yml` | 同上 |
| 7 | P1-08B | `skills/setup-ci/references/ci-leptos.yml` | 同上 |
| 8 | P1-08B | `skills/setup-ci/references/job-e2e.yml` | E2E 結果 PR コメント投稿ステップ追加（コメントアウト） |
| 9 | P1-08B | `skills/setup-ci/SKILL.md` | `--no-pr-comments` オプション追加 |
| 10 | P1-08C | `skills/spec-implement/SKILL.md` | Phase Review に CI フィードバックガイダンス追加 |
| 11 | P1-08C | `skills/create-pr/SKILL.md` | PR ボディに CI フィードバックセクション追加 |

全ファイルパスは `.claude-plugin/` 配下（プロジェクトルート: `/home/arimakouyou/harness-template/spec-workflow-mcp`）

---

## 1. 新規スキル: `/generate-api-docs`（P1-06B）

**ファイル:** `.claude-plugin/skills/generate-api-docs/SKILL.md`

### フロントマター

```yaml
---
name: generate-api-docs
description: >
  ソースコードからOpenAPI 3.1ドキュメントを自動生成する。APIルート定義の解析、
  ハンドラシグネチャ・型定義・doc comment収集、OpenAPI YAML生成、doc comment改善提案を行う。
  Triggers: 'generate API docs', 'OpenAPI生成', 'APIドキュメント生成', '/generate-api-docs'.
argument-hint: "[--output <path>] [--framework <axum|express|auto>]"
user-invokable: true
---
```

### スキル本文構成

1. **引数パース**: `--output`（デフォルト: `docs/openapi.yaml`）、`--framework`（デフォルト: auto）
2. **フレームワーク検出**（`--framework auto` 時）:
   - `Cargo.toml` に `axum` 依存 → Axum
   - `Cargo.toml` に `actix-web` 依存 → Actix-web
   - `package.json` に `express` → Express
   - `package.json` に `fastify` → Fastify
   - 検出失敗 → エラー報告
3. **ルート解析**（フレームワーク別パターン）:
   - Axum: `Router::new()` / `.route()` / `.nest()` パターン検索
   - Express: `app.get()` / `router.post()` 等のパターン検索
4. **ハンドラ分析**: シグネチャ、Rustdoc/JSDoc、リクエスト/レスポンス型、フィールドレベル doc comment 収集
5. **OpenAPI 3.1 YAML 生成**: info / paths / components/schemas を構成し、出力先に書き出し
6. **Doc Comment ギャップ分析**: 不足している doc comment の一覧をファイルパス・行番号付きで提示
7. **Design.md クロスリファレンス**（`.spec-workflow/specs/*/design.md` 存在時）: 設計書の API Design セクションとの差分検出

---

## 2. spec-design ガイダンス追加（P1-06C）

**ファイル:** `.claude-plugin/skills/spec-design/SKILL.md`
**挿入位置:** 235行目（`- Error responses` の直後）

追加内容:

```markdown

> **OpenAPI 生成ガイダンス**: OpenAPI スキーマの自動生成（`/generate-api-docs`）のため、リクエスト/レスポンス型の各フィールドにはフィールドレベルの説明を doc comment で記述すること。設計段階で説明を定義しておくことで、実装時の doc comment と OpenAPI の `description` フィールドが一貫する。
>
> 記述例:
> ```rust
> struct UserResponse {
>     /// ユーザーの一意識別子
>     id: Uuid,
>     /// 表示用ユーザー名（2-50文字）
>     display_name: String,
>     /// アカウント作成日時（UTC）
>     created_at: DateTime<Utc>,
> }
> ```
```

---

## 3. spec-implement レビューチェックリスト拡張（P1-06C）

**ファイル:** `.claude-plugin/skills/spec-implement/SKILL.md`

### 3a. per-task review-worker プロンプト（step 6）

**挿入位置:** 672行目（カテゴリ F の直後）

```
    **G: API Documentation** — API変更（エンドポイント追加・変更・型変更）がある場合、`docs/openapi.yaml` の更新を確認。openapi.yaml が存在しない場合はスキップ
```

### 3b. Phase Review review-worker プロンプト（step 3.5.3）

**挿入位置:** 390行目付近（`Review across all aspects (A–F)` を `(A–G)` に変更）

プロンプト末尾に追記:
```
    G: API Documentation — docs/openapi.yaml が存在し、API関連ファイルに変更がある場合、
    openapi.yaml が更新されているか確認。未更新の場合は `/generate-api-docs` の実行を推奨として報告。
```

---

## 4. review-worker エージェント定義拡張（P1-06C）

**ファイル:** `.claude-plugin/agents/review-worker.md`

### 4a. セクション G 追加

**挿入位置:** 153行目（セクション F の末尾 `Implementers are not permitted to change the design on their own.` の直後）

```markdown

### G. API Documentation Conformance (conditional)

`docs/openapi.yaml` が存在するプロジェクトの場合のみ確認する。存在しない場合はスキップ。

- API 関連ファイル（ハンドラ、ルーター、リクエスト/レスポンス型）に変更がある場合、`docs/openapi.yaml` が更新されているか
- 新規エンドポイントが `docs/openapi.yaml` の paths に追加されているか
- 変更されたリクエスト/レスポンス型が components/schemas に反映されているか

**Severity**: Minor（`/generate-api-docs` の実行を推奨する報告とし、auto-fix は行わない）
```

### 4b. Severity Classification テーブル更新

**変更位置:** 163行目

```
| **Minor** | A (Style and conventions), G (API Docs) | review-worker auto-fixes (rustfmt, naming corrections, etc.) and continues. G は `/generate-api-docs` の実行を推奨として報告 |
```

### 4c. observations 参照範囲の更新

- 77行目: `(A-F)` → `(A-G)`
- 171行目: `各カテゴリ (A-F)` → `各カテゴリ (A-G)`
- 186行目の例に追加: `  - G: checked-ok — openapi.yaml 未存在のためスキップ` or `  - G: checked-ok — API変更なし`
- 276行目: `(A-F)` → `(A-G)`

### 4d. Completion Report に `api_docs` キーを追加

**変更位置:** 275行目の後

```
    - api_docs: pass|skip|advisory
```

---

## 5. CI テンプレート YAML 変更（P1-08B）

### 設計方針

- **Sticky Comment 方式**: `actions/github-script@v7` で HTML コメントタグによるコメント一意識別 → 更新 or 新規作成
- **check ジョブ**: タグ `<!-- ci-check-result -->`、E2E ジョブ: タグ `<!-- ci-e2e-result -->`（別々の sticky comment）
- **セキュリティ**: untrusted input を `run:` で実行しない。テスト出力はファイル経由で読み取り
- **テスト出力キャプチャ**: 既存 Tests ステップを `| tee` で出力ファイルに保存（別ステップでの再実行を避ける）
- **PR イベントガード**: `if: always() && github.event_name == 'pull_request'`
- **permissions**: `pull-requests: write` をワークフローレベルで追加

### 5a. ci-rust.yml

**ファイル:** `.claude-plugin/skills/setup-ci/references/ci-rust.yml`

変更内容:
1. ワークフローレベルに `permissions:` ブロック追加（`contents: read`, `pull-requests: write`）
2. 既存ステップに `id:` 追加: `format-check`, `clippy`, `tests`, `security-audit`
3. Tests ステップの `run:` を `cargo test --quiet 2>&1 | tee /tmp/test-output.txt` に変更
4. 末尾に PR コメント投稿ステップ追加:

```yaml
      - name: Post CI results to PR
        if: always() && github.event_name == 'pull_request'
        uses: actions/github-script@v7
        env:
          FMT_RESULT: ${{ steps.format-check.outcome }}
          CLIPPY_RESULT: ${{ steps.clippy.outcome }}
          TEST_RESULT: ${{ steps.tests.outcome }}
          AUDIT_RESULT: ${{ steps.security-audit.outcome }}
        with:
          script: |
            const fs = require('fs');
            const testOutput = fs.existsSync('/tmp/test-output.txt')
              ? fs.readFileSync('/tmp/test-output.txt', 'utf8').trim().split('\n').slice(-20).join('\n')
              : 'No test output';
            const icon = (r) => r === 'success' ? ':white_check_mark:' : ':x:';
            const tag = '<!-- ci-check-result -->';
            const allPass = [process.env.FMT_RESULT, process.env.CLIPPY_RESULT,
                             process.env.TEST_RESULT, process.env.AUDIT_RESULT]
                            .every(r => r === 'success');
            const body = [
              tag,
              `## ${allPass ? ':white_check_mark:' : ':x:'} CI Quality Checks`,
              '',
              '| Check | Result |',
              '|-------|--------|',
              `| Format (rustfmt) | ${icon(process.env.FMT_RESULT)} |`,
              `| Clippy | ${icon(process.env.CLIPPY_RESULT)} |`,
              `| Tests | ${icon(process.env.TEST_RESULT)} |`,
              `| Security Audit | ${icon(process.env.AUDIT_RESULT)} |`,
              '',
              '<details><summary>Test output (last 20 lines)</summary>',
              '', '```', testOutput, '```', '',
              '</details>',
            ].join('\n');
            const { data: comments } = await github.rest.issues.listComments({
              owner: context.repo.owner, repo: context.repo.repo,
              issue_number: context.issue.number,
            });
            const existing = comments.find(c => c.body.includes(tag));
            if (existing) {
              await github.rest.issues.updateComment({
                owner: context.repo.owner, repo: context.repo.repo,
                comment_id: existing.id, body,
              });
            } else {
              await github.rest.issues.createComment({
                owner: context.repo.owner, repo: context.repo.repo,
                issue_number: context.issue.number, body,
              });
            }
```

### 5b. ci-nodejs.yml

同パターン。ステップ ID: `typecheck`, `lint`, `format-check`, `tests`, `build`。
テーブル列: Type Check / Lint / Format / Tests / Build。
テスト出力: `{{PACKAGE_MANAGER}} test 2>&1 | tee /tmp/test-output.txt`

### 5c. ci-leptos.yml

ci-rust.yml と同パターン。追加ステップ ID: `leptos-build`。テーブルに Leptos Build 行を追加。

### 5d. job-e2e.yml

**ファイル:** `.claude-plugin/skills/setup-ci/references/job-e2e.yml`

末尾にコメントアウト状態で E2E 結果 PR コメントステップを追加:

```yaml
      # --- PR comment: E2E results (uncomment when configuring) ---
      # - name: Post E2E results to PR
      #   if: always() && github.event_name == 'pull_request'
      #   uses: actions/github-script@v7
      #   env:
      #     E2E_RESULT: ${{ steps.e2e-tests.outcome }}
      #   with:
      #     script: |
      #       // Tag: <!-- ci-e2e-result -->
      #       // Sticky comment logic (same pattern as check job)
```

---

## 6. setup-ci スキル拡張（P1-08B）

**ファイル:** `.claude-plugin/skills/setup-ci/SKILL.md`

### 6a. フロントマター更新

9行目 `argument-hint` を更新:
```yaml
argument-hint: "[--with-e2e] [--with-services] [--no-pr-comments]"
```

### 6b. Step 4 にオプション処理追加

110行目の後に追記:

```markdown
#### `--no-pr-comments`

PR コメントフィードバックステップを削除する:
- `check` ジョブから "Post CI results to PR" ステップを削除
- `e2e` ジョブ（`--with-e2e` 併用時）から "Post E2E results to PR" ステップを削除

デフォルトでは PR コメントフィードバックは**有効**。このオプションで明示的にオプトアウトする。
```

### 6c. Step 3 にテンプレートカスタマイズ説明追加

98行目付近に追記:

```markdown
**PR コメントステップ**（全プロジェクトタイプ共通）:
- PR コメント投稿ステップはデフォルトで全テンプレートに含まれる
- `--no-pr-comments` 指定時は "Post CI results to PR" ステップをテンプレートから除去
```

### 6d. Step 6 レポートに追加

135行目付近:
```
  - PR コメントフィードバック: {有効/無効 (--no-pr-comments)}
```

---

## 7. spec-implement CI フィードバックガイダンス追加（P1-08C）

**ファイル:** `.claude-plugin/skills/spec-implement/SKILL.md`
**挿入位置:** 399行目（step 3.5.3 の `review_action: escalate` 分岐の直後、step 3.5.4 Complete の直前）

```markdown

> **CI フィードバック**: CI ワークフローが `/setup-ci` で構成されている場合、テスト結果サマリーが PR コメントに自動投稿される（sticky comment 方式で更新）。Phase Review 後に `/create-pr` で PR を作成した際、CI 実行結果を PR コメントから確認可能。`--no-pr-comments` で無効化されている場合はコメント投稿なし。
```

---

## 8. create-pr PR ボディ拡張（P1-08C）

**ファイル:** `.claude-plugin/skills/create-pr/SKILL.md`
**挿入位置:** 483行目（セクション 4.5 Spec ドキュメントの直後、セクション 4.6 フッターの直前）

```markdown

#### 4.5.5 CI フィードバックセクション

`.github/workflows/ci.yml` が存在する場合のみ表示:

```markdown
## CI フィードバック
CI テスト結果は PR コメントに自動投稿されます（sticky comment 方式）。詳細はコメント欄を確認してください。
```

`.github/workflows/ci.yml` が存在しない場合はこのセクションを省略する。
```

---

## 実装順序

依存関係なしで並列実行可能なグループ:

**Group A**（並列可）:
1. `generate-api-docs/SKILL.md` 新規作成
2. CI テンプレート YAML 4ファイル変更（ci-rust, ci-nodejs, ci-leptos, job-e2e）
3. `setup-ci/SKILL.md` オプション追加

**Group B**（Group A 完了後）:
4. `spec-design/SKILL.md` ガイダンス追加
5. `create-pr/SKILL.md` CI フィードバックセクション追加
6. `spec-implement/SKILL.md` カテゴリ G + CI ガイダンス追加
7. `review-worker.md` セクション G + severity テーブル + observation 範囲更新

---

## 検証方法

1. **スキル定義の構文確認**: 各 SKILL.md の YAML フロントマターが正しくパースされるか（`/reload-plugins` で確認）
2. **CI テンプレートの YAML 構文確認**: `python3 -c "import yaml; yaml.safe_load(open('ci-rust.yml'))"` 等で構文チェック（ただしプレースホルダ `{{TOOLCHAIN}}` があるため、置換後に検証）
3. **review-worker チェックリスト整合性**: spec-implement のプロンプト内カテゴリ（A-G）と review-worker.md のセクション（A-G）が一致していることを目視確認
4. **TODO 消化確認**: `docs/TODO-P1-plugin-workflow.md` の全項目（B/C）が対応済みであることを確認
