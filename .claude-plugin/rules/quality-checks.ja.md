---
paths:
  - "**/*.rs"
  - "**/Cargo.toml"
  - "**/package.json"
---

# 品質チェックコマンド

parallel-worker、review-worker、その他のエージェントが実行する品質チェックの統一コマンド仕様。すべてのエージェントはこのルールで定義されたコマンドを使用しなければならない。

> **ビルドキャッシュ**: これらのコマンドを実行する際は、`.claude-plugin/rules/rust-build-cache.md` に記載された Rust ビルドキャッシュ設定を適用すること（例: キャッシュ設定と `cargo` コマンドの両方を含む単一の Bash スニペットを使用するか、コマンドごとに `RUSTC_WRAPPER=sccache cargo ...` プレフィックスを使用する）。

## rustfmt

```bash
cargo fmt --all -- --check
```

- `src` と `tests` の両方を対象とする（片方だけチェックしない）
- 自動修正するには `--check` なしで実行: `cargo fmt --all`

## clippy

```bash
cargo clippy --quiet --all-targets -- -D warnings
```

- `--all-targets`: テストコード、ベンチマーク、examples もチェック対象に含める
- `-D warnings`: すべての警告をエラーとして扱う
- `--quiet`: 進捗出力を抑制する

## test

```bash
cargo test --quiet
```

- すべてのテスト（ユニット + 統合）を実行する
- 特定のテストのみ実行する場合: `cargo test --test {test_name} -- --nocapture`

## Leptos フルスタック（WASM フロントエンド）ビルド検証

プロジェクトが `cargo-leptos` を使用している場合（`Cargo.toml` に `[package.metadata.leptos]` が存在することで検出）、上記の標準チェックに加えて以下の追加チェックが**必須**となる。

### cargo-leptos ビルド（推奨）

```bash
cargo leptos build
```

- 単一コマンドで SSR と WASM の両方のターゲットをビルドする
- `cargo build` / `cargo test` だけでは検出できない WASM コンパイルエラーをキャッチする（これらはホストターゲットのみをコンパイルする）
- コミット前に必ずパスしなければならない

### WASM 固有の clippy（cargo-leptos が利用できない場合の必須フォールバック）

```bash
cargo clippy --target wasm32-unknown-unknown --no-default-features --features hydrate --quiet -- -D warnings
```

- `cargo-leptos` がインストールされていない場合に**必須** — WASM 検証をスキップしてはならない
- `--features hydrate`: クライアントサイドのコードパスのみをコンパイルする
- WASM 非互換の API 使用（例: `std::fs`、`std::net`、`tokio::spawn`）を検出する

### エージェント向けの検出と利用可能性チェック

品質チェックを実行する前に、エージェントは Leptos フルスタック構成とツールの利用可能性を確認しなければならない:

```bash
# ステップ 1: Leptos プロジェクトの検出（ブラケット付きヘッダでマッチ）
grep -q '\[package.metadata.leptos\]' Cargo.toml 2>/dev/null

# ステップ 2: Leptos が検出された場合、cargo-leptos の利用可能性を確認
cargo leptos --version 2>/dev/null
```

| Leptos 検出 | cargo-leptos 利用可能 | アクション |
|-------------|----------------------|-----------|
| いいえ | — | WASM チェックをスキップ |
| はい | はい | `cargo leptos build` を実行 |
| はい | いいえ | WASM 固有の clippy を必須フォールバックとして実行 |

完全なチェック順序は以下の通り:

1. `cargo fmt --all -- --check`
2. `cargo clippy --quiet --all-targets -- -D warnings`
3. `cargo test --quiet`
4. `cargo leptos build` または WASM 固有の clippy フォールバック（Leptos プロジェクトのみ）

## Node.js タスクレベルの品質チェック

プロジェクトが Node.js ベースの場合（Rust の指標なしに `package.json` が存在することで検出）、以下のタスクレベルの品質チェックを使用する。

### lint

```bash
npx eslint . --max-warnings=0
```

- eslint が設定されていない場合は `npx tsc --noEmit` にフォールバックする
- eslint も TypeScript も設定されていない場合はこのチェックをスキップする

### format

```bash
npx prettier --check .
```

- プロジェクトに prettier が設定されていない場合はスキップする

### test

```bash
npm test
```

- プロジェクトのテストランナーに応じて `npx vitest run` / `npx jest` も可
- 特定のテストを実行する場合: `npm test -- --testPathPattern={test_name}`

Node.js プロジェクトの完全なチェック順序:

1. `npx eslint . --max-warnings=0`（または `npx tsc --noEmit` フォールバック）
2. `npx prettier --check .`
3. `npm test`

## 統合検証（フェーズレビュー / 最終 E2E ゲート）

