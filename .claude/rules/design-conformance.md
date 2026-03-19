---
always_apply: true
---

# Design Conformance

承認済み design.md からの逸脱を防止するルール。

## 原則

**承認済みの設計は実装フェーズで変更しない。** design.md で定義された DB スキーマ、API 設計、データモデルは実装の「契約」であり、実装者が独断で変更してはならない。

## 実装時の禁止事項

### DB Schema
- design.md に定義されていないテーブル・カラムを追加しない
- 定義済みのカラム型・制約を変更しない
- インデックスの追加・削除を勝手に行わない
- **FK の ON DELETE 動作は design.md の定義通りに実装する**（CASCADE / RESTRICT / SET NULL を勝手に変更・追加しない）
- NULL 許容/NOT NULL は design.md の定義に従う

### API
- design.md に定義されていないエンドポイントを追加しない
- 定義済みの HTTP メソッド・パス・ステータスコードを変更しない
- リクエスト/レスポンスのフィールドを追加・削除・型変更しない
- エラーレスポンスのフォーマットを変更しない
- **エラーコード**: design.md の Error Handling セクションに定義されたエラーコードのみ使用する。実装中に未定義のエラーケースが発生した場合は以下の順で対応する:
  1. design.md に定義済みのエラーコードで代替できないか検討する（例: `Conflict` が未定義なら `BadRequest("duplicate key")` で代替）
  2. 代替不可能な場合は escalate してユーザーに確認する

### Data Model
- design.md に定義されていないフィールドを Model / DTO に追加しない
- DTO ↔ API 定義の不一致を作らない

## 設計変更が必要な場合

実装中に設計の問題を発見した場合:

1. 実装を中断する
2. 問題点と変更提案を明確に記述する
3. ユーザーにエスカレーションする（review-worker の `review_action: escalate`）

ユーザーの判断により以下のいずれかに分岐する:

### A. design.md の範囲内で実装を調整する（軽微な場合）

- `_Prompt` の Restrictions に調整内容を追記し、parallel-worker に rework で差し戻す
- design.md は変更しない

### B. design.md の変更が必要（根本的な問題の場合）— Phase Reset

**design.md を変更する場合、それまでの実装は全て破棄し Phase 2 からやり直す。** 部分的な修正は許可しない。

Phase Reset 手順:
1. **Phase 4 の中断**: 進行中のタスク（`[-]`）を `[ ]` に戻す
2. **実装コードの破棄**: Phase 4 で実装・コミットされたコードを `git revert` で取り消す
3. **tasks.md の削除**: `.spec-workflow/specs/{spec-name}/tasks.md` を削除する（Phase 3 の成果物）
4. **design.md の修正**: Phase 2 に戻り design.md を修正する
5. **再レビュー**: spec-review (check) で design.md を再検証する
6. **再承認**: Approval Workflow で design.md の再承認を取得する
7. **Phase 3 再実行**: `/spec-tasks` で tasks.md を再作成する
8. **Phase 4 再実行**: `/spec-implement` で実装を最初から再開する

**注意:** Phase Reset は大きなコストを伴う。これを避けるために Phase 2 の設計レビュー（DB Schema, API Design, Data Model, Error Handling）を徹底すること。

## review-worker での検証

review-worker はコードレビュー時に `design.md` を読み込み、以下を照合する:

- 実装された DB マイグレーションが design.md のスキーマ定義と一致しているか
- 実装されたエンドポイントのパス・メソッド・リクエスト/レスポンス型が design.md の API 定義と一致しているか
- 実装された Model / DTO のフィールドが design.md のデータモデル定義と一致しているか
- design.md に定義されていない追加物がないか
