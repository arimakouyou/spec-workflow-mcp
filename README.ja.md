# Spec Workflow MCP

[![npm version](https://img.shields.io/npm/v/@arimakouyou/spec-workflow-mcp)](https://www.npmjs.com/package/@arimakouyou/spec-workflow-mcp)

リアルタイムダッシュボードを備えた、構造化された仕様駆動開発のためのModel Context Protocol (MCP) サーバーです。

## ☕ このプロジェクトを支援する

<a href="https://buymeacoffee.com/arimakouyou" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" style="height: 60px !important;width: 217px !important;" ></a>

## 📺 ショーケース

### 🔄 承認システムの動作

<a href="https://www.youtube.com/watch?v=C-uEa3mfxd0" target="_blank">
  <img src="https://img.youtube.com/vi/C-uEa3mfxd0/maxresdefault.jpg" alt="Approval System Demo" width="600">
</a>

> 承認システムの動作をご覧ください：ドキュメント作成、ダッシュボードでの承認リクエスト、フィードバック提供、改訂の追跡。

### 📊 ダッシュボードと仕様管理

<a href="https://www.youtube.com/watch?v=g9qfvjLUWf8" target="_blank">
  <img src="https://img.youtube.com/vi/g9qfvjLUWf8/maxresdefault.jpg" alt="Dashboard Demo" width="600">
</a>

> リアルタイムダッシュボードを探索：仕様の表示、進捗の追跡、ドキュメントのナビゲート、開発ワークフローの監視。

## ✨ 主な機能

- **構造化された開発ワークフロー** - 順次仕様作成(steering → 要求仕様 → 要件 → 設計 → テスト設計)。タスクは承認済みの文書から生成する
- **事実の単一所有** - 名前・シグネチャ・パス・テストケースはそれぞれ 1 つの文書だけが所有し、他の文書は ID で参照する。決定的な lint で強制する
- **承認台帳** - 上流の文書を再承認すると、下流の承認は自動で失効する
- **リアルタイムWebダッシュボード** - ライブ更新で仕様、タスク、進捗を監視
- **承認ワークフロー** - 改訂を含む完全な承認プロセス
- **タスク進捗追跡** - ビジュアル進捗バーと詳細なステータス
- **実装ログ** - コード統計を含むすべてのタスク実装の検索可能なログ

## 🚀 クイックスタート

### 方法1: Claude Code プラグイン（Claude Code ユーザーに推奨）

Claude Code プラグインとして直接インストールできます。スキル、エージェント、ルール、フック、MCP サーバーがすべて自動で設定されます：

```bash
claude plugin add --from https://github.com/arimakouyou/spec-workflow-mcp
```

> **プラグインに含まれるもの：**
>
> - **MCP サーバー** — `approvals` ツールと承認台帳
> - **spec フローの skill** — steering-doc、spec-request-spec、spec-investigate、spec-requirements、spec-design、spec-test-design、spec-review、check-approval、spec-change、spec-implement、spec-status、spec-archive。加えて TDD と統合テストの手順、フレームワーク別の参照(Rust / .NET)
> - **8 つのサブエージェント** — spec-author / spec-reviewer(文書)、impl-worker / integ-test-worker(実装)、unit-test-engineer / frontend-test-engineer / integ-test-auditor(読み取り専用の検証)、review-worker(唯一のコミット主体)
> - **決定的なスクリプト(Bash)** — 文書の lint(`spec-lint.sh`)、シグネチャのコンパイル確認(`spec-sigcheck.sh`)、タスク生成(`spec-plan.sh`)、brief、コミットゲート(`spec-git.sh`、G0-G9)、仕様変更後の再オープン
> - **フック** — exit 2 でフローを強制する guard-edit / guard-git / guard-agent / guard-approval-request と、record-subagent / stop-failure / session-start
>
> フロー全体は [PLUGIN_FLOWS.ja.md](PLUGIN_FLOWS.ja.md) を参照。

> **プラグインのスクリプトとフックの前提:** `bash`、`jq`、`gawk`、`sha256sum`、`git`。Rust のシグネチャ確認には `cargo`。MCP サーバーと Web ダッシュボードはこれらに依存しない。

### 方法2: 手動 MCP 設定

MCP設定に追加します（以下のクライアント固有のセットアップを参照）：

```json
{
  "mcpServers": {
    "spec-workflow": {
      "command": "npx",
      "args": ["-y", "@arimakouyou/spec-workflow-mcp@latest", "/path/to/your/project"]
    }
  }
}
```

### ステップ2: インターフェースを選択する

### ステップ2: インターフェース（Webダッシュボード）
ダッシュボードを起動します（デフォルトポート5000で実行）：
```bash
npx -y @arimakouyou/spec-workflow-mcp@latest --dashboard
```

ダッシュボードは以下のURLでアクセス可能です：http://localhost:5000

> **注意：** ダッシュボードインスタンスは1つだけ必要です。すべてのプロジェクトが同じダッシュボードに接続します。

## 📝 使い方

Claude Code プラグインでの使い方:

- **`/steering-doc`** - プロジェクトの steering 文書を作る(初回のみ)
- **`/spec-request-spec`** - 新しい spec を始める。ダッシュボードで承認して `/check-approval` を実行すると、次の段階へ進む
- **`/spec-implement <spec>`** - 承認済みの spec をタスクごとに実装する
- **`/spec-change <spec>`** - 承認済みの文書を変更する。下流の文書と影響を受けるタスクが追従する
- **`/spec-status <spec>`** - 文書の状態と進捗を表示する

フロー全体は [PLUGIN_FLOWS.ja.md](PLUGIN_FLOWS.ja.md) を参照。

## 🔧 MCPクライアントセットアップ

<details>
<summary><strong>Augment Code</strong></summary>

Augment設定で設定します：
```json
{
  "mcpServers": {
    "spec-workflow": {
      "command": "npx",
      "args": ["-y", "@arimakouyou/spec-workflow-mcp@latest", "/path/to/your/project"]
    }
  }
}
```
</details>

<details>
<summary><strong>Claude Code CLI</strong></summary>

MCP設定に追加します：
```bash
claude mcp add spec-workflow npx @arimakouyou/spec-workflow-mcp@latest -- /path/to/your/project
```

**重要な注意事項：**
- `-y`フラグは、スムーズなインストールのためにnpmプロンプトをバイパスします
- `--`区切り文字により、パスがnpxではなくspec-workflowスクリプトに渡されます
- `/path/to/your/project`を実際のプロジェクトディレクトリパスに置き換えてください

**Windows用の代替方法（上記が機能しない場合）：**
```bash
claude mcp add spec-workflow cmd.exe /c "npx @arimakouyou/spec-workflow-mcp@latest /path/to/your/project"
```
</details>

<details>
<summary><strong>Claude Desktop</strong></summary>

`claude_desktop_config.json`に追加します：
```json
{
  "mcpServers": {
    "spec-workflow": {
      "command": "npx",
      "args": ["-y", "@arimakouyou/spec-workflow-mcp@latest", "/path/to/your/project"]
    }
  }
}
```

> **重要：** MCPサーバーを起動する前に、`--dashboard`を使用してダッシュボードを別途実行してください。

</details>

<details>
<summary><strong>Cline/Claude Dev</strong></summary>

MCPサーバー設定に追加します：
```json
{
  "mcpServers": {
    "spec-workflow": {
      "command": "npx",
      "args": ["-y", "@arimakouyou/spec-workflow-mcp@latest", "/path/to/your/project"]
    }
  }
}
```
</details>

<details>
<summary><strong>Continue IDE Extension</strong></summary>

Continue設定に追加します：
```json
{
  "mcpServers": {
    "spec-workflow": {
      "command": "npx",
      "args": ["-y", "@arimakouyou/spec-workflow-mcp@latest", "/path/to/your/project"]
    }
  }
}
```
</details>

<details>
<summary><strong>Cursor IDE</strong></summary>

Cursor設定（`settings.json`）に追加します：
```json
{
  "mcpServers": {
    "spec-workflow": {
      "command": "npx",
      "args": ["-y", "@arimakouyou/spec-workflow-mcp@latest", "/path/to/your/project"]
    }
  }
}
```
</details>

<details>
<summary><strong>OpenCode</strong></summary>

`opencode.json`設定ファイルに追加します：
```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "spec-workflow": {
      "type": "local",
      "command": ["npx", "-y", "@arimakouyou/spec-workflow-mcp@latest", "/path/to/your/project"],
      "enabled": true
    }
  }
}
```
</details>

<details>
<summary><strong>Windsurf</strong></summary>

`~/.codeium/windsurf/mcp_config.json`設定ファイルに追加します：
```json
{
  "mcpServers": {
    "spec-workflow": {
      "command": "npx",
      "args": ["-y", "@arimakouyou/spec-workflow-mcp@latest", "/path/to/your/project"]
    }
  }
}
```
</details>

<details>
<summary><strong>Codex</strong></summary>

`~/.codex/config.toml`設定ファイルに追加します：
```toml
[mcp_servers.spec-workflow]
command = "npx"
args = ["-y", "@arimakouyou/spec-workflow-mcp@latest", "/path/to/your/project"]
```
</details>

## 🐳 Dockerデプロイ

Dockerコンテナでダッシュボードを実行し、分離されたデプロイを実現します：

```bash
# Docker Composeを使用（推奨）
cd containers
docker-compose up --build

# またはDocker CLIを使用
docker build -f containers/Dockerfile -t spec-workflow-mcp .
docker run -p 5000:5000 -v "./workspace/.spec-workflow:/workspace/.spec-workflow:rw" spec-workflow-mcp
```

ダッシュボードは以下のURLで利用可能になります：http://localhost:5000

[Dockerセットアップガイドを見る →](containers/README.md)

## 🔒 サンドボックス環境

`$HOME`が読み取り専用のサンドボックス環境（例：Codex CLIの`sandbox_mode=workspace-write`）の場合、`SPEC_WORKFLOW_HOME`環境変数を使用してグローバル状態ファイルを書き込み可能な場所にリダイレクトします：

```bash
SPEC_WORKFLOW_HOME=/workspace/.spec-workflow-mcp npx -y @arimakouyou/spec-workflow-mcp@latest /workspace
```

[設定ガイドを見る →](docs/CONFIGURATION.ja.md#environment-variables)

## 📚 ドキュメント

- [設定ガイド](docs/CONFIGURATION.ja.md) - コマンドラインオプション、設定ファイル
- [ユーザーガイド](docs/USER-GUIDE.ja.md) - 包括的な使用例
- [ワークフロープロセス](docs/WORKFLOW.ja.md) - 開発ワークフローとベストプラクティス
- [インターフェースガイド](docs/INTERFACES.ja.md) - ダッシュボードの詳細
- [プロンプティングガイド](docs/PROMPTING-GUIDE.ja.md) - 高度なプロンプティング例
- [ツールリファレンス](docs/TOOLS-REFERENCE.ja.md) - 完全なツールドキュメント
- [開発](docs/DEVELOPMENT.ja.md) - 貢献と開発セットアップ
- [トラブルシューティング](docs/TROUBLESHOOTING.ja.md) - 一般的な問題と解決策

## 📁 プロジェクト構造

### 作業ディレクトリ（プロジェクトごと）

```
your-project/
  .spec-workflow/
    approvals/<spec>/ledger.json   # 承認台帳(MCP サーバーだけが書く)
    approvals/<spec>/content/      # 承認された本文(sha256 ごと)
    archive/specs/
    specs/<spec>/                  # request-spec、requirements、design、test-design、tasks(生成物)、evidence/、task-logs/
    steering/                      # product.md、tech.md、structure.md
```

### プラグイン構造（`.claude-plugin/` で配布）

```text
.claude-plugin/
  plugin.json              # プラグインマニフェスト
  marketplace.json         # マーケットプレイスリスティング
  .mcp.json                # MCP サーバー設定

  hooks/                   # フローを強制するフック(exit 2)とセッションの文脈
    hooks.json
    session-start.sh       # SessionStart: 実装の状態と次のタスク
    guard-edit.sh          # PreToolUse Edit|Write: 承認済み文書・生成物・台帳を守る
    guard-git.sh           # PreToolUse Bash: コミットは spec-git.sh 経由だけ
    guard-agent.sh         # PreToolUse Agent: 直列・タスクと agent の対応・順序
    guard-approval-request.sh # PreToolUse approvals: 依頼の前に lint と sigcheck
    record-subagent.sh     # SubagentStop: agent の最終 JSON を記録
    stop-failure.sh        # StopFailure: 中断を記録
    post-edit.sh           # PostToolUse Edit|Write: フォーマッタ

  scripts/                 # 決定的な Bash ツール
    spec-lint.sh           # 文書の lint(L01-L26)
    spec-sigcheck.sh       # design のシグネチャをコンパイル(Rust)
    spec-state.sh          # 承認台帳による文書の状態
    spec-plan.sh           # tasks.md の生成
    spec-next.sh / spec-brief.sh / spec-trace.sh
    spec-git.sh            # 唯一のコミット経路(ゲート G0-G9)
    spec-reopen.sh         # 仕様変更で影響を受けるタスク
    ...

  contract/                # 承認台帳の契約 v1 と共有フィクスチャ(TS / Bash / Rust)
  templates/docs/          # 文書テンプレート(プラグインが所有)

  skills/                  # spec フロー、TDD / 統合テストの手順、フレームワーク別の参照
  agents/                  # spec-author、spec-reviewer、impl-worker、integ-test-worker、
                           # unit-test-engineer、frontend-test-engineer、integ-test-auditor、review-worker
  rules/                   # doc-format.md(文書の文法)、test-taxonomy.md、verdict.md、
                           # quality-checks.md、security.md、design-principles.md、type-safety.md ほか
```

## 🛠️ 開発

```bash
# 依存関係をインストール
npm install

# プロジェクトをビルド
npm run build

# 開発モードで実行
npm run dev
```

[開発ガイドを見る →](docs/DEVELOPMENT.ja.md)

## 📄 ライセンス

GPL-3.0

## ⭐ スター履歴

<a href="https://www.star-history.com/#arimakouyou/spec-workflow-mcp&Date">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=arimakouyou/spec-workflow-mcp&type=Date&theme=dark" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=arimakouyou/spec-workflow-mcp&type=Date" />
   <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=arimakouyou/spec-workflow-mcp&type=Date" />
 </picture>
</a>
