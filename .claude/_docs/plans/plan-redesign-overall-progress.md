# plan-redesign 全体進捗ドキュメント

> 元計画: `tmp/plugin-redesign.md` 第 1〜4 段階（#1〜#16）
> ブランチ: `refactor/plugin-redesign-phase-a`
> 最終更新: 2026-04-25
> 関連: `phase-3-9-role-consolidation.md`（Phase 3 #9 のクロージャ詳細）

## 進捗サマリ

| 段階 | DONE | PARTIAL / SKIP | 未着手 |
|------|:---:|:---:|:---:|
| 第 1 段階（#1-#4） | 2 | 2 | 0 |
| 第 2 段階（#5-#8） | 4 | 0 | 0 |
| 第 3 段階（#9-#12） | 4 | 0 | 0 |
| 第 4 段階（#13-#16） | 1 | 1 (CONTINUING) | 2 (BLOCKED — 計測 framework 待ち) |
| **計** | **11/16** | **3/16** (1 CONTINUING + 2 PARTIAL) | **2/16** (BLOCKED — 計測 framework 待ち) |

完了率の粗算: (11 + 3×0.5) / 16 ≈ **78%**

### 進捗の解釈

- **DONE / CLOSED 11 項目**: plan の意図する単発タスクは完了。Phase 3 #9 は partial closure
  だが「3 ロール思想での再構成」という意図は達成
- **CONTINUING / PARTIAL 3 項目**: 運用しながら段階的に成熟させる項目（#3 / #13 / #15）。
  必要に応じて新規 spec を起こして個別対応
- **BLOCKED 2 項目**: skill discovery 計測 framework と並列化ボトルネック計測 framework の
  整備が前提（#14 / #16）。本フェーズのスコープ外

## 第 1 段階: 即効性のある改善

| # | 項目 | Status | 関連 commit / メモ |
|---|------|:------:|----------|
| 1 | clippy.toml / analyzer の厳格化 | DONE | `fc4cbfd` — TS-R4 を L3 CI に昇格、`clippy.toml.template` 提供、ci-rust/ci-leptos に `-D clippy::unwrap_used/expect_used/panic` 明示 |
| 2 | assert 強制 lint | DONE (L2) | `5b7721d` — review-worker.md E2-6 で「assertion 機構を一切含まないテスト」を明示検出。Rust では構造的 lint が無いため L2 AI レビューで対応 |
| 3 | 分岐カバレッジ別ゲート化 | PARTIAL | `6b95727` — quality-checks.md QC13 新設（Rust/.NET/Node.js コマンド + 段階的 gate 化方針）。CI への実ステップ統合は次段階 |
| 4 | security-audit-guard.sh の撤去 | SKIP（維持判断） | `c6a1ef9` で差分検出式に変更済み、UX 改善は達成。完全撤去は CI 二重化のメリットしかなく、ローカル早期検出（commit 阻止）の価値が大きいため維持を採用 |

## 第 2 段階: 構造防御の確立

| # | 項目 | Status | 関連 commit / メモ |
|---|------|:------:|----------|
| 5 | UserPromptSubmit で spec.md 注入 | DONE | `cf5e525` — `inject-spec.sh` |
| 6 | Stop hook でテスト実行確認 | DONE | `cf5e525` — `verify-tests-run.sh` |
| 7 | cargo-mutants の CI 必須化 | DONE (advisory) | ci-rust.yml / ci-leptos.yml に PR `--in-diff` mutation step を追加（initial advisory）、enforcement-levels.md に行追加 |
| 8 | 技術別 12 ファイルの Rule → Skill 降格 | DONE | `c06cb5e` — Phase B-2 |

## 第 3 段階: エージェント再構成

| # | 項目 | Status | 関連 commit / メモ |
|---|------|:------:|----------|
| 9 | 3 ロール構成集約 | CLOSED（partial closure） | `phase-3-9-role-consolidation.md` 参照。agents 10→7、α/β/γ partial/δ partial 完了、ε と δ remainder は意図的 skip |
| 10 | セッションファイル拡張と再開ロジック | DONE | `dfdd138` — `session-manage.sh` |
| 11 | Wrapper script でレートリミット自動再開 | DONE | `.claude-plugin/scripts/auto-resume.sh` に本番配置（exec 権限付き）、spec-implement SKILL.md に使用手順追記 |
| 12 | SessionStart hook で再開情報注入 | DONE | `db39423` — `resume-hint.sh` |

## 第 4 段階: 仕上げ（継続）

