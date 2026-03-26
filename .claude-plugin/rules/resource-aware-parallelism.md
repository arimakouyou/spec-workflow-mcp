---
always_apply: true
---

# リソース適応型並列制御

並列エージェント起動前にシステムリソースを検査し、利用可能な CPU コア数と空きメモリに基づいて最大並列数を動的に調整するルール。全並列実行スキルに適用される。

## リソース検出

並列エージェントを起動する**直前**に、以下の Bash スニペットを**単一の Bash 呼び出し**内で実行してリソース情報を取得する（Claude Code の Bash ツールはコマンド間でシェル状態を保持しない）。

```bash
# === リソース検出 + 最大並列数計算 ===
CPU_CORES=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)
if [ -f /proc/meminfo ]; then
  FREE_MEM_MB=$(awk '/MemAvailable/{printf "%d", $2/1024}' /proc/meminfo)
elif command -v vm_stat >/dev/null 2>&1; then
  FREE_MEM_MB=$(vm_stat | awk '/Pages free/{gsub(/\./,"",$3); print int($3*4096/1048576)}')
else
  FREE_MEM_MB=4096
fi
MAX_OVERRIDE=${SWM_MAX_PARALLEL_AGENTS:-""}

# 重量エージェント（コンパイル系: parallel-worker, integ-test-worker）
if [ -n "$MAX_OVERRIDE" ]; then
  MAX_HEAVY=$MAX_OVERRIDE
elif [ "$CPU_CORES" -ge 8 ] && [ "$FREE_MEM_MB" -ge 16384 ]; then
  BY_CPU=$((CPU_CORES / 2)); BY_MEM=$((FREE_MEM_MB / 4096))
  MAX_HEAVY=$(( BY_CPU < BY_MEM ? BY_CPU : BY_MEM ))
  MAX_HEAVY=$(( MAX_HEAVY > 4 ? 4 : MAX_HEAVY ))
elif [ "$CPU_CORES" -ge 4 ] && [ "$FREE_MEM_MB" -ge 8192 ]; then
  BY_CPU=$((CPU_CORES / 2)); BY_MEM=$((FREE_MEM_MB / 4096))
  MAX_HEAVY=$(( BY_CPU < BY_MEM ? BY_CPU : BY_MEM ))
  MAX_HEAVY=$(( MAX_HEAVY > 3 ? 3 : MAX_HEAVY ))
elif [ "$CPU_CORES" -ge 2 ] && [ "$FREE_MEM_MB" -ge 4096 ]; then
  MAX_HEAVY=2
else
  MAX_HEAVY=1
fi

# 軽量エージェント（読み取り中心: phase-review-team experts）
if [ -n "$MAX_OVERRIDE" ]; then
  MAX_LIGHT=$MAX_OVERRIDE
elif [ "$CPU_CORES" -ge 4 ] && [ "$FREE_MEM_MB" -ge 4096 ]; then
  MAX_LIGHT=5
elif [ "$CPU_CORES" -ge 2 ] && [ "$FREE_MEM_MB" -ge 2048 ]; then
  MAX_LIGHT=3
else
  MAX_LIGHT=2
fi

echo "RESOURCE_CHECK: CPU_CORES=$CPU_CORES FREE_MEM_MB=$FREE_MEM_MB MAX_HEAVY_AGENTS=$MAX_HEAVY MAX_LIGHT_AGENTS=$MAX_LIGHT"
```

## エージェント種別分類

| 種別 | 変数 | 対象エージェント | 特徴 |
|------|------|--------------|------|
| **重量** | `MAX_HEAVY_AGENTS` | `parallel-worker`, `integ-test-worker` | cargo build/test/clippy 実行、高メモリ消費 |
| **軽量** | `MAX_LIGHT_AGENTS` | `general-purpose`（phase-review-team experts） | ほぼ読み取り専用の解析 |

## 閾値テーブル（重量エージェント）

| CPU コア数 | 空きメモリ | 最大並列数 | 根拠 |
|:---:|:---:|:---:|------|
| >= 8 | >= 16GB | min(cores/2, mem/4GB, 4) | 潤沢なリソース。上限4で安全マージン確保 |
| >= 4 | >= 8GB | min(cores/2, mem/4GB, 3) | 中規模。上限3 |
| >= 2 | >= 4GB | 2 | 最低限の並列化 |
| < 2 or < 4GB | * | 1 | 逐次実行（安全策） |

## 閾値テーブル（軽量エージェント）

| CPU コア数 | 空きメモリ | 最大並列数 | 根拠 |
|:---:|:---:|:---:|------|
| >= 4 | >= 4GB | 5 | 読み取り中心のため制約が緩い |
| >= 2 | >= 2GB | 3 | コンテキスト切替オーバーヘッド考慮 |
| < 2 or < 2GB | * | 2 | 最小グループ |

## ユーザー上書き

環境変数 `SWM_MAX_PARALLEL_AGENTS` を設定することで、自動検出値を上書きできる（重量・軽量の区別なく両方に適用）。

```bash
# 例: 最大2エージェントに制限
export SWM_MAX_PARALLEL_AGENTS=2
```

## 適用ルール

1. **並列エージェント起動前に必ずリソース検出を実行する**
2. wave 内のタスク数が `MAX_HEAVY_AGENTS` を超える場合、wave を**サブバッチ**に分割する
   - 例: wave に 6 タスクあり MAX_HEAVY=3 の場合 → [3, 3] のサブバッチで逐次実行
3. `MAX_HEAVY_AGENTS=1` の場合は逐次実行（並列化しない）
4. リソース検出結果はログ出力し、ユーザーに可視化する
5. リソース検出コマンドが失敗した場合のフォールバック: CPU=2, メモリ=4096MB として計算
