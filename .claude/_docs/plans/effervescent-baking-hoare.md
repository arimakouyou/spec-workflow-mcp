# 事前調査厚め・仕様書本体スリム化ワークフロー改修

## Context

レガシープロジェクトの移植で「現行踏襲の API テスト仕様を作ったが、既存コードの読み込みが甘く仕様ベースで実装が進まず手戻りが多発」という事象が発生した。ユーザー方針は「仕様化にかかる時間より、手戻り時間のほうが圧倒的に大きい」。ただし対策はレガシー移植に偏らず、API 追加・UI 追加/変更・bugfix・refactor など広いタスク類型に対応させたい。

同時に、現行仕様書は既に大きい（要件/設計/テスト設計は 1 ファイル 500-700 行規模）。コード根拠をそのまま本体に書き足すとさらに肥大化し、実装時のコンテキスト効率も落ちる。そこで「本体はスリム、証跡は外部 evidence ファイルへ隔離、実装時は必要な evidence のみ選択読込」という構造に変更する。

対象は `.claude-plugin/skills/spec-*` 群と `.spec-workflow/templates/*`、および承認前バリデーション（各スキル末尾の Step B check サブエージェント）。

## アーキテクチャ概要

```
Phase 0   spec-request-spec       task_type を frontmatter に宣言
          ↓ approval → /check-approval next:/spec-investigate
Phase 0.5 spec-investigate [NEW]  read-only サブエージェントで evidence 生成
          → .spec-workflow/specs/{name}/evidence/{category}/EV-*.md
          ↓ (承認不要・Step B で網羅性検査のみ)
Phase 1   spec-requirements       REQ-N.M に <!-- EV-... --> コメントで紐付け
Phase 2   spec-design (W1/W2)     DES-N / MOD-N の Code Reuse を EV 参照化
Phase 2.5 spec-test-design        UT/IT/E2E ケース毎に EV-ID 必須
Phase 3   spec-tasks              _Evidence: EV-... を _Leverage と併記
Phase 4   spec-impl-*             タスクの _Evidence から該当 EV だけ選択読込
```

仕様書本体は「要点＋EV-ID」のみ。ファイル:行番号・分岐一覧・呼び出し元一覧などの詳細は evidence/ に隔離する。EV-ID は既存の `spec-dependency-graph.md` (SD1) の命名体系（REQ-N.M / DES-N / MOD-N / UT-N.M）と直交する形で追加する。

## タスク類型（初期 5 種）

`.claude-plugin/rules/task-types.md` で定義し、`.spec-workflow/user-config/task-types.yml` で上書き可能にする。

| 類型 | 必須 evidence category |
|------|------------------------|
| `feature-add` (API/UI 追加) | `entry-points` / `domain-models` / `cross-cutting` / `test-harness` |
| `feature-modify` (API/UI 変更) | `callers` / `contract-current` / `branches` / `regressions` |
| `bugfix` | `repro` / `root-cause-paths` / `callers` / `regressions` |
| `refactor` | `api-surface` / `callers` / `invariants` / `test-coverage-gap` |
| `legacy-migration` | `feature-add` + `legacy-source`（移植元引用） |

## Evidence ディレクトリと命名

```
.spec-workflow/specs/{spec-name}/evidence/
  manifest.md                             # 調査計画とカバレッジ結果
  callers/EV-callers-001.md               # 1 EV = 1 トピック、50-150 行推奨
  entry-points/EV-entry-points-001.md
  branches/EV-branches-002.md
  ...
```

- ID: `EV-{category}-{NNN}`
- 各 EV は frontmatter に `ev_id` / `category` / `task_type` / `sources: [path:Lstart-Lend]` を必須化
- 粒度は「1 EV = 1 論点」（ファイル単位ではなくトピック単位）にし、実装時の最小ロードを可能にする

## 新設/改修ファイル

### 新設

- `.claude-plugin/skills/spec-investigate/SKILL.md` — Phase 0.5。`task_type` と request-spec を入力に、read-only サブエージェントを並列起動して evidence を生成。approvals は通さず、末尾で `spec-investigate-check` サブエージェントが必須 category 網羅と sources 実在を検査してから Phase 1 を呼ぶ
- `.spec-workflow/templates/investigation-manifest-template.md` — 何を何粒度で調べるかの宣言様式
- `.spec-workflow/templates/evidence-template.md` — EV ファイルの雛形（frontmatter スキーマ込み）
- `.claude-plugin/rules/task-types.md` — 類型定義、必須 category マッピング、拡張 YAML の仕様
- `.claude-plugin/rules/evidence-coverage.md` — EV-ID 記法、必須カバレッジ、参照整合ルール。Step B check から参照される

### 改修

- `.claude-plugin/skills/spec-request-spec/SKILL.md` — frontmatter に `task_type` 必須化、完了後の遷移先を `/check-approval {id} next:/spec-investigate` に差し替え。Step B check に `task_type` 存在確認を追加
- `.claude-plugin/skills/spec-requirements/SKILL.md` / `spec-design/SKILL.md` / `spec-test-design/SKILL.md` / `spec-tasks/SKILL.md` — 各 Step B check プロンプトに「evidence 参照整合」「本体コード引用行数上限（例: 20 行/セクション超で FAIL）」「類型ごとの必須 category カバレッジ」を追加
- `.claude-plugin/skills/spec-impl-code/SKILL.md` / `spec-impl-test-write/SKILL.md` — タスクの `_Evidence` を解決し該当 EV-*.md のみ選択読込
- `.spec-workflow/templates/requirements-template.md` / `design-template.md` / `tasks-template.md` — EV-ID 参照欄・`_Evidence:` 行を追加。設計テンプレの Code Reuse Analysis は evidence 参照に差し替えて本体を短縮
- `src/markdown/templates/test-design-template.md` / `request-spec-template.md` — 同様に EV 参照欄と `task_type` 欄を追加（プラグイン本体テンプレ）
- `.claude-plugin/rules/spec-dependency-graph.md` — SD1 の ID 表に EV-{category}-NNN を追記、depends_on.refs が EV を参照できる旨を明記
- `.claude-plugin/rules/INDEX.md` — 新規 2 ルールを登録

