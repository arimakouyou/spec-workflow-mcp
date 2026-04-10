# Plan: ビルドツール・コンテナのバージョン例更新と動的検出の強制

## Context

プラグインのワークフロー（spec-design, spec-test-design）のテンプレートとスキルに記載されたビルドツール・コンテナイメージのバージョン例が大幅に古い。これにより、AIが設計書やDockerfileを生成する際に古いバージョン（例: `rust:1.83-bookworm`）を採用してしまい、開発時のビルドツールとリリース用コンテナのバージョン不整合が発生する。

**現状 vs 実際:**

| 項目 | テンプレート/スキルの例 | 実際の安定版 |
|------|----------------------|------------|
| cargo | >= 1.82 | 1.93.0 |
| Rust base image | rust:1.82-slim | rust:1.93-slim |
| docker | >= 24.0 | 29.2.1 |
| docker compose | >= 2.20 | 5.1.0 |
| node | node:22-alpine | node:24-alpine |
| playwright | >= 1.42.0 | >= 1.58.0 |
| chromium | any | (bundled with playwright) |

未実装の先行プラン `calm-conjuring-rain.md` の動的検証ステップ（Step 1, 2, 4, 5）も合わせて実装する。CVE監査（Step 3）はスコープ外とし別PRで対応。

---

## 変更対象ファイル

| # | ファイル | 変更内容 |
|---|---------|---------|
| 1 | `src/markdown/templates/design-template.md` | バージョン例の更新 + 検出注記追加 |
| 2 | `src/markdown/templates/test-design-template.md` | バージョン例の更新 + 検出注記追加 |
| 3 | `.claude-plugin/skills/spec-design/SKILL.md` | バージョン例更新 + 検出指示強化 + Version Freshness Verification ステップ追加 + 整合性ルール追加 |
| 4 | `.claude-plugin/skills/spec-test-design/SKILL.md` | Section 3.3.1 テストツールバージョン検証追加 |
| 5 | (ビルド) `dist/markdown/templates/` | `npm run build` で自動反映 |

---

## Step 1: `src/markdown/templates/design-template.md` — バージョン例更新

### 1a. Container Architecture base image (L87)

```
変更前: - **Base Image:** [例: rust:1.82-slim, node:22-alpine]
変更後: - **Base Image:** [例: rust:1.93-slim, node:24-alpine]
```

### 1b. Required Build Tools テーブル (L113-116)

```
変更前:
| [例: cargo] | [例: >= 1.82] | ...
| [例: docker] | [例: >= 24.0] | ...
| [例: docker compose] | [例: >= 2.20] | ...

変更後:
| [例: cargo] | [例: >= 1.93] | ...
| [例: docker] | [例: >= 29.0] | ...
| [例: docker compose] | [例: >= 5.1] | ...
```

### 1c. Notes セクション末尾 (L121 の後) にバージョン検出注記追加

```markdown
- **Version Detection (MANDATORY)**: 上記テーブルの例はフォーマットの参考のみ。実際のバージョンは `cargo --version`, `docker --version`, `docker compose version` 等を実行して検出した値を記載すること。AI の学習データやテンプレートの例をそのまま使用しない
- **Container Image Consistency**: Base Image のタグ（例: `rust:1.93-slim`）は Required Build Tools の Min Version と一致させること
```

## Step 2: `src/markdown/templates/test-design-template.md` — バージョン例更新

### 2a. Required Test Tools テーブル (L33-35)

```
変更前:
| [例: docker] | [例: >= 24.0] | ...
| [例: playwright] | [例: >= 1.42.0] | ...
| [例: chromium] | [例: any] | [例: E2E ブラウザエンジン] | [例: node -e "console.log(require('playwright').chromium.executablePath())"] | [例: npx playwright install chromium] | Yes |

変更後:
| [例: docker] | [例: >= 29.0] | ...
| [例: playwright] | [例: >= 1.58.0] | ...
| [例: chromium] | [例: (bundled with playwright)] | [例: E2E ブラウザエンジン（Playwright バージョンに対応するビルドを使用）] | [例: npx playwright --version] | [例: npx playwright install chromium] | Yes |
```

### 2b. Notes 末尾 (L43 の後) にバージョン検出注記追加

