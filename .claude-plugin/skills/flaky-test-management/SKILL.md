---
name: flaky-test-management
description: |
  Flaky Test (不安定テスト) 管理ポリシー。FT1 分類 (Timing / Order / Environment / Data-dependent)、FT2 CI ベースおよび手動検出 (`cargo test --test-threads=1` や 10 回リピート、`npx jest --runInBand`)、FT3 GitHub Issues での追跡 (`flaky-test` label + Issue テンプレ)、FT4 リトライ設定 (cargo-nextest / Vitest / Jest / GitHub Actions nick-fields/retry)、FT5 隔離 (`#[ignore]` / `.skip`、最大 30 日、全テストの 5% 以下)、FT6 予防 (sleep 禁止、固定ポート禁止、`DateTime::now()` 禁止、testcontainers / シード付き乱数を推奨) をカバー。flaky テスト発生時、CI で断続的に失敗するテストの対処、テスト環境分離の設計、`regression-test-policy` の健全性指標レビュー時に参照。
allowed-tools: [Read, Edit, Write, Bash, Grep, Glob]
---

# Flaky Test 管理ポリシー

Flaky test（不安定テスト）の定義、検出、追跡、対処方針を定義する。
P6-07, P6-08, P6-09 に対応する。

## 対象

- CI で断続的に失敗するテストの検出と対処
- テスト隔離判断（`#[ignore]` / `.skip`）
- Issue テンプレートに沿った flaky テスト追跡
- テストランナー設定（cargo-nextest / Vitest / Jest / GitHub Actions）でのリトライ
- flaky を生みにくいテスト設計（testcontainers、シード付き乱数、トランザクションロールバック）

## 対象外

- テストコード全般の書き方 → `tdd-skills` / `tdd-skills-rust` / `tdd-skills-dotnet`
- リグレッションテストの定着 → `regression-test-policy` Skill
- 統合テストのフィクスチャ設計 → `integration-test` / `integration-test-dotnet` Skill

## FT1: 定義と分類 (P6-07)

**Flaky test** とは、コード変更なしに実行結果（成功/失敗）が変わるテストのこと。

### 分類

| カテゴリ | 原因 | 典型例 |
|---------|------|--------|
| Timing-dependent | 競合状態、タイムアウト感度 | `sleep(100)` に依存、非同期処理の完了待ち不足 |
| Order-dependent | 実行順序、共有可変状態 | テスト間でグローバル状態を共有、DB が未クリーンアップ |
| Environment-dependent | ポート、ファイルハンドル、ネットワーク | 固定ポートの衝突、ディスク容量不足、DNS 解決失敗 |
| Data-dependent | タイムスタンプ、乱数、外部 API | `DateTime::now()` に依存、外部 API のレート制限 |

## FT2: 検出 (P6-08)

### CI ベースの検出

テストが CI で失敗し、コード変更なしの再実行で成功した場合、flaky 候補として記録する。

### 手動検出コマンド

```bash
# Rust: 順序依存の分離（シングルスレッド実行）
cargo test -- --test-threads=1

# Rust: 繰り返し実行で安定性を確認（10回）
for i in $(seq 1 10); do
  cargo test --quiet 2>&1 || echo "FAIL on iteration $i"
done

# Node.js: 順序依存の分離
npx jest --runInBand
# または
npx vitest --pool=forks --poolOptions.forks.singleFork
```

### リトライベースの検出

リトライ設定（FT4）を有効にした状態で、リトライ 2回目以降に成功したテストは flaky として自動検出する。

## FT3: 追跡 (P6-08)

Flaky test は GitHub Issues で `flaky-test` ラベルを付けて管理する。

### Issue テンプレート

```markdown
## Flaky Test Report

- **テスト名**: `{test_module}::{test_name}`
- **分類**: {FT1 カテゴリ: Timing / Order / Environment / Data}
- **初検出日**: {YYYY-MM-DD}
- **頻度**: {N}回中{M}回失敗（直近 {period}）
- **CI ログ**: {link to failed run}
- **担当者**: @{assignee}

### 再現手順

{再現コマンドと条件}

### 仮説

{flaky の原因仮説}
```

## FT4: リトライ設定 (P6-09)

リトライは**緩和策**であり修正ではない。リトライされたテストは FT3 に従って追跡対象とする。

### Rust (cargo-nextest)

`.config/nextest.toml`:

```toml
[profile.default]
retries = 2
```

### Node.js (Vitest)

`vitest.config.ts`:

```typescript
export default defineConfig({
  test: {
    retry: 2,
  },
});
```

### Node.js (Jest)

`jest.config.js`:

```javascript
module.exports = {
  // グローバルリトライ
  // jest.retryTimes(2) をテストファイル内で呼び出す
};
```

### GitHub Actions (ステップレベル)

```yaml
- name: Tests (with retry)
  uses: nick-fields/retry@v3
  with:
    max_attempts: 3
    command: cargo test --quiet
```

## FT5: 隔離（Quarantine） (P6-09)

持続的に不安定なテストは隔離し、PR マージをブロックしないようにする。

### 隔離方法

| 言語 | 方法 | 例 |
|------|------|-----|
| Rust | `#[ignore]` + コメント | `#[ignore = "flaky: #123"]` |
| Jest/Vitest | `.skip` + コメント | `it.skip('test name') // flaky: #123` |

### 隔離ルール

- 隔離テストには必ず Issue 番号をコメントに記載すること
- 隔離テストは別の CI ジョブ（`flaky-quarantine`）で非ブロッキング実行
- **最大隔離期間: 30日** — 超過したら修正するかテスト自体を削除する
- 隔離数の上限: プロジェクト全体のテスト数の 5% 以下

### 隔離テスト用 CI ジョブ（参考）

```yaml
  flaky-quarantine:
    name: Quarantined Tests (non-blocking)
    runs-on: ubuntu-latest
    continue-on-error: true
    steps:
      - uses: actions/checkout@v4
      # Rust: #[ignore] 付きテストのみ実行
      - run: cargo test -- --ignored --test-threads=1
```

## FT6: 予防

Flaky test の発生を防ぐためのガイドライン。

### 禁止パターン

| パターン | 代替 |
|---------|------|
| `sleep(N)` / 固定タイムアウト | ポーリング + 指数バックオフ + 最大待機時間 |
| 固定ポート番号 | ランダムポート or OS 割当（port 0） |
| `DateTime::now()` に依存 | Clock trait / テスト用固定時刻を DI |
| 外部 API への直接呼び出し | モック / WireMock / testcontainers |
| 共有 DB への直接書き込み | トランザクションロールバック / testcontainers |
| テスト間の暗黙的順序依存 | 各テストで完全なセットアップ/ティアダウン |

### 推奨パターン

- **testcontainers** で外部サービスを完全に隔離する
- **シード付き乱数** (`StdRng::seed_from_u64(42)`) で決定論的なテストデータ
- **ファクトリ/フィクスチャ** パターンでテストデータを構造化
- **トランザクションロールバック** で DB テストの分離を保証
- 疑わしいテストは `--test-threads=1` で分離実行して原因を特定

## 関連 Rule / Skill

- 普遍制約: `quality-checks` (QC3, QC12), `diagnostic-reasoning` (DR1-DR6), `failure-taxonomy` (FC1-FC6)
- 関連 Skill: `regression-test-policy`, `tdd-skills`, `tdd-skills-rust`, `tdd-skills-dotnet`, `integration-test`, `integration-test-dotnet`, `setup-ci`