`check-approval` スキルは**無改修**。検査は既存の Step B check サブエージェント拡張だけで完結させる。

## 後方互換

- 既存 spec の request-spec に `task_type` 未記載なら `task_type: legacy`（= evidence 検査スキップ）として扱う。`spec-workflow-enforcement.md` の「Legacy workflow exception」と同じ流儀
- evidence/ が存在しない既存 spec は approvals を従来通り通す
- 既承認の spec には touch しない。必要なら `/spec-investigate --retrofit` で後付け生成できる導線だけ用意

## 段階導入の推奨順

1. **Step 1（opt-in、1-2 週）**: `spec-investigate` スキル、evidence テンプレ、`task-types.md` を追加。Phase 0 に `task_type` 欄を追加するのみで、下流は参照を許容するが必須にしない。→ 調査を任意で厚くできるようになる
2. **Step 2（検証強化）**: Step B check に「EV-ID 参照整合」と「本体コード引用行数上限」を追加。→ 仕様書本体の膨張に歯止め
3. **Step 3（coverage 必須化）**: `task-types.md` の必須 category を Step B で強制、requirements/tasks の `_Evidence` を必須化。→ 類型ごとの事前調査深度を構造的に保証
4. **Step 4（選択読込）**: `spec-impl-*` を `_Evidence` 駆動の選択読込に改修。→ 実装フェーズのコンテキスト効率化と手戻り削減を定量化

各段階は独立して価値を出し、逆順ロールバックも容易。

## 修正対象ファイル（確認済み実在パス）

- `/home/arimakouyou/harness-template/spec-workflow-mcp/.claude-plugin/skills/spec-request-spec/SKILL.md`
- `/home/arimakouyou/harness-template/spec-workflow-mcp/.claude-plugin/skills/spec-requirements/SKILL.md`
- `/home/arimakouyou/harness-template/spec-workflow-mcp/.claude-plugin/skills/spec-design/SKILL.md`
- `/home/arimakouyou/harness-template/spec-workflow-mcp/.claude-plugin/skills/spec-test-design/SKILL.md`
- `/home/arimakouyou/harness-template/spec-workflow-mcp/.claude-plugin/skills/spec-tasks/SKILL.md`
- `/home/arimakouyou/harness-template/spec-workflow-mcp/.claude-plugin/skills/spec-impl-code/SKILL.md`
- `/home/arimakouyou/harness-template/spec-workflow-mcp/.claude-plugin/skills/spec-impl-test-write/SKILL.md`
- `/home/arimakouyou/harness-template/spec-workflow-mcp/.claude-plugin/rules/spec-dependency-graph.md`
- `/home/arimakouyou/harness-template/spec-workflow-mcp/.claude-plugin/rules/INDEX.md`
- `/home/arimakouyou/harness-template/spec-workflow-mcp/.spec-workflow/templates/requirements-template.md`
- `/home/arimakouyou/harness-template/spec-workflow-mcp/.spec-workflow/templates/design-template.md`
- `/home/arimakouyou/harness-template/spec-workflow-mcp/.spec-workflow/templates/tasks-template.md`
- `/home/arimakouyou/harness-template/spec-workflow-mcp/src/markdown/templates/request-spec-template.md`
- `/home/arimakouyou/harness-template/spec-workflow-mcp/src/markdown/templates/test-design-template.md`

## 既存資産の再利用

- **ID 体系（`spec-dependency-graph.md` SD1）**: EV-{category}-NNN を既存 REQ-N.M / DES-N / MOD-N / UT-N.M と同じ座標系で追加
- **Step A/B サブエージェント 2 段階バリデーション**: 全 Phase で確立済み。evidence 検査は Step B のプロンプト追記のみで実現
- **`/check-approval next:/...` 自動遷移**: spec-request-spec → spec-investigate の接続に流用
- **`_Leverage`・`_Requirements`・`_DependsOn` メタ**: 既存規約。`_Evidence` を同じ行記法で追加するだけ
- **Frontmatter `depends_on.refs`**: EV 参照をここに追記できる（SD2 を拡張）
- **Legacy workflow exception（`spec-workflow-enforcement.md`）**: 後方互換の踏襲先

## 検証計画

1. **プラグイン単体**: ビルド / Lint / 既存テスト (`npm test` と関連 vitest) を通す。プラグイン内の変更だけの場合フロントテストは省略可（CLAUDE.md 指示）
2. **サンプル spec での End-to-End**:
   - Step 1 導入後: 新規 spec で `task_type: feature-add` 宣言 → `/spec-investigate` 起動 → evidence 生成 → Phase 1 遷移が動くことを確認
   - Step 2 導入後: わざと本体に長大コード引用を入れた spec を Step B check に通し、FAIL で差し戻されることを確認
   - Step 3 導入後: 必須 category が欠けた状態で approval リクエストを出し、Step B check で FAIL することを確認
   - Step 4 導入後: 実装フェーズで `_Evidence` に列挙された EV だけが読み込まれることを確認（ログ/コンテキスト観察）
3. **後方互換**: `task_type` 未宣言の既存 spec が従来通り通過することを、既存サンプル（`.spec-workflow/specs/` 配下、あれば）で確認
4. **ダッシュボード / VS Code 拡張**: evidence/ 配下のファイルが承認対象として誤って表示されないことを UI 側で確認
