# エラーメッセージ品質ガイドライン

カスタムテスト、アーキテクチャテスト、lint スクリプトのエラーメッセージに
修復手順と修正例を含めるための基準。P6-05 に対応する。

## EM1: テストアサーションメッセージ

カスタムテストの assert メッセージには以下の 3 要素を含めること:

1. **何が起きたか**（WHAT）: 検出された問題の具体的な説明
2. **何が期待されるか**（EXPECTED）: 正しい状態・値
3. **どう修正するか**（FIX）: 具体的な修正手順

### Rust の例

```rust
assert!(
    violations.is_empty(),
    "アーキテクチャ違反を検出:\n{violations}\n\n\
     Expected: {from_layer} → {to_layer} の依存は禁止。\n\
     Fix: `use crate::{to_module}` を削除するか、\
     design.md Module Boundaries の依存方向ルールを見直してください。"
);
```

### TypeScript/JavaScript の例

```typescript
expect(result).toBe(expected,
  `FAIL: ${description}\n` +
  `Expected: ${expected}\n` +
  `Fix: ${repairInstruction}`
);
```

## EM2: アーキテクチャテストのエラーメッセージ

`/generate-arch-tests` で生成されるテストは以下の情報を含むこと:

- 違反ファイルのパス
- 違反している依存方向ルール（From → To の禁止ルール）
- 修正アクション（import の削除 or design.md の見直し）

### 期待される出力例

```
アーキテクチャ違反を検出:
  src/services/payment.rs → handlers (services → handlers は禁止)

Fix: `use crate::handlers` の import を削除するか、
design.md Module Boundaries の依存方向ルールを見直してください。
```

## EM3: CI ステップのエラー出力

CI ワークフローの各ステップは以下を満たすこと:

- ステップ名が明確で動作を説明する（例: "Format check", "Security audit"）
- `id` フィールドを設定し、PR コメントスクリプトから参照可能にする
- エラー出力をファイルにキャプチャ（`2>&1 | tee /tmp/output.txt`）
- PR コメントで結果をマークダウンテーブルとして構造化表示

setup-ci が生成する CI テンプレートはこの基準に準拠している。

## EM4: カスタム lint/バリデーションスクリプト

独自のバリデーションスクリプトの推奨エラー出力形式:

```
{SEVERITY}: {rule_id} — {description}
  File: {file_path}:{line_number}
  Fix: {repair_instruction}
```

| フィールド | 必須 | 説明 |
|-----------|------|------|
| SEVERITY | Yes | ERROR / WARN / INFO |
| rule_id | Yes | ルール ID（例: FT5, EM1） |
| description | Yes | 問題の説明 |
| File | Recommended | ファイルパスと行番号 |
| Fix | Yes | 具体的な修正手順 |

### 出力例

```
WARN: FT5 — 隔離テストが 30 日超過
  File: tests/integration/payment_test.rs:42
  Fix: #[ignore] を削除してテストを修正するか、テスト自体を削除してください

ERROR: EM1 — アサーションメッセージに修正手順が含まれていない
  File: tests/unit/auth_test.rs:15
  Fix: assert! の第2引数に "Fix: ..." を含むメッセージを追加してください
```
