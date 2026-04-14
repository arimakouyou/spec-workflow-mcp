#!/usr/bin/env bash
# Lockfile コミットガード — git commit 時にマニフェストと lockfile の整合性を検証
# ブロッキング: lockfile 未コミットの場合は exit 2 でコミットを阻止
# 参照 QC: QC9 (Lockfile Verification)
#
# 参考パターン: arch-lint-guard.sh (wingrs-paas-front-api)

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)

# git commit 以外は素通し
if ! echo "$COMMAND" | grep -qE '^\s*git\s+commit'; then
  exit 0
fi

FAIL=false

# --- Node.js (いずれか 1 つで OK) ---
if [ -f package.json ]; then
  if [ ! -f package-lock.json ] && [ ! -f yarn.lock ] && [ ! -f pnpm-lock.yaml ]; then
    echo "⛔ [lockfile-guard] package.json が存在しますが lockfile がありません (package-lock.json, yarn.lock, pnpm-lock.yaml)"
    echo "   修正: npm install / yarn install / pnpm install を実行して lockfile を生成してください"
    FAIL=true
  fi
fi

# --- Rust ---
if [ -f Cargo.toml ] && [ ! -f Cargo.lock ]; then
  echo "⛔ [lockfile-guard] Cargo.toml が存在しますが Cargo.lock がありません"
  echo "   修正: cargo generate-lockfile を実行してください"
  FAIL=true
fi

# --- Go ---
if [ -f go.mod ] && [ ! -f go.sum ]; then
  echo "⛔ [lockfile-guard] go.mod が存在しますが go.sum がありません"
  echo "   修正: go mod tidy を実行してください"
  FAIL=true
fi

# --- .NET (RestorePackagesWithLockFile 有効時のみ) ---
if find . -maxdepth 2 -name '*.csproj' -print -quit 2>/dev/null | grep -q .; then
  if find . -maxdepth 3 \( -name '*.csproj' -o -name 'Directory.Build.props' -o -name 'Directory.*.props' \) -exec grep -l 'RestorePackagesWithLockFile' {} + 2>/dev/null | head -1 | grep -q .; then
    if ! find . -maxdepth 3 -name 'packages.lock.json' -print -quit 2>/dev/null | grep -q .; then
      echo "⛔ [lockfile-guard] RestorePackagesWithLockFile が有効ですが packages.lock.json がありません"
      echo "   修正: dotnet restore を実行してください"
      FAIL=true
    fi
  fi
fi

# --- Poetry (Python) ---
if [ -f pyproject.toml ] && grep -q '\[tool.poetry\]' pyproject.toml 2>/dev/null; then
  if [ ! -f poetry.lock ]; then
    echo "⛔ [lockfile-guard] pyproject.toml (Poetry) が存在しますが poetry.lock がありません"
    echo "   修正: poetry lock を実行してください"
    FAIL=true
  fi
fi

# --- Bundler (Ruby) ---
if [ -f Gemfile ] && [ ! -f Gemfile.lock ]; then
  echo "⛔ [lockfile-guard] Gemfile が存在しますが Gemfile.lock がありません"
  echo "   修正: bundle install を実行してください"
  FAIL=true
fi

# --- マニフェスト変更時の lockfile 同期チェック ---
# ステージ済みファイルにマニフェストが含まれる場合、対応する lockfile もステージされていることを検証
STAGED=$(git diff --cached --name-only 2>/dev/null || true)

# check_sync: マニフェストがステージ済みなら対応する lockfile もステージされているか確認
# $1: マニフェストファイル名  $2: lockfile 名（スペース区切りで複数可）  $3: install コマンド
check_sync() {
  local manifest="$1"
  local lockfiles="$2"
  local fix_cmd="$3"
  # ドットをエスケープして正規表現の末尾アンカー付きでマッチ
  local manifest_re
  manifest_re=$(printf '%s' "$manifest" | sed 's/\./\\./g')

  if echo "$STAGED" | grep -qE "(^|/)${manifest_re}$"; then
    local found=false
    for lf in $lockfiles; do
      local lf_re
      lf_re=$(printf '%s' "$lf" | sed 's/\./\\./g')
      if echo "$STAGED" | grep -qE "(^|/)${lf_re}$"; then
        found=true
        break
      fi
    done
    if [ "$found" = false ]; then
      echo "⛔ [lockfile-guard] $manifest が変更されていますが、対応する lockfile がステージされていません"
      echo "   修正: $fix_cmd を実行し、lockfile を git add してください"
      FAIL=true
    fi
  fi
}

if [ -n "$STAGED" ]; then
  # package.json は依存関係フィールドの変更時のみチェック
  # (scripts, version, description 等の変更では lockfile 更新不要)
  for pkg in $(echo "$STAGED" | grep -E '(^|/)package\.json$' || true); do
    if [ -n "$pkg" ]; then
      PKG_DIFF=$(git diff --cached -- "$pkg" 2>/dev/null || true)
      if echo "$PKG_DIFF" | grep -qE '"(dependencies|devDependencies|peerDependencies|optionalDependencies|overrides|resolutions)"'; then
        local_found=false
        for lf in package-lock.json yarn.lock pnpm-lock.yaml; do
          local lf_re
          lf_re=$(printf '%s' "$lf" | sed 's/\./\\./g')
          if echo "$STAGED" | grep -qE "(^|/)${lf_re}$"; then
            local_found=true
            break
          fi
        done
        if [ "$local_found" = false ]; then
          echo "⛔ [lockfile-guard] $pkg の依存関係が変更されていますが、対応する lockfile がステージされていません"
          echo "   修正: npm install / yarn install / pnpm install を実行し、lockfile を git add してください"
          FAIL=true
        fi
      fi
    fi
  done

  # Cargo.toml は [dependencies] セクションの変更時のみチェック
  for cargo in $(echo "$STAGED" | grep -E '(^|/)Cargo\.toml$' || true); do
    if [ -n "$cargo" ]; then
      CARGO_DIFF=$(git diff --cached -- "$cargo" 2>/dev/null || true)
      if echo "$CARGO_DIFF" | grep -qE '^\+.*(dependencies|\.version\s*=)'; then
        if ! echo "$STAGED" | grep -qE '(^|/)Cargo\.lock$'; then
          echo "⛔ [lockfile-guard] $cargo の依存関係が変更されていますが、Cargo.lock がステージされていません"
          echo "   修正: cargo generate-lockfile を実行し、Cargo.lock を git add してください"
          FAIL=true
        fi
      fi
    fi
  done

  check_sync "go.mod" "go.sum" "go mod tidy"
  check_sync "pyproject.toml" "poetry.lock" "poetry lock"
  check_sync "Gemfile" "Gemfile.lock" "bundle install"
fi

# --- .gitignore で lockfile が除外されていないことを確認 ---
for lockfile in package-lock.json yarn.lock pnpm-lock.yaml Cargo.lock go.sum poetry.lock Gemfile.lock packages.lock.json; do
  if [ -f "$lockfile" ] && git check-ignore -q "$lockfile" 2>/dev/null; then
    echo "⛔ [lockfile-guard] $lockfile が .gitignore で除外されています — 再現可能なビルドのためコミットが必要です"
    FAIL=true
  fi
done

if [ "$FAIL" = true ]; then
  exit 2
fi

exit 0
