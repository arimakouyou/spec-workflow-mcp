---
always_apply: true
---

# Spec Dependency Graph

仕様書間の依存関係を宣言的に管理する語彙。requirements.md → design.md → test-design.md → tasks.md の上流→下流方向のトレーサビリティを機械可読にする。

`/spec-impact-analyze`（F: 影響分析）と `/spec-verify`（I: 整合性検証）の入力となる。既存のタスク層メタデータ（`_Requirements:` / `_DependsOn:` / `_Leverage:`）は維持し、これと直交する**仕様書ファイル間**の依存を宣言する。

## SD1: Identifier System

仕様書内のセクションを機械可読に参照するための ID 規則。既存テンプレートの naming を尊重した明文化。

| ファイル | ID 形式 | 例 | 既存規則との関係 |
|---------|---------|-----|----------------|
| `requirements.md` | `REQ-N.M` | `REQ-1.1`, `REQ-2.3` | Requirement N の Acceptance Criteria M に対応。既存の `_Requirements:` の値 `1.1`, `2.1` と同じ座標系 |
| `design.md`（Components and Interfaces） | `DES-N` | `DES-1`, `DES-2` | 既存の `### Component N` を DES-N として明示化。見出しを `### DES-1: ComponentName` の形で書く |
| `design.md`（Data Models） | `MOD-N` | `MOD-1`, `MOD-2` | 既存の `### Model N` を MOD-N として明示化（optional） |
| `design.md`（API / Endpoint） | `API-N` | `API-1` | API 定義がある場合の識別子（optional） |
| `test-design.md`（Unit Test） | `UT-N.M` | `UT-1.1` | 既存規則のまま |
| `test-design.md`（Integration Test） | `IT-N` | `IT-1` | 既存規則のまま |
| `test-design.md`（E2E Test） | `E2E-N` | `E2E-1` | 既存規則のまま |
| `tasks.md`（Task） | `N.M` | `1.1`, `2.3` | 既存規則のまま（task-parser.ts がパース） |

- `REQ-` / `DES-` / `MOD-` / `API-` のプレフィックスは `requirements.md` / `design.md` 内で ID を見出しに付与することで明示する（例: `### REQ-1.1: User Login Validation`）
- 既存 spec に ID を後付けする場合は Minor 変更扱いとし、参照する下流がなければ付与しなくてもよい（SD3 参照）
- UT-N.M の M は N の下位番号（Component N のテストケース M）であり、REQ-N.M の M（Acceptance Criteria M）とは**独立**

## SD2: Frontmatter Schema

各仕様書ファイルの先頭に YAML frontmatter を置く。

```yaml
---
spec_id: {spec-name}              # kebab-case, .spec-workflow/specs/ 配下のディレクトリ名と一致
phase: requirements | design | test-design | tasks
version: 1                         # optional, 大きな改訂時に +1（F のキャッシュ判定に利用）
depends_on:                        # 上流仕様書への参照。requirements.md は空配列
  - file: requirements.md
    refs: [REQ-1.1, REQ-1.2, REQ-2.1]
---
```

### 各 phase の depends_on

| phase | 典型的な depends_on |
|-------|---------------------|
| `requirements` | `[]`（最上流） |
| `design` | `requirements.md` の REQ- のうち本 design が実装するもの |
| `test-design` | `requirements.md` の REQ-（検証対象）+ `design.md` の DES-（テスト対象コンポーネント） |
| `tasks` | `design.md` の DES-（実装対象）+ `test-design.md` の UT-/IT-/E2E-（満たすテスト） |

### refs の書き方

- `refs` は文字列配列。**上流仕様書に実在する ID** のみ許可（SD4 で検証）
- 同じ上流ファイルを複数行で書かない（`file: requirements.md` は一意）
- refs が空配列なら `depends_on` の要素自体を書かない（余分な宣言を避ける）

## SD3: Backward Compatibility (Opt-in for Legacy Specs)

frontmatter は**新規 spec では必須**、**既存 spec ではオプトイン**。

