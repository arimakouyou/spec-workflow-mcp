---
ev_id: EV-lib-001
category: lib
spec: todo-api
topic: axum の Json 抽出子が本文の不一致を拒否するときの状態コード
sources:
  - crate:axum@0.8:axum::extract::rejection::JsonRejection
---

# axum の Json 抽出子による拒否

## 要約

要求本文が要求型に合わないとき、axum はハンドラを呼ぶ前に拒否応答を返す。design の DEP-1 Contract と IT-4 の根拠。

## 根拠

- `JsonDataError`: 本文は構文として正しい JSON だが、要求型に変換できない(未知の項目を `deny_unknown_fields` で拒否した場合を含む)。状態コードは 422 Unprocessable Entity。
- `JsonSyntaxError`: 本文が JSON として不正。状態コードは 400 Bad Request。
- `MissingJsonContentType`: Content-Type が `application/json` でない。状態コードは 415 Unsupported Media Type。
