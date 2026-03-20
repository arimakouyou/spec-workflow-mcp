# Spec Workflow Enforcement

spec-workflow のスキルを正しく使うための強制ルール。

## ⛔ tasks.md を読んだ後の直接実装禁止

`.spec-workflow/specs/*/tasks.md` を Read した場合、**いかなる理由があっても直接コードを書き始めてはならない**。

- タスクの実装は **必ず `/spec-implement` スキル経由** で行う
- tasks.md の内容を確認しただけでも、続けて実装を始めることは禁止
- ユーザーが「このタスクを実装して」と言っても、スキルを使わずに直接書くことは禁止

**正しい対応:**
1. tasks.md を読んだ後、ユーザーに「`/spec-implement` を実行してください」と案内する
2. または自分で `/spec-implement` スキルを起動する

## ⛔ spec-implement スキルの外でのコード実装禁止

`.spec-workflow/specs/` 配下の任意のファイル（requirements.md / design.md / tasks.md）の内容に基づいてコードを書く場合は、`spec-implement` スキルを経由すること。

スキルを経由せずに「このタスクに相当するコードを書く」行為は禁止。

## spec-workflow ファイルの Read 後の義務

| 読んだファイル | 次にすべきこと |
|-------------|------------|
| `requirements.md` のみ | `/spec-design` スキルを案内 |
| `requirements.md` + `design.md` のみ | `/spec-tasks` スキルを案内 |
| `tasks.md` が存在 | `/spec-implement` スキルを案内 |

## なぜこのルールが必要か

spec-implement スキルは以下のエージェントチェーンを強制する:
- `parallel-worker` → TDD 実装
- `unit-test-engineer` → テスト品質検証
- `review-worker` → レビュー + コミット

このチェーンを省略した直接実装は TDD 品質保証を完全に迂回するため、絶対に許可されない。
