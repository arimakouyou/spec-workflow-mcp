---
name: spec-tasks
description: "Phase 4 of spec-driven development: break an approved design into atomic implementation tasks. Use this skill after test design is approved, when the user wants to create tasks, plan implementation steps, or break down work into actionable items. Triggers on: 'create tasks', 'break down into tasks', 'implementation plan', 'task breakdown for X', or any request to create a tasks.md document."
---

# Spec Tasks (Phase 4)

Break the approved design into atomic, implementable tasks. This phase converts architecture decisions into a concrete action plan.

## Prerequisites Check (MANDATORY — DO NOT SKIP)

Before doing anything else, verify all prerequisite files exist:

1. Check `.spec-workflow/specs/{spec-name}/request-spec.md` exists
2. Check `.spec-workflow/specs/{spec-name}/requirements.md` exists
3. Check `.spec-workflow/specs/{spec-name}/design.md` exists
4. Check `.spec-workflow/specs/{spec-name}/test-design.md` exists

**Legacy workflow exception**: If `request-spec.md` does not exist but `requirements.md` already exists, this is a legacy spec created before Phase 0. Skip the `request-spec.md` check and proceed normally.

If `requirements.md`, `design.md`, or `test-design.md` is missing — **STOP immediately.** Inform the user: "{filename} does not exist; cannot begin task breakdown. Please run {skill-name} first." Then exit this skill.

| Missing File | Required Skill | Skip if legacy? |
|-------------|---------------|-----------------|
| request-spec.md | `/spec-request-spec` | Yes (if requirements.md exists) |
| requirements.md | `/spec-requirements` | No |
| design.md | `/spec-design` | No |
| test-design.md | `/spec-test-design` | No |

---

Test design must be approved and cleaned up (Phases 1-3 complete). If not, use `/spec-test-design` first.

## Inputs

The same **spec name** used in previous phases (kebab-case, e.g., `user-authentication`).

## Process

### 1. Load the Template

Check for a custom template first, then fall back to the default:

1. `.spec-workflow/user-templates/tasks-template.md` (custom)
2. `.spec-workflow/templates/tasks-template.md` (default)

### 2. Read Approved Documents

- `.spec-workflow/specs/{spec-name}/request-spec.md`
- `.spec-workflow/specs/{spec-name}/requirements.md`
- `.spec-workflow/specs/{spec-name}/design.md`
- `.spec-workflow/specs/{spec-name}/test-design.md`

### 2.5 Detect New Project

新規プロジェクトかどうかを検出し、Git 初期化タスクの追加要否を判断する。

```bash
# Git リポジトリが存在するか確認
git -C "{project-path}" rev-parse --is-inside-work-tree 2>/dev/null
echo $?
```

**結果に応じた分岐（終了コード優先）:**

| 終了コード | `--is-inside-work-tree` の出力 | 判定 | アクション |
|-----------|-------------------------------|------|-----------|
| `0` | `true` | 既存リポジトリ（作業ツリーあり） | Git 初期化タスク不要。Phase 0 に含めない |
| `0` | `false` | 既存リポジトリ（bare repo または `.git` ディレクトリ直下） | Git 初期化タスク不要。必要であれば、bare から通常リポジトリへの移行タスクを別途検討 |
| `128` | （任意） | 新規プロジェクト（Git未初期化） | Phase 0 の先頭に Git 初期化タスクを追加 |
| `127` | （任意） | git コマンドが見つからない | ユーザーにエラー報告: 「git がインストールされていません。git をインストールしてから再実行してください。」タスク生成を中断 |
| その他 | （任意） | パス不正・権限エラー等 | ユーザーにエラー報告: 「プロジェクトパスの確認中にエラーが発生しました（exit code: {N}）。パスとアクセス権限を確認してください。」タスク生成を中断 |

新規プロジェクト（exit code 128）の場合、Phase 0 の先頭（他のすべてのタスクの前）に以下のタスクを自動追加する:

```markdown
## Phase 0: Project Setup

- [ ] 0.0 Initialize Git repository
  - File: .gitignore
  - _TDDSkip: true_
  - _Requirements: REQ-0_
  - _Prompt: Role: DevOps Engineer | Task: Initialize a Git repository, create an appropriate .gitignore for the project type (Rust: target/, *.swp, .env etc.), and make the initial commit | Restrictions: Do not include secrets or build artifacts in the initial commit. The .gitignore must cover the project's language/framework (e.g., /target for Rust, node_modules for Node.js). Do not configure remote repository (user will do this manually) | Success: `git log` shows the initial commit, `.gitignore` exists and covers the project type_
```