Phase Review (3.5.1.5) および全Phase完了後の Final E2E Gate (セクション9) で実行する統合レベルの検証。
タスク単位の品質チェック（rustfmt, clippy, cargo test）とは独立したステップとして実行する。

### プロジェクトタイプ検出

以下の順で検出し、最初にマッチしたタイプを採用する:

```bash
# 1. Leptos フルスタック検出（ブラケット付きヘッダで誤検出を防止）
if grep -q '\[package.metadata.leptos\]' Cargo.toml 2>/dev/null; then
  echo "leptos"
# 2. Rust API 検出（axum, actix-web, rocket 等）
elif grep -qE '(axum|actix-web|rocket)' Cargo.toml 2>/dev/null; then
  echo "rust-api"
# 3. Node.js 検出
elif test -f package.json; then
  echo "nodejs"
# 4. いずれにも該当しない
else
  echo "generic"
fi
```

### Step B: ビルド検証（全プロジェクト共通・必須）

成果物のビルドが成功することを確認する。ビルド失敗は即座に FAIL とする。

| タイプ | コマンド | 備考 |
|--------|---------|------|
| Leptos | `cargo leptos build` | SSR + WASM 両方をビルド |
| Rust API | `cargo build` | リリースビルドは不要（デバッグビルドで十分） |
| Node.js | `npm run build` | `build` スクリプトが package.json に存在する場合のみ。存在しない場合は SKIP（FAIL ではない）とし、ログに「build スクリプトなし」と記録 |
| Generic | `cargo build` or `npm run build` | 検出可能なビルドコマンドを実行。該当コマンドがない場合は SKIP とする |

### Step C: 統合テスト実行

統合テストファイルが存在する場合に実行する。存在しない場合の判定（優先順）:
- design.md の Excluded Test Environments に当該統合テスト環境の除外宣言がある → **SKIP（設計時除外）**
- 上記の除外宣言はなく、test-design.md に当該統合テスト仕様が定義されている → **FAIL（実装漏れ）** — テストファイルの作成が必要
- 上記いずれにも該当せず、test-design.md に当該統合テスト仕様が未定義 → **SKIP（設計上不要）** — ログに理由を記録し Expert Team Review で補完

**「test-design.md に統合テスト仕様が定義されている」の客観的判定基準**（オーケストレータはこのルールに厳密に従うこと）:
- test-design.md 内に `## Integration Test Specifications` セクション見出しが存在する
- かつ、そのセクション内に `### IT-` で始まる見出しが 1 件以上存在する（例: `### IT-1: APIエンドポイント統合テスト`）
- 上記 2 条件を共に満たす場合のみ「仕様あり」とみなす。条件を満たさない場合は「仕様なし」

```bash
# Rust: 統合テストの存在確認（tests/ ディレクトリ内の .rs ファイル。e2e/ と unit/ は再帰的に除外）
# 検出対象: tests/integration*/ 配下の .rs ファイル、または tests/ 直下の .rs ファイル
find tests -type f -name '*.rs' ! -regex '.*/tests/\(e2e\|unit\)/.*' -print -quit 2>/dev/null

# Node.js: 統合テストスクリプトまたはファイルの存在確認
grep -q '"test:integration"' package.json 2>/dev/null || \
  find tests test __tests__ -type f -name 'integration*' -print -quit 2>/dev/null
```

| タイプ | コマンド |
|--------|---------|
| Rust | `cargo test --tests --quiet` |
| Node.js（スクリプトあり） | `npm run test:integration` |
| Node.js（ファイルのみ） | `npm test -- --testPathPattern=integration` |

### Step D: スモークテスト（API プロジェクトのみ）

API サーバを一時的に起動し、ヘルスチェックエンドポイントへの疎通を確認する。

**コンテナベース（docker-compose.yml が存在する場合 — 優先）:**

```bash
# docker-compose でサービスを起動
docker-compose up -d
sleep 10
```

ヘルスチェック実行後:
```bash
docker-compose down
```

**直接起動（docker-compose.yml が存在しない場合 — フォールバック）:**

