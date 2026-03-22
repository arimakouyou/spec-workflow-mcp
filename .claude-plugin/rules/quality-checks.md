---
paths:
  - "**/*.rs"
  - "**/Cargo.toml"
  - "**/package.json"
---

# Quality Check Commands

Unified command specification for quality checks run by parallel-worker, review-worker, and other agents. All agents must use the commands defined in this rule.

## rustfmt

```bash
cargo fmt --all -- --check
```

- Targets both `src` and `tests` (do not check only one of them)
- To auto-fix, run without `--check`: `cargo fmt --all`

## clippy

```bash
cargo clippy --quiet --all-targets -- -D warnings
```

- `--all-targets`: Includes test code, benchmarks, and examples in the check
- `-D warnings`: Treats all warnings as errors
- `--quiet`: Suppresses progress output

## test

```bash
cargo test --quiet
```

- Runs all tests (unit + integration)
- To run a specific test only: `cargo test --test {test_name} -- --nocapture`

## Leptos Full-Stack (WASM Frontend) Build Verification

When the project uses `cargo-leptos` (detected by `[package.metadata.leptos]` in `Cargo.toml`), the following additional checks are **required** after the standard checks above.

### cargo-leptos build (preferred)

```bash
cargo leptos build
```

- Builds both SSR (server) and WASM (client) targets in a single command
- Catches WASM compilation errors that `cargo build` / `cargo test` alone cannot detect (they only compile for the host target)
- Must pass before any commit

### WASM-specific clippy (required fallback when cargo-leptos is unavailable)

```bash
cargo clippy --target wasm32-unknown-unknown --no-default-features --features hydrate --quiet -- -D warnings
```

- **Required** when `cargo-leptos` is not installed — WASM verification must not be skipped
- `--features hydrate`: Compiles only the client-side code path
- Detects WASM-incompatible API usage (e.g., `std::fs`, `std::net`, `tokio::spawn`)

### Detection and availability check for agents

Before running quality checks, agents must check for a Leptos full-stack configuration and tool availability:

```bash
# Step 1: Detect Leptos project（ブラケット付きヘッダでマッチ）
grep -q '\[package.metadata.leptos\]' Cargo.toml 2>/dev/null

# Step 2: If Leptos detected, check cargo-leptos availability
cargo leptos --version 2>/dev/null
```

| Leptos detected | cargo-leptos available | Action |
|-----------------|----------------------|--------|
| No | — | Skip WASM checks |
| Yes | Yes | Run `cargo leptos build` |
| Yes | No | Run WASM-specific clippy as required fallback |

The full check order becomes:

1. `cargo fmt --all -- --check`
2. `cargo clippy --quiet --all-targets -- -D warnings`
3. `cargo test --quiet`
4. `cargo leptos build` OR WASM-specific clippy fallback (Leptos projects only)

## Integration Verification (Phase Review / Final E2E Gate)

Phase Review (3.5.1.5) および全Phase完了後の Final E2E Gate (セクション9) で実行する統合レベルの検証。
タスク単位の品質チェック（rustfmt, clippy, cargo test）とは独立したステップとして実行する。

### プロジェクトタイプ検出

以下の順で検出し、最初にマッチしたタイプを採用する:

```bash
# 1. Leptos フルスタック検出
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
| Node.js | `npm run build` | `build` スクリプトが package.json に存在する場合のみ |
| Generic | `cargo build` or `npm run build` | 検出可能なビルドコマンドを実行 |

### Step C: 統合テスト実行（テストが存在する場合のみ）

統合テストファイルが存在する場合にのみ実行する。存在しない場合は SKIP（FAIL ではない）。

```bash
# Rust: 統合テストの存在確認（find を使用し globstar 依存を回避）
find tests -type f -name 'integration*' -print -quit 2>/dev/null

# Node.js: 統合テストスクリプトまたはファイルの存在確認
grep -q '"test:integration"' package.json 2>/dev/null || \
  find tests test __tests__ -type f -name 'integration*' -print -quit 2>/dev/null
```

| タイプ | コマンド |
|--------|---------|
| Rust | `cargo test --test 'integration*' --quiet` |
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
  # package.json に dev スクリプトがあれば優先的に使用し、なければ npm start を利用
  if command -v node >/dev/null 2>&1 && \
     node -e "const p=require('./package.json'); process.exit(p.scripts && p.scripts.dev ? 0 : 1)" >/dev/null 2>&1; then
    START_CMD="npm run dev"
  else
    START_CMD="npm start"
  fi
else
  echo "Step D: 対応するプロジェクトタイプ（Rust/Node.js）が見つからないため、スモークテストをスキップします。" >&2
  exit 0
fi

# バックグラウンドでサーバ起動（プロセスグループで確実に停止）
$START_CMD &
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

# クリーンアップ（trap でも処理されるが明示的にも実行）
kill -- -$SERVER_PID 2>/dev/null
wait $SERVER_PID 2>/dev/null
```

**スモークテストの SKIP 条件**（FAIL ではなく SKIP として扱う）:
- ヘルスチェックエンドポイントが定義されていない（設計書に記載なし）
- 外部依存（DB、キャッシュ等）が必要でローカル起動できない
- サーバ起動コマンドが不明（Cargo.toml に `[[bin]]` セクションがない等）
- Node.js プロジェクトで `start` / `dev` スクリプトが存在しない
- 対応するプロジェクトタイプ（Rust/Node.js）が検出されない

SKIP 時は必ずログに理由を記録し、Expert Team Review で補完する。

### 統合検証の結果判定

| 結果 | 条件 | アクション |
|------|------|----------|
| **PASS** | ビルド成功 + 統合テスト全パス（or SKIP）+ スモーク OK（or SKIP） | 次ステップに進む |
| **FAIL (ビルド)** | ビルド失敗 | ビルドエラーを分析し、根本原因タスクを特定して差し戻し |
| **FAIL (統合テスト)** | 統合テスト失敗 | 失敗テストのエラーを分析。Phase内タスク → 差し戻し、前Phase → ユーザーエスカレート |
| **FAIL (スモーク)** | ヘルスチェック失敗（SKIP条件に該当しない場合） | 起動ログを分析し根本原因を特定して差し戻し |
| **SKIP** | 環境依存で実行不可 | ログに SKIP 理由を記録し、次ステップに進む。Expert Team Review で補完 |