**注意:**
- Git 初期化タスクは常に Phase 0 の最初のタスク（0.0）とする
- 後続のタスク番号は 0.1 から始める
- 既存リポジトリの場合、タスク番号は従来通り 0.1 から始まる

### 2.6 Detect Container Requirements

design.md の Container Architecture セクションを読み、コンテナセットアップタスクの要否を判断する。

**検出ロジック:**
1. design.md に「Container Architecture」セクションが存在するか
2. Service Dependencies テーブルにサービスが列挙されているか

**Container Architecture が存在する場合**、Phase 0 に以下のタスクを追加する（Git 初期化タスクの後、他のセットアップタスクの前）:

```markdown
- [ ] 0.1 Create Dockerfile and docker-compose.yml
  - File: Dockerfile, docker-compose.yml, .dockerignore
  - _TDDSkip: true_
  - _Requirements: REQ-0_
  - _Prompt: Role: DevOps Engineer | Task: design.md の Container Architecture に基づいて Dockerfile (multi-stage build) と docker-compose.yml を作成する。Service Dependencies テーブルの全サービスを含める | Restrictions: シークレットを Dockerfile に埋め込まない。.dockerignore で不要ファイルを除外。ポート番号は design.md の定義に従う | Success: `docker-compose up -d` で全サービスが起動する_

- [ ] 0.2 Create test container configuration
  - File: docker-compose.test.yml
  - _TDDSkip: true_
  - _DependsOn: 0.1_
  - _Requirements: REQ-0_
  - _Prompt: Role: DevOps Engineer | Task: テスト用の docker-compose.test.yml を作成する。外部ポートは固定値ではなく環境変数（例: ${TEST_DB_PORT}:5432）で指定し、起動スクリプトで5桁のランダムポート（10000-65535）を生成して渡す方式にする。TEST_DB_PORT が未設定の場合は起動を失敗させる。DB にはテスト用の初期化スクリプトを含める | Restrictions: 本番用 docker-compose.yml を修正しない。テスト用ボリュームは永続化しない（tmpfs 推奨）。固定オフセットポート（5432→15432 等）は他プロセスとの競合リスクがあるため使用しない | Success: ランダムポートで `docker-compose -f docker-compose.test.yml up -d` が起動し、本番用と共存できる_
```

**Container Architecture が存在しない場合**: コンテナタスクを追加しない（従来通り）。

**注意:** Git 初期化タスク (0.0) がある場合、コンテナタスクは 0.1, 0.2 とし、他のセットアップタスクは 0.3 から始める。

### 2.7 Detect CI Workflow Requirements

`.github/workflows/` 配下に PR トリガーの CI ワークフローが存在するか確認し、CI セットアップタスクの要否を判断する。

**検出ロジック:**

```bash
# PR トリガーの CI ワークフローが存在するか
# pull_request: (マッピング形式)、- pull_request (リスト形式)、[..., pull_request, ...] (インライン配列) を検出
if test -d .github/workflows; then
  grep -rEl '(^\s*pull_request:|^\s*-\s*pull_request|\[\s*.*pull_request)' .github/workflows --include='*.yml' --include='*.yaml'
  echo $?
else
  echo "1"
fi
```

| 結果 | 判定 | アクション |
|------|------|-----------|
| ファイルが見つかった（exit 0） | PR トリガーの CI ワークフローが既に存在 | CI タスクを追加しない |
| ファイルが見つからない（exit 1）| PR トリガーの CI ワークフローが未作成 | Phase 0 に CI セットアップタスクを追加 |
| `.github/workflows/` が存在しない | CI 未構成 | Phase 0 に CI セットアップタスクを追加 |

**PR トリガーの CI ワークフローが存在しない場合**、Phase 0 に以下のタスクを追加する（Git 初期化 → コンテナ → CI の順）:

```markdown
- [ ] 0.N Create CI workflow
  - File: .github/workflows/ci.yml
  - _TDDSkip: true_
  - _Requirements: REQ-0_
  - _Prompt: Role: DevOps Engineer | Task: /setup-ci スキルを使用して、プロジェクトタイプに応じた PR トリガーの GitHub Actions CI ワークフローを生成する。.claude-plugin/rules/quality-checks.md に定義された品質チェックコマンドと同一のステップを含めること。design.md に Container Architecture がある場合は --with-services オプションを使用する | Restrictions: シークレットをワークフローにハードコードしない。既存の CI ワークフロー（npm-publish.yml 等）を変更しない | Success: PR 作成時に CI が自動実行され、.claude-plugin/rules/quality-checks.md に定義された品質チェックが通る_
```

