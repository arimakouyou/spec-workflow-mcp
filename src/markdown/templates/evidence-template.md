---
ev_id: EV-{category}-{NNN}
category: {category}
task_type: {task_type}
spec_name: {spec-name}
topic: {short description of the one topic this evidence covers}
sources:
  - path: {path/to/file.ext}
    lines: {Lstart-Lend}
  - path: {path/to/another.ext}
    lines: {Lstart-Lend}
related_refs: []
---

# {Topic title}

> 1 エビデンス = 1 論点。ファイル単位ではなくトピック単位で粒度を切る。
> 目安は 50〜150 行。これより大きくなる場合は別トピックに分割する。

## 要約 (What this evidence establishes)

{1〜3 文で、このエビデンスが仕様書のどの判断の根拠になるかを述べる。}

## 根拠となる既存コード

### {Source A — `path/to/file.ext:Lstart-Lend`}

```{lang}
{必要最小限のコード引用。全文コピペではなく判断に必要な部分だけ}
```

**読み取れる振る舞い / 契約**:
- {箇条書きで、このコード片が示している現行仕様・前提・制約}

### {Source B — `path/to/another.ext:Lstart-Lend`}

```{lang}
{...}
```

**読み取れる振る舞い / 契約**:
- {...}

## 仕様書への影響

- **紐づく REQ / DES / テスト ID**: {REQ-1.2, DES-3, UT-2.1, ...}
- **この根拠が支える判断**: {例: "既存ハンドラはトークン検証後に DB トランザクションを開くため、新規 API もこの順序に従う"}

## 未解決・要追加調査

- [ ] {調査が足りていない論点があれば列挙。なければこのセクションごと削除}
