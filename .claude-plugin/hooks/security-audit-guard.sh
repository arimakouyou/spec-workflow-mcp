#!/usr/bin/env bash
# セキュリティ監査コミットガード — git commit 時に依存パッケージの脆弱性をチェック
# ブロッキング: Rust は cargo audit の終了コードに従い脆弱性が1件でもあれば、Node/.NET は高/重大な脆弱性検出時に
# exit 2 でコミットを阻止
# 参照 QC: QC4 (cargo audit: 脆弱性検出時にブロック), QC6 (npm audit), QC12 (dotnet list package --vulnerable)
#
# 参考パターン: docker-env-guard.sh + arch-lint-guard.sh (wingrs-paas-front-api)

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)

# git commit 以外は素通し
if ! echo "$COMMAND" | grep -qE '^\s*git\s+commit'; then
  exit 0
fi

FAIL=false

# --- Rust: cargo audit ---
if [ -f Cargo.toml ] && [ -f Cargo.lock ]; then
  if command -v cargo-audit >/dev/null 2>&1; then
    if ! cargo audit --quiet 2>&1; then
      echo "⛔ [security-audit] cargo audit: 脆弱性が検出されました"
      echo "   詳細: cargo audit を実行して確認してください"
      FAIL=true
    fi
  fi
fi

# --- Node.js: npm audit ---
if [ -f package.json ] && [ -f package-lock.json ]; then
  if command -v npm >/dev/null 2>&1; then
    # 出力をキャプチャし、失敗時のみ表示（成功時のノイズを抑制）
    AUDIT_OUTPUT=$(npm audit --audit-level=high 2>&1) || AUDIT_EXIT=$?
    AUDIT_EXIT=${AUDIT_EXIT:-0}
    if [ "$AUDIT_EXIT" -ne 0 ]; then
      echo "⛔ [security-audit] npm audit: 高/重大な脆弱性が検出されました"
      echo "$AUDIT_OUTPUT" | grep -iE '(high|critical)' | head -5
      echo "   修正: npm audit fix を実行するか、脆弱なパッケージを更新してください"
      FAIL=true
    fi
  fi
# yarn.lock 使用時
elif [ -f package.json ] && [ -f yarn.lock ]; then
  if command -v yarn >/dev/null 2>&1; then
    # Yarn v1 と v2+ で監査コマンドが異なる
    if yarn --version 2>/dev/null | grep -q '^1\.'; then
      yarn audit --level high 2>&1 | tail -5 || {
        echo "⛔ [security-audit] yarn audit: 高/重大な脆弱性が検出されました"
        FAIL=true
      }
    else
      yarn npm audit --severity high 2>&1 | tail -5 || {
        echo "⛔ [security-audit] yarn npm audit: 高/重大な脆弱性が検出されました"
        FAIL=true
      }
    fi
  fi
fi

# --- .NET: dotnet list package --vulnerable ---
if ls *.sln >/dev/null 2>&1 || find . -maxdepth 2 -name '*.csproj' -print -quit 2>/dev/null | grep -q .; then
  if command -v dotnet >/dev/null 2>&1; then
    OUTPUT=$(dotnet list package --vulnerable --include-transitive 2>&1 || true)
    if echo "$OUTPUT" | grep -qE "(Critical|High)"; then
      echo "⛔ [security-audit] dotnet: 高/重大な脆弱性が検出されました"
      echo "$OUTPUT" | grep -E "(Critical|High)" | head -10
      echo "   修正: 脆弱なパッケージを更新してください"
      FAIL=true
    fi
  fi
fi

if [ "$FAIL" = true ]; then
  exit 2
fi

exit 0
