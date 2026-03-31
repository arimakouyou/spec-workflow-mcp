---
name: spec-impl-test-write
description: "spec-implement ワークフローの TDD RED フェーズ。プロダクションコードの前に失敗テストを記述する。サブエージェントとして実行するよう設計 — Agent ツールで起動する。トリガー: spec-implement オーケストレーターからのサブエージェント呼び出しのみ。"
---

# テストライター — RED フェーズ（サブエージェント）

このスキルは Agent ツール経由で**サブエージェント**として実行するよう設計されている。TDD の RED フェーズに従い、タスク仕様に基づいて失敗テストを記述する。

## 呼び出し元エージェントによる起動方法

```javascript
Agent({
  subagent_type: "general-purpose",
  description: "RED: 失敗テストを記述",
  prompt: `あなたは TDD テストライターです。以下のタスクに対する失敗テストを記述してください。

    Project path: {project-path}
    Spec name: {spec-name}
    Task ID: {task-id}
    Task prompt: {task _Prompt content}
    Test focus areas: {_TestFocus content from task, if available}
    Design doc path: {project-path}/.spec-workflow/specs/{spec-name}/design.md

    /spec-impl-test-write スキルの指示に従ってください。

    作成したテストファイルのリストとテスト名を返してください。`
})
```

## RED フェーズのルール

1. **テストを先に書く** — プロダクションコードが存在する前に
2. **テストは失敗しなければならない** — まだ存在しないモジュールのインポートを参照し、それは正しい
3. **プロダクションコードを書かない** — スタブや空の実装さえも書かない
4. **既存のプロダクションコードを変更しない**

## 実行ステップ

### 1. テスト対象を理解する

- タスクの `_Prompt` フィールド（プロンプトで提供される）から Role、Task、Restrictions、Success criteria を読む
- `_TestFocus` フィールドが提供されている場合（「Test focus areas」パラメータ経由）、4カテゴリで構成されている: **ハッピーパス / 境界値 / エラーハンドリング / エッジケース**。指定された**全4カテゴリ**をカバーするテストを記述する — これらのカテゴリは unit-test-engineer の品質検証基準と整合しており、手戻りを最小化する
- 設計ドキュメントを読んでインターフェース、データモデル、期待される動作を理解する
- 公開 API サーフェスを特定する: 関数、メソッド、エンドポイント、コンポーネント

### 2. 既存のテストパターンを発見する

テストを書く前に、プロジェクトのテスト規約を理解する:

- 既存のテストファイルを検索して以下を判定:
  - テストフレームワーク（vitest、jest、pytest など）
  - ファイル命名規約（`*.test.ts`、`*.spec.ts`、`*_test.py` など）
  - ディレクトリ構造（`__tests__/`、`tests/`、コロケーションなど）
  - インポートパターンとテストユーティリティ
  - アサーションスタイル（`expect()`、`assert` など）

```bash
# 既存のテストファイルを検索
find . -name "*.test.*" -o -name "*.spec.*" -o -name "*_test.*" | head -20
```

### 3. テストを記述する

`/tdd-skills` の原則に従う:

**テスト構造** — Given-When-Then を使用:
```
// Given — 前提条件のセットアップ
// When  — アクションの実行
// Then  — 結果の検証
```

**テスト命名** — 説明的な名前を使用:
- `test_{action}_when_{condition}`（例: `test_returns_empty_when_no_users`）
- `test_{action}_raises_{error}_when_{condition}`（例: `test_raises_not_found_when_invalid_id`）

**テスト対象:**
- ハッピーパス: Success criteria からの通常の期待動作
- エッジケース: 空の入力、境界値、null
- エラーケース: 不正な入力、欠損データ、設計ドキュメントのエラーシナリオ
- 境界値分析とテスト設計については `/tdd-skills` のリファレンスを参照

**テスト構成:**
- テスト対象のコンポーネント/モジュールごとに1つのテストファイル
- `describe`/`context` ブロックで関連テストをグルーピング
- テストの独立性を保つ（F.I.R.S.T 原則）

### 4. テストインポートが未存在コードを参照していることを確認

テストは GREEN フェーズで作成されるモジュールからインポートすべきである。例:

```typescript
// このインポートは失敗する — モジュールはまだ存在しない。それが正しい。
import { createUser } from '../services/user-service';
```

これが RED フェーズの期待される状態である。

## 出力フォーマット

呼び出し元エージェントに返す:

```
## RED フェーズ完了

### 作成したテストファイル
- {path/to/test-file-1}
- {path/to/test-file-2}

### 記述したテスト
- {describe ブロック}: {テスト名1}
- {describe ブロック}: {テスト名2}
- ...

### テストランナーコマンド
{これらの特定テストファイルを実行するコマンド}

### 注記
- {前提や判断の説明}
```