```markdown
- **Version Detection (MANDATORY)**: Min Version はテンプレートの例をそのまま使用しない。実行環境で各ツールの Check Command を実行し、検出した値を記載すること
- **Browser Version**: Chromium/Chrome のバージョンは Playwright のバージョンと連動する。`npx playwright install chromium` で Playwright バージョンに対応する最新ブラウザを取得すること。古い Playwright を使うと古いブラウザエンジンが使用される
```

## Step 3: `.claude-plugin/skills/spec-design/SKILL.md` — 検出指示強化

### 3a. Required Build Tools 例テーブル (L222-223)

```
変更前:
| cargo | >= 1.82 | Rust build system | cargo --version | rustup update | Yes |
| docker | >= 24.0 | Container runtime | docker --version | apt install docker.io | Yes |

変更後:
| cargo | >= 1.93 | Rust build system | cargo --version | rustup update | Yes |
| docker | >= 29.0 | Container runtime | docker --version | apt install docker.io | Yes |
```

### 3b. 検出指示の強化 (L215)

```
変更前:
Based on the Key Design Decisions from Wave 1, list all CLI tools needed to build, test, and run the project. Search the codebase to detect current tool versions.

変更後:
Based on the Key Design Decisions from Wave 1, list all CLI tools needed to build, test, and run the project. Run each tool's `--version` command to detect the actually-installed version. Do NOT copy example versions from this skill file or the template — the examples below are format references only.
```

### 3c. 導出ルール (L231 の後) にルール6追加

```markdown
6. Min Version はテンプレートや本スキルの例をそのまま使用しない。`cargo --version`, `docker --version` 等を実行して実バージョンを検出し、その値を記載すること
7. Container Architecture の Base Image タグ（例: `rust:X.YZ-slim`）は Required Build Tools の Min Version と一致させること。不一致は Wave 2 Self-Review で FAIL
```

### 3d. Version Freshness Verification ステップ追加 (L105 付近、Wave 1 step 3 の後)

`calm-conjuring-rain.md` の Step 1 の内容を挿入:

```markdown
### 3.5 Version Freshness Verification (MANDATORY)

Key Design Decisions の記述後、記載した全てのライブラリ・フレームワークのバージョンが最新安定版であることを検証する。

#### 3.5.1 バージョン情報の抽出
Key Design Decisions セクションから技術名＋バージョンのペアを全て収集する。

#### 3.5.2 最新安定版の確認
1. **WebSearch**（推奨）: "{ライブラリ名} latest stable release"
2. **context7 MCP**（補助）: resolve-library-id → query-docs
3. **レジストリ CLI フォールバック**: `cargo search {crate} --limit 1` / `npm view {pkg} version`

#### 3.5.3 バージョン更新
| Library | Design Version | Latest Stable | Action |
|---------|---------------|---------------|--------|
| {name} | {old} | {new} | Updated / Kept (理由) |

- steering ドキュメントが特定バージョンを指定している場合は維持し理由を注記
- メジャーバージョン変更がある場合は Architecture Confirmation でユーザーに報告
```

## Step 4: `.claude-plugin/skills/spec-test-design/SKILL.md` — テストツールバージョン検証

`calm-conjuring-rain.md` の Step 2 の内容。Section 3.3 (L104-123) の末尾に追加:

```markdown
#### 3.3.1 テストツールバージョン検証

Required Test Tools テーブルの各ツールについて、Min Version が最新安定版であることを確認する:

1. WebSearch またはレジストリ CLI で最新安定版を確認
   - Playwright: `npx playwright --version` で検出
   - Chromium: Playwright バージョンに対応するバンドル版を使用（`npx playwright install chromium`）。Min Version は `(bundled with playwright)` と記載し、Playwright のバージョンアップで自動的に最新ブラウザエンジンが適用されるようにする
2. Min Version を検証済みの最新安定版に更新

Phase 2 step 3.5 と同様、AI の学習データのデフォルト値を使用しない。
```

## Step 5: ビルド

```bash
npm run build
```

`copy-static.cjs` により `src/markdown/templates/*.md` → `dist/markdown/templates/*.md` に反映される。

---

## 検証方法

1. `grep -n "1\.82\|1\.42\|24\.0\|2\.20\|22-alpine" src/markdown/templates/*.md .claude-plugin/skills/spec-design/SKILL.md .claude-plugin/skills/spec-test-design/SKILL.md` → 0件であること（chromium の `any` も残っていないこと）
2. `npm run build` が成功すること
3. `npm test -- --run` が通ること
4. `diff src/markdown/templates/design-template.md dist/markdown/templates/design-template.md` で dist が最新であること
