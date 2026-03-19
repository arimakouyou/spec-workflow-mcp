---
name: tdd-skills-rust
description: >
  tdd-skills の Rust 固有版。t-wada さんの教えに基づく TDD 原則の Rust 実装パターンを提供する。
  Red-Green-Refactor サイクル、Rust のテスト機能（#[test], mockall, rstest）によるテスト実装、
  trait ベースのテストダブル設計、境界値テストの設計を含む。
  Rust プロジェクトでのテスト実装、テスト設計、TDD 実践時に使用。
---

# TDD Skills (Rust)

> 基本原則は言語非依存版の `/tdd-skills` を参照。本スキルは Rust 固有の実装パターンに特化する。

t-wadaさん（和田卓人氏）の教えに基づくTDD原則と実践方法を、Rust の言語機能に沿って提供する。

## 事前確認: Know-how 参照

`feedback-loop` rule の Know-how INDEX から testing 等の関連 know-how を Read する。
チェックリスト・反例をテスト設計に反映すること。

## TDDの本質

TDDは「プログラミング手法」であり、「テストを書く技法」ではない。

> 「TDDは不安を退屈に変える技術である」 - t-wada

## Red-Green-Refactor サイクル

```
Red:      失敗するテストを書く
  ↓
Green:    最小限のコードで通す
  ↓
Refactor: リファクタリング
  ↓
Red:      次のテスト...
```

### Green 戦略（3つ）

1. **仮実装（Fake It）**: まず定数を返す（最も安全）
2. **三角測量（Triangulation）**: 複数のテストから一般化
3. **明白な実装（Obvious Implementation）**: 明白な時は直接実装

詳細: [references/green-strategies.md](references/green-strategies.md)

## テスト構造（Given-When-Then）

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use mockall::predicate::*;

    #[test]
    fn get_user_returns_entity_when_exists() {
        // Given
        let mut mock_repo = MockUserRepository::new();
        mock_repo
            .expect_find_by_id()
            .with(eq(123))
            .returning(|_| Ok(Some(User { id: 123, name: "Alice".into() })));
        let query = UserQueryService::new(Box::new(mock_repo));

        // When
        let result = query.get_user_by_id(123).unwrap();

        // Then
        assert_eq!(result.id, 123);
    }
}
```

## テスト命名規則

| パターン | 例 |
|----------|-----|
| `{動作}_when_{条件}` | `returns_empty_when_no_users` |
| `{動作}_with_{入力}` | `calculates_total_with_multiple_items` |
| `fails_when_{条件}` | `fails_when_invalid_id` |

Rust ではテスト関数名が `test_` プレフィックス不要（`#[test]` アトリビュートで識別）。
ただし慣習的に付ける場合は統一する。

## テストの種類

| 種類 | 対象 | テストダブル | 速度 |
|------|------|-------------|------|
| ユニット | Domain, UseCase | trait ベースの mock/fake | 高速 |
| 統合 | API, Repository | テスト用 DB + トランザクション | 低速 |

## テストダブル

| 種類 | 用途 | Rust での実現 |
|------|------|-------------|
| Stub | 決まった値を返す | trait 実装 or `mockall` の `returning()` |
| Mock | 呼び出し検証 | `mockall` の `expect_*()` |
| Fake | 簡易実装 | `HashMap` ベースの InMemoryRepository |

詳細: [references/test-doubles.md](references/test-doubles.md)

## F.I.R.S.T 原則

- **F**ast: 高速
- **I**ndependent: 独立
- **R**epeatable: 再現可能
- **S**elf-Validating: 自己検証
- **T**imely: プロダクションコードの前に書く

## トラブルシューティング

| 問題 | 解決策 |
|------|--------|
| mock の型が合わない | `#[automock]` を trait に付与、`Box<dyn Trait>` で注入 |
| async テストが動かない | `#[tokio::test]` を使用 |
| テスト間でデータが干渉 | `test_transaction` でロールバック |
| コンパイルが遅い | `#[cfg(test)]` でテスト用コードを分離 |

## 詳細リファレンス

| ドキュメント | 内容 |
|------------|------|
| [green-strategies.md](references/green-strategies.md) | Green 戦略の詳細と実践例 |
| [test-design.md](references/test-design.md) | 境界値分析・同値分割 |
| [test-patterns.md](references/test-patterns.md) | Fixture, パラメータ化テスト |
| [test-doubles.md](references/test-doubles.md) | テストダブルの種類と使い分け |
| [tdd-and-design.md](references/tdd-and-design.md) | TDD が設計にもたらす効果 |
| [advanced-techniques.md](references/advanced-techniques.md) | レガシーコード対応、アンチパターン |
