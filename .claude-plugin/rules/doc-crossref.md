# ドキュメント間クロスリファレンス検証

spec-workflow のドキュメント間の参照整合性を検証する。

## 検証対象

### Spec ドキュメント間の参照

| 参照元 | 参照先 | 検証内容 |
|--------|--------|---------|
| requirements.md | request-spec.md | 要件が要求仕様に基づいているか |
| design.md | requirements.md | Requirements Traceability Matrix の Requirement ID が存在するか |
| test-design.md | design.md | テスト対象コンポーネントが design.md に定義されているか |
| tasks.md | design.md | `_Requirements` フィールドの ID が requirements.md に存在するか |
| tasks.md | test-design.md | `_Prompt` の参照先が test-design.md に存在するか |

### コード ↔ ドキュメント参照

| 参照元 | 参照先 | 検証内容 |
|--------|--------|---------|
| design.md API Design | ソースコード | 定義されたエンドポイントが実装されているか |
| design.md Error Handling | ソースコード | 定義されたエラーコードが使用されているか |
| test-design.md | テストファイル | テスト仕様に対応するテストファイルが存在するか |
| docs/openapi.yaml | ソースコード | OpenAPI 定義がソースと一致しているか |

### ルールファイル間の参照

| 参照元 | 参照先 | 検証内容 |
|--------|--------|---------|
| review-worker.md | rules/*.md | 参照先ルールファイルが存在するか |
| spec-implement.md | agents/*.md | 参照先エージェントが存在するか |
| INDEX.md | rules/*.md | インデックスのファイルパスが正しいか |

## 検証コマンド

### Markdown 内部リンクの検証

```bash
# spec ドキュメント内のファイル参照を抽出して存在確認
grep -roP '\[.*?\]\((\.spec-workflow/[^)]+)\)' .spec-workflow/specs/ | while IFS=: read -r file match; do
  ref=$(echo "$match" | grep -oP '\(([^)]+)\)' | tr -d '()')
  [ ! -f "$ref" ] && echo "BROKEN: $file → $ref"
done
```

### Requirements Traceability Matrix の検証

```bash
# design.md の Requirement ID が requirements.md に存在するか
SPEC_DIR=".spec-workflow/specs/{spec-name}"
if [ -f "$SPEC_DIR/design.md" ] && [ -f "$SPEC_DIR/requirements.md" ]; then
  grep -oP 'REQ-\d+' "$SPEC_DIR/design.md" | sort -u | while read -r req_id; do
    grep -q "$req_id" "$SPEC_DIR/requirements.md" || echo "MISSING: $req_id in requirements.md"
  done
fi
```

### テスト仕様 ↔ テストファイルの検証

```bash
# test-design.md の IT-/UT- ID に対応するテストが存在するか
grep -oP '(IT|UT)-\d+' "$SPEC_DIR/test-design.md" | sort -u | while read -r test_id; do
  grep -rq "$test_id" tests/ src/ || echo "UNIMPLEMENTED: $test_id"
done
```

## ワークフロー統合

### Phase Review 時（step 3.5.2 Expert Team Review）

実装担当が以下を確認:
- tasks.md の `_Requirements` が requirements.md に存在するか
- 実装がすべての Requirement ID をカバーしているか

### 週次定期チェック（`--with-scheduled`）

定期 CI で以下を実行:
- Markdown 内部リンクの破損チェック
- Requirements Traceability Matrix の整合性チェック
- INDEX.md のファイルパス整合性チェック

### `/generate-api-docs` 実行時

- design.md API Design セクションとの差分を Step 6 で検出（既存機能）

## QC10 との関係

機械的なフォーマット検証とリンク切れ検出は `quality-checks.md` の QC10 (Documentation Lint) が担当する。
本ルールは spec-workflow 固有のセマンティック参照整合性（Requirements Traceability Matrix、テスト仕様 ↔ テストファイル対応等）を対象とする。
