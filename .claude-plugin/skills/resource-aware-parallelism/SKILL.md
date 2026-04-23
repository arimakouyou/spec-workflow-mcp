---
name: resource-aware-parallelism
description: |
  並列エージェント起動前にシステムリソース (CPU コア数 / 空きメモリ) を動的検出し、最大並列数を自動調整するスキル。重量エージェント (parallel-worker, integ-test-worker など compile-heavy) には MAX_HEAVY_AGENTS、軽量エージェント (phase-review-team experts など read-mostly) には MAX_LIGHT_AGENTS を段階的閾値で算出し、SWM_MAX_PARALLEL_AGENTS 環境変数による上書きにも対応。spec-implement の wave 実行前、integration-test の Worker 割当前、phase-review-team の専門家起動前、任意の並列サブエージェント起動前に参照。
allowed-tools: [Read, Bash, Grep]
---

# Resource-Aware Parallelism Skill

## 対象

- 複数の並列サブエージェントを起動する前の max concurrency 決定
- `spec-implement` の wave 実行時のサブバッチ分割
- `integration-test` / `integration-test-dotnet` の Worker 割当
- `phase-review-team` の並列専門家起動
- `wave-harness-worker` / `parallel-worker` などの並列フレームワーク利用時

## 対象外

- 実際の並列起動の実装 → 各 Skill / Agent の該当セクション
- CPU / メモリを要求する個別ジョブのチューニング → プロジェクト側の設定

## 主要観点

### 1. リソース検出スニペット

並列エージェントを起動する**直前**に、以下を**単一の Bash 呼び出し**内で実行する（Claude Code の Bash はコマンド間でシェル状態を保持しないため）:

```bash
# === リソース検出 + 最大並列数計算 ===
CPU_CORES=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)
if [ -f /proc/meminfo ]; then
  FREE_MEM_MB=$(awk '/MemAvailable/{printf "%d", $2/1024}' /proc/meminfo)
elif command -v vm_stat >/dev/null 2>&1; then
  PAGE_SIZE=$(sysctl -n hw.pagesize 2>/dev/null || echo 4096)
  FREE_MEM_MB=$(vm_stat | awk -v PS="$PAGE_SIZE" '/Pages free/{gsub(/\./,"",$3); print int($3*PS/1048576)}')
else
  FREE_MEM_MB=4096
fi

# 数値ガード: パース失敗時はフォールバック値
case "$CPU_CORES" in ''|*[!0-9]*) CPU_CORES=2 ;; esac
case "$FREE_MEM_MB" in ''|*[!0-9]*) FREE_MEM_MB=4096 ;; esac

# ユーザー上書き値のバリデーション（正の整数のみ受付）
MAX_OVERRIDE=${SWM_MAX_PARALLEL_AGENTS:-""}
if [ -n "$MAX_OVERRIDE" ]; then
  case "$MAX_OVERRIDE" in ''|*[!0-9]*|0) MAX_OVERRIDE="" ;; esac
fi

# 重量エージェント（コンパイル系: parallel-worker, integ-test-worker）
if [ -n "$MAX_OVERRIDE" ]; then
  MAX_HEAVY_AGENTS=$MAX_OVERRIDE
elif [ "$CPU_CORES" -ge 8 ] && [ "$FREE_MEM_MB" -ge 16384 ]; then
  BY_CPU=$((CPU_CORES / 2)); BY_MEM=$((FREE_MEM_MB / 4096))
  MAX_HEAVY_AGENTS=$(( BY_CPU < BY_MEM ? BY_CPU : BY_MEM ))
  MAX_HEAVY_AGENTS=$(( MAX_HEAVY_AGENTS > 4 ? 4 : MAX_HEAVY_AGENTS ))
elif [ "$CPU_CORES" -ge 4 ] && [ "$FREE_MEM_MB" -ge 8192 ]; then
  BY_CPU=$((CPU_CORES / 2)); BY_MEM=$((FREE_MEM_MB / 4096))
  MAX_HEAVY_AGENTS=$(( BY_CPU < BY_MEM ? BY_CPU : BY_MEM ))
  MAX_HEAVY_AGENTS=$(( MAX_HEAVY_AGENTS > 3 ? 3 : MAX_HEAVY_AGENTS ))
elif [ "$CPU_CORES" -ge 2 ] && [ "$FREE_MEM_MB" -ge 4096 ]; then
  MAX_HEAVY_AGENTS=2
else
  MAX_HEAVY_AGENTS=1
fi

# 軽量エージェント（読み取り中心: phase-review-team experts）
if [ -n "$MAX_OVERRIDE" ]; then
  MAX_LIGHT_AGENTS=$MAX_OVERRIDE
elif [ "$CPU_CORES" -ge 4 ] && [ "$FREE_MEM_MB" -ge 4096 ]; then
  MAX_LIGHT_AGENTS=5
elif [ "$CPU_CORES" -ge 2 ] && [ "$FREE_MEM_MB" -ge 2048 ]; then
  MAX_LIGHT_AGENTS=3
else
  MAX_LIGHT_AGENTS=2
fi

echo "[resource-check] CPU_CORES=$CPU_CORES FREE_MEM_MB=$FREE_MEM_MB MAX_HEAVY_AGENTS=$MAX_HEAVY_AGENTS MAX_LIGHT_AGENTS=$MAX_LIGHT_AGENTS"
```

