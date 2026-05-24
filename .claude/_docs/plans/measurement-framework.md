# 計測 framework — plan-redesign #14 / #16 の前提整備

> 関連: `tmp/plugin-redesign.md` 第 4 段階 #14 (skill description 磨き込み) / #16 (タスク間並列)
> ブランチ: `refactor/plugin-redesign-phase-a`
> 最終更新: 2026-04-25

## 目的

plan-redesign の運用思想 **「効いているもの・効いていないものを判定して降格・削除」** を支える
計測基盤を整備する。**計測なし改修なし** を徹底するため、本 framework が前提条件となる。

## カバー範囲

| 計測対象 | 取得手段 | 用途 |
|---------|---------|------|
| Tool 所要時間 (Bash / Edit / Write 等) | `timing-logger-pre/post.sh` | bottleneck 分析、UX 改善 |
| Phase 所要時間 (Step 4 TDD / Step 5 UT 等) | `session-manage.sh start-phase/complete-phase` | 律速フェーズ特定 |
| Hook 実行 (所要時間 / exit code / preview) | `_wrap.sh` | Hook の効果と UX 影響、撤去判断 |
| Rule file Read 頻度 | `timing-logger-post.sh` 拡張 | 使われていない Rule 抽出 |
| Rule 違反検出 (rule_ref) | `session-manage.sh record-findings` | 昇格判断、Rule の効き |

## 設計

### データ保存先

`.implement-session/metrics.jsonl` (append-only JSONL)

```jsonl
{"event":"task_start","task_id":"T1.1","wave_id":"wave-1","ts":"..."}
{"event":"phase_start","task_id":"T1.1","phase":"step4_tdd","ts":"..."}
{"event":"tool","tool":"Bash","cmd_summary":"cargo test","duration_ms":45000,"ts":"..."}
{"event":"hook","hook":"verify-tests-run","duration_ms":15,"exit_code":0,"preview":"","ts":"..."}
{"event":"rule_read","rule":"type-safety","ts":"..."}
{"event":"rule_violation","rule":"security.md#C2","severity":"Moderate","task_id":"T1.1","ts":"..."}
{"event":"phase_end","task_id":"T1.1","phase":"step4_tdd","duration_ms":540000,"ts":"..."}
{"event":"task_end","task_id":"T1.1","duration_ms":960000,"ts":"..."}
```

### 計測の階層

```text
Wave (e.g., wave-1)
└── Task (e.g., T1.1)
    └── Phase (Step 4 TDD / Step 5 UT / Step 6 Review)
        └── Subagent invocation (parallel-worker / review-worker)
            └── Tool execution (Bash: cargo test, Edit: file.rs, ...)
```

## 実装ファイル

| ファイル | 役割 |
|---------|------|
| `.claude-plugin/hooks/_wrap.sh` | 全 Hook の wrapper、所要時間 / exit code / preview 記録 |
| `.claude-plugin/hooks/timing-logger-pre.sh` | Tool 開始時刻記録 (PreToolUse) |
| `.claude-plugin/hooks/timing-logger-post.sh` | Tool 所要時間 + rule_read 記録 (PostToolUse) |
| `.claude-plugin/scripts/session-manage.sh` | start-phase / complete-phase / record-findings 追加 |
| `.claude-plugin/scripts/aggregate-metrics.sh` | 集計スクリプト (Hook 別 / Phase 別 / Rule 別) |
| `.claude-plugin/hooks/hooks.json` | 既存 Hook を `_wrap.sh` 経由に一括書き換え + timing-logger 追加 |

## 集計コマンド

```bash
# wave 全体の概要
.claude-plugin/scripts/aggregate-metrics.sh summary

# Hook 別所要時間ランキング
.claude-plugin/scripts/aggregate-metrics.sh hooks

# Phase 別所要時間 (律速特定)
.claude-plugin/scripts/aggregate-metrics.sh phases

# Rule 別違反数 (昇格判断)
.claude-plugin/scripts/aggregate-metrics.sh rules

# 並列化 speedup 見積もり
.claude-plugin/scripts/aggregate-metrics.sh speedup --wave wave-1
```

## 意思決定への変換

### Hook 撤去 / 設計見直し候補

| 条件 | 判定 |
|------|------|
| 平均 > 1000ms | UX 阻害、軽量化検討 |
| warn_rate > 50% | false positive 多発、検出条件見直し |
| count = 0 | 一度も発火していない、撤去候補 |

### Rule 昇格候補

| 条件 | 判定 |
|------|------|
| 同一 rule の violation 2 件以上 | L1 → L2 昇格候補 |
| rule_read = 0 + violation = 0 | 効いていない、撤去候補 |

### 並列化判断

| 条件 | 判定 |
|------|------|
| `speedup_ratio = sequential_time / critical_path >= 1.5` | 並列化に着手する価値あり |
| review-worker が phase 全体の > 50% | review bound、並列効果限定的 |
| cargo build > 60% + sccache hit < 50% | 並列で hit 率低下リスク、慎重に |

## 段階実装

| Phase | 内容 | 目的 |
|-------|------|------|
| **1** | `_wrap.sh` + hooks.json 書き換え | Hook 計測のみで bottleneck 確認 |
| **2** | `timing-logger-pre/post.sh` | Tool 所要時間 + rule_read 取得 |
| **3** | `session-manage.sh` 拡張 | Phase + 違反計測 |
| **4** | `aggregate-metrics.sh` | 意思決定への変換 |

各 phase で動作確認、機能不足を検出してから次へ。本ドキュメントでは全 phase を一括実装。

## 副作用への配慮

- `_wrap.sh` は **stderr / exit code / stdout を完全に元 Hook と同じに保つ**
  - stdout のみ capture (Claude に注入される対象)
  - stderr はそのまま流す (log)
  - exit code を `exit $EXIT_CODE` で尊重
- 計測失敗が Hook の動作を壊さないよう **`|| true` で fail-safe**
- `.implement-session/` が無い環境 (spec 外) では silent skip

## 関連ドキュメント

- `plan-redesign-overall-progress.md` — #14 / #16 の Status
- `phase-3-9-role-consolidation.md` — Phase 3 #9 の closure 記録
- `.claude-plugin/rules/enforcement-levels.md` — 昇格基準

## 完了条件

- [x] `_wrap.sh` 作成 + hooks.json 一括書き換え
- [x] `timing-logger-pre.sh` / `timing-logger-post.sh` 作成
- [x] `session-manage.sh` 拡張 (start-phase / complete-phase / record-findings、
  task_start/task_end metrics 追加)
- [x] `aggregate-metrics.sh` 作成 (summary / hooks / tools / phases / rules / speedup)
- [x] 動作確認 (sleep 1 + duration 1004ms 整合、全イベント種別記録確認)
- [x] vitest pass / rumdl 新規違反 0
- [x] `plan-redesign-overall-progress.md` 更新 (#14 #16 を BLOCKED → READY)
