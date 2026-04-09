---
name: generate-arch-tests
description: >
  design.md の Module Boundaries セクションからアーキテクチャ不変条件テストを自動生成する。
  レイヤー間の依存方向ルール（逆方向依存の禁止）をソースコードレベルで機械的に検証する
  テストコードを生成する。現在は Rust に対応。
  Triggers: 'generate arch tests', 'アーキテクチャテスト生成', '依存方向テスト', '/generate-arch-tests'.
argument-hint: "[--spec <spec-name>] [--output <path>]"
user-invokable: true
---

# アーキテクチャ不変条件テスト生成

design.md の Module Boundaries（レイヤー定義・依存方向ルール）を読み取り、
依存方向違反を機械的に検出するテストコードを自動生成する。

## 前提

- design.md に `## Module Boundaries` セクションが存在すること
- 現在の対応言語: **Rust**（`use` / `mod` 文を解析）

## 引数パース

| 引数 | デフォルト | 説明 |
|------|-----------|------|
| `--spec <spec-name>` | 省略時は最新の spec を自動検出 | Module Boundaries を読み取る design.md の spec 名 |
| `--output <path>` | `tests/architecture.rs` | 生成するテストファイルのパス |

## Step 1: Module Boundaries の読み取り

`.spec-workflow/specs/{spec-name}/design.md` から `## Module Boundaries` セクションを読み取る。

### 期待するフォーマット

design.md には以下の形式でレイヤー定義が記述されている:

```markdown
## Module Boundaries

### レイヤー定義

| Layer | Directory | Description |
|-------|-----------|-------------|
| handlers | src/handlers/ | HTTP ハンドラ層（最上位） |
| services | src/services/ | ビジネスロジック層（中間） |
| infra | src/infra/ | インフラ層（最下層・横断的関心事） |

### 依存方向ルール

| From (依存元) | Allowed Dependencies (許可) | Forbidden (禁止) |
|--------------|---------------------------|-----------------|
| handlers | services, infra | — |
| services | infra | handlers |
| infra | — | handlers, services |
```

### パース処理

1. `## Module Boundaries` 見出しを検索
2. `### レイヤー定義` テーブルからレイヤー名とディレクトリを抽出
3. `### 依存方向ルール` テーブルから各レイヤーの禁止依存先を抽出
4. パースに失敗した場合はエラーを報告し終了

## Step 2: ソースコード構造の検証

パースしたレイヤー定義に対応するディレクトリが実際に存在するか確認する:

```bash
# 各レイヤーのディレクトリ存在確認
for dir in src/handlers src/services src/infra; do
  if [ ! -d "$dir" ]; then
    echo "WARNING: Layer directory not found: $dir"
  fi
done
```

存在しないディレクトリがある場合は警告を出力するが、テスト生成は続行する（将来作成されるディレクトリを先行して保護するため）。

## Step 3: テストコード生成（Rust）

以下のテンプレートに基づいてアーキテクチャテストを生成する。

### 生成テンプレート

```rust
//! アーキテクチャ不変条件テスト
//!
//! design.md の Module Boundaries に基づき、レイヤー間の依存方向ルールを
//! ソースコードレベルで機械的に検証する。
//!
//! 自動生成: /generate-arch-tests スキル
//! 元設計: .spec-workflow/specs/{spec-name}/design.md

use std::collections::HashMap;
use std::fs;
use std::path::Path;

/// レイヤー定義
struct Layer {
    name: &'static str,
    dir: &'static str,
}

/// 禁止された依存ルール
struct ForbiddenDep {
    from_layer: &'static str,
    to_layer: &'static str,
    to_modules: &'static [&'static str],
}

// --- design.md から生成されたレイヤー定義 ---
const LAYERS: &[Layer] = &[
    {layers}
];

// --- design.md から生成された禁止依存ルール ---
const FORBIDDEN_DEPS: &[ForbiddenDep] = &[
    {forbidden_deps}
];

/// 指定ディレクトリ配下の .rs ファイルを再帰的に収集する
fn collect_rs_files(dir: &Path) -> Vec<std::path::PathBuf> {
    let mut files = Vec::new();
    if !dir.exists() {
        return files;
    }
    for entry in fs::read_dir(dir).unwrap().flatten() {
        let path = entry.path();
        if path.is_dir() {
            files.extend(collect_rs_files(&path));
        } else if path.extension().is_some_and(|e| e == "rs") {
            files.push(path);
        }
    }
    files
}

/// ソースファイルから use / mod 文を抽出し、依存先モジュール名を返す
fn extract_dependencies(path: &Path) -> Vec<String> {
    let content = fs::read_to_string(path).unwrap_or_default();
    let mut deps = Vec::new();
    for line in content.lines() {
        let trimmed = line.trim();
        // use crate::module_name::... の形式を検出
        if let Some(rest) = trimmed.strip_prefix("use crate::") {
            if let Some(module) = rest.split("::").next() {
                deps.push(module.to_string());
            }
        }
        // mod module_name; の外部モジュール参照は除外（同一レイヤー内の構造定義）
    }
    deps
}

/// レイヤー名からディレクトリのトップレベルモジュール名を取得するマップを構築
/// extract_dependencies が use crate::<first_segment>::... の先頭セグメントのみを
/// 依存先として抽出するため、ここでも先頭セグメントのみを登録する。
fn build_layer_modules_map() -> HashMap<&'static str, Vec<&'static str>> {
    let mut map = HashMap::new();
    for layer in LAYERS {
        // ディレクトリパスからトップレベルモジュール名を推定
        // src/handlers/ → "handlers", src/services/directory_scanner → "services"
        if let Some(module) = layer.dir
            .trim_start_matches("src/")
            .trim_end_matches('/')
            .split('/')
            .next()
            .filter(|s| !s.is_empty())
        {
            map.entry(layer.name)
                .or_insert_with(Vec::new)
                .push(module);
        }
    }
    map
}

{test_functions}
```

