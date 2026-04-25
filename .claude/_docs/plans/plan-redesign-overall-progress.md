# plan-redesign 全体進捗ドキュメント

> 元計画: `tmp/plugin-redesign.md` 第 1〜4 段階（#1〜#16）
> ブランチ: `refactor/plugin-redesign-phase-a`
> 最終更新: 2026-04-25
> 関連: `phase-3-9-role-consolidation.md`（Phase 3 #9 のクロージャ詳細）

## 進捗サマリ

| 段階 | DONE | PARTIAL / SKIP | 未着手 |
|------|:---:|:---:|:---:|
| 第 1 段階（#1-#4） | 2 | 2 | 0 |
| 第 2 段階（#5-#8） | 3 | 0 | 1 |
| 第 3 段階（#9-#12） | 3 | 1 | 0 |
| 第 4 段階（#13-#16） | 0 | 2 | 2 |
| **計** | **8/16** | **5/16** | **3/16** |

完了率の粗算: (8 + 5×0.5) / 16 ≈ **66%**

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
| 7 | cargo-mutants の CI 必須化 | 未着手 | Skill (`cargo-mutants`) は存在、CI workflow への統合がまだ |
| 8 | 技術別 12 ファイルの Rule → Skill 降格 | DONE | `c06cb5e` — Phase B-2 |

## 第 3 段階: エージェント再構成

| # | 項目 | Status | 関連 commit / メモ |
|---|------|:------:|----------|
| 9 | 3 ロール構成集約 | CLOSED（partial closure） | `phase-3-9-role-consolidation.md` 参照。agents 10→7、α/β/γ partial/δ partial 完了、ε と δ remainder は意図的 skip |
| 10 | セッションファイル拡張と再開ロジック | DONE | `dfdd138` — `session-manage.sh` |
| 11 | Wrapper script でレートリミット自動再開 | PARTIAL | `tmp/auto-resume.sh` のみ、本番配置未着手 |
| 12 | SessionStart hook で再開情報注入 | DONE | `db39423` — `resume-hint.sh` |

## 第 4 段階: 仕上げ（継続）

| # | 項目 | Status | 関連 commit / メモ |
|---|------|:------:|----------|
| 13 | Rule に残したものの補強 Hook 実装 | PARTIAL | `cf5e525`/`db39423` — `auto-verify-spec.sh`、`detect-new-files.sh`、`inject-skill-hint.sh`、`inject-build-cache.sh` 実装済み。残 Rule の網羅は継続 |
| 14 | skill description の磨き込み（discovery 精度向上） | 未着手 | 計測ツールも未整備 |
| 15 | arch test / schema test による design-conformance L4 化 | PARTIAL | `generate-arch-tests` Skill 存在、自動化 / CI 統合は未着手 |
| 16 | 計測してボトルネックを見てからタスク間並列を導入 | 未着手 | 計測 framework 自体が未整備（plan で明示的に「計測してから」と継続扱い） |

## 残タスク優先度

### 高優先

- **#7 cargo-mutants の CI 必須化**: 既存 Skill を CI workflow テンプレート (`scheduled-quality-standalone.yml` or `ci-rust.yml`) に組み込むだけ。差分モード (`--in-diff`) で実行時間を抑えられる
- **#3 残作業（CI 統合）**: QC13 の枠組みは整備済み。`scheduled-quality-standalone.yml` に line + branch coverage ステップを追加すれば advisory gate 化を達成

### 中優先

- **#11 auto-resume wrapper 本番配置**: `tmp/auto-resume.sh` を `templates/` または `wrappers/` に移して setup 手順を整備
- **#15 arch test 自動化**: `generate-arch-tests` の出力を CI で実行し、依存方向違反 / 循環依存を
  blocking にする

### 低優先（plan で「継続」と明記）

- #14 skill description 磨き込み（要計測 framework）
- #16 タスク間並列（要計測 framework）

## 関連ドキュメント

- `tmp/plugin-redesign.md` — 元計画（マスター）
- `phase-3-9-role-consolidation.md` — Phase 3 #9 のクロージャ判断記録
- `.claude-plugin/rules/enforcement-levels.md` — 執行レベル一覧
- `.claude-plugin/rules/quality-checks.md` — QC1〜QC13 の品質チェック定義

## 更新方針

- 各項目を進めた際に **Status 列** と **関連 commit** を更新
- 判断（skip / partial 採用など）は理由を必ず記載
- 全体完了率は粗算（DONE = 1.0、PARTIAL/SKIP = 0.5、未着手 = 0）で算出
