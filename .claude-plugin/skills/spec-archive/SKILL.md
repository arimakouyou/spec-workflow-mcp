---
name: spec-archive
description: "Move a completed spec from `.spec-workflow/specs/{name}/` to `.spec-workflow/archive/specs/{name}/` after implementation is finished (Final E2E Gate PASS + PR created). The spec remains visible in the dashboard's Archived tab and can be restored via unarchive. Triggers on: '/spec-archive', 'archive spec', 'spec implementation complete and archive', or automatic invocation at the end of /spec-implement."
---

# Spec Archive — 実装完了 spec のアーカイブ

実装が完了した spec を active ディレクトリから archive ディレクトリへ移動する。archive 先のパスは MCP 側の `SpecArchiveService` と同一なので、**ダッシュボードの Archived タブから引き続き閲覧でき、unarchive ボタンで active に戻すこともできる**。

## When to Use

- `/spec-implement` の Final E2E Gate が PASS かつ PR 作成が完了した直後（Orchestrator が自動呼び出し）
- 既に完了した spec を手動で active 一覧から整理したいとき

## When NOT to Use

- 実装が途中／FAIL／ユーザーエスカレーション中の spec（active のまま残す）
- ダッシュボードから既に archive 済みの spec（重複チェックで拒否される）

## Inputs

- **spec name** (kebab-case, required)

## Process

### 1. パス確定

```bash
PROJECT_DIR="$(pwd)"
ACTIVE_PATH="${PROJECT_DIR}/.spec-workflow/specs/{spec-name}"
ARCHIVE_ROOT="${PROJECT_DIR}/.spec-workflow/archive/specs"
ARCHIVE_PATH="${ARCHIVE_ROOT}/{spec-name}"
```

> archive-service.ts (`src/core/archive-service.ts`) の `PathUtils.getArchiveSpecPath` と同一パス規約。
> ダッシュボード API の archive エンドポイントとも一致するので、Active / Archived タブの整合性が保たれる。

### 2. 事前チェック

実行前に以下を確認する。いずれかが false なら処理を中断しユーザーに報告:

| チェック | 条件 | 失敗時メッセージ |
|---------|-----|------------------|
| active 存在 | `ACTIVE_PATH` がディレクトリとして存在する | `Spec '{spec-name}' not found in active specs` |
| archive 先未使用 | `ARCHIVE_PATH` が存在しない | `Spec '{spec-name}' already exists in archive — unarchive it first or rename the active spec` |

### 3. Archive 実行

```bash
mkdir -p "$ARCHIVE_ROOT"
mv "$ACTIVE_PATH" "$ARCHIVE_PATH"
```

`mv` が失敗した場合はユーザーに報告する（権限、同一ファイルシステム外、ディスクフル等）。

### 4. Session ファイルの退避（任意）

実装セッション中に作成された `.implement-session.json` が残っている場合、併せて archive に退避する:

```bash
if [ -f "${PROJECT_DIR}/.implement-session.json" ]; then
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/session-manage.sh" archive
fi
```

退避先: `.spec-workflow/archive/sessions/implement-session-{timestamp}.json`。

### 5. 完了報告

ユーザーに以下を伝える:

```text
Spec '{spec-name}' archived successfully.
  From: .spec-workflow/specs/{spec-name}/
  To:   .spec-workflow/archive/specs/{spec-name}/

ダッシュボードの「Archived」タブで引き続き閲覧できます。
active に戻す場合はダッシュボードの unarchive ボタンを使用してください。
```

## Rules

- 移動先パスは `.spec-workflow/archive/specs/{spec-name}/` で固定（archive-service.ts と同じ）
- 既に archive 済みの spec に対しては冪等ではない — ユーザーに重複を報告して中断
- ファイルのコピー + 削除ではなく `mv` を使用（atomicity と権限保持のため）
- 失敗時は active 側をそのまま残す（部分状態を作らない）
- このスキル自体はダッシュボード API を呼び出さない — FS 操作のみ（ダッシュボード未起動でも動作する）
- unarchive は MCP サーバー側の `SpecArchiveService.unarchiveSpec` またはダッシュボードの
  unarchive ボタンに委ねる（本スキルは archive 方向のみ）
