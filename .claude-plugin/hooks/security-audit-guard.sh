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

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)

# git commit 以外は素通し
if ! echo "$COMMAND" | grep -qE '^\s*git\s+commit'; then
  exit 0
fi

AUDIT_TIMEOUT=120

# --- ステージ差分から対象言語を判定 ---
STAGED=$(git diff --cached --name-only 2>/dev/null || true)

CHECK_RUST=false
CHECK_NODE=false
CHECK_DOTNET=false

# Rust: Cargo.lock の変更 or Cargo.toml の依存セクション追加
if echo "$STAGED" | grep -qE '(^|/)Cargo\.lock$'; then
  CHECK_RUST=true
else
  for cargo_file in $(echo "$STAGED" | grep -E '(^|/)Cargo\.toml$' || true); do
    [ -n "$cargo_file" ] || continue
    CARGO_DIFF=$(git diff --cached -- "$cargo_file" 2>/dev/null || true)
    if echo "$CARGO_DIFF" | grep -qE '^\+.*(dependencies|\.version\s*=)'; then
      CHECK_RUST=true
      break
    fi
  done
fi

# Node.js: lockfile の変更 or package.json の依存セクション変更
if echo "$STAGED" | grep -qE '(^|/)(package-lock\.json|yarn\.lock|pnpm-lock\.yaml)$'; then
  CHECK_NODE=true
else
  for pkg_file in $(echo "$STAGED" | grep -E '(^|/)package\.json$' || true); do
    [ -n "$pkg_file" ] || continue
    PKG_DIFF=$(git diff --cached -- "$pkg_file" 2>/dev/null || true)
    if echo "$PKG_DIFF" | grep -qE '"(dependencies|devDependencies|peerDependencies|optionalDependencies|overrides|resolutions)"'; then
      CHECK_NODE=true
      break
    fi
  done
fi

# .NET: packages.lock.json / Directory.Packages.props / csproj の PackageReference 変更
if echo "$STAGED" | grep -qE '(^|/)(packages\.lock\.json|Directory\.Packages\.props)$'; then
  CHECK_DOTNET=true
else
  for csproj_file in $(echo "$STAGED" | grep -E '\.csproj$' || true); do
    [ -n "$csproj_file" ] || continue
    CSPROJ_DIFF=$(git diff --cached -- "$csproj_file" 2>/dev/null || true)
    if echo "$CSPROJ_DIFF" | grep -qE '^\+.*<PackageReference'; then
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
    timeout "${AUDIT_TIMEOUT}s" cargo audit --quiet 2>&1
    RC=$?
    set -e
    if [ "$RC" -eq 124 ]; then
      echo "⛔ [security-audit] cargo audit が ${AUDIT_TIMEOUT}s 以内に完了しませんでした（fail-close）"
      FAIL=true
    elif [ "$RC" -ne 0 ]; then
      echo "⛔ [security-audit] cargo audit: 脆弱性が検出されました"
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
      echo "$AUDIT_OUTPUT" | grep -iE '(high|critical)' | head -5
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
      echo "$YARN_OUTPUT" | tail -10
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
      echo "$PNPM_OUTPUT" | tail -10
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
    elif echo "$DOTNET_OUTPUT" | grep -qE "(Critical|High)"; then
      echo "⛔ [security-audit] dotnet: 高/重大な脆弱性が検出されました"
      echo "$DOTNET_OUTPUT" | grep -E "(Critical|High)" | head -10
      echo "   修正: 脆弱なパッケージを更新してください"
      FAIL=true
    fi
  fi
fi

if [ "$FAIL" = true ]; then
  exit 2
fi

exit 0
