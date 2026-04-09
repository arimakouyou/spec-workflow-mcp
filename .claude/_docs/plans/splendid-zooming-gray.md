# ワークフロー整合性修正プラン

## Context

プラグインが公開するワークフロー（5フェーズの仕様駆動開発プロセス）において、強制ルール・スキル定義・ユーザー向けドキュメント間に複数の矛盾が存在する。外部レビューで6件の指摘を受けた（指摘 6 は対応しない）。本プランは指摘 1〜4 を修正し、ワークフロー全体の整合性を回復する。

**設計方針**: ダッシュボード承認後のフェーズ自動遷移は維持・修正する。フェーズ間の停止は最小限（理想は0）。品質チェックの緩和は行わない。

---

## Phase A: コア強制ルールとフェーズ遷移（指摘 1 + 2）

### A1. 強制ルールテーブルの完全化（指摘 1: 重大）

**ファイル**: `.claude-plugin/rules/spec-workflow-enforcement.md` (L32-38)

**問題**: テーブルが `request-spec.md`（Phase 0）と `test-design.md`（Phase 3）を考慮していない

**修正**: テーブルを全5フェーズ + レガシー例外を含む形に置換

```markdown
| spec ディレクトリの状態 | 次のアクション |
|------------------------|---------------|
| spec ファイルなし | `/spec-request-spec` へ案内して停止 |
| `request-spec.md` のみ | `/spec-requirements` へ案内して停止 |
| `request-spec.md` + `requirements.md` のみ | `/spec-design` へ案内して停止 |
| `requirements.md` + `design.md` あり、`test-design.md` なし | `/spec-test-design` へ案内して停止 |
| `design.md` + `test-design.md` あり、`tasks.md` なし | `/spec-tasks` へ案内して停止 |
| `tasks.md` あり | `/spec-implement` へ案内して**必ず停止**（会話からの自動起動禁止） |

**レガシー例外**: `request-spec.md` が存在せず `requirements.md` が存在する場合、レガシー仕様として扱い request-spec チェックをスキップ。残りのファイルで次フェーズを判定する。
```

### A2. 強制ルールの /spec-implement 自動起動禁止スコープを明確化（指摘 2: 重大）

**ファイル**: `.claude-plugin/rules/spec-workflow-enforcement.md` (L18-24)

**問題**: 自動起動禁止が会話文脈での口頭承認バイパスを禁じているのか、ダッシュボード承認後の自動遷移も含むのか曖昧

**修正**: L18-24 を以下に置換

```markdown
**会話文脈からの `/spec-implement` 自動起動は厳禁。** 以下はすべて「会話からの自動起動」として禁止:
- ユーザーが "yes"、"go ahead"、"OK" と返答した場合
- ユーザーが "implement this task" と言った場合（スキルを経由しない直接実装も禁止）
- AI が会話の流れから `/spec-implement` を起動すると判断した場合

**例外 — ダッシュボード承認による自動遷移**: `check-approval` スキルは以下の条件をすべて満たす場合に限り `next:` パラメータで `/spec-implement` を起動できる:
1. `approvals` MCP ツールが tasks.md の承認に対して `approved` ステータスを返した
2. `approvals action:'delete'` のクリーンアップが成功した
3. `/loop` 呼び出しで `next:/spec-implement` パラメータが渡されていた

この例外が安全な理由: ダッシュボード承認はユーザーの意図的・認証済みのアクションであり、会話的なバイパスではないため。

`/spec-implement` が起動される正当な経路:
- ユーザーが `/spec-implement` コマンドを直接入力
- "implement task X"、"start coding" 等のトリガーフレーズをユーザーが入力
- tasks.md のダッシュボード承認による自動遷移（上記の例外条件を満たす場合）
```

### A3. check-approval に `next:` パラメータと自動遷移機能を追加（指摘 2: 重大）

**ファイル**: `.claude-plugin/skills/check-approval/SKILL.md`（全体書き換え）

**問題**: check-approval は承認検出→クリーンアップ→ループ停止のみ。「呼び出し元スキルの auto-transition が処理する」と書いているが、/loop にはコールバック機構がなく、制御が呼び出し元に戻らない。

**修正**: check-approval に `next:` パラメータを追加。承認+クリーンアップ成功時に Skill ツールで次スキルを自動起動。

主な変更点:
- Usage セクション: `/loop 1m /check-approval <approvalId> next:/spec-requirements`
- `next:` はオプション（省略時は従来通りループ停止のみ）
- approved パス: クリーンアップ成功後、`next:` があれば Skill ツールで即座に起動
- needs-revision / rejected パス: 自動遷移しない（現行のまま）

### A4. 各 spec スキルの承認ワークフローセクションを修正（指摘 2: 重大）

5つの spec スキルの Approval Workflow セクションを修正:

| ファイル | loop 呼び出し | 削除する記述 |
|---------|-------------|-------------|
| `skills/spec-request-spec/SKILL.md` (L118-133) | `next:/spec-requirements` を追加 | Step 4 "Next phase"（デッドコード） |
| `skills/spec-requirements/SKILL.md` (L126-147) | `next:/spec-design` を追加 | Step 4 "Next phase"（デッドコード） |
| `skills/spec-design/SKILL.md` (L447-467) | `next:/spec-test-design` を追加 | Step 4 "Next phase"（デッドコード） |
| `skills/spec-test-design/SKILL.md` (L378-399) | `next:/spec-tasks` を追加 | Step 4 "Next phase"（デッドコード） |
| `skills/spec-tasks/SKILL.md` (L419-440) | `next:/spec-implement` を追加 | Step 4 "Next phase"（デッドコード） |