**注意:** タスク番号 `0.N` は Phase 0 内の順序に応じて割り振る（Git 初期化 0.0 → コンテナ 0.1, 0.2 → CI 0.3 の順。コンテナタスクがない場合は繰り上げる）。

### 2.8 Detect ADR Directory

`.claude/_docs/adr/` ディレクトリが存在するか確認し、ADR プロセスの初期化タスクの要否を判断する。

**検出ロジック:**

```bash
test -d .claude/_docs/adr && test -f .claude/_docs/adr/INDEX.md
echo $?
```

| 結果 | 判定 | アクション |
|------|------|-----------|
| exit 0 | ADR ディレクトリと INDEX.md が存在 | タスクを追加しない |
| exit 1 | ADR が未初期化 | Phase 0 に ADR 初期化タスクを追加 |

**ADR が未初期化の場合**、Phase 0 に以下のタスクを追加する（CI タスクの後）:

```markdown
- [ ] 0.N Initialize ADR directory
  - File: .claude/_docs/adr/INDEX.md
  - _TDDSkip: true_
  - _Requirements: REQ-0_
  - _Prompt: Role: DevOps Engineer | Task: .claude/_docs/adr/ ディレクトリと INDEX.md を作成する。INDEX.md には ADR テーブルのヘッダー（ADR, Title, Status, Date）のみ記載する。design.md の Key Design Decisions から /adr スキルを使用して初期 ADR を生成する | Restrictions: 既存の .claude/ 配下のファイルを変更しない | Success: .claude/_docs/adr/INDEX.md が存在し、design.md の主要決定に対応する ADR ファイルが作成されている_
```

**注意:** タスク番号は Phase 0 内の最後のセットアップタスクとする（Git 初期化 → コンテナ → CI → ADR の順）。

### 3. Create Tasks

Convert the design into atomic tasks. Each task should touch 1-3 files and be independently implementable. Include:

- File paths that will be created or modified
- Requirement references (which requirements the task implements)
- Logical ordering (dependencies between tasks)

#### Single Responsibility Criteria

Task granularity is determined by the number of **responsibilities**, not just the number of files. 1 task = 1 responsibility.

**Decision rules:**
1. **Can the task be described in a single sentence?** — If multiple behaviors are joined with "and", consider splitting
2. **Do the Success criteria converge on a single verification target?** — If there are multiple independent Success conditions, split the task
3. **Does it complete within one TDD cycle?** — All tests written in the RED phase belong to the same module/function

**Examples requiring splitting:**
- "Create model and implement API endpoint" → `create model` + `implement endpoint`
- "Implement CRUD with validation and caching" → `implement CRUD` + `add validation` + `add caching`
- "Define DB schema and implement repository" → `create migration` + `implement repository`

**Examples that do NOT require splitting (fit within 1 responsibility):**
- "Create User model with Queryable/Insertable/AsChangeset derives"
- "Implement GET /users/{id} endpoint returning UserDto"
- "Add email format validation to CreateUserRequest"

### 3.5 Phase-Based Organization

Group tasks into phases using `## Phase N: Title` headings. Each phase is a **vertical slice** — a testable, committable increment that delivers end-to-end value.

- 1 phase = 2-5 implementation tasks + 1 review task
- Each phase ends with a `_PhaseReview: true_` task for review and commit
- Phases are ordered by dependency (core → API → UI → integration)

### 3.6 IT / ST / E2E Test Tasks（J-5 で改訂）

test-design.md の IT / ST / E2E 仕様を基に、Phase の適切な位置にテストタスクを配置する。各層の責務範囲は `quality-checks.md` の Test Taxonomy 参照。

#### IT タスク（backend HTTP API only）
- test-design.md の各 IT 仕様（IT-1, IT-2, ...）に対応するタスクを作成
- **配置**: 対象コンポーネントがすべて実装済みの Phase に配置（通常は backend Phase 完了直後の PhaseReview 直前）
- `_TestFocus` は test-design.md の IT 仕様を参照し、Verification Points を列挙
- `_Prompt` の Task に「test-design.md の IT-{N} 仕様に基づいて backend HTTP API 統合テストを実装する」と明記
- **責務範囲**: UI 操作 / DOM 検証を含めない（`quality-checks.md` Test Taxonomy 参照）

