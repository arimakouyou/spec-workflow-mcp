---
always_apply: true
---

# Failure Taxonomy

横断的な失敗分類語彙。`parallel-worker` / `review-worker` / `wave-harness-worker` / `spec-impl-test-run` 等のリトライ・差し戻し・DIVERGENT 判定で**共通キー**として使う。

目的は以下の 3 点：

1. 各エージェントが独自に用いていた自由記述の `last_error` に加え、**機械可読な分類タグ** `failure_category` を必須化する
2. `diagnostic-reasoning.md` DR6（DIVERGENT Strategy）の閾値判定を「同一カテゴリの連続失敗」で行うための語彙を提供する
3. review-worker の Severity Classification（Minor / Moderate / Critical）と失敗分類の対応を明示し、差し戻し判定を一貫させる

## FC1: Category Set

主要カテゴリは 4 種類。それぞれにサブカテゴリを定義する。

| Category | When to use | Sub-categories |
|----------|-------------|---------------|
| `compile_error` | ソースコード・テストコードがビルド／コンパイルを通らない。実行以前の失敗 | `syntax_error`, `type_error`, `unresolved_import`, `missing_symbol`, `borrow_check_error`, `trait_bound_unsatisfied` |
| `test_failure` | ビルドは成功するが、テスト実行で失敗 | `assertion_failure`, `panic`, `timeout`, `unexpected_pass`（RED 期待のテストが PASS した場合）, `flaky` |
| `quality_check_failure` | 品質ゲートでの失敗 | `format_violation`（rustfmt / dotnet format）, `lint_violation`（clippy / Roslyn）, `dependency_vulnerability`（cargo audit / dotnet list package --vulnerable）, `mutation_survived`（cargo-mutants / Stryker.NET）, `wasm_build_failure`（cargo leptos build）, `trim_aot_incompatibility`（dotnet publish -p:PublishTrimmed=true） |
| `spec_mismatch` | 実装と仕様書（requirements.md / design.md / tasks.md の `_Prompt`）との乖離 | `design_conformance_violation`（review カテゴリ F）, `requirement_missing`（D）, `restriction_violated`（D）, `api_contract_mismatch`（G）, `test_design_missing`（E） |

**Escalation-only category（DIVERGENT のカウント対象外）**:

- `unknown`: 他のどの分類にも当てはまらない場合**のみ**使用する。2 回目以降の attempt で `unknown` を再利用してはならない（FC6 で明示的に禁止）

## FC2: Required Reporting Fields

以下の箇所では `failure_category` を**必須フィールド**として含める（`failure_subcategory` は optional、省略時は空文字列または未指定）。

| 記述場所 | 記述形式 |
|---------|---------|
| `diagnosis.md` の DR2 attempt エントリ | 次の 1 行を追加（FC4 参照）: `- **Failure category**: {category} / {subcategory}` |
| `parallel-worker` の `retry_exhausted` レポート | `- failure_category: {category}` / `- failure_subcategory: {subcategory}`（optional） |
| `parallel-worker` / `wave-harness-worker` の completion report の `diagnosis` オブジェクト | `failure_category: {category}`（`root_cause` / `responsible_files` / `approach` と並置） |
| `review-worker` の `findings` エントリ | `failure_category: {category}` / `failure_subcategory: {subcategory}`（既存の `category: A|B|C|D|E|E2|F|G` とは別。両方記載する） |
| `spec-impl-test-run` の Output Format の Verdict | `- **Failure Category**: {category}` / `- **Failure Subcategory**: {subcategory}`（fail 時のみ） |
| `spec-implement` の `diagnostic_history` 累積テンプレート | `- **Failure category**: {category}` / `{subcategory}` |

`failure_category` が得られないレガシー経路では `(not reported)` と記録するが、その次の attempt では必ず具体化する。

## FC3: Severity Mapping (with review-worker)

`review-worker.md` の Severity Classification（Minor / Moderate / Critical）との対応。**review-worker が findings を生成するとき**にこの表を参照し、`failure_category` / `failure_subcategory` と `severity` を矛盾なく付与する。

| failure_category | failure_subcategory | review-worker category | severity | 備考 |
|------------------|---------------------|------------------------|----------|------|
| `compile_error` | (any) | — | N/A | review 到達前に `parallel-worker` が解消する。万一 review で検出された場合は Moderate (B) |
| `test_failure` | (any) | E | Moderate | send back |
| `quality_check_failure` | `format_violation` | A | Minor | review-worker が auto-fix |
| `quality_check_failure` | `lint_violation` | A / B | Minor / Moderate | 警告レベル依存。clippy `-D warnings` 相当は Moderate |
| `quality_check_failure` | `dependency_vulnerability` | C | Critical | blocking（コミット不可） |
| `quality_check_failure` | `mutation_survived` | E | Moderate | テスト不足として send back |
| `quality_check_failure` | `wasm_build_failure` / `trim_aot_incompatibility` | B | Moderate | |
| `spec_mismatch` | `design_conformance_violation` | F | Critical | escalate to user |
| `spec_mismatch` | `requirement_missing` / `restriction_violated` | D | Critical | escalate to user |
| `spec_mismatch` | `api_contract_mismatch` | G | Minor | `/generate-api-docs` 推奨として報告 |
| `spec_mismatch` | `test_design_missing` | E | Moderate | send back |