- `/spec-requirements`, `/spec-design`, `/spec-test-design`, `/spec-tasks` が生成する**新規仕様書**は frontmatter 必須
- 既存仕様書（frontmatter を持たないもの）は `phase: legacy` として扱われる
- `/spec-impact-analyze` と `/spec-verify` は frontmatter が無い仕様書に対して「依存情報なし」と報告し、静的解析をスキップする（`not_available` ステータス）。エラーにはしない
- 既存 spec を frontmatter 対応に昇格したい場合は、手動で frontmatter を追加すればよい（既存の本文改変は不要）

## SD4: Reference Integrity

`depends_on.refs` に書かれた ID は、参照先ファイル内に実在していなければならない。

- `/spec-verify` はこれを検証する
- 実在しない ID への参照は **`fail` で報告**（警告ではなく blocking）
- 参照先ファイルが frontmatter を持たない legacy の場合は、本文中の ID 明記（例: `### REQ-1.1:`）で検出する

## SD5: No Cycles

`depends_on` で循環依存を作ってはならない（requirements → design → requirements のような経路）。phase の順序 `requirements → design → test-design → tasks` を逆行する参照は禁止。

- `/spec-verify` は DAG 性を検証する
- 循環が検出された場合は blocking（実装開始を止める）

## SD6: Coexistence with Task-level Metadata

**タスク層**（tasks.md 内の個別タスク行）のメタデータは既存規則を維持：

| メタデータ | 意味 | 例 |
|-----------|------|-----|
| `_Requirements:` | このタスクが満たす REQ-N.M | `_Requirements: 1.1, 2.1` |
| `_DependsOn:` | このタスクが先行する他のタスク（task-id） | `_DependsOn: 1.1` |
| `_Leverage:` | このタスクが再利用するファイル | `_Leverage: src/types/base.ts` |
| `_PhaseReview:` | Phase Review タスクのマーカー | `_PhaseReview: true` |
| `_TDDSkip:` | TDD をスキップするマーカー | `_TDDSkip: true` |
| `_TestFocus:` | テスト重点領域の自由記述 | `_TestFocus: boundary values` |

**仕様書間**の `depends_on` frontmatter は tasks.md 全体が依存する design.md / test-design.md の DES-/UT- を宣言する。タスク個別の REQ 紐付けは従来通り `_Requirements:` で行う（二重管理ではなく、**粒度の異なる直交情報**）。

## SD7: Change Propagation Semantics

`depends_on` が宣言された時、上流の変更がどのように下流へ影響するかの意味論を定める（`/spec-impact-analyze` の判定基準）。

| 変更の種類 | 下流への影響 | Impact Analysis 分類 |
|-----------|-------------|--------------------|
| 上流 ID の**新規追加** | 下流に新しい参照候補が増えるだけ | `gray`（参考） |
| 上流 ID の**削除** | 下流の `refs` から参照できなくなる — 削除が必要 | `amber`（確認要、参照ありの場合） |
| 上流 ID の**条件・意図の実質変更**（Acceptance Criteria の書き換え等） | 下流の設計・テスト・実装が前提を失う | `amber`（確認要、参照ありの場合） |
| 上流 ID の**表現揺れ・typo 修正**（機能条件は変わらない） | 下流は不変 | `green`（自動反映可） |
| 上流 ID に**参照していない変更** | 下流は無関係 | `gray`（参考） |

「実質変更」と「表現揺れ」の判別は現時点では LLM 判定に委ねる（`/spec-impact-analyze` が判定）。将来的に機械的な差分検出（キーワード抽出など）に寄せる可能性があるが、現段階ではヒューリスティックを固定しない。

## Related Skills

この依存グラフ定義を入力とする独立スキル群（いずれも read-only、ワークフローを gate しない）:

| Skill | 役割 |
|-------|------|
| `/spec-impact-analyze` | 上流（requirements.md 等）の変更差分を入力に、下流ファイルへの波及を SD7 の green/amber/gray で分類して報告 |
| `/spec-verify` | SD1-SD7 を使い、frontmatter 存在・refs 整合性（SD4）・DAG 性（SD5）・REQ→テスト→タスクのカバレッジを検証 |
| `/spec-graph` | frontmatter から mermaid 依存グラフを生成（file level / id level）。視覚的な俯瞰に使う |

これらは Harness-as-Code アプローチの 3 側面（変更伝搬 / 整合性検証 / 可視化）に相当し、ルールを直接触らずに価値を引き出す補助スキルとして追加された。
