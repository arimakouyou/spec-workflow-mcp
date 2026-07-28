#!/usr/bin/env bash
# セキュリティ監査コミットガード — git commit 時に依存関係の変更があるときだけ audit を実行
# ブロッキング: 脆弱性検出 or audit タイムアウトで exit 2 でコミットを阻止（fail-close）
# 参照 QC: QC4 (cargo audit), QC6 (npm audit), QC12 (dotnet list package --vulnerable)
#
# 発火条件:
#   - git commit コマンドかつ、ステージ済みファイルにマニフェスト(依存セクション変更) or lockfile が含まれる
#   - いずれも満たさない commit は即 exit 0 で素通し
#
# タイムアウト方針（fail-close）:
#   - 各 audit コマンドを `timeout ${AUDIT_TIMEOUT}s` で実行
#   - 120s 以内に完了しない場合は exit 2 でコミットを阻止する
#   - これにより Claude Code 側の hook timeout（non-blocking）へフォールバックすることを防ぐ
#
# 実装上の注意（issue #79 と同種の SIGPIPE 対策）:
#   - `set -o pipefail` 下で `... | grep -q` / `... | head -N` を使うと、読み手が
#     短絡終了した際に書き手が SIGPIPE(141) で落ち、パイプライン全体が 141 になる。
#     判定に使えば脆弱性の見逃し、単独実行なら errexit でスクリプトごと中断し
#     `exit 2` に到達しない（いずれも fail-open）。
#   - このため変数の検査は here-string、出力の打ち切りは `grep -m N` を使う。

set -euo pipefail

# jq が無ければ入力 JSON を解析できないため dormant（他 hooks と同じ fail-open 方針）
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)

# git commit 以外は素通し
# 空白は `[[:space:]]` を使う。`\s` は POSIX ERE に無い GNU 拡張で、非対応環境では
# 文字 `s` として解釈され `git commit` 判定が常に外れる（= ガードが丸ごと素通しする）
if ! grep -qE '^[[:space:]]*git[[:space:]]+commit' <<< "$COMMAND"; then
  exit 0
fi

# ブロック理由は stderr に出す必要がある（exit 2 時に Claude へ渡るのは stderr のみ）
exec 1>&2

AUDIT_TIMEOUT=120

# --- ステージ差分から対象言語を判定 ---
STAGED=$(git diff --cached --name-only 2>/dev/null || true)

CHECK_RUST=false
CHECK_NODE=false
CHECK_DOTNET=false

# Rust: Cargo.lock の変更 or Cargo.toml の依存セクション追加
if grep -qE '(^|/)Cargo\.lock$' <<< "$STAGED"; then
  CHECK_RUST=true
else
  for cargo_file in $(echo "$STAGED" | grep -E '(^|/)Cargo\.toml$' || true); do
    [ -n "$cargo_file" ] || continue
    CARGO_DIFF=$(git diff --cached -- "$cargo_file" 2>/dev/null || true)
    if grep -qE '^\+.*(dependencies|\.version[[:space:]]*=)' <<< "$CARGO_DIFF"; then
      CHECK_RUST=true
      break
    fi
  done
fi

# Node.js: lockfile の変更 or package.json の依存セクション変更
if grep -qE '(^|/)(package-lock\.json|yarn\.lock|pnpm-lock\.yaml)$' <<< "$STAGED"; then
  CHECK_NODE=true
else
  for pkg_file in $(echo "$STAGED" | grep -E '(^|/)package\.json$' || true); do
    [ -n "$pkg_file" ] || continue
    PKG_DIFF=$(git diff --cached -- "$pkg_file" 2>/dev/null || true)
    if grep -qE '"(dependencies|devDependencies|peerDependencies|optionalDependencies|overrides|resolutions)"' <<< "$PKG_DIFF"; then
      CHECK_NODE=true
      break
    fi
  done
fi

# .NET: packages.lock.json / Directory.Packages.props / csproj の PackageReference 変更
if grep -qE '(^|/)(packages\.lock\.json|Directory\.Packages\.props)$' <<< "$STAGED"; then
  CHECK_DOTNET=true
else
  for csproj_file in $(echo "$STAGED" | grep -E '\.csproj$' || true); do
    [ -n "$csproj_file" ] || continue
    CSPROJ_DIFF=$(git diff --cached -- "$csproj_file" 2>/dev/null || true)
    if grep -qE '^\+.*<PackageReference' <<< "$CSPROJ_DIFF"; then
      CHECK_DOTNET=true
      break
    fi
  done
fi

# どの言語でも依存変更がないなら素通し
if [ "$CHECK_RUST" = false ] && [ "$CHECK_NODE" = false ] && [ "$CHECK_DOTNET" = false ]; then
  exit 0
fi

FAIL=false

