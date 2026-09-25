---
spec: todo-api
doc: request-spec
task_type: greenfield
---

# Request: Todo API

## Overview

自分のツールから Todo を登録し、登録順に一覧できる HTTP API を新しく作る。入力の検証は API の境界で行い、不正な入力は理由が分かるエラーで拒否する。

## Requests

### RQ-1: Todo を登録する
- Actor: 個人の開発者
- Goal: タイトルを送って Todo を 1 件登録する
- Flow:
  - タイトルを送る
  - 登録された Todo を受け取る
- Exceptions:
  - タイトルが空、または長すぎる

### RQ-2: Todo を一覧する
- Actor: 個人の開発者
- Goal: 登録済みの Todo を登録順に取得する
- Flow:
  - 一覧を要求する
  - 登録順の Todo の列を受け取る

### RQ-3: Todo を完了にする
- Actor: 個人の開発者
- Goal: 登録済みの Todo を完了状態にする
- Flow:
  - Todo を指定して完了を要求する

## Out of Scope

- 永続化(プロセス終了で消えてよい)