```bash
# プロジェクトタイプに応じてサーバ起動コマンドを切り替え
if [ -f Cargo.toml ]; then
  START_CMD="cargo run"
elif [ -f package.json ]; then
  # package.json に dev スクリプトがあれば優先的に使用し、なければ start スクリプトを確認
  if command -v node >/dev/null 2>&1 && \
     node -e "const p=require('./package.json'); process.exit(p.scripts && p.scripts.dev ? 0 : 1)" >/dev/null 2>&1; then
    START_CMD="npm run dev"
  elif command -v node >/dev/null 2>&1 && \
       node -e "const p=require('./package.json'); process.exit(p.scripts && p.scripts.start ? 0 : 1)" >/dev/null 2>&1; then
    START_CMD="npm start"
  else
    echo "Step D: Node.js プロジェクトで start / dev スクリプトが存在しないため、スモークテストをスキップします。" >&2
    exit 0
  fi
else
  echo "Step D: 対応するプロジェクトタイプ（Rust/Node.js）が見つからないため、スモークテストをスキップします。" >&2
  exit 0
fi

# バックグラウンドでサーバ起動（新しいセッションで確実に停止可能にする）
setsid sh -c "$START_CMD" &
SERVER_PID=$!
trap "kill -- -$SERVER_PID 2>/dev/null; wait $SERVER_PID 2>/dev/null" EXIT
sleep 5

# ヘルスチェック（/health と /api/health を順に試行）
HEALTH_STATUS="000"
for ENDPOINT in "/health" "/api/health" "/healthz"; do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${PORT:-3000}${ENDPOINT}" 2>/dev/null)
  if [ "$STATUS" = "200" ]; then
    HEALTH_STATUS="200"
    break
  fi
done

# クリーンアップ
kill -- -$SERVER_PID 2>/dev/null
wait $SERVER_PID 2>/dev/null

# PASS/FAIL 判定
if [ "$HEALTH_STATUS" != "200" ]; then
  echo "Step D: ヘルスチェック失敗 — いずれのエンドポイントからも 200 が返りませんでした。" >&2
  exit 1
fi
```

**スモークテストの SKIP 条件**（設計上テストが不要・不可能な場合のみ）:
- ヘルスチェックエンドポイントが設計書に未定義
- サーバ起動コマンドが不明（Cargo.toml に `[[bin]]` セクションがない等）
- Node.js プロジェクトで `start` / `dev` スクリプトが存在しない
- 対応するプロジェクトタイプ（Rust/Node.js）が検出されない

**環境不備の FAIL 条件**（ツール・ランタイム不足の場合 — 環境依存のスキップは一切許可しない）:
- Docker/コンテナランタイムが未インストール、または `docker` / `docker-compose` コマンドが存在しない・権限不足で実行できない（`docker-compose up` の起動失敗を含む）
- Chrome/ブラウザが未インストール
- DB/キャッシュ起動に必要なツールが未インストール
- サーバ起動に必要なランタイム（cargo, node 等）が未インストール
- 外部依存（DB、キャッシュ等）が必要でローカル起動できない（Docker/testcontainers で起動できるようにするのが設計の責務）

環境不備 FAIL 時は、不足ツールを明示してユーザーにエスカレートする。design.md / test-design.md の Required Tools テーブルの Install Command を提示すること。特に `docker-compose.yml` が存在しスモークテストで `docker-compose up` を実行する場合、コマンド未存在・実行権限不足・起動失敗はいずれも FAIL（環境不備）として直ちに STOP し、SKIP/PASS として扱わないこと。

**テスト実装漏れの FAIL 条件**:
- test-design.md に E2E テスト仕様が定義されているのにテストファイルが存在しない → FAIL（実装漏れ）
- test-design.md に IT 仕様が定義されているのに統合テストファイルが存在しない → FAIL（実装漏れ）

SKIP 時は必ずログに理由を記録し、Expert Team Review で補完する。

### 統合検証の結果判定

| 結果 | 条件 | アクション |
|------|------|----------|
| **PASS** | ビルド成功 + 全テストパス + スモーク OK（SKIP(設計上不要)/SKIP(設計時除外)/SKIP(ビルドコマンド未検出) を含む） | 次ステップに進む |
| **FAIL (ビルド)** | ビルド失敗 | ビルドエラーを分析し、根本原因タスクを特定して差し戻し |
| **FAIL (統合テスト)** | 統合テスト失敗 | 失敗テストのエラーを分析。Phase内タスク → 差し戻し、前Phase → ユーザーエスカレート |
| **FAIL (スモーク)** | ヘルスチェック失敗（SKIP条件に該当しない場合） | 起動ログを分析し根本原因を特定して差し戻し |
| **FAIL (環境不備)** | 必須ツール・ランタイム未インストール | 不足ツールをユーザーに報告し、Required Tools テーブルの Install Command を提示。実装を停止（STOP） |
| **FAIL (実装漏れ)** | test-design.md にテスト仕様ありだがテストファイルなし | テスト実装の漏れとしてユーザーに報告 |
| **SKIP (設計上不要)** | テスト仕様自体が存在しない（設計書に未定義） | ログに SKIP 理由を記録し、次ステップに進む。Expert Team Review で補完 |
| **SKIP (設計時除外)** | design.md の「Excluded Test Environments」で明示的に除外 | 除外理由をログに記録し、次ステップに進む |