各スキルの修正パターン:
1. `/loop 1m /check-approval <approvalId>` → `/loop 1m /check-approval <approvalId> next:/spec-{next}`
2. approved の説明を「check-approval が自動的に次スキルを起動」に更新
3. needs-revision の再送信ループにも `next:` を含める
4. **Step 4 "Next phase" を削除** — 自動遷移は check-approval が担当するため不要（デッドコード除去）

### A5. guides.ts の自動遷移記述を明確化（指摘 2: 重大）

**ファイル**: `src/core/guides.ts` (L70)

**修正**: 自動遷移の実行主体を明記（check-approval の `next:` パラメータ経由）

```
- **Auto-transition**: After each phase's approval is approved and cleaned up, check-approval automatically invokes the next phase's skill via the `next:` parameter. Do not stop between phases to ask user for skill names. The only user interaction points are approval reviews (dashboard/VS Code extension)
```

---

## 自動遷移チェーン（修正後）

```
spec-request-spec → /loop check-approval next:/spec-requirements → [dashboard承認] → spec-requirements
spec-requirements → /loop check-approval next:/spec-design       → [dashboard承認] → spec-design
spec-design       → /loop check-approval next:/spec-test-design  → [dashboard承認] → spec-test-design
spec-test-design  → /loop check-approval next:/spec-tasks        → [dashboard承認] → spec-tasks
spec-tasks        → /loop check-approval next:/spec-implement    → [dashboard承認] → spec-implement
```

フェーズ間停止: 0（ダッシュボード承認のみがユーザーインタラクションポイント）

---

## Phase B: ドキュメント整合性（指摘 3 + 4）

### B1. WORKFLOW.md（英語版）の修正

**ファイル**: `docs/WORKFLOW.md`

1. L80: "Four-Document System" → "Five-Document System (Phase 0–4)"
2. Phase 0 (Request Spec) をファイルツリー・ベストプラクティスに追加
3. L296-305: ファイルツリーに `request-spec.md` を追加
4. L407-415: "Sequential Document Creation" に Phase 0 を追加
5. L255-274: テスト戦略セクションを TDD ベースに置換
   - ユニットテスト: Phase 3 (test-design.md) で設計、TDD RED フェーズで実装
   - IT/E2E: test-design.md で設計、`/spec-e2e-implement` で実装（並行可）
   - Final E2E Gate: `/spec-implement` 内で全テスト実行
6. ステアリングドキュメント: "prerequisite" → "recommended"（guides.ts の "optional" と整合）

### B2. WORKFLOW.ja.md（日本語版）の修正

**ファイル**: `docs/WORKFLOW.ja.md`

1. L10: 概要にリクエスト仕様（Phase 0）を追加
2. L15: ステアリングを「フェーズ0」→「プロジェクトセットアップ（推奨）」に変更
3. L57 前: Phase 0（リクエスト仕様）セクションを新規追加
4. L59: "4ドキュメントシステム" → "5ドキュメントシステム"
5. L271-295: ファイルツリーに `request-spec.md` を追加
6. L240-258: テスト戦略セクションを TDD ベースに置換（B1 と同内容の日本語版）
7. L391-399: ベストプラクティスに Phase 0 を追加

---

## 指摘 6（軽微）: 対応しない

品質チェック（バージョン検証、ADR 自動生成、Docker/CI/ADR タスク注入）の緩和は結果の品質低下につながるため、現行のまま維持する。

---

## 実施順序

```
Phase A (A1 → A2 → A3 → A4 → A5)  ← 重大指摘、最優先
    ↓
Phase B (B1, B2 並行可)             ← ドキュメント整合
```

---

## 検証方法

### Phase A 完了後
- check-approval が `next:` パラメータのパースと Skill ツール起動の記述を持つことを確認
- 全5 spec スキルの loop 呼び出しに `next:/spec-{next}` が含まれることを確認
- 全5 spec スキルから "Next phase" デッドコード（Step 4）が削除されていることを確認
- 強制ルールテーブルが6状態を網羅していることを確認
- 強制ルール L18-24 がダッシュボード承認例外を明記していることを確認
- `grep "begin immediately" .claude-plugin/skills/spec-*/SKILL.md` → 0件
- `grep "calling skill's auto-transition" .claude-plugin/` → 0件

### Phase B 完了後
- `grep -r "Four-Document\|4ドキュメント" docs/` → 0件
- 両 WORKFLOW ドキュメントのファイルツリーに `request-spec.md` が含まれること
- テスト戦略セクションに「実装後にテスト作成」の記述がないこと
- ステアリングが "recommended"/"推奨" と記述されていること

---

## 修正対象ファイル一覧

| ファイル | 関連指摘 | Phase |
|---------|---------|-------|
| `.claude-plugin/rules/spec-workflow-enforcement.md` | 1, 2 | A |
| `.claude-plugin/skills/check-approval/SKILL.md` | 2 | A |
| `.claude-plugin/skills/spec-request-spec/SKILL.md` | 2 | A |
| `.claude-plugin/skills/spec-requirements/SKILL.md` | 2 | A |
| `.claude-plugin/skills/spec-design/SKILL.md` | 2 | A |
| `.claude-plugin/skills/spec-test-design/SKILL.md` | 2 | A |
| `.claude-plugin/skills/spec-tasks/SKILL.md` | 2 | A |
| `src/core/guides.ts` | 2 | A |
| `docs/WORKFLOW.md` | 3, 4 | B |
| `docs/WORKFLOW.ja.md` | 3, 4 | B |