#### ST タスク（単一機能の full-stack、J-7 で新設）
- test-design.md の各 ST 仕様（ST-1, ST-2, ...）に対応するタスクを作成
- **配置**: 対象機能の component / endpoint がすべて実装済みの Phase **末尾**（CT/IT 完了後、E2E より前）
- `_TestFocus` は test-design.md の ST 仕様を参照し、Test Path / Verification Points を列挙
- `_Prompt` の Task に「test-design.md の ST-{N} 仕様に基づいて単一機能の full-stack テストを実装する」と明記
- **責務範囲**: 1 機能分のみ（複数機能の連鎖を含めない）

#### E2E タスク（user journey only）
- test-design.md の各 E2E 仕様（E2E-1, E2E-2, ...）に対応するタスクを **最終 Phase** に配置
- `_TestFocus` は test-design.md の E2E 仕様を参照し、Scenario Steps と Success Criteria を列挙
- `_Prompt` の Task に「test-design.md の E2E-{N} 仕様に基づいて user journey E2E テストを実装する」と明記
- **責務範囲**: 複数機能の連鎖を含む user journey のみ（個別機能テストは ST に振る）

#### 配置ルールの優先順序

```
Phase N (backend 実装):  ... → IT-N tasks → PhaseReview
Phase M (UI 実装):       ... → CT-N tasks (H 実装後) → PhaseReview
Phase L (機能完成):      ... → ST-N tasks → PhaseReview
最終 Phase:              E2E-N tasks → Final PhaseReview
```

### 3.7 TDD Task Design Rules

- **No standalone unit test tasks.** TDD handles unit testing automatically in each task's RED phase. However, IT/E2E test tasks (defined in section 3.6) are **allowed and expected** as separate tasks — they implement integration and end-to-end tests from test-design.md specifications.
- **Each task must be independently testable** — it must produce observable behavior that can be verified.
- **`_TestFocus` field** — Structured in 4 categories (Happy Path / Boundary Values / Error Handling / Edge Cases) as required by the unit-test-engineer. Free-form text is not allowed. **Must be derived from test-design.md**: reference the corresponding UT spec IDs (e.g., UT-1.1, UT-1.2) and include the concrete test cases defined there.

#### Tasks eligible for TDD skip (`_TDDSkip: true`)

Tasks with no runtime behavior and nothing to test receive `_TDDSkip: true`. For these tasks, parallel-worker skips the TDD cycle and performs direct implementation + quality checks only.

**Tasks where `_TDDSkip: true` applies:**
- Project initialization (`cargo init`, directory structure creation, `Cargo.toml` dependency additions)
- Infrastructure/config files (Dockerfile, docker-compose.yml, CI/CD configuration)
- DB migrations (creating up.sql/down.sql via `diesel migration generate`)
- Environment config files (`.env.example`, `diesel.toml`, `.cargo/config.toml`)

**Tasks where `_TDDSkip: true` does NOT apply (must be merged):**
- Interface-only tasks (trait/struct/enum definitions only) → merge into the first implementing task

Decision rule: "Is this task self-contained?"
- A Dockerfile is self-contained → `_TDDSkip: true`
- A trait definition is meaningless without an implementing task → merge

`_TDDSkip: true` tasks do not need a `_TestFocus` field (may be omitted).

### 4. Generate _Prompt Fields

This is critical for implementation quality. Each task needs a `_Prompt` field with structured AI guidance, plus a `_TestFocus` field for TDD:

```markdown
## Phase 0: Project Setup

- [ ] 0.1 Initialize project and create Dockerfile
  - File: Cargo.toml, Dockerfile, docker-compose.yml, .env.example
  - _TDDSkip: true_
  - _Requirements: REQ-0_
  - _Prompt: Role: DevOps Engineer | Task: Initialize Cargo project, create Dockerfile and docker-compose.yml for Axum + PostgreSQL + Valkey | Restrictions: Do not include secrets in .env.example | Success: Containers start with docker-compose up_

- [ ] 0.2 Create DB migration for users table
  - File: migrations/YYYYMMDD_create_users/up.sql, down.sql
  - _TDDSkip: true_
  - _Requirements: REQ-1_
  - _Prompt: Role: Backend Developer | Task: Create users table migration with diesel migration generate | Restrictions: Strictly follow the DB Schema definition in design.md | Success: diesel migration run succeeds_

## Phase 1: Core Models & Repository

- [ ] 1.1 Create User model with Diesel derives
  - File: src/models/user.rs, src/schema.rs
  - Implement Queryable, Insertable, AsChangeset
  - _Leverage: src/models/mod.rs_
  - _Requirements: REQ-1_
  - _TestFocus: Happy Path: construction and field access for User/NewUser/UpdateUser | Boundary Values: minimum (1 char) and maximum (255 chars) name length | Error Handling: empty string name, invalid email format | Edge Cases: multi-byte character name_
  - _Prompt: Role: Backend Developer | Task: Create User model with Queryable/Insertable/AsChangeset derives | Restrictions: schema.rs is auto-generated by diesel print-schema — do not edit manually | Success: User, NewUser, UpdateUser structs are defined and the code compiles_

- [ ] 1.2 Implement UserRepository with CRUD operations
  - File: src/db/repository/users.rs
  - Implement find_by_id, list, create, update, delete
  - _DependsOn: 1.1_
  - _Leverage: src/db/mod.rs, src/models/user.rs_
  - _Requirements: REQ-1_
  - _TestFocus: Happy Path: success paths for all CRUD operations | Boundary Values: list with 0 / 1 / many records | Error Handling: find with nonexistent ID, create with duplicate key, DB connection error | Edge Cases: concurrent updates_
  - _Prompt: Role: Backend Developer | Task: Implement UserRepository with CRUD operations using diesel-async | Restrictions: All methods must return Result<T, AppError> | Success: All CRUD methods are implemented and tests pass_

- [ ] 1.3 Review and commit Phase 1
  - _PhaseReview: true_
  - _Prompt: Role: Code reviewer | Task: Review all Phase 1 changes, run tests, commit | Success: All tests pass, committed_
```

