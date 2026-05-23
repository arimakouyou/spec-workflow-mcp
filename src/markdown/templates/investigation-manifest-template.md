---
spec_name: {spec-name}
task_type: {task_type}
generated_at: {ISO8601}
status: draft   # draft | ready | failed
---

# 調査マニフェスト (Investigation Manifest)

`spec-investigate` スキルが `request-spec.md` と `task_type` をもとに生成する調査計画と結果のインデックス。
本ファイルは承認対象ではない（Phase 0.5）。ただし Step B チェックが後続フェーズで網羅性を検査する際の入力になる。

## 1. 調査スコープ

- **対象 spec**: `{spec-name}`
- **task_type**: `{task_type}`（`.claude-plugin/rules/task-types.md` TT2）
- **request-spec の要点**: {request-spec.md の「フィーチャー概要」「スコープ内」を 3 行以内で要約}

## 2. 必須 Evidence Category の充足計画

`task-types.md` TT2 で `{task_type}` に定義された必須カテゴリごとに、どの範囲をどの深度で調べるかを宣言する。`.spec-workflow/user-config/task-types.yml` による上書きがあれば反映する。

| Category | 調査対象 (glob / ディレクトリ / 既知のファイル) | 深度 | 担当 sub-agent |
|----------|-----------------------------------------|------|----------------|
| `{category-1}` | `{path}/**` | shallow / deep | Explore |
| `{category-2}` | `{path}/...` | shallow / deep | Explore |

深度ガイド:

- **shallow**: 該当ディレクトリのエントリーポイントと代表ファイル 1〜3 件を読む。周辺の一覧・命名規則・登録箇所のみ把握。
- **deep**: 分岐・状態遷移・エラー経路まで踏み込み、関連するテスト・設定・マイグレーションも辿る。

## 3. 生成された Evidence ファイル

`spec-investigate` が書き出した EV ファイルを列挙する。各 EV の `sources:` は実在するパスと行範囲を指していること。

| Category | EV ID | Topic | 主要 sources |
|----------|-------|-------|--------------|
| `{category-1}` | `EV-{category-1}-001` | {topic} | `path:Lx-Ly` |
| `{category-1}` | `EV-{category-1}-002` | {topic} | `path:Lx-Ly` |
| `{category-2}` | `EV-{category-2}-001` | {topic} | `path:Lx-Ly` |

## 4. カバレッジ結果

`spec-investigate` の末尾チェックが書き込む自己診断。

- [ ] `task_type` で必須の全カテゴリに EV が 1 件以上存在する
- [ ] 全 EV の `sources` パスが実在する（存在確認ツールで PASS）
- [ ] 1 EV = 1 トピックに分割されている（150 行超が無いこと）
- [ ] 本マニフェストの 3 節が生成実態と一致している

## 5. 既知のギャップと今後の調査タスク

次フェーズ以降で追加調査が必要な論点を列挙。`spec-requirements` や `spec-test-design` で EV を追加生成する際の入口になる。

- [ ] {gap topic 1}
- [ ] {gap topic 2}