### テスト関数の生成ルール

各禁止依存ルール（`FORBIDDEN_DEPS` の各エントリ）に対して、1つのテスト関数を生成する:

```rust
#[test]
fn {from_layer}_must_not_depend_on_{to_layer}() {
    let from_dir = Path::new("{from_dir}");
    if !from_dir.exists() {
        // レイヤーディレクトリが未作成の場合はスキップ
        return;
    }

    let forbidden_modules: &[&str] = &[{to_modules}];
    let files = collect_rs_files(from_dir);
    let mut violations = Vec::new();

    for file in &files {
        let deps = extract_dependencies(file);
        for dep in &deps {
            if forbidden_modules.contains(&dep.as_str()) {
                violations.push(format!(
                    "  {} → {} ({})",
                    file.display(),
                    dep,
                    "{from_layer} → {to_layer} は禁止"
                ));
            }
        }
    }

    assert!(
        violations.is_empty(),
        "アーキテクチャ違反を検出:\n{}\n\n\
         Fix: `use crate::` の import を削除するか、\
         design.md Module Boundaries の依存方向ルールを見直してください。",
        violations.join("\n")
    );
}
```

### 追加テスト: 循環依存検出（P2-02）

レイヤー間の循環依存（A→B かつ B→A）を検出するテストを生成する。依存方向ルールが正しく定義されていれば循環は発生しないが、ファイルレベルの `use crate::` を直接走査して実際の循環を検出する:

```rust
#[test]
fn no_circular_dependencies_between_layers() {
    // 各レイヤーの実際の依存先レイヤーを収集
    let mut layer_deps: HashMap<&str, Vec<&str>> = HashMap::new();

    for layer in LAYERS {
        let dir = Path::new(layer.dir);
        if !dir.exists() {
            continue;
        }
        let files = collect_rs_files(dir);
        let mut deps_set = std::collections::HashSet::new();
        for file in &files {
            for dep in extract_dependencies(file) {
                // 依存先モジュールがどのレイヤーに属するか特定
                for other in LAYERS {
                    if other.name == layer.name {
                        continue;
                    }
                    let other_modules: Vec<&str> = other.dir
                        .trim_start_matches("src/")
                        .trim_end_matches('/')
                        .split('/')
                        .collect();
                    if other_modules.contains(&dep.as_str()) {
                        deps_set.insert(other.name);
                    }
                }
            }
        }
        layer_deps.insert(layer.name, deps_set.into_iter().collect());
    }

    // 循環検出: A→B かつ B→A のペアを検索
    let mut cycles = Vec::new();
    let layer_names: Vec<&str> = LAYERS.iter().map(|l| l.name).collect();
    for (i, &a) in layer_names.iter().enumerate() {
        for &b in &layer_names[i + 1..] {
            let a_deps_b = layer_deps.get(a).is_some_and(|d| d.contains(&b));
            let b_deps_a = layer_deps.get(b).is_some_and(|d| d.contains(&a));
            if a_deps_b && b_deps_a {
                cycles.push(format!("  {} ↔ {} (双方向依存)", a, b));
            }
        }
    }

    assert!(
        cycles.is_empty(),
        "循環依存を検出:\n{}",
        cycles.join("\n")
    );
}
```