# --- Rust: cargo audit ---
if [ "$CHECK_RUST" = true ] && [ -f Cargo.toml ] && [ -f Cargo.lock ]; then
  if command -v cargo-audit >/dev/null 2>&1; then
    set +e
    CARGO_AUDIT_OUTPUT=$(timeout "${AUDIT_TIMEOUT}s" cargo audit --quiet 2>&1)
    RC=$?
    set -e
    if [ "$RC" -eq 124 ]; then
      echo "⛔ [security-audit] cargo audit が ${AUDIT_TIMEOUT}s 以内に完了しませんでした（fail-close）"
      FAIL=true
    elif [ "$RC" -ne 0 ]; then
      echo "⛔ [security-audit] cargo audit: 脆弱性が検出されました"
      printf '%s\n' "$CARGO_AUDIT_OUTPUT" | tail -10
      echo "   詳細: cargo audit を実行して確認してください"
      FAIL=true
    fi
  fi
fi

# --- Node.js: npm audit (npm / yarn / pnpm) ---
if [ "$CHECK_NODE" = true ] && [ -f package.json ]; then
  if [ -f package-lock.json ] && command -v npm >/dev/null 2>&1; then
    set +e
    AUDIT_OUTPUT=$(timeout "${AUDIT_TIMEOUT}s" npm audit --audit-level=high 2>&1)
    RC=$?
    set -e
    if [ "$RC" -eq 124 ]; then
      echo "⛔ [security-audit] npm audit が ${AUDIT_TIMEOUT}s 以内に完了しませんでした（fail-close）"
      FAIL=true
    elif [ "$RC" -ne 0 ]; then
      echo "⛔ [security-audit] npm audit: 高/重大な脆弱性が検出されました"
      grep -iE -m 5 '(high|critical)' <<< "$AUDIT_OUTPUT" || true
      echo "   修正: npm audit fix を実行するか、脆弱なパッケージを更新してください"
      FAIL=true
    fi
  elif [ -f yarn.lock ] && command -v yarn >/dev/null 2>&1; then
    set +e
    if yarn --version 2>/dev/null | grep -q '^1\.'; then
      YARN_OUTPUT=$(timeout "${AUDIT_TIMEOUT}s" yarn audit --level high 2>&1)
    else
      YARN_OUTPUT=$(timeout "${AUDIT_TIMEOUT}s" yarn npm audit --severity high 2>&1)
    fi
    RC=$?
    set -e
    if [ "$RC" -eq 124 ]; then
      echo "⛔ [security-audit] yarn audit が ${AUDIT_TIMEOUT}s 以内に完了しませんでした（fail-close）"
      FAIL=true
    elif [ "$RC" -ne 0 ]; then
      echo "⛔ [security-audit] yarn audit: 高/重大な脆弱性が検出されました"
      printf '%s\n' "$YARN_OUTPUT" | tail -10
      FAIL=true
    fi
  elif [ -f pnpm-lock.yaml ] && command -v pnpm >/dev/null 2>&1; then
    set +e
    PNPM_OUTPUT=$(timeout "${AUDIT_TIMEOUT}s" pnpm audit --audit-level high 2>&1)
    RC=$?
    set -e
    if [ "$RC" -eq 124 ]; then
      echo "⛔ [security-audit] pnpm audit が ${AUDIT_TIMEOUT}s 以内に完了しませんでした（fail-close）"
      FAIL=true
    elif [ "$RC" -ne 0 ]; then
      echo "⛔ [security-audit] pnpm audit: 高/重大な脆弱性が検出されました"
      printf '%s\n' "$PNPM_OUTPUT" | tail -10
      FAIL=true
    fi
  fi
fi

# --- .NET: dotnet list package --vulnerable ---
if [ "$CHECK_DOTNET" = true ]; then
  if { ls *.sln >/dev/null 2>&1 || find . -maxdepth 2 -name '*.csproj' -print -quit 2>/dev/null | grep -q .; } && command -v dotnet >/dev/null 2>&1; then
    set +e
    DOTNET_OUTPUT=$(timeout "${AUDIT_TIMEOUT}s" dotnet list package --vulnerable --include-transitive 2>&1)
    RC=$?
    set -e
    if [ "$RC" -eq 124 ]; then
      echo "⛔ [security-audit] dotnet list package --vulnerable が ${AUDIT_TIMEOUT}s 以内に完了しませんでした（fail-close）"
      FAIL=true
    elif grep -qE "(Critical|High)" <<< "$DOTNET_OUTPUT"; then
      echo "⛔ [security-audit] dotnet: 高/重大な脆弱性が検出されました"
      grep -E -m 10 "(Critical|High)" <<< "$DOTNET_OUTPUT" || true
      echo "   修正: 脆弱なパッケージを更新してください"
      FAIL=true
    fi
  fi
fi

if [ "$FAIL" = true ]; then
  exit 2
fi

exit 0
