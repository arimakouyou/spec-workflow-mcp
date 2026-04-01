---
name: tdd-skills-rust
description: >
  tdd-skills の Rust 固有バージョン。t-wada の教えに基づく TDD 原則と Rust 実装パターンを提供する。
  Red-Green-Refactor サイクル、Rust テスト機能（#[test]、mockall、rstest）を使用したテスト実装、
  trait ベースのテストダブル設計、境界値テスト設計をカバー。
  Rust プロジェクトでのテスト実装、テスト設計、TDD 実践時に使用する。
---

# TDD スキル（Rust）

> 基礎原則については、言語非依存の `/tdd-skills` を参照。このスキルは Rust 固有の実装パターンに焦点を当てる。

t-wada（和田卓人）の教えに基づく TDD の原則と実践を、Rust 言語の機能に合わせて提供する。

## 事前チェック: ノウハウ参照

`feedback-loop` ルール配下の Know-how INDEX からテスト関連のノウハウを読む。
チェックリストと反例をテスト設計に組み込む。

## TDD の本質

TDD は「テストを書く技法」ではなく「プログラミング技法」である。

> 「TDD は不安をつまらなさに変える技術である。」- t-wada

## Red-Green-Refactor サイクル

```
Red:      失敗テストを書く
  ↓
Green:    最小限のコードでパスさせる
  ↓
Refactor: リファクタリング
  ↓
Red:      次のテスト...
```

### Green 戦略（3種類）

1. **Fake It**: まず定数を返す（最も安全）
2. **Triangulation**: 複数のテストから一般化
3. **Obvious Implementation**: 解決策が明確な場合に直接実装

詳細: [references/green-strategies.ja.md](references/green-strategies.ja.md)

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

## テスト命名規約

| パターン | 例 |
|---------|---|
| `{action}_when_{condition}` | `returns_empty_when_no_users` |
| `{action}_with_{input}` | `calculates_total_with_multiple_items` |
| `fails_when_{condition}` | `fails_when_invalid_id` |

Rust ではテスト関数に `test_` プレフィックスは不要（`#[test]` 属性で識別される）。
ただし、慣例として使用する場合は一貫して適用する。

## テストの種類

| 種類 | 対象 | テストダブル | 速度 |
|-----|------|------------|------|
| ユニット | ドメイン、ユースケース | trait ベースの mock/fake | 高速 |
| インテグレーション | API、リポジトリ | テスト DB + トランザクション | 低速 |

## テストダブル

| 種類 | 目的 | Rust 実装 |
|-----|------|----------|
| Stub | 固定値を返す | trait impl または `mockall` の `returning()` |
| Mock | 呼び出しを検証 | `mockall` の `expect_*()` |
| Fake | 軽量な実装 | `HashMap` ベースの InMemoryRepository |

詳細: [references/test-doubles.ja.md](references/test-doubles.ja.md)

## F.I.R.S.T 原則

- **F**ast: 高速
- **I**ndependent: 独立
- **R**epeatable: 再現可能
- **S**elf-Validating: 自己検証
- **T**imely: プロダクションコードの前に記述

## トラブルシューティング

| 問題 | 解決策 |
|-----|--------|
| Mock の型不一致 | trait に `#[automock]` を適用、`Box<dyn Trait>` で注入 |
| async テストが実行されない | `#[tokio::test]` を使用 |
| テスト間のデータ干渉 | `test_transaction` でロールバック |
| コンパイルが遅い | `#[cfg(test)]` でテスト専用コードを分離 |

## 詳細リファレンス

| ドキュメント | 内容 |
|-----------|------|
| [green-strategies.ja.md](references/green-strategies.ja.md) | Green 戦略の詳細と実践例 |
| [test-design.ja.md](references/test-design.ja.md) | 境界値分析と同値分割 |
| [test-patterns.ja.md](references/test-patterns.ja.md) | フィクスチャとパラメータ化テスト |
| [test-doubles.ja.md](references/test-doubles.ja.md) | テストダブルの種類と使い分け |
| [tdd-and-design.ja.md](references/tdd-and-design.ja.md) | TDD が設計に与える効果 |
| [advanced-techniques.ja.md](references/advanced-techniques.ja.md) | レガシーコードの対処とアンチパターン |
