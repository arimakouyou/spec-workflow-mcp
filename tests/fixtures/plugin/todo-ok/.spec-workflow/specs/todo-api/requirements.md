---
spec: todo-api
doc: requirements
---

# Requirements: Todo API

## Requirements

### REQ-1: Todo の登録
- Source: RQ-1
- Story: As a 個人の開発者, I want タイトルを送って Todo を登録する, so that 後で一覧できる
- Evidence: EV-lib-001
- REQ-1.1: WHEN 前後の空白を除いて 1〜100 文字のタイトルが送られた THEN the system SHALL 空白を除いたタイトルで未完了の Todo を登録し、登録した Todo を返す
- REQ-1.2: IF 前後の空白を除いたタイトルが空である THEN the system SHALL 検証エラーとして拒否する
- REQ-1.3: IF 前後の空白を除いたタイトルが 100 文字を超える THEN the system SHALL 上限の文字数を示す検証エラーとして拒否する
- REQ-1.4: IF 要求本文に title 以外の項目が含まれる THEN the system SHALL 要求を拒否する

### REQ-2: Todo の一覧
- Source: RQ-2
- Story: As a 個人の開発者, I want 登録済みの Todo を取得する, so that 残作業を確認できる
- REQ-2.1: WHEN 一覧が要求された THEN the system SHALL 登録済みのすべての Todo を登録順に返す

## Non-Functional

### NFR-1: 起動確認
- Category: reliability
- Criterion: 起動後に稼働確認用のエンドポイントが 200 を返す
- Rationale: デプロイ後の疎通確認を自動化するため

## Journeys

### JRN-1: 登録して一覧で確かめる
- Covers: REQ-1, REQ-2
- Steps:
  - Todo を 2 件登録する
  - 一覧を取得し、登録した 2 件が登録順に並んでいることを確かめる

## Out of Scope

- RQ-3: 完了操作は次の spec で扱う