### 追加テスト: レイヤー網羅性チェック

全ての `src/` 直下モジュールがいずれかのレイヤーに属していることを検証するテストも生成する:

```rust
#[test]
fn all_modules_belong_to_a_layer() {
    let known_modules: &[&str] = &[{all_layer_modules}];
    let exceptions: &[&str] = &["lib", "main", "error"];

    let src = Path::new("src");
    if !src.exists() {
        return;
    }

    let mut orphans = Vec::new();
    for entry in fs::read_dir(src).unwrap().flatten() {
        let name = entry.file_name().to_string_lossy().to_string();
        let module_name = name.trim_end_matches(".rs");
        if !known_modules.contains(&module_name) && !exceptions.contains(&module_name) {
            orphans.push(module_name.to_string());
        }
    }

    assert!(
        orphans.is_empty(),
        "レイヤー未定義のモジュールを検出（design.md Module Boundaries への追加が必要）:\n  {}",
        orphans.join(", ")
    );
}
```

### 追加テスト: 共有型配置検証 (P5-06)

design.md の `### 共有型定義` テーブルが存在する場合、共有型ファイルが指定された配置先ディレクトリに存在するか検証するテストを生成する:

```rust
#[test]
fn shared_types_exist_in_designated_directories() {
    // design.md の共有型定義テーブルから配置先を取得
    let shared_type_dirs: &[&str] = &[{shared_type_directories}];

    for dir in shared_type_dirs {
        let path = Path::new(dir);
        assert!(
            path.exists(),
            "共有型ディレクトリが見つかりません（design.md 共有型定義で指定）: {}",
            dir
        );
    }
}
```

このテストは `### 共有型定義` テーブルが design.md に存在する場合のみ生成する。テーブルが存在しない場合はスキップする。

## Step 4: ファイル出力

1. `--output` パス（デフォルト: `tests/architecture.rs`）に書き出し
2. `tests/` ディレクトリが存在しない場合は作成
3. 既存ファイルがある場合は差分を表示し、上書き前にユーザーに確認
4. 生成ファイルの先頭にヘッダコメントを付与:
   ```rust
   //! 自動生成: /generate-arch-tests (do not edit manually)
   //! 元設計: .spec-workflow/specs/{spec-name}/design.md — Module Boundaries
   //! 再生成: /generate-arch-tests --spec {spec-name}
   ```

## Step 5: 動作確認

生成したテストが正常にコンパイル・実行できるか確認する:

```bash
cargo test --test architecture --quiet
```

- **PASS**: テストが通過（アーキテクチャ違反なし）→ 完了
- **FAIL (コンパイルエラー)**: 生成コードに問題あり → 修正して再出力
- **FAIL (テスト失敗)**: 既存コードにアーキテクチャ違反あり → 違反箇所をユーザーに報告

## Step 6: 完了レポート

```
## /generate-arch-tests 完了レポート

- Spec: {spec-name}
- 出力先: {output-path}
- レイヤー数: {N}
- 禁止依存ルール数: {M}
- 生成テスト関数数: {K} (依存方向 {M} + 循環依存 1 + 網羅性 1)
- 総アサーション数: {A} (目標: 20以上)
- テスト実行結果: {PASS / FAIL}
- アーキテクチャ違反: {0件 / N件（詳細は上記）}

> **P2-08 基準**: アーキテクチャ不変条件テストには 20 個以上のアサーションが必要。レイヤー数が少なくアサーションが不足する場合は、以下の追加テストを検討すること:
> - 命名規約テスト（ハンドラは `_handler` サフィックス等）
> - エクスポート規則テスト（内部モジュールが `pub` で公開されていないか）
> - ファイル配置テスト（テストファイルが `tests/` 配下にあるか）
```

## 将来拡張

現在は Rust のみ対応。以下の言語サポートを将来的に追加予定:

| 言語 | 解析対象 | テスト形式 |
|------|---------|-----------|
| TypeScript | `import` / `require` 文 | Jest / Vitest テスト |
| Go | `import` ブロック | `_test.go` ファイル |

言語追加時は Step 3 のテンプレートを言語別に分岐させる。フレームワーク検出（`Cargo.toml` / `package.json`）は `/generate-api-docs` と同じロジックを再利用する。
