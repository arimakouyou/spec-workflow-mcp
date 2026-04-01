---
name: tdd-skills
description: "t-wada の教えに基づく TDD の原則と実践。Red-Green-Refactor サイクル、テスト構造、テストダブル、境界値テスト、TDD による設計をカバー。言語やフレームワークに関係なく、テスト実装、テスト戦略設計、TDD 実践時に使用する。"
---

**TDD Skills Active**

# TDD スキル

t-wada（和田卓人）の教えに基づく TDD の原則と実践。

## 核心原則

**TDD はテスト技法ではなく、プログラミング技法である。**

> 「TDD は不安をつまらなさに変える。」— t-wada

## Red-Green-Refactor サイクル

```
RED:      失敗テストを書く
  ↓
GREEN:    最小限のコードでパスさせる
  ↓
REFACTOR: 動作を変えずにクリーンアップ
  ↓
RED:      次のテスト...
```

### Green 戦略

1. **Fake It**: まず定数を返す（最も安全）
2. **Triangulation**: 複数のテストケースから一般化
3. **Obvious Implementation**: 解決策が明確な場合に直接実装

詳細: [references/green-strategies.ja.md](references/green-strategies.ja.md)

## テスト構造（Given-When-Then）

```
// Given — 前提条件のセットアップ
// When  — アクションの実行
// Then  — 結果の検証
```

## テスト命名

| パターン | 例 |
|---------|---|
| `test_{action}_when_{condition}` | `test_returns_empty_when_no_users` |
| `test_{action}_raises_{error}_when_{condition}` | `test_raises_not_found_when_invalid_id` |

## テストの種類

| 種類 | 対象 | モック | 速度 |
|-----|------|-------|------|
| ユニット | ドメイン、ユースケース | 全依存関係 | 高速 |
| インテグレーション | API、リポジトリ | DB 接続 | 低速 |

## テストダブル

| 種類 | 目的 |
|-----|------|
| Stub | 固定値を返す |
| Mock | インタラクションを検証する |
| Fake | 軽量な実装（例: インメモリストア） |

詳細: [references/test-doubles.ja.md](references/test-doubles.ja.md)

## F.I.R.S.T 原則

- **F**ast: テストは高速に実行される
- **I**ndependent: テスト間に依存がない
- **R**epeatable: 毎回同じ結果
- **S**elf-Validating: 手動検査なしで合否判定
- **T**imely: プロダクションコードの前に記述

## トラブルシューティング

| 問題 | 解決策 |
|-----|--------|
| モック呼び出しを検証できない | 仕様ベースのモックを使用（例: Python の `Mock(spec=Port)`、TS の型付きモック） |
| フィクスチャ読み込みエラー | テスト設定ファイルが正しいディレクトリにあることを確認 |
| 非同期テストの失敗 | フレームワーク適切な非同期テストデコレータ/ランナーを使用 |

## リファレンス

| 優先度 | ドキュメント |
|--------|-----------|
| 高 | [green-strategies.ja.md](references/green-strategies.ja.md) — Green 戦略 |
| 高 | [test-design.ja.md](references/test-design.ja.md) — 境界値分析 |
| 中 | [test-patterns.ja.md](references/test-patterns.ja.md) — テストパターン |
| 中 | [test-doubles.ja.md](references/test-doubles.ja.md) — テストダブル |
| 低 | [advanced-techniques.ja.md](references/advanced-techniques.ja.md) — 高度なテクニック |
| 低 | [tdd-and-design.ja.md](references/tdd-and-design.ja.md) — TDD と設計 |
