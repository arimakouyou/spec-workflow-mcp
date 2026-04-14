---
name: spec-test-design
description: "Phase 3 of spec-driven development: create a test design document that defines UT/IT/E2E test specifications. Use this skill after design is approved, when the user wants to define test strategy, test specifications, or plan testing before task breakdown. Triggers on: 'create test design', 'test specification', 'define test plan for X', 'test-design for X', or any request to create a test-design.md document."
---

# Spec Test Design (Phase 3)

Create a test design document that defines **how to test** the feature. This phase follows approved design and precedes task breakdown. The document defines concrete test cases at UT/IT/E2E levels, which subsequent phases reference for test implementation and verification.

## Prerequisites Check (MANDATORY — DO NOT SKIP)

Before doing anything else, verify all prerequisite files exist:

1. Check `.spec-workflow/specs/{spec-name}/request-spec.md` exists
2. Check `.spec-workflow/specs/{spec-name}/requirements.md` exists
3. Check `.spec-workflow/specs/{spec-name}/design.md` exists

**Legacy workflow exception**: If `request-spec.md` does not exist but `requirements.md` already exists, this is a legacy spec created before Phase 0. Skip the `request-spec.md` check and proceed normally.

If `requirements.md` or `design.md` is missing — **STOP immediately.** Inform the user: "{filename} does not exist; cannot begin test design. Please run {skill-name} first." Then exit this skill.

| Missing File | Required Skill | Skip if legacy? |
|-------------|---------------|-----------------|
| request-spec.md | `/spec-request-spec` | Yes (if requirements.md exists) |
| requirements.md | `/spec-requirements` | No |
| design.md | `/spec-design` | No |

---

Design must be approved and cleaned up (Phases 1-2 complete). If not, use `/spec-design` first.

## Inputs

The same **spec name** used in previous phases (kebab-case, e.g., `user-authentication`).

## Process

### 1. Load Resources

**Template** — prefer custom, fall back to default; if neither exists, use the structure defined in this skill:
1. `.spec-workflow/user-templates/test-design-template.md` (custom)
2. `.spec-workflow/templates/test-design-template.md` (default; may not exist in all environments)
3. If both files are missing, do **not** fail; instead, construct `test-design.md` directly following the sections and guidance described below.

**Steering documents** — load if they exist:
```
.spec-workflow/steering/product.md
.spec-workflow/steering/tech.md
.spec-workflow/steering/structure.md
```

### 2. Read Approved Documents

- `.spec-workflow/specs/{spec-name}/request-spec.md`
- `.spec-workflow/specs/{spec-name}/requirements.md`
- `.spec-workflow/specs/{spec-name}/design.md`

### 3. Analyze (メインエージェント)

メインエージェントが以下を調査・決定する。サブエージェントに渡すコンテキストとなる。

#### 3.1 コンテナ・テストインフラの技術選定

プロジェクトタイプとコンテナ構成を検出し、テスト技術を選定する:

1. **コンテナ構成の確認**:
   - design.md の Container Architecture セクションを読む
   - docker-compose.yml / Dockerfile の存在確認

2. **DB テスト戦略の決定**:
   - DB 依存あり → testcontainers（デフォルト）
   - docker-compose.test.yml が既存 → それを活用
   - DB なし → 不要

3. **E2E テストランナーの決定**:
   - フロントエンドあり（HTML テンプレート、JSX/TSX、Leptos view! マクロ）→ Playwright
   - API のみ → reqwest (Rust) / supertest (Node.js)

#### 3.2 既存テストパターンの把握

コードベースを探索し、既存のテストフレームワーク・パターン・ヘルパーを把握する:

```bash
# テストファイルの構造を確認
find . -name "*test*" -o -name "*spec*" | head -20

# テストフレームワークの確認
grep -r "mockall\|rstest\|jest\|pytest\|vitest" Cargo.toml package.json 2>/dev/null

# 既存のテストヘルパー
find . -path "*/test*/*helper*" -o -path "*/test*/*fixture*" -o -path "*/test*/*util*" | head -10
```

調査結果を以下の形式でまとめ、サブエージェントへの入力とする:
```
テスト技術サマリー:
- テストフレームワーク: [vitest / jest / rstest / pytest 等]
- DB テスト戦略: [testcontainers / docker-compose.test.yml / 不要]
- E2E テストランナー: [Playwright / reqwest / supertest 等]
- 既存テストヘルパー: [ファイルパスのリスト]
- 既存テストパターン: [パターンの概要]
```

#### 3.3 テスト用ツール要件の列挙

セクション 3.1 と 3.2 の結果に基づき、テスト実行に必要なツールを Required Test Tools テーブル形式で列挙する:

1. **テストフレームワーク**（cargo test, vitest, jest 等）→ Check Command と共に Required=Yes で記録
2. **コンテナランタイム**（testcontainers 使用時）→ docker (Required=Yes)
3. **E2E テストランナー**（Playwright, Cypress 等）→ Required=Yes、Install Command 含めて記録
4. **ブラウザエンジン**（Browser E2E 時）→ chromium (Required=Yes) — **環境依存スキップ不可**
5. **DB ツール**（diesel_cli, prisma 等）→ Required=Yes
6. **ビルドキャッシュ等の最適化ツール** → Recommended

結果を以下の形式でまとめ、Step 5 で test-design.md に挿入する:
```
テスト用ツール一覧:
| Tool | Min Version | Purpose | Check Command | Install Command | Required |
|------|-------------|---------|---------------|-----------------|----------|
| ... | ... | ... | ... | ... | ... |
```

**重要**: E2E テストに必要なツール（Playwright, Chrome等）は必ず Required=Yes とする。design.md の「Excluded Test Environments」で明示的に除外されているテスト以外は、すべて実行必須。

#### 3.3.1 テストツールバージョン検証

Required Test Tools テーブルの各ツールについて、**「インストール済みバージョンの検出」** と **「最新安定版の調査」** を分けて扱うこと。`Min Version` に採用するのは、前者ではなく**後者で確認した最新安定版**である。

1. WebSearch またはレジストリ CLI で**最新安定版**を確認する
   - crates.io / npm のパッケージの場合のみレジストリ CLI を使ってよい
     - `npm view {pkg} version`
     - Rust: `cargo search {crate} --limit 1 | grep "^{crate} ="` （完全一致を確認）
   - それ以外のツール（docker, chromium 等）は WebSearch で公式リリースページを確認
   - Playwright: `npm view playwright version` で最新安定版を確認する
   - Chromium: Playwright バージョンに対応するバンドル版を使用（`npx playwright install chromium`）。Min Version は `(bundled with playwright)` と記載
2. 必要に応じて、ローカル環境・プロジェクト依存として**現在インストール済みのバージョン**を別途検出する
   - Playwright: `npx playwright --version` は最新安定版の調査ではなく、インストール済みバージョンの検出として扱う
3. `Min Version` は、手順 1 で検証した最新安定版を採用して更新する。手順 2 の結果は差分確認用の参考情報であり、`Min Version` の根拠にしない

Phase 2 step 3.5 と同様、AI の学習データのデフォルト値を使用しない。

---

### 4. Generate Test Specifications via Subagents

3つのサブエージェントを **並列で** 起動し、UT/IT/E2E 仕様をそれぞれ独立に導出する。

**重要**: 3つの Agent 呼び出しを **1つのメッセージ内で同時に** 行うこと（並列実行）。

#### Subagent A: UT 仕様の導出

```
Agent({
  subagent_type: "general-purpose",
  model: "sonnet",
  description: "UT 仕様を導出",
  prompt: "You are a test specification engineer. Generate Unit Test specifications.

    Read the following files:
    - {project-path}/.spec-workflow/specs/{spec-name}/design.md
    - {project-path}/.spec-workflow/specs/{spec-name}/requirements.md

    Task:
    design.md の **Components and Interfaces** セクションから、各コンポーネントのユニットテスト仕様を導出せよ。

    導出ルール:
    1. 各コンポーネントの公開インターフェース（メソッド/関数）を列挙
    2. 各インターフェースに対して、4カテゴリ（Happy Path / Boundary Values / Error Handling / Edge Cases）のテストケースを設計
    3. コンポーネントの **Dependencies** からモック対象を特定
    4. design.md の **Error Handling** テーブルから、各エラーコードに対応するエラーハンドリングテストを設計
    5. **Leptos フロントエンドコンポーネント**: コンポーネントが Leptos フロントエンドコンポーネント（view! マクロ、#[component]、signal 使用、pages/ / components/ ディレクトリ配置）の場合:
       - HTML レンダリングや DOM 構造のテストは指定しない
       - 代わりに以下のテストを指定:
         a. シグナル状態遷移（初期状態、更新後の値）
         b. 派生計算の正しさ（クロージャ、Memo の値）
         c. バリデーションロジック（コンポーネントから抽出）
         d. Callback/ハンドラロジック（抽出した関数の動作）
         e. サーバー関数ビジネスロジック（コア計算）
       - UT テーブルの Verification 列に「Test target: extracted logic function」と注記

    命名規則: UT-{コンポーネント番号}.{テストケース番号} (例: UT-1.1, UT-1.2, UT-2.1)

    品質基準:
    - design.md の全コンポーネントに対して UT 仕様が存在すること
    - 各 UT は 4カテゴリのうち該当するカテゴリを網羅していること
    - テストケースの Input / Expected Output / Verification が具体的であること（プレースホルダー不可）
    - Leptos フロントエンドコンポーネントの UT 仕様は抽出可能なロジック（シグナル、バリデーション、計算）を対象とし、HTML レンダリングは対象としないこと

    テスト技術コンテキスト:
    {メインエージェントが調査したテスト技術サマリーをここに挿入}

    Output format:
    ## Unit Test Specifications のマークダウンセクションをそのまま出力せよ。
    各コンポーネントをサブセクション (###) とし、テストケースをテーブル形式で記載。"
})
```