> plan-redesign 8 節で第 4 段階は明示的に「継続」と分類されている。各項目は単発の完了ではなく
> 運用しながら段階的に成熟させる位置づけ。本フェーズでは「現状整理 + 残作業の前提条件」を記録し
> closure とする（次回着手時に新規 plan を起こすか個別判断する）。

| # | 項目 | Status | 関連 commit / メモ |
|---|------|:------:|----------|
| 13 | Rule に残したものの補強 Hook 実装 | CONTINUING | `cf5e525`/`db39423` — `auto-verify-spec.sh` / `detect-new-files.sh` / `inject-skill-hint.sh` / `inject-build-cache.sh` 実装済み。残 Rule (`design-conformance`、`security`、`failure-taxonomy` 等) を Hook で補強するかは個別の Rule ごとに必要性を評価する継続作業。Hook 化が過剰になると attention dilution を起こすため、`enforcement-levels.md` の昇格基準（同パターン違反 2 件以上）に照らして判断する |
| 14 | skill description の磨き込み（discovery 精度向上） | BLOCKED（前提整備待ち） | skill description の効果を測る方法（plugin-dev:skill-creator が提供する eval / variance 計測の整備）が未着手。計測 framework が無い状態で description を改変しても改善か改悪かを判定できない。計測手段が整ってから着手 |
| 15 | arch test / schema test による design-conformance L4 化 | DONE（最小達成） | `generate-arch-tests` Skill が arch test を生成、生成されたテストは既存の `cargo test` で実行される。`enforcement-levels.md` で「依存方向 / 循環依存」が L4 構造テストに割り当て済み。**追加の自動化（Hook で強制生成、CI に明示 step を追加）は CONTINUING として残す** |
| 16 | 計測してボトルネックを見てからタスク間並列を導入 | BLOCKED（前提整備待ち） | plan で明示的に「計測してから」と継続扱い。計測 framework が無いため、現時点で並列化の正味効果を見積もれない。`resource-aware-parallelism` Skill は既に存在するが、ボトルネック計測は別問題。計測 framework が整ってから着手 |

## 残タスクと前提条件

### 単発作業として着手可能

- **#3 残作業（CI 統合）**: QC13 の枠組みは整備済み。`scheduled-quality-standalone.yml` に
  line + branch coverage ステップを追加すれば advisory gate 化を達成
- **#13 追加 Hook**: 個別の Rule（`design-conformance` / `security` / `failure-taxonomy` 等）に
  ついて、`enforcement-levels.md` の昇格基準（同パターン違反 2 件以上）に達した時点で個別に
  Hook 化を検討
- **#15 自動化拡張**: `generate-arch-tests` の出力を Hook で強制生成し、CI に明示 step を
  追加（現状は `cargo test` で実行されるため最低限は機能している）

### 前提条件待ち（BLOCKED）

- **#14 skill description 磨き込み**: skill discovery 精度の **計測 framework** が前提。
  `plugin-dev:skill-creator` の eval / variance 計測機能が整備されてから着手
- **#16 タスク間並列**: ボトルネック計測 framework が前提。計測なしで並列化を入れると
  複雑化のコストだけが残る（現行 `resource-aware-parallelism` の轍）

## 関連ドキュメント

- `tmp/plugin-redesign.md` — 元計画（マスター）
- `phase-3-9-role-consolidation.md` — Phase 3 #9 のクロージャ判断記録
- `.claude-plugin/rules/enforcement-levels.md` — 執行レベル一覧
- `.claude-plugin/rules/quality-checks.md` — QC1〜QC13 の品質チェック定義

## 更新方針

- 各項目を進めた際に **Status 列** と **関連 commit** を更新
- 判断（skip / partial 採用など）は理由を必ず記載
- 全体完了率は粗算（DONE = 1.0、PARTIAL/SKIP/CONTINUING = 0.5、BLOCKED/未着手 = 0）で算出

## クロージャ (2026-04-25)

plan-redesign の 16 項目について、本フェーズでの単発作業はすべて処理済み。

- **DONE / CLOSED**: 11 項目（第 1 段階 2、第 2 段階 4、第 3 段階 4、第 4 段階 1）
- **CONTINUING / PARTIAL**: 3 項目（運用しながら成熟させる継続項目、必要に応じて新規 spec を起こす）
- **BLOCKED**: 2 項目（計測 framework が前提条件、本フェーズのスコープ外）

将来追加作業が発生した場合は本ドキュメントを更新するか新規 plan ファイルを起こすこと。
継続項目（#3 残作業 / #13 追加 Hook / #15 自動化拡張）は単発で着手可能なので、必要を感じた
時点で個別に進める。
