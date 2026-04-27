# Upstream Spec Content Expansion (K)

> マスター: `dapper-hardening-orchestrator.md` の根本原因 K
> Branch: `refactor/plugin-redesign-phase-a`
> Status: TODO（Pre-flight なし、retrofit 検証スキップ。改良後ワークフローで新規 spec を作成して検証）
> 起票日: 2026-04-28

## 目的

requirements.md / design.md（上流仕様書）の content を拡張し、下流 (J/I/H/D/E) が **明示宣言ベースで check 対象を判定**できるようにする。dojin-viewer 起点の問題分析で「下流が heuristic に頼っている根因は上流の content 不足」と判明した。

## 修正対象（マスタープラン K-1〜K-7 から転記）

### K-1: requirements.md の Acceptance Criterion に Test Layers フィールド追加

- [ ] `spec-requirements/SKILL.md` Step 4 に Test Layers フィールドの書式を追加
- [ ] `requirements-template.md` を更新（example 追加）
- [ ] `spec-verify/SKILL.md` 新規 Check 9: REQ_TEST_LAYERS_DECLARED

書式例（template に追加するもの）:
```markdown
### REQ-1: フォルダ一覧の表示
**User Story**: ユーザーとして、...

**Acceptance Criteria**:
1. WHEN ... THEN ... SHALL ... <!-- REQ-1.1 -->
   - Test Layers: UT, IT-1, ST-3, E2E-1
2. WHEN ... THEN ... SHALL ... <!-- REQ-1.2 -->
   - Test Layers: UT, CT, ST-3
```

### K-2: design.md DES-N に Required Test Layers フィールド追加

- [ ] `spec-design/SKILL.md` Wave 2 (Components and Interfaces) に `Test Layers` フィールドを追加
- [ ] `design-template.md` を更新（component 性質別の例: UI / backend / library / utility）
- [ ] `spec-design/SKILL.md` Step B 拡張: 「全 DES-N に Test Layers 宣言があるか」「test-design.md に対応する仕様があるか」

書式例:
```markdown
### DES-11: FolderTreePane
- Purpose: ...
- Interfaces: ...
- Dependencies: server fn list_folder, list_roots
- Reuses: ...
- Satisfies: REQ-1.1, REQ-1.2
- Test Layers: UT (toggle_expanded), CT (Resource + Suspense + on_select), ST-1 (folder navigation flow)
```

### K-3: design.md に「Architecture for Testability」セクション新設

- [ ] `spec-design/SKILL.md` Wave 2 に新規セクション規約追加
- [ ] `design-template.md` に 5 サブセクション例示（Mock points / Clock / RNG / External I/O / Test fixtures）
- [ ] `spec-design/SKILL.md` Step B 拡張: 「Architecture for Testability セクションが 5 サブセクション揃って存在するか」

5 サブセクション:
1. **Mock points**: trait 境界 / DI 注入点 / port-adapter 構造
2. **Clock injection**: `trait Clock` + `MockClock` / WASM の `js-sys::Date` 取扱い
3. **RNG injection**: `trait Rng` + `MockRng`
4. **External I/O isolation**: HTTP (mockito / wiremock) / fs (tempfile) / env (`dotenvy::from_path_override`)
5. **Test fixtures**: 共通 fixture の配置 / lifetime / clean-up 方針

I-2 (UT Properties Gate) との連携: I の lint で禁止される clock/RNG/env 直接呼出について、K-3 で宣言された Mock 経由のみ許可。

### K-4: design.md「Phase Deliverables」セクション必須化

- [ ] `spec-design/SKILL.md` Wave 1 に新規セクション規約追加
- [ ] `design-template.md` に Phase 別 deliverable + Test Layers + Smokeable の例示
- [ ] `spec-design/SKILL.md` Step B 拡張: 「全 Phase に Deliverable + Test Layers + Smokeable が記載されているか」

書式例:
```markdown
## Phase Deliverables

### Phase 1: Core domain (Rust crate)
- Deliverable: `crates/shared` の DTO + validation
- Test Layers: UT (Negative Assertions 含む)
- Smokeable: cargo build --lib

### Phase 2: HTTP server
- Deliverable: `crates/server` の axum endpoints
- Test Layers: UT, IT (HTTP), smoke (L1 + L2 wiring)
- Smokeable: server boot + /health

### Phase 3: ...
```

E-2 の Phase Deliverable 部分は K-4 に統合済（E-2 は smokeable check のみ）。

### K-5: requirements.md NFR に「Testability」必須化

