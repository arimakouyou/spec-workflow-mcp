---
description: "Rust のユニットテスト設計・実装"
---

`unit-test-engineer` エージェントにユニットテスト作成を委譲する。

## 実行手順

Agent ツールで `unit-test-engineer` を起動し、対象ファイル・モジュールのユニットテストを設計・実装させる。

```
Agent(
  subagent_type: "unit-test-engineer",
  prompt: "以下の対象に対してユニットテストを設計・実装してください。\n\n対象: $ARGUMENTS"
)
```

エージェントの完了後、結果をユーザーに報告する。