#### UI Component task テンプレ（D で追加、dapper-hardening）

UI component（Leptos / Blazor / React 等）の task は `_Prompt.Task` で以下を **必須記述**:

1. **view! / 出力 DOM**: 「view! 内に `<img src=...>` `<button>...</button>` 等の {期待要素} をレンダリングする」と明示文字列で記述
2. **依存配線**: design.md DES-N の `Dependencies:` 列の各 server fn / 外部 API / 兄弟 component を「{依存名} を呼び出す / 統合する / 受け取る」と明示
3. **data-testid 付与**: test-design.md の CT/E2E 仕様で参照される testid を view! 内の該当位置に付与（test_ids.rs 等で定数化推奨）
4. **event listener attach**: `on:click` / `on:submit` / `on:input` 等の event handler が signal を update するように配線

`_Prompt.Success` は **動作証跡** で書く（grep だけでは不十分、Check 18 SUCCESS_BEHAVIORAL_VERIFICATION で error）:

- CT-N が PASS（mount + signal + DOM 観測 chain）
- 必要に応じて grep などの補助確認も併記可（単独では不可）

```markdown
- [ ] 4.4 Implement ThumbnailGrid component
  - File: crates/app/src/components/thumbnail_grid.rs
  - Render thumbnail items from list_folder Resource
  - _DependsOn: 4.3
  - _Leverage: crates/app/src/server_fns/list_folder.rs, crates/app/src/test_ids.rs
  - _Requirements: REQ-2.1, REQ-2.2
  - _TestFocus: Happy Path: 5枚画像表示 / Boundary Values: 0枚 / 1枚 / 200枚 / Error Handling: list_folder error 時のエラー表示 / Edge Cases: 多バイトパス / Negative Assertions: list_folder を 1 回しか呼ばない / Isolation Properties: list_folder は MockServer 経由
  - _Prompt: Role: Frontend Component Engineer | Task: ThumbnailGrid component を実装。view! 内に Resource::new で list_folder を呼び出し、Suspense で pending 状態を表示、各画像に <img src="/api/thumbnails/{path}"> + data-testid="thumbnail-item" を付与。on:click で on_open callback を実行 | Restrictions: design.md DES-12 の Interfaces を変更しない。pure helper 抽出のみで終わらせない（Check 18） | Success: CT-12.1 (initial render) / CT-12.2 (5 件画像表示) / CT-12.3 (click → on_open 呼び出し) が全 PASS、view! 内に data-testid="thumbnail-grid" / "thumbnail-item" が grep で検出される_
```

**Note:** The Task field must focus on a single responsibility. Do not join multiple responsibilities with "and" (e.g., "Create model and implement repository").

Also include:
- `_Leverage`: Existing files/utilities to reuse (copied from the Code Reuse Analysis table in design.md)
- `_Requirements`: Which requirements this task fulfills (traceability)
- `_DependsOn`: Same Phase 内で、このタスクが依存する他タスクのID（カンマ区切り）。依存がない場合は省略する。依存があるタスクは、依存先が完了するまで実行されない。Phase 跨ぎの依存は不要（Phase 順序で暗黙保証）。例: `_DependsOn: 1.1, 1.2_`
- `_TestFocus`: Written in the 4-category structured format (see below)
- `_BugFix` / `_RegressionBugId` (J-10 で必須化、`dapper-hardening-orchestrator.md` 参照):
  - バグ修正系 task の場合 `_BugFix: true_` を必須化、合わせて `_RegressionBugId: BUG-NNN_` （または `GH#NNN_`）を必須化
  - 例: `- _BugFix: true_\n- _RegressionBugId: GH#123_`
  - 対応する regression test は `regression-test-policy/SKILL.md` の命名規則 (`regression_issue_NNN_*` / `it('regression #NNN: ...')`) で実装する
  - parallel-worker は `_BugFix: true` を検知したら RT1 フロー（修正前に再現テストを RED phase で書き、修正後 GREEN にする）に従う