#### Subagent B: IT 仕様の導出

```
Agent({
  subagent_type: "general-purpose",
  model: "sonnet",
  description: "IT 仕様を導出",
  prompt: "You are a test specification engineer. Generate Integration Test specifications.

    Read the following files:
    - {project-path}/.spec-workflow/specs/{spec-name}/design.md
    - {project-path}/.spec-workflow/specs/{spec-name}/requirements.md

    Task:
    design.md の **Architecture** 図と **Components and Interfaces** の Dependencies 記述から、コンポーネント間の重要な相互作用を特定しテストケース化せよ。

    導出ルール:
    1. Architecture 図の矢印（依存関係）ごとに、結合テストシナリオを検討
    2. DB アクセスを伴うコンポーネントには DB 統合テストを設計
    3. 外部 API 連携がある場合はモック/スタブを使った統合テストを設計

    命名規則: IT-{シナリオ番号} (例: IT-1, IT-2)

    品質基準:
    - design.md Architecture の全主要依存関係に IT 仕様が存在すること
    - 各 IT に Components, Interaction, Technology, Preconditions, Steps, Expected Result, Verification Points を記載

    テスト技術コンテキスト:
    {メインエージェントが調査したテスト技術サマリーをここに挿入}

    Output format:
    ## Integration Test Specifications のマークダウンセクションをそのまま出力せよ。
    各シナリオをサブセクション (###) とし、詳細をテーブルまたは構造化リストで記載。"
})
```

#### Subagent C: E2E 仕様の導出

```
Agent({
  subagent_type: "general-purpose",
  model: "sonnet",
  description: "E2E 仕様を導出",
  prompt: "You are a test specification engineer. Generate End-to-End Test specifications.

    Read the following files:
    - {project-path}/.spec-workflow/specs/{spec-name}/requirements.md
    - {project-path}/.spec-workflow/specs/{spec-name}/design.md

    Task:
    requirements.md の **ユーザーストーリー** と **Acceptance Criteria** から、ユーザージャーニーレベルのテストシナリオを導出せよ。

    導出ルール:
    1. 各ユーザーストーリーの正常フローを E2E シナリオ化
    2. 重要な失敗シナリオ（認証エラー、権限不足等）も E2E シナリオに含める
    3. design.md の API Design セクションがある場合、API レスポンスの検証ポイントを明記

    命名規則: E2E-{シナリオ番号} (例: E2E-1, E2E-2)

    品質基準:
    - requirements.md の全ユーザーストーリーに最低1つの E2E 仕様が存在すること
    - 各 E2E に User Story 参照、Test Type、Technology、Scenario Steps、Success Criteria、Failure Scenarios を記載

    テスト技術コンテキスト:
    {メインエージェントが調査したテスト技術サマリーをここに挿入}

    Output format:
    ## E2E Test Specifications のマークダウンセクションをそのまま出力せよ。
    各シナリオをサブセクション (###) とし、詳細をテーブルまたは構造化リストで記載。"
})
```

---

### 5. Integrate and Create Document (メインエージェント)

3つのサブエージェントの出力を統合し、完全な `test-design.md` を作成する。

1. **Test Strategy Overview** を冒頭に追加:
   - テスト全体方針、Test Pyramid（UT > IT > E2E）、環境要件
   - セクション 3 で決定したテスト技術選定の結果
   - **Required Test Tools** テーブル: セクション 3.3 で列挙したツール一覧

2. **サブエージェント結果を順序通り配置**:
   - Unit Test Specifications（Subagent A の出力）
   - Integration Test Specifications（Subagent B の出力）
   - E2E Test Specifications（Subagent C の出力）

3. **Requirements-Test Traceability Matrix** を構築:
   - 全サブエージェント結果を横断し、全 Requirement ID に UT/IT/E2E が紐づくことを確認
   - 漏れがある場合はメインエージェントが追加

4. **Test Data Requirements** を追加:
   - 共有フィクスチャ、テストデータ生成方針

5. **E2E Test Infrastructure** を追加:
   - Project Type Detection、Container Test Setup、Test Runner Configuration

6. ファイルに書き出し:
```
.spec-workflow/specs/{spec-name}/test-design.md
```

**品質基準（統合時チェック）:**
- 全 Requirement ID に最低1つの UT と、関連する IT または E2E が紐づいていること
- design.md の全コンポーネントに対して UT 仕様が存在すること
- テストケースの Input / Expected Output / Verification が具体的であること（プレースホルダー不可）
- サブエージェント間で命名・フォーマットが一貫していること（不一致があれば統一する）

