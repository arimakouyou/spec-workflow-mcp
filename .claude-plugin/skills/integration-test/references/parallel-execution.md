# 並列実行フロー詳細

Agent Teams を使った並列テスト作成の全フェーズ詳細。

## チーム構成

| 役割 | 数 | 責務 |
|------|:--:|------|
| Command（司令塔） | 1 | 分析・分担・監視・最終検証 |
| Workers（テスト実装） | 1-2 | テストファイル作成 |
| Pentagon（品質レビュー） | 1 | 品質ゲート判定 |

## フェーズ詳細

### P0: Parse & Analyze

```
入力: /integration-test users,posts
  ↓
カンマで分割 → ["users", "posts"]
  ↓
各対象を分析:
  users → src/handlers/users.rs → src/db/repository/users.rs → src/models/user.rs
  posts → src/handlers/posts.rs → src/db/repository/posts.rs → src/models/post.rs
  ↓
Worker 分担:
  alpha → users (test_users.rs)
  bravo → posts (test_posts.rs)
```

### P1: Setup Team

1. 共通ヘルパーの確認
   - `tests/integration/helpers/` が存在するか
   - TestContext が対象ドメインで動作するか
   - 新規 fixture が必要なら Command が追加

2. ホワイトボード作成
   - `whiteboard-template.md` に従い作成
   - Key Questions を 1-3 個設定

### P2: Launch Agents

Workers と Pentagon を `.claude/agents/` のエージェント定義を使ってサブエージェントとして起動。

**起動順序:**
1. Pentagon（`subagent_type: "integ-test-auditor"`）— 起動後はレビュー依頼待ち
2. Workers（`subagent_type: "integ-test-worker"`）— alpha, bravo を並列起動

```
# Pentagon 起動
Agent(subagent_type: "integ-test-auditor", prompt: "ホワイトボード: {whiteboard_path}\nレビュー依頼を待機")

# Worker 起動（並列）
Agent(subagent_type: "integ-test-worker", prompt: "Worker名: alpha\nドメイン: {domain_a}\n...")
Agent(subagent_type: "integ-test-worker", prompt: "Worker名: bravo\nドメイン: {domain_b}\n...")
```

### P3: Monitor & Facilitate

```
while 未完了タスクが存在:
  ├─ Worker 完了を検出
  │   ├─ ホワイトボードに Findings 転記
  │   ├─ Pentagon にレビュー依頼
  │   └─ Pentagon 結果を待つ
  │       ├─ PASS → Quality Gate 更新、次タスクがあれば割当
  │       └─ FAIL → レビュー回数確認
  │           ├─ < 3 回 → Worker に差し戻し
  │           └─ = 3 回 → 残存指摘付きで完了
  └─ 全タスク完了 → P4 へ
```

**差し戻し時の Worker 再実行:**
- 元の prompt に Pentagon の指摘事項を追加
- 「修正箇所」と「修正理由」を明示

### P4: Final Verification

```bash
# 全テスト実行
cargo test --test integration_users --test integration_posts -- --nocapture

# コード品質チェック
rustfmt tests/integration/test_users.rs tests/integration/test_posts.rs
cargo clippy --tests --quiet
```

失敗した場合:
- コンパイルエラー → Command が直接修正
- テスト失敗 → 原因を特定し Command が修正 or Worker に再依頼
- clippy 警告 → Command が修正

### P5: Cleanup & Report

1. ホワイトボードを `.claude/_docs/deleted/` に移動
2. 最終レポート出力

```
integration-test 並列実装完了

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
対象: users, posts

生成ファイル:
  tests/integration/test_users.rs (12 tests)
  tests/integration/test_posts.rs (10 tests)

テスト結果:
  22 tests passed, 0 failed

品質ゲート:
  test_users.rs: PASS (cycle 1)
  test_posts.rs: PASS (cycle 2)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## タイムアウトと中断

| 状況 | 対処 |
|------|------|
| Worker が 10 分以上応答なし | Command が状態確認、必要なら再起動 |
| Pentagon が 5 分以上応答なし | Command が状態確認、必要なら再起動 |
| 3 回差し戻し後も品質不足 | 残存指摘付きで完了、レポートに注記 |