#### _BugFix task の例（J-10）

```markdown
- [ ] N.M Fix login failure on multibyte usernames
  - File: src/services/login.rs, tests/regression/issue_123.rs
  - _BugFix: true_
  - _RegressionBugId: GH#123_
  - _DependsOn: ...
  - _Requirements: REQ-N
  - _TestFocus: Happy Path: multibyte username login succeeds | Boundary Values: empty / 1-char / 256-char username | Error Handling: invalid byte sequence | Edge Cases: combining characters | Negative Assertions: login does NOT panic on invalid UTF-8 | Isolation Properties: Mock-only clock for token expiry test
  - _Prompt: Role: Bug Fixer | Task: GH#123 を修正。再現テスト regression_issue_123_login_fails_with_multibyte_username をまず RED phase で書き、その後修正 | Restrictions: 既存の login flow を破壊しない | Success: regression test PASS、既存テスト全件 PASS_
```

#### _TestFocus Format（I-1 で 4→6 カテゴリに拡張）

To align with the unit-test-engineer's required test coverage, use the following **6-category structure** (extended from 4 to 6 per I-1, `dapper-hardening-orchestrator.md`). Free-form text is not allowed.

```
_TestFocus: Happy Path: {specific test targets} | Boundary Values: {specific boundaries} | Error Handling: {specific error cases} | Edge Cases: {specific cases} | Negative Assertions: {specific behaviors that must NOT happen} | Isolation Properties: {external dependency strategy}
```

カテゴリ説明:

1. **Happy Path**: 仕様に基づく正常系の挙動を verify
2. **Boundary Values**: 境界値（最小・最大・閾値直前後）の挙動
3. **Error Handling**: エラー条件への対処（不正入力 / 失敗 / タイムアウト等）
4. **Edge Cases**: 例外的な状況（マルチバイト / 重複 / 連続操作）
5. **Negative Assertions（I-1 で追加）**: **仕様外の挙動が起きないことの確認**:
   - 入力 mutation が起きないこと（pure function は副作用ゼロ）
   - 不要な log / metric / event を吐かないこと
   - 想定外の入力で panic しないこと（適切なエラーで失敗）
   - 仕様外のフィールドを返さないこと
6. **Isolation Properties（I-1 で追加）**: **外部依存ゼロ + 順序非依存 + 決定性**:
   - clock / RNG / env / fs / HTTP / DB の直接呼出ゼロ（Mock 経由のみ）
   - 順序非依存（他 test の状態に依存しない、share された global state を持たない）
   - 決定性（同じ入力で常に同じ結果。clock や RNG に依存しない）

If a category does not apply, explicitly write "N/A" (do not omit it). Negative Assertions / Isolation Properties が "N/A" になる場合は理由を明記（pure function で副作用が原理的に無い場合のみ）。
- Instructions about marking task status in tasks.md and logging implementation with `/log-implementation` skill

### 5. Create the Document

Write the tasks document to:
```
.spec-workflow/specs/{spec-name}/tasks.md
```

**Frontmatter (required for new specs, per `.claude-plugin/rules/spec-dependency-graph.md` SD2, SD6):**

以下の YAML frontmatter をファイル冒頭に追加する。これは tasks.md **全体**が依存する上流仕様書 ID の宣言であり、タスク個別の `_Requirements:` / `_DependsOn:` メタデータとは粒度が異なる直交情報:

```yaml
---
spec_id: {spec-name}
phase: tasks
version: 1
depends_on:
  - file: design.md
    refs: [DES-1, DES-2]  # 実装対象のコンポーネント
  - file: test-design.md
    refs: [UT-1.1, IT-1]  # 満たすべきテスト仕様
---
```

タスク個別メタデータ（`_Requirements:` / `_Leverage:` / `_DependsOn:` / `_PhaseReview:` / `_TDDSkip:` / `_TestFocus:`）は従来通り維持する（SD6）。