### 2. エージェント種別分類

| 種別 | 変数 | 対象エージェント | 特徴 |
|---|---|---|---|
| 重量 | `MAX_HEAVY_AGENTS` | `parallel-worker`, `integ-test-worker` | cargo build/test/clippy、高メモリ |
| 軽量 | `MAX_LIGHT_AGENTS` | `general-purpose`（phase-review-team experts） | ほぼ読み取り専用 |

### 3. 閾値テーブル（重量エージェント）

| CPU コア | 空きメモリ | 最大並列 | 根拠 |
|:---:|:---:|:---:|---|
| >= 8 | >= 16GB | `min(cores/2, mem/4GB, 4)` | 潤沢リソース。上限 4 で安全マージン |
| >= 4 | >= 8GB | `min(cores/2, mem/4GB, 3)` | 中規模。上限 3 |
| >= 2 | >= 4GB | 2 | 最低限の並列化 |
| < 2 or < 4GB | — | 1 | 逐次実行（安全策） |

### 4. 閾値テーブル（軽量エージェント）

| CPU コア | 空きメモリ | 最大並列 | 根拠 |
|:---:|:---:|:---:|---|
| >= 4 | >= 4GB | 5 | 読み取り中心のため制約が緩い |
| >= 2 | >= 2GB | 3 | コンテキスト切替オーバーヘッド考慮 |
| < 2 or < 2GB | — | 2 | 最小グループ |

### 5. ユーザー上書き

環境変数 `SWM_MAX_PARALLEL_AGENTS` で自動検出値を上書きできる（重量・軽量の区別なく両方に適用）:

```bash
# 例: 最大 2 エージェントに制限
export SWM_MAX_PARALLEL_AGENTS=2
```

### 6. 適用ルール

1. **並列エージェント起動前に必ずリソース検出を実行**
2. wave 内のタスク数が `MAX_HEAVY_AGENTS` を超える場合、wave を**サブバッチ**に分割する
   - 例: wave に 6 タスクあり `MAX_HEAVY_AGENTS=3` → `[3, 3]` のサブバッチで逐次実行
3. `MAX_HEAVY_AGENTS=1` の場合は逐次実行（並列化しない）
4. リソース検出結果はログ出力しユーザーに可視化
5. 検出コマンド失敗時のフォールバック: `CPU=2`, `メモリ=4096MB`

## よくある落とし穴

1. **リソース検出をスキップして固定並列数で起動**: メモリ不足で SIGKILL、builder host がダウンするリスク
2. **複数 Bash 呼び出しに分ける**: Claude Code の Bash はシェル状態を保持しないので変数が消える。必ず単一呼び出し
3. **`MAX_HEAVY_AGENTS=1` で wave 分割をしない**: ログが見づらくなるだけなので、常にサブバッチ分割経路を通す
4. **overflow 時の上限 clamp を忘れる**: `min(X, 4)` / `min(X, 3)` の clamp を必ず適用

## プロジェクト固有の規約

- `spec-implement` の wave 実行は常にリソース検出を経由する（直接の並列起動は禁止）
- `integration-test` の Worker 割当も同様
- CI 環境では `SWM_MAX_PARALLEL_AGENTS` を runner の vCPU 数に基づいて設定する

## 関連 Rule / Skill

- 関連 Skill: `spec-implement`, `integration-test`, `integration-test-dotnet`, `phase-review-team`
- 関連 Rule: `failure-taxonomy`（リソース枯渇で SIGKILL 発生時の分類）

## 参考リンク

- GNU coreutils `nproc`: <https://www.gnu.org/software/coreutils/manual/html_node/nproc-invocation.html>
- macOS `sysctl` / `vm_stat`: man ページ参照
