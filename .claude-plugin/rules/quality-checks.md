---
paths:
  - "**/*.rs"
  - "**/Cargo.toml"
  - "**/package.json"
---

# Quality Check Commands

Unified command specification for quality checks run by parallel-worker, review-worker, and other agents. All agents must use the commands defined in this rule.

> **CI Parity**: These commands are also used by the `/setup-ci` skill to generate GitHub Actions CI workflow YAML. CI templates may include additional setup steps (tool installation etc.) as prerequisites, but the quality check commands themselves must be identical. Re-run `/setup-ci` after updating this file to keep CI in sync.

> **Build Cache**: When running these commands, apply the Rust build cache configuration as described in `.claude-plugin/rules/rust-build-cache.md` (e.g., by using a single Bash snippet that both configures the cache and runs the `cargo` commands, or by using a per-command `RUSTC_WRAPPER=sccache cargo ...` prefix).

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

## Dependency Analysis (Optional Tools)

Additional checks for dependency hygiene and security. These tools are optional — they run when installed and are skipped when unavailable. Agents must detect availability before running.

> **Note**: sccache (`RUSTC_WRAPPER`) is **not** applied to these commands. `cargo audit` does not invoke the compiler, and `cargo-udeps` uses `+nightly` which has unreliable sccache compatibility.

### cargo-audit (Security — blocking)

```bash
cargo audit
```

- Checks dependencies against the RustSec Advisory Database
- **Blocking**: If installed and vulnerabilities are found, the check **fails**. Agents must report findings and stop
- Fast execution (database lookup only, no compilation)
- See also: `.claude-plugin/rules/security.md` section A9

### cargo-udeps (Unused dependencies — advisory)

```bash
cargo +nightly udeps --quiet
```

- Detects unused dependencies declared in `Cargo.toml`
- **Advisory**: Results are reported as warnings but **do not block** commits
- Requires nightly toolchain (`rustup run nightly`)
- Runs the compiler internally, so the project must compile successfully first (place after `cargo test`)

### Detection and availability check

```bash
# cargo-audit
AUDIT_AVAILABLE=false
if command -v cargo-audit >/dev/null 2>&1; then
  AUDIT_AVAILABLE=true
fi

# cargo-udeps (requires nightly)
UDEPS_AVAILABLE=false
if command -v cargo-udeps >/dev/null 2>&1 && rustup run nightly rustc --version >/dev/null 2>&1; then
  UDEPS_AVAILABLE=true
fi
```

| Tool | Installed | Nightly available | Action |
|------|-----------|-------------------|--------|
| cargo-audit | Yes | — | Run `cargo audit`. Fail on vulnerabilities |
| cargo-audit | No | — | Skip with log: "cargo-audit not installed, skipping vulnerability check" |
| cargo-udeps | Yes | Yes | Run `cargo +nightly udeps --quiet`. Warn on findings |
| cargo-udeps | Yes | No | Skip with log: "nightly toolchain unavailable, skipping udeps" |
| cargo-udeps | No | — | Skip silently |

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
4. `cargo audit` (if installed — blocking on vulnerabilities)
5. `cargo +nightly udeps --quiet` (if installed — advisory only)
6. `cargo leptos build` OR WASM-specific clippy fallback (Leptos projects only)

## Node.js Task-Level Quality Checks

When the project is Node.js-based (detected by `package.json` existence without Rust indicators), use the following task-level quality checks.

### lint

```bash
npx eslint . --max-warnings=0
```

- Falls back to `npx tsc --noEmit` if eslint is not configured
- If neither eslint nor TypeScript is configured, skip this check

### format

```bash
npx prettier --check .
```

- Skip if prettier is not configured in the project

### test

```bash
npm test
```

- Or `npx vitest run` / `npx jest` depending on the project's test runner
- To run a specific test: `npm test -- --testPathPattern={test_name}`

### type check (conditional)

```bash
npx tsc --noEmit
```

- Only run if `typescript` is in devDependencies
- If eslint is not configured, this serves as the lint fallback (see above)

### build (conditional)

```bash
npm run build
```

- Only run if `scripts.build` exists in package.json
- Skip if no build script is defined (not a failure)

The full check order for Node.js projects:

1. `npx eslint . --max-warnings=0` (or `npx tsc --noEmit` fallback)
2. `npx prettier --check .`
3. `npm test`
4. `npx tsc --noEmit` (if TypeScript configured and not already run as lint fallback)
5. `npm run build` (if build script exists)

## Integration Verification (Phase Review / Final E2E Gate)

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