### 6. Self-Review via Subagent (before approval)

Validate the document in **2 stages** before approval.

#### Step A: fix (mechanical auto-fixes)

Auto-fix placeholders, formatting, and typos. Do not add or change content:

```
Agent({
  subagent_type: "general-purpose",
  model: "sonnet",
  description: "Fix test-design spec (auto-fix)",
  prompt: "You are a spec document reviewer. Auto-fix minor issues in the document at:
    {project-path}/.spec-workflow/specs/{spec-name}/test-design.md

    Document type: test-design

    Items eligible for auto-fix (may directly modify the file):
    - Remove placeholder text ([describe...], TODO, TBD)
    - Fix markdown formatting (table alignment, heading levels, etc.)
    - Obvious typos

    Items NOT eligible for auto-fix (report as issues only):
    - Adding, removing, or modifying test cases
    - Changing test case content (Input, Expected Output, Verification)
    - Traceability inconsistencies

    Mode: fix — Return a structured report (auto-fixed items + remaining issues)."
})
```

#### Step B: check (content validation)

After fix completes, detect content issues. Do not modify the file:

```
Agent({
  subagent_type: "general-purpose",
  model: "opus",
  description: "Review test-design spec (check)",
  prompt: "You are a spec document reviewer. Review the document (do NOT modify the file) at:
    {project-path}/.spec-workflow/specs/{spec-name}/test-design.md

    Document type: test-design
    Template: {project-path}/.spec-workflow/templates/test-design-template.md
    Requirements: {project-path}/.spec-workflow/specs/{spec-name}/requirements.md
    Design: {project-path}/.spec-workflow/specs/{spec-name}/design.md

    Checks:
    1. TEMPLATE: Every section from the template must exist with real content (no placeholders)
    2. UT COVERAGE: Every component in design.md must have corresponding UT specifications
    3. UT CATEGORIES: Each component's UT specs must cover all applicable categories (Happy Path, Boundary Values, Error Handling, Edge Cases)
    4. IT COVERAGE: Every significant component interaction in design.md Architecture must have an IT specification
    5. E2E COVERAGE: Every user story in requirements.md must have at least one E2E specification
    6. TRACEABILITY: Requirements-Test Traceability Matrix must cover ALL Requirement IDs. Every Requirement ID must have at least one UT and one IT or E2E
    7. SPECIFICITY: Test cases must have concrete Input, Expected Output, and Verification (no placeholders or vague descriptions)
    8. NAMING: Test case IDs follow the naming convention (UT-N.M, IT-N, E2E-N)
    9. ERROR HANDLING: design.md Error Handling table entries must have corresponding error handling test cases
    10. TEST DATA: Test Data Requirements section must define shared fixtures and generation strategy
    11. E2E INFRASTRUCTURE: E2E Test Infrastructure section must define project type, container test setup, and test runner
    12. CONTAINER CONSISTENCY: IT/E2E specs Technology fields must be consistent with design.md Container Architecture and E2E Test Infrastructure section
    13. REQUIRED TEST TOOLS: Required Test Tools section must exist within Test Environment Requirements, with at least one tool entry in table format (Tool, Min Version, Purpose, Check Command, Install Command, Required columns). All E2E test tools must be Required=Yes.

    Mode: check — DO NOT modify the file. List all issues with location and suggested fix.
    Return a structured report (PASS/FAIL with issues list)."
})
```

If check returns FAIL, fix the issues yourself and re-run check (up to 3 times). Once PASS, proceed to approval.

### 7. Approval Workflow

Same strict process — verbal approval is never accepted.

1. **Request approval**: `approvals` tool, `action: 'request'`, filePath only. Save the returned `approvalId`.

2. **Automatic polling with auto-transition**: Start approval polling (Bash script with 60-minute timeout):
   ```
   /check-approval <approvalId> next:/spec-tasks
   ```
   The polling script will automatically check approval status and handle the result:
   - **approved**: Cleanup is performed automatically, and check-approval automatically invokes `/spec-tasks`
   - **needs-revision**: Reviewer comments are displayed
   - **timeout**: Reported to user, can re-run to resume

3. **Handle needs-revision** (if polling ends with needs-revision):
   - Update test-design using reviewer comments, spawn the review subagent again
   - Submit a NEW approval request and run `/check-approval <newApprovalId> next:/spec-tasks`

## Rules

- Feature names use kebab-case
- One spec at a time
- Every design.md component must have UT specs
- Every requirement must appear in the Traceability Matrix
- Test cases must be concrete (no placeholders in Input/Expected Output/Verification)
- Approval requests: filePath only, never content
- Never accept verbal approval — dashboard/VS Code extension only
- Never proceed if approval delete fails
