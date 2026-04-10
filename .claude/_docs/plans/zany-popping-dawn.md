# ドキュメント配置の統一: `.spec-workflow/` の人間向けドキュメントを `.claude/_docs/` へ移動

## Context

プラグインが管理するドキュメントが `.claude/_docs/`（adr, know-how, tech-debt, plans）と `.spec-workflow/`（specs, steering 等）の2箇所に分散している。`.claude/_docs/` に統一し、`.spec-workflow/` はツールランタイム専用にする。

## 統一後のディレクトリ構造

```
.claude/_docs/                   # 全ドキュメント統一
├── specs/                       # ← .spec-workflow/specs/ から移動
│   └── {spec-name}/
│       ├── request-spec.md
│       ├── requirements.md
│       ├── design.md
│       ├── test-design.md
│       ├── tasks.md
│       ├── reviews/
│       └── Implementation Logs/
├── steering/                    # ← .spec-workflow/steering/ から移動
│   ├── product.md
│   ├── tech.md
│   ├── structure.md
│   └── logs/
├── archive/                     # ← .spec-workflow/archive/ から移動
│   ├── specs/
│   └── whiteboards/
├── adr/                         # 既存（変更なし）
├── know-how/                    # 既存（変更なし）
├── tech-debt/                   # 既存（変更なし）
└── plans/                       # 既存（変更なし）

.spec-workflow/                  # ツールランタイム専用
├── approvals/                   # JSON 承認データ
├── templates/                   # サーバー起動時に自動コピー（読み取り専用）
├── user-templates/              # ユーザーテンプレートオーバーライド
├── user-prompts/                # カスタムプロンプト JSON
├── agents/                      # ツール管理エージェント設定
├── commands/                    # ツール管理コマンド
├── config.toml                  # ツール設定
└── audit.log                    # セキュリティ監査ログ
```

## 変更戦略

### 原則: `PathUtils` を起点にした機械的リファクタリング

TypeScript ソースの全パス構築は `PathUtils` クラスを経由する。
1. `PathUtils` に `getDocsRoot()` メソッドを追加
2. `getSpecPath()`, `getSteeringPath()`, `getArchiveSpecPath()` 等を `getDocsRoot()` ベースに変更
3. `getWorkflowRoot()` はランタイム用途のまま維持（approvals, templates, config 等）
4. 残りはコールサイトの機械的更新

### Phase 1: TypeScript コア（パス定義の起点）

**1-1. `src/core/path-utils.ts`**
- `getDocsRoot(projectPath)` 追加 → `.claude/_docs` を返す
- `getSpecPath()` — `.spec-workflow/specs/` → `.claude/_docs/specs/`
- `getSteeringPath()` — `.spec-workflow/steering` → `.claude/_docs/steering`
- `getArchiveSpecPath()` — `.spec-workflow/archive/specs/` → `.claude/_docs/archive/specs/`
- `getArchiveSpecsPath()` — 同上
- `getAdrPath()` 追加 → `.claude/_docs/adr`
- `getKnowHowPath()` 追加 → `.claude/_docs/know-how`
- `getTechDebtPath()` 追加 → `.claude/_docs/tech-debt`
- 変更しないメソッド: `getWorkflowRoot()`, `getTemplatesPath()`, `getApprovalsPath()`, `getAgentsPath()`, `getCommandsPath()`

**1-2. `src/core/workspace-initializer.ts`**
- `initializeDirectories()` を分割:
  - `.spec-workflow/` 配下: approvals, templates, user-templates, user-prompts（既存のまま）
  - `.claude/_docs/` 配下: specs, steering, steering/logs, archive, adr, know-how, tech-debt（新規追加）
- archive を `.spec-workflow/` → `.claude/_docs/` に移動

**1-3. `src/core/guides.ts`**
- ファイル構造 ASCII ツリーを新構造に更新（`.spec-workflow/` セクションと `.claude/_docs/` セクション）
- フェーズ説明内のパス参照を更新

### Phase 2: ダッシュボード・ツール

**2-1. `src/dashboard/multi-server.ts`**
- `join(project.projectPath, '.spec-workflow', 'specs', ...)` → PathUtils 呼び出しに統一
- `join(project.projectPath, '.spec-workflow', 'steering', ...)` → 同上
- approvals 関連パスは変更なし

**2-2. `src/dashboard/watcher.ts`**
- ファイル監視パスを `.claude/_docs/` に変更（specs, steering）
- approvals 監視は `.spec-workflow/approvals/` のまま

**2-3. `src/tools/approvals.ts`**
- spec ドキュメント参照パスを更新（承認データ自体は `.spec-workflow/approvals/` のまま）

**2-4. `src/dashboard/approval-storage.ts`**
- ファイル解決パスの更新

**2-5. `src/dashboard/job-scheduler.ts`**
- spec クリーンアップパスの更新

**2-6. `src/core/implementation-log-migrator.ts`**
- Implementation Logs パスの更新

**2-7. `src/core/security-utils.ts`**
- 変更なし（audit.log は `.spec-workflow/` に残る）

### Phase 3: プロンプト・設定

**3-1. `src/prompts/implement-task.ts`**
- `.spec-workflow/specs/${specName}/tasks.md` → `.claude/_docs/specs/...`
- Implementation Logs パスの更新

