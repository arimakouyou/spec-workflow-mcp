---
name: context7
description: |
  Context7 MCP を活用して、ライブラリ・フレームワーク・外部ツールの**最新ドキュメント**を実装前・設定前・エラー対応時に取得するガイドライン。メモリベースの古い知識や古い Stack Overflow 回答に頼らず、Context7 MCP で公式ドキュメントを参照してから記述・修正する。ライブラリ API 利用時、設定ファイル (tsconfig, vite, eslint, etc.) 記述時、ライブラリ/ツール起因のエラー発生時、CLI オプション確認時に参照。
allowed-tools: [Read, Edit, Write, Bash, Grep]
---

# Context7 MCP Usage Skill

## 対象

- ライブラリ / フレームワークの API 利用を含む新規実装
- 設定ファイル（`tsconfig.json`, `vite.config.ts`, `eslint.config.mjs`, `pyproject.toml` など）の記述
- CLI ツール（webpack, rollup, esbuild, etc.）の引数・設定の確認
- ライブラリ起因のエラー解決（バージョン差分含む）

## 対象外

- プロジェクト内部のコード設計・リファクタリング（Context7 の責務外）
- 公開されていない社内ツール・API（Context7 にドキュメントがない）

## 主要観点

### 1. ライブラリ利用時

ライブラリの API を呼び出すコードを書く前に、Context7 MCP で該当ライブラリの最新ドキュメントとコード例を取得する。メモリに残っている古い使い方で書かずに、Context7 が返す最新の使い方に合わせる。

```text
(Bad)
React の useState を呼び出すとき、memory にある書き方で実装する。

(Good)
Context7 MCP で "react hooks useState" を検索 → 最新の usage を確認 → 実装する。
```

### 2. 外部ツール設定とシンタックス

設定ファイルの記述時、CLI オプションの指定時は、Context7 MCP で正しい option や format を確認してから書く。推測で書かない。

### 3. エラー対応時

ライブラリ / ツール起因のエラーが発生したら、Context7 MCP で該当エラーの対処法を確認し、公式ドキュメントに基づいた修正を行う。古い Stack Overflow 回答やメモリ由来の推測に基づく修正は避ける。

## よくある落とし穴

1. **「知ってるから大丈夫」で書き始める**: ライブラリのバージョンが変わって API も変わっているかもしれない。必ず Context7 を確認する
2. **エラー発生後に Context7 を使わない**: 最初に試す対処法として Context7 は最も speed と正確性が高い
3. **設定ファイルで古い書き方**: eslint flat config、vite v5、tsconfig の新オプションなど、移行を伴う変更は Context7 で最新確認する

## プロジェクト固有の規約

- プラグイン `.claude-plugin/.mcp.json` に Context7 MCP が登録されているプロジェクトでは、このスキルを優先的に使う
- Context7 が該当ライブラリのドキュメントを持っていない場合は、公式 docs サイトを WebFetch で取得する

## 関連 Rule / Skill

- 関連 Skill: `spec-design`（設計フェーズで library 選定時に Context7 を参照）
- `axum` / `diesel` / `leptos` などの技術別 Skill: 該当技術の Context7 検索クエリを明示的に提示する

## 参考リンク

- Context7: <https://context7.com/>
- Model Context Protocol: <https://modelcontextprotocol.io/>