- [ ] `spec-requirements/SKILL.md` Step 4 の Non-Functional Requirements に Testability を追加
- [ ] `requirements-template.md` の NFR セクションに Testability を必須項目として追加
- [ ] `spec-requirements/SKILL.md` Step 5 (self-review Check 3) で 6 観点（既存 5 + Testability）を必須化

記載内容:
- 全 REQ が UT で verify 可能か（不可なら理由 + どの層で代替）
- External I/O / Clock / RNG / 並列性 / 状態を持つ component の testability 戦略
- Test fixture / mock の責任範囲

### K-6: spec-design Step B (self-review check) の総合拡張

- [ ] 既存 check に追加:
  - 全 DES-N に Required Test Layers が宣言されているか
  - Architecture for Testability セクションが存在し 5 サブセクションが揃っているか
  - Phase Deliverables セクションが存在し全 Phase をカバーしているか
  - 各 Phase Deliverable の Test Layers が test-design.md と整合（forward reference）するか

K-2 / K-3 / K-4 の各 check はそれぞれの sub で個別記載するが、Step B での統合運用（実行順序 / error/warn 分類）は K-6 で確定する。

### K-7: spec-test-design Subagent を「明示宣言ベース」に切替

- [ ] `spec-test-design/SKILL.md` 全 Subagent (A: UT / B: IT / C: E2E / D: CT [H 後] / E: ST [J 後]) の derivation 入力に「design.md の Required Test Layers 宣言」を最優先で読み込むロジックを追加
- [ ] **宣言外の層を導出しない**（heuristic 排除）規約を明示
- [ ] フォールバック: design.md に Test Layers 宣言が無い（legacy）場合のみ heuristic で derivation

依存: K-2 (DES-N の Test Layers field 必須化) が前提。J (taxonomy 確定) と H (Subagent D 新設) と J-6 (Subagent E 新設) も先行必要。よって K-7 は K の最後 + J/H の関連 sub-task が完了してから着手。

## 完了記録

（実装が進むにつれて追記）

| 日付 | sub-task | commit | 備考 |
|------|---------|--------|------|
| 2026-04-28 | （前提）J-3 Test Taxonomy セクション先行 | e0d3279 | `quality-checks.md` に挿入済。K-1/K-2/K-4 が参照する taxonomy 正規定義 |
| 2026-04-28 | K-1: REQ Acceptance Criterion に Test Layers field 追加 | 1dfbb1c | spec-requirements SKILL.md / requirements-template.md / spec-verify Check 8 を更新。Check 番号は 9→8 に調整（C 未実装のため） |
| 2026-04-28 | K-5: NFR Testability 必須項目 | 1dfbb1c | spec-requirements SKILL.md self-review check 3 / requirements-template.md NFR セクション を更新 |
| 2026-04-28 | K-2: DES-N に Required Test Layers field | （未 commit） | spec-design SKILL.md Wave 2 / design-template.md DES-1/2 example を更新 |
| 2026-04-28 | K-3: design.md Architecture for Testability section 新設 | （未 commit） | spec-design SKILL.md Wave 2 / design-template.md に 5 サブセクション必須化 |
| 2026-04-28 | K-4: design.md Phase Deliverables section 必須化 | （未 commit） | spec-design SKILL.md Wave 1 list に追加 / design-template.md に section example |
| 2026-04-28 | K-6: spec-design Step B (self-review check) 拡張 | （未 commit） | check 10/11/12 (Test Layers / Architecture for Testability / Phase Deliverables) 追加 |
| 2026-04-28 | K-7: spec-test-design Subagent 明示宣言ベース化 | （これから commit）| Section 4 冒頭に「明示宣言ベースの derivation」記載。各 Subagent (A/B/C/E) が design.md / requirements.md の Test Layers 宣言を最優先で読み込む。Subagent D は H 後に同パターン適用 |

## 影響範囲

- `spec-requirements/SKILL.md` + `templates/requirements-template.md`
- `spec-design/SKILL.md` (Wave 1 + Wave 2) + `templates/design-template.md`
- `spec-test-design/SKILL.md` (Subagent 全体)
- `spec-verify/SKILL.md` (新規 Check 9)
- 既存 spec の retrofit: warning（`spec-verify --legacy-tolerant` で段階移行）

## 注意

- K-7 は K の中で順序的に最後（K-2 必須、J / H の関連 sub-task に依存）
- K の他の sub (K-1〜K-6) は概ね並列着手可能
- template の例示は Rust / Leptos に偏らず、Node.js / .NET でも通用する形で記述

## 関連

- マスタープラン: `dapper-hardening-orchestrator.md` 根本原因 K (line 725 〜)
- 関連 sub-plan: `test-taxonomy-and-st-introduction.md` (J), `component-test-layer-introduction.md` (H)