Severity と action の対応（`review-worker.md` 既存ルールの再掲）:

- **Minor** → auto-fix or advisory
- **Moderate** → send back to parallel-worker（最大 3 rework）
- **Critical** → escalate to user

### 外部 severity スケールとの対応（正本）

`review-worker.md` findings / log-implementation 等の各所で使われる Minor / Moderate / Critical を、外部の一般的 severity 語彙と対応付ける。**本表が正本（SSoT）**で、他のドキュメント（例: `review-worker.md` の severity 対応表）は本表の再掲として扱う。

| FC3（本書） | 一般的な外部スケール | CVSS 相当 |
|-------------|---------------------|----------|
| Minor | low | informational / low |
| Moderate | medium | medium |
| Critical | high / critical | high / critical |

findings を emit する際は Minor / Moderate / Critical のラベルを使い、Severity Classification 表 / FC3 表 / findings 出力のすべてで語彙を揃える。外部ツール（`cargo audit` / `npm audit` / GitHub Advisory 等）の出力を取り込む場合は、本表を使って FC3 語彙に正規化する。

## FC4: Integration with DR2 (diagnostic-reasoning.md)

`diagnostic-reasoning.md` DR2 の attempt エントリに `Failure category` 行を追加する。**書き込みタイミングは DR1 の "write before fix"** と同じ（Attempt エントリ本体と同時に、`Result` 行より前に書き切る）。

```markdown
### Attempt {N}/{max}
- **Root cause**: {specific analysis}
- **Responsible**: {file:line}
- **Expected behavior**: {per design docs / test spec}
- **Approach**: {what you will do}
- **Failure category**: `{FC1 category}` / `{FC1 subcategory}`
- **Result**: {PASS or FAIL — error summary}
```

- `Root cause` / `Approach` と矛盾しないこと（例: `Root cause` が「テストが通らない」なのに `Failure category: compile_error` は不整合）
- `failure_category` は attempt を書き始める時点で決定する（原因調査の一環）。`Result` 確定後に事後的に書き足すのは不可
- 以前の attempt と**主要カテゴリ**が連続した場合は FC5 の DIVERGENT 判定対象

## FC5: DIVERGENT Trigger Condition

`diagnostic-reasoning.md` DR6 の閾値判定は `failure_category`（**主要カテゴリのみ**、サブカテゴリは無視）で行う。

- 同一 phase（`## GREEN Phase` / `## Quality Checks` / `## Rework Cycle`）内で、直近 **2 回連続** で同じ `failure_category` が `Result: FAIL` として記録された場合、次の attempt は DR6 DIVERGENT モードで実行
- `failure_subcategory` が違っても主要カテゴリが同じならカウントされる（例: `test_failure / assertion_failure` → `test_failure / panic` は「同じ mechanism」として扱う）
- 主要カテゴリが変わった場合はカウンタをリセット（例: `compile_error` → `test_failure`）
- phase をまたいだ場合もカウンタをリセット（GREEN Phase の test_failure と Quality Checks の test_failure は別カウント）

## FC6: Prohibited Patterns

以下は分類の信頼性を損なうため禁止する。review-worker は findings のレビュー時にこれらを検出した場合、rework 差し戻しの根拠とする。

1. **`unknown` の連続使用**: 2 回目以降の attempt で `unknown` を再利用してはならない。必ず具体的な分類に落とし込む
2. **`failure_category` の未記載**: リトライ・差し戻し・`diagnosis.md` エントリで `failure_category` が省略されている場合、orchestrator は `(not reported)` と記録した上で警告ログを出す。次の attempt では必ず記載する
3. **複数カテゴリの並記**: 1 つの attempt につき 1 カテゴリ。本当に複合的な失敗であれば、**最も本質的な原因**（fix の起点になるもの）を選ぶ
4. **Severity と category の矛盾**: review-worker の findings で、FC3 の対応表と矛盾する severity を付けてはならない（例: `quality_check_failure / format_violation` に `Critical` を付けるなど）
5. **`Approach` と `failure_category` の不整合**: `Approach` が解消しようとしている失敗と `failure_category` は同じ原因を指していなければならない。fix しない側のカテゴリを書いてはならない
