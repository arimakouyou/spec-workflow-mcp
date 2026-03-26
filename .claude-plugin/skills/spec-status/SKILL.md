---
name: spec-status
description: "仕様の進捗状態を確認する。指定したスペック名のフェーズ完了状態（request-spec → requirements → design → test-design → tasks → implementation）とタスク進捗を表示。Triggers on: /spec-status invocation, or when user asks about spec progress."
---

# Spec Status — 仕様進捗確認

指定スペックの現在の進捗を確認・表示する。

## 入力

- **specName** (spec-name): スペック名（kebab-case）。`$ARGS` の最初の引数として受け取る。

**呼び出し形式**: `/spec-status <spec-name>` （例: `/spec-status user-authentication`）

## 手順

### 1. ファイル存在チェック

`.spec-workflow/specs/{spec-name}/` 配下のファイルを Glob で確認する:

| ファイル | フェーズ |
|---------|---------|
| `request-spec.md` | Phase 0: Request Spec |
| `requirements.md` | Phase 1: Requirements |
| `design.md` | Phase 2: Design |
| `test-design.md` | Phase 3: Test Design |
| `tasks.md` | Phase 4: Tasks |

### 2. タスク進捗集計

`tasks.md` が存在する場合、タスクのステータスをカウントする:
- `[ ]` → pending（未着手）
- `[-]` → in-progress（進行中）
- `[x]` → completed（完了）

Grep で各パターンをカウント:
```bash
grep -c '^\- \[ \]' .spec-workflow/specs/{spec-name}/tasks.md
grep -c '^\- \[-\]' .spec-workflow/specs/{spec-name}/tasks.md
grep -c '^\- \[x\]' .spec-workflow/specs/{spec-name}/tasks.md
```

### 3. 現在フェーズの判定

存在するファイルから現在のフェーズを判定する。**次に必要なフェーズ**を報告する:
- tasks.md あり + タスク全完了 → `completed`
- tasks.md あり + 未完了タスクあり → `implementation`
- tasks.md あり + 全タスク未着手 → `tasks`（実装開始待ち）
- test-design.md まで存在 → `tasks-needed`（Phase 4 未完了）
- design.md まで存在 → `test-design-needed`（Phase 3 未完了）
- requirements.md まで存在 → `design-needed`（Phase 2 未完了）
- request-spec.md のみ存在 → `requirements-needed`（Phase 1 未完了）
- 何もなし → `not-started`

**レガシースペック互換**: `request-spec.md` が存在しなくても `requirements.md` が存在する場合は、Phase 0 をスキップして Phase 1 完了として扱う（request-spec は後から導入されたフェーズのため）。

### 4. 結果表示

以下のフォーマットで表示:

```
## {spec-name} — 仕様進捗

**現在フェーズ**: {currentPhase}

### フェーズ状態
- [x] Phase 0: Request Spec
- [x] Phase 1: Requirements
- [ ] Phase 2: Design
- [ ] Phase 3: Test Design
- [ ] Phase 4: Tasks

### タスク進捗（Phase 4 完了時）
- 完了: {completed}/{total}
- 進行中: {inProgress}
- 未着手: {pending}
```