Task status markers:
- `- [ ]` = Pending
- `- [-]` = In progress
- `- [x]` = Completed

### 6. Update Design Traceability Matrix

After creating tasks.md, back-fill the "Target Task ID" column in the Requirements Traceability Matrix in design.md. This enables tracing from design components to tasks.

1. Read the Traceability Matrix in design.md
2. Identify the corresponding task ID from tasks.md for each component row
3. Fill in the "Target Task ID" column
4. **Verify that every component has an assigned task** — if any component row is unassigned, add a task and update the matrix

### 7. Self-Review via Subagent (before approval)

Validate the document in **2 stages** before approval.

#### Step A: fix (mechanical auto-fixes)

Auto-fix placeholders, formatting, and typos. Do not add or change content:

```
Agent({
  subagent_type: "general-purpose",
  model: "sonnet",
  description: "Fix tasks spec (auto-fix)",
  prompt: "You are a spec document reviewer. Auto-fix minor issues in the document at:
    {project-path}/.spec-workflow/specs/{spec-name}/tasks.md

    Document type: tasks

    Items eligible for auto-fix (may directly modify the file):
    - Remove placeholder text ([describe...], TODO, TBD)
    - Fix markdown formatting (table alignment, heading levels, etc.)
    - Obvious typos

    Items NOT eligible for auto-fix (report as issues only):
    - Adding, removing, or merging tasks
    - Changing the content of _Prompt, _Leverage, _Requirements, etc.
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
  description: "Review tasks spec (check)",
  prompt: "You are a spec document reviewer. Review the document (do NOT modify the file) at:
    {project-path}/.spec-workflow/specs/{spec-name}/tasks.md

    Document type: tasks
    Template: {project-path}/.spec-workflow/templates/tasks-template.md
    Requirements: {project-path}/.spec-workflow/specs/{spec-name}/requirements.md
    Design: {project-path}/.spec-workflow/specs/{spec-name}/design.md
    Test Design: {project-path}/.spec-workflow/specs/{spec-name}/test-design.md

    Checks:
    1. TEMPLATE: Every task has - [ ] marker, file path(s), _Requirements, _Prompt fields. Every implementation task also has _Leverage (Phase 0 setup tasks, PhaseReview tasks, and IT/E2E test tasks may omit _Leverage)
    2. _Prompt has: Role, Task, Restrictions, Success fields in the format "Role: ... | Task: ... | Restrictions: ... | Success: ..."
    3. CROSS-REFERENCE: Read requirements.md and design.md —
       every requirement must have at least one implementing task,
       every design component must have at least one creating task,
       _Requirements IDs must match actual requirement IDs,
       **(D 拡張、dapper-hardening)** every DES-N の `Dependencies:` 列に列挙された全 server fn / 外部 API / 兄弟 component が、対応 task の `_Prompt.Task` 文に **「{依存名} を呼び出す/統合する/受け取る」と明示文字列で記載されているか** 確認
    4. TRACEABILITY: Verify that the Target Task ID column is filled in for all components in the Requirements Traceability Matrix in design.md.
       If any component row is empty, add a task to tasks.md and update the matrix in design.md.
    5. Tasks are atomic (1-3 files), in logical dependency order
    6. No placeholder text, descriptions specific enough for AI implementation
    7. PHASE STRUCTURE: Tasks are grouped under ## Phase headings with vertical slices
    8. TDD: No standalone unit test tasks (e.g., 'write tests', 'create unit tests'). IT/E2E test tasks are allowed as separate tasks.
    9. Every non-PhaseReview task has a _TestFocus field
    10. Each phase ends with a _PhaseReview: true_ task
    11. DEPENDENCIES: _DependsOn references point to valid task IDs within the same Phase. No circular dependencies. No self-references. Tasks that use types/models/outputs created by another task declare the dependency.
    12. TEST-DESIGN TRACEABILITY: Read test-design.md —
        every UT spec must have a corresponding task with matching _TestFocus,
        every IT spec must have an integration test task,
        every ST spec must have a system test task (J-7),
        every E2E spec must have an E2E test task
    13. FRONTMATTER (spec-dependency-graph.md SD2, SD6): Valid YAML frontmatter with spec_id, phase: tasks, version, depends_on (file entries pointing to design.md and test-design.md with refs) must exist at the top of the file. DES-/UT-/IT-/ST-/E2E- IDs in depends_on.refs must exist in the referenced upstream files (SD4). Task-level metadata (_Requirements, _Leverage, _DependsOn) remains orthogonal to this frontmatter
    14. COMPOSITION_TASK (D, dapper-hardening): If design.md の Component List に top-level (root) component（例: AppRoot, MainShell, RootRoute）が存在する場合、その配下 component を子要素として組み立てる **専用の composition task** が tasks.md に存在するか。task の `_Prompt.Task` には「N 個の子 component を view! 内に配置し、prop / signal を配線する」、`_Prompt.Success` には「すべての子 component が DOM tree に出現する E2E スモーク (後続 Phase で) が成立する前提を満たす」を明記
    15. UI_OBSERVABILITY (D, dapper-hardening): UI component task の `_Prompt.Success` には「data-testid を {期待値} で付与する」「実 view! が {要求要素 (`<img>`, `<button>`, etc.)} をレンダリングする」が含まれているか。test-design.md の E2E / CT 仕様で `getByTestId(...)` / `query_selector("[data-testid=...]")` 参照されている testid が、対応する component task の `_Prompt.Success` に明示されているか
    16. FIXTURE_REALIZATION (D, dapper-hardening): test-design.md の Test Data Requirements に列挙された fixture path（`tests/fixtures/...`、`photos/landscape/...` 等）が、いずれかの task の `File:` 列または `_Prompt.Task` 文で生成・配置される旨が記載されているか
    17. PHASE_SMOKEABLE (E-2, dapper-hardening): 各 Phase の最後の `_PhaseReview: true_` task の前に、その Phase で smoke 可能な deliverable が **少なくとも 1 件存在するか**。design.md の Phase Deliverables（K-4 で必須化）と突合し、Phase が deliverable ゼロの場合は escalate（Phase 境界の見直し提案）
    18. SUCCESS_BEHAVIORAL_VERIFICATION (H-4, dapper-hardening): The `_Success` field must NOT be completed by static checks alone (e.g., grep for string existence / "the file exists" / "implementation contains X"). At least one **動作証跡 (behavioral evidence)** is required: test PASS (UT-N / CT-N / IT-N / ST-N) / smoke PASS / DOM observation. UI component task の `_Success` には CT-N PASS（mount + signal 操作 + DOM 観測）を必須化
    19. TESTFOCUS_NEGATIVE (I-1, dapper-hardening): _TestFocus must include all 6 categories (Happy Path / Boundary Values / Error Handling / Edge Cases / Negative Assertions / Isolation Properties). If Negative Assertions or Isolation Properties is "N/A", the task must be a pure function with no side effects (and the reason must be explicitly noted)
    20. ST_PLACEMENT (J-7, dapper-hardening): For every ST-N spec in test-design.md, a corresponding task must exist in tasks.md, placed at the end of the Phase that completes the target feature's component / endpoint dependencies (after CT/IT, before final E2E Phase).
    21. REGRESSION_BUG_ID (J-10, dapper-hardening): Tasks marked with `_BugFix: true` (or with `Role: Bug Fixer` in _Prompt) must include a `_RegressionBugId: BUG-NNN` (or `GH#NNN`) metadata field. The corresponding regression test must follow the naming convention `regression_issue_NNN_*` (Rust) / `regression #NNN` (TS) per regression-test-policy/SKILL.md.

    Mode: check — DO NOT modify the file. List all issues with location and suggested fix.
    Return a structured report (PASS/FAIL with issues list)."
})
```

If check returns FAIL, fix the issues yourself and re-run check (up to 3 times). Once PASS, proceed to approval.

### 8. Approval Workflow

Same strict process — verbal approval is never accepted.

1. **Request approval**: `approvals` tool, `action: 'request'`, filePath only. Save the returned `approvalId`.

2. **Check approval (synchronous)**: After the user approves via the dashboard / VS Code extension, run:
   ```
   /check-approval <approvalId> next:/spec-implement
   ```
   `check-approval` fetches status once via the `approvals` MCP tool (no polling) and branches:
   - **pending**: User has not acted yet — instruct the user to approve, then re-run `/check-approval`
   - **approved**: Cleanup is performed automatically, and `check-approval` automatically invokes `/spec-implement`
   - **needs-revision**: Reviewer comments are displayed
   - **rejected**: Rejection reason is displayed — revise and create a new approval

3. **Handle needs-revision** (if status was needs-revision):
   - Update tasks using reviewer comments, spawn the review subagent again
   - Submit a NEW approval request and run `/check-approval <newApprovalId> next:/spec-implement`

## Rules

- Feature names use kebab-case
- One spec at a time
- Tasks should be atomic (1-3 files each)
- Every task needs a `_Prompt` field with structured guidance
- Approval requests: filePath only, never content
- Never accept verbal approval — dashboard/VS Code extension only
- Never proceed if approval delete fails
