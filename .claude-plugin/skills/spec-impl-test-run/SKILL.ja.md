---
name: spec-impl-test-run
description: "spec-implement ワークフローの TDD テストランナー。テストを実行し、期待モード（red=全失敗、green=全パス）に対して結果を検証する。サブエージェントとして実行するよう設計 — Agent ツールで起動する。トリガー: spec-implement オーケストレーターからのサブエージェント呼び出しのみ。"
---

# テストランナー（サブエージェント）

このスキルは Agent ツール経由で**サブエージェント**として実行するよう設計されている。指定されたテストファイルを実行し、期待される結果に対して検証する。

## 呼び出し元エージェントによる起動方法

```javascript
Agent({
  subagent_type: "general-purpose",
  description: "テスト実行（{mode} モード）",
  prompt: `あなたは TDD テストランナーです。指定されたテストを実行し、結果を検証してください。

    Project path: {project-path}
    Test files: {test-file-paths}
    Expected mode: {red|green}

    /spec-impl-test-run スキルの指示に従ってください。

    構造化された結果サマリーを返してください。`
})
```

## パラメータ

- **Project path**: プロジェクトのルートディレクトリ
- **Test files**: 実行するテストファイルパスのカンマ区切りリスト
- **Expected mode**: `red`（全テスト失敗すべき）または `green`（全テストパスすべき）

## 実行ステップ

### 1. テストランナーの検出

プロジェクトのテストランナーを以下の順序で検出する:

1. `package.json` のスクリプト — `test`、`vitest`、`jest` スクリプトを探す
2. 設定ファイル: `vitest.config.*`、`jest.config.*`、`pytest.ini`、`pyproject.toml`
3. `package.json` の依存関係: `vitest`、`jest`、`mocha`、`pytest`

### 2. テストの実行

**指定されたテストファイルのみ**を実行する（全スイートではない）:

```bash
# ランナー別の例:
npx vitest run {test-files} --reporter=verbose
npx jest {test-files} --verbose
python -m pytest {test-files} -v
```

テストごとのパス/失敗の詳細を取得するため、`--reporter=verbose` または同等のフラグを使用する。

### 3. 結果の解析

テスト出力から以下を抽出する:
- **total**: 実行されたテスト数
- **passed**: パスしたテスト数
- **failed**: 失敗したテスト数
- **errors**: 失敗テストのエラーメッセージリスト（テスト名 + エラー）

### 4. モードに対する検証

**Red モード** (`red`):
- 期待: 全テスト失敗（passed = 0）
- **コンパイルエラー**: テストランナーがビルド/コンパイルに失敗した場合（例: 未実装モジュールの未解決インポート）、これをハード失敗として扱う — `{ status: "fail", message: "Compile error: {error summary}", ... }` を返す。呼び出し元エージェントは RED を検証する前にコンパイルエラーを修正しなければならない。
- テストが1つでもパスした場合、問題として報告する — これは以下のいずれかを意味する:
  - テストが実際には新しい動作をテストしていない
  - テストを満たす実装が既に存在する
- 返却: 全失敗（かつビルド成功）なら `{ status: "pass", ... }`、それ以外は `{ status: "fail", message: "N tests unexpectedly passed", ... }`

**Green モード** (`green`):
- 期待: 全テストパス（failed = 0）
- テストが1つでも失敗した場合、各失敗をエラーメッセージとともに報告
- 返却: 全パスなら `{ status: "pass", ... }`、それ以外は `{ status: "fail", message: "N tests failed", errors: [...] }`

## 出力フォーマット

呼び出し元エージェントに返す:

```
## テスト実行結果

- **モード**: {red|green}
- **ステータス**: {pass|fail}
- **合計**: {N} テスト
- **パス**: {N}
- **失敗**: {N}

### エラー（もしあれば）
- {テスト名}: {エラーメッセージ}

### 判定
{結果が期待と一致するかの説明}
```