**3-2. `src/prompts/create-steering-doc.ts`**
- steering パスの更新（テンプレートパスは `.spec-workflow/templates/` のまま）

**3-3. `src/prompts/create-spec.ts`**
- spec パスの更新

**3-4. `src/prompts/spec-status.ts`**
- spec ディレクトリパスの更新

**3-5. `src/prompts/inject-spec-workflow-guide.ts`**
- テンプレートパスは変更なし

**3-6. `src/prompts/inject-steering-guide.ts`**
- steering パスの更新

**3-7. `src/config.ts`**
- 変更なし（config.toml は `.spec-workflow/` に残る）

### Phase 4: VS Code 拡張

**4-1. `vscode-extension/src/extension/services/SpecWorkflowService.ts`**
- spec/steering パス解決を `.claude/_docs/` ベースに変更

**4-2. `vscode-extension/src/extension/services/FileWatcher.ts`**
- 監視パターンを分割: `.claude/_docs/**/*`（docs）+ `.spec-workflow/approvals/**/*`（approvals）

**4-3. `vscode-extension/src/extension/services/ApprovalEditorService.ts`**
- ファイルパス解決の更新

**4-4. `vscode-extension/src/extension/services/ArchiveService.ts`**
- アーカイブパスを `.claude/_docs/archive/` に変更

**4-5. `vscode-extension/src/extension/services/ImplementationLogService.ts`**
- Implementation Logs パスの更新

**4-6. `vscode-extension/src/extension.ts`**
- コマンドパスの更新

**4-7. `vscode-extension/src/extension/providers/SidebarProvider.ts`**
- ダイアログテキストとパスの更新

**4-8. `vscode-extension/src/webview/locales/*.json`** (11ファイル)
- UI テキスト内のパス参照更新

### Phase 5: テスト

**5-1.** 以下のテストファイルのパス fixtures を更新:
- `src/core/__tests__/path-utils.test.ts`
- `src/tools/__tests__/projectPath.test.ts`
- `src/dashboard/__tests__/watcher-error-handling.test.ts`
- `src/dashboard/__tests__/approval-storage-path-resolution.test.ts`
- `src/dashboard/__tests__/multi-server-approvals-content.test.ts`
- `vscode-extension/src/test/extension.test.ts`
- `vscode-extension/src/test/pathResolution.test.ts`

### Phase 6: プラグインスキル・ルール

**6-1.** `.spec-workflow/specs/` → `.claude/_docs/specs/` の置換（~24ファイル）:
- 全 spec-* スキル（spec-implement, spec-design, spec-tasks, spec-requirements, spec-request-spec, spec-test-design, spec-review, spec-status, spec-e2e-implement, spec-impl-code, spec-impl-review, spec-impl-test-run, spec-impl-test-write）
- steering-doc スキル
- create-pr スキル
- setup-ci スキル
- ルール: spec-workflow-enforcement, doc-freshness, doc-crossref, design-conformance, quality-checks

**6-2.** `.spec-workflow/steering/` → `.claude/_docs/steering/` の置換（同上のファイル群）

**6-3.** `.claude/_docs/deleted/` → `.claude/_docs/archive/whiteboards/` の置換:
- integration-test スキル + references

**6-4.** フック:
- `.claude-plugin/hooks/tasks-read-guard.sh` — regex パターンを `.claude/_docs/specs/` に更新

### Phase 7: ドキュメント・メタ

**7-1.** `.gitignore` — `!.claude/_docs/` は既存のまま維持
**7-2.** `docs/WORKFLOW.ja.md`, `docs/WORKFLOW.md` — ファイル構造セクション更新
**7-3.** `docs/USER-GUIDE.ja.md`, `docs/USER-GUIDE.md` — パス参照更新
**7-4.** `docs/CONFIGURATION.ja.md`, `docs/CONFIGURATION.md` — 設定パス説明更新
**7-5.** `docs/TOOLS-REFERENCE.ja.md`, `docs/TOOLS-REFERENCE.md` — API パス例更新
**7-6.** `docs/TROUBLESHOOTING.ja.md`, `docs/TROUBLESHOOTING.md` — 診断コマンド更新
**7-7.** `docs/technical-documentation/file-structure.md` — ディレクトリマッピング更新
**7-8.** `docs/technical-documentation/architecture.md` — 設計図更新
**7-9.** `docs/technical-documentation/context-management.md` — ファイル監視スコープ更新
**7-10.** `README.md`, `README.ja.md` — ディレクトリ構造例更新

## 検証方法

1. `npm run build` — TypeScript コンパイル通過
2. `npm test` — 全テストパス
3. `grep -r '\.spec-workflow/specs' src/` → 0件（approvals 以外の残存参照なし）
4. `grep -r '\.spec-workflow/steering' src/` → 0件
5. `grep -r '\.spec-workflow/specs' .claude-plugin/` → 0件
6. `grep -r '\.spec-workflow/steering' .claude-plugin/` → 0件
7. `grep -r '\.spec-workflow/archive' src/ .claude-plugin/` → 0件
8. VS Code 拡張: `cd vscode-extension && npm run compile` — コンパイル通過
