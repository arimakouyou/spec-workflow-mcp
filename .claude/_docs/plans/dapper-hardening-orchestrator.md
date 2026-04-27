# dojin-viewer 実行で露呈した spec-workflow 弱点と対策計画

> 起票日: 2026-04-27
> 対象: `spec-workflow-mcp` プラグイン（spec-driven workflow）
> ブランチ: `refactor/plugin-redesign-phase-a` 上で起票（実装は新ブランチで個別 spec 化推奨）
> 関連: `plan-redesign-overall-progress.md`（plan-redesign 16 項目はクロージャ済み。本 plan は運用フィードバック起点の補強）

## 背景

公開ワークフローを `/home/arimakouyou/tmp/dojin-viewer`（Leptos フルスタック画像ビューアー）の実装で運用したところ、13 件の不具合・不快事象が連鎖的に発生した。13 件 → **10 個の根本原因（A〜K、ただし G は E に統合済み）** に収束することを確認した。本 plan は各根本原因について「症状 / 原因 / 修正対象 / 提案変更 / 影響範囲」を整理し、後続セッションで個別 spec 化するための見取り図を提供する。

実装は本 plan では行わない。優先順位を確認した上で、項目ごとに `/spec-request-spec` から Phase 0 を起こすこと。

### ユーザー指摘で構造変更した点（重要）

#### 1. Smoke Gate の 3 重問題（E に統合）

初版で「Smoke Test SKIP は仕様通り、透明性追加で済む」と整理したのは表面的だった。ユーザー指摘により以下が同根の 3 重問題と判明し、E を全面再設計項目に格上げした:

- `spec-implement/SKILL.md` L325 / L1024 の「Smoke Test は API プロジェクトのみ」は **narrow すぎる**。Library / CLI / UI でも boot 確認は意味がある
- 「HTTP server が無い Phase で SKIP は正解」という判定自体が誤り。**何も smoke できない Phase は Phase 境界の設計問題** であり、silently SKIP は隠蔽
- API 実装時の Phase Review smoke は `/health` のみで薄い。`L1024` の Final smoke が GET endpoint も叩く深さを持つのに、Phase Review に降りていない

さらに「API GET しか見ないのか / Ping だけか / 引数境界はチェックしないのか」のユーザー指摘により smoke の深さを 4 層化（L1: Health / L2: Wiring 全 method / L3: Auth / L4: 入力境界）。詳細は E セクション。

#### 2. テスト責務階層の構造的欠陥（H として新設）

ユーザー指摘「実装時に何をテストして OK としたのか」を受けて dojin-viewer の実テストを調査した結果、構造的欠陥が判明し H を新規追加した:

- 全 6 component の UT が **100% pure helper のみ**（detail_viewer 39 件 / folder_tree 7 件 / thumbnail_grid 14 件 など全件）
- **component reactivity（Resource / Signal / Effect / event handler 統合）テストはゼロ件**
- `frontend-test-engineer/agent.md` L104-112 が **明示的に**「`view!` / DOM 配線 / Suspense / Resource / hydration は **すべて E2E の責務**」と定めている
- E2E は Final Gate でのみ走る → Phase 内フィードバックループから脱落
- task `_Success` が「UT PASS + grep "Resource::new" 文字列存在」のような **grep ベース判定** で完結する構造
- 結果として「pure helper UT + grep 通過 = `[x]` 完了」が成立し、placeholder view! でも commit 可能だった

これは個別実装者の問題ではなく、**仕様（test-design.md / frontend-test-engineer / spec-tasks _Success template）が明示的にこの行動を許容していた構造的結果**。H で UT と E2E の中間に **CT (Component Test) 層** を導入する。

#### 3. UT 品質特性の暗黙性（I として新設）

ユーザー指摘「**実装時の UT はコードが動作するか（cargo test PASS）ではなく仕様の検証**である。UT は仕様を満たすだけでなく **仕様外の挙動をしない** ことも確認する。**外部依存を持たず**、**何回・どんな順で実行しても結果が同じ**」を受けて確認した結果、現状の spec-workflow がこれらを **明示的には enforce していない** ことが判明:

- `_TestFocus` の 4 カテゴリ（Happy Path / Boundary Values / Error Handling / Edge Cases）は positive assertion 寄りで、**Negative Assertions（仕様外の挙動が起きないことの確認）を明示していない**
- 外部依存ゼロ（FIRST の Isolated）は「pure logic 抽出」で **副次的に**成立しているだけで、enforce ではない
- 順序非依存（FIRST の Independent）は `cargo nextest --shuffle` のような検証が CI に組み込まれていない
- 決定性（FIRST の Repeatable）は clock / RNG モックの強制が無い

I で `_TestFocus` を 6 カテゴリに拡張し、`quality-checks.md` に「UT Properties Gate (QC15)」を新設して `cargo nextest --shuffle` + clock/RNG/env/fs/HTTP の直接呼出 lint を CI gate 化する。

#### 4. テスト分類の責務範囲混乱と ST 層欠落（J として新設）

ユーザー指摘「**E2E が IT になっている / E2E は全体の動作の流れを検証するもので個々の機能の確認は行わない / 現状 IT が無い / ST 入れたほうがいい / 機能テスト + リグレッションテスト**」を受けて確認した結果、4 重の混乱が判明:

- **E2E が個別機能テスト化**: dojin-viewer の e2e-* 11 件中 9 件が個別機能テスト（zoom/rotate, info panel, errors, container smoke, localStorage 等）。真の E2E は 2 件のみ
- **IT 仕様が「server fn 経由」と「HTTP 経路」を混在**: IT-1, IT-7 等がフロントの Resource → server fn 境界を含む不純 IT。ユーザー認識「IT は backend を **フロントとは別に**」と乖離
- **ST (System Test) 層が完全欠落**: spec-workflow 全体に System Test の言及ゼロ。E2E を狭めると個別機能 full-stack テストの責務が宙に浮く
- **Regression は既存 skill があるが taxonomy 統合が weak**: `regression-test-policy/SKILL.md` で RT1/RT2/RT3 と命名規則 `regression_issue_NNN_*` が定義済だが、**新 taxonomy への組込み + CI gate 化** が未実施

J でテスト分類を **UT / CT / IT / ST / smoke / E2E + Regression（cross-cutting type）** として正規定義し、ST 層を新設、regression を全層に横断適用させる。

#### 5. 上流仕様書の内容不足（K として新設）

ユーザー指摘「**仕様書作成は修正しなくても大丈夫？**」を受けて確認した結果、既存項目 (C/D/E/F/H/I/J) が **下流（test-design / tasks / spec-verify）に集中**しており、上流（requirements / design）の content が薄いことが判明:

- requirements.md に **Acceptance Criterion ごとの Test Layers 宣言**が無い → 「どの REQ が UT/CT/IT/ST/E2E のどれで verify されるか」が implicit
- design.md DES-N に **Required Test Layers** フィールドが無い → spec-test-design Subagent が heuristic で test 層を判定
- design.md に **「Architecture for Testability」セクション**が無い → mock 点 / clock 注入 / DI 設計が記載されないため、I (Isolation Properties) を当てる先が曖昧
- design.md に **「Phase Deliverables」セクション**が無い → 各 Phase が「何を作る + どの test 層で検証する」を一元宣言できない（E-2 で部分提案、K-4 に統合）
- requirements.md NFR に **Testability 観点**が必須化されていない

K で上流の content を拡張し、下流の J/I/H/D/E が **明示宣言ベースの check 対象**に当てられる構造にする。

---

## 根本原因 A: LLM 挙動の幻覚（仕様にない概念の発明）

### 症状（issue #1, #2）

- Wave 1 完了後に「Auto Mode のため、ユーザー確認を省略して Wave 2 へ進みます」と進行された（ユーザーは Auto Mode を指示していない）
- 「10〜20 時間必要」と説明した直後に「続行します」とユーザー確認なしで Phase 0 を進めた

### 原因

- `spec-design/SKILL.md:223` は明確に `If the direction looks good, reply "continue". If changes are needed, please provide specific instructions.` とユーザー確認を要求している
- `spec-implement/SKILL.md` 全体に「Auto Mode」概念は **存在しない**（`auto-resume.sh` はレートリミット時の wrapper 再起動専用で、ユーザー確認スキップとは無関係）
- つまり dojin-viewer 側の Claude が **存在しない概念を発明してユーザー確認を省略した**（LLM hallucination）。spec を書き換えても再発する性質の問題

### 修正対象 / 提案変更

| 対象 | 変更内容 |
|------|----------|
| `spec-design/SKILL.md` Step 4 (L199-230) | **Negative example** を追記：「『Auto Mode』『継続モード』など、本仕様に存在しない概念を発明してユーザー確認をスキップしてはならない。Wave 1→2 の遷移は user reply `continue` でのみ許可される」 |
| `spec-implement/SKILL.md` Task Cycle 冒頭 | 同様の negative example：「Phase 進行・Wave 進行・大規模並列起動の前は必ず user confirmation を取る。`auto-resume.sh` はレートリミット復旧専用であり、ユーザー意思確認の代替ではない」 |
| `.claude-plugin/hooks/` 新規 `confirm-phase-progression.sh`（PreToolUse on Agent or Stop） | "Wave (1→2|2→3)" "Phase \d+ (完了|continue)" のような進行宣言を含むレスポンスを検出し、直前の user prompt が「continue / yes / 進めて」等の明示同意でない場合は **block + user に確認を求める** |

### 影響範囲

- 表面的には spec-design / spec-implement の 2 skill だが、根は LLM の解釈逸脱なので **negative example が他の skill にも波及する可能性**（特に Approval workflow を持つ他 skill）。Hook での捕捉が確実
- false positive のリスク: ユーザーが先回りして `continue` 済みのケースで block されると煩雑。前 N 行 user message を遡って同意があるか確認する logic が必要

---

## 根本原因 B: Worktree 間 bookkeeping 同期欠落

### 症状（issue #3）

- Phase 1 終了時、main 側 `tasks.md` の `[x]` マーク更新と `Implementation Logs/` の更新が未コミットで残った
- 次の PhaseReview worktree は HEAD から派生するため、main の未コミット差分は worktree に持ち込まれず、`git add -A` でも回収されない

### 原因

- `spec-implement/SKILL.md:402-475` の PhaseReview フローで worktree を新規作成するが、**作成前に main 側 bookkeeping をコミットする手順が無い**
- `spec-implement/SKILL.md:959-969` の `session-manage.sh complete-task` は session JSON のみ更新で、tasks.md / Implementation Logs を git commit しない
- orchestrator (本体 Claude) が main 上で `[x]` マーク・log を書き込み、worktree で commit を取る分離なので、bookkeeping が両者の隙間に落ちる

### 修正対象 / 提案変更

| 対象 | 変更内容 |
|------|----------|
| `spec-implement/SKILL.md` Step 3.5.2 冒頭 (PhaseReview 直前) | 新規ステップ「3.5.0 Bookkeeping Commit」を追加。<br>`git status --porcelain` で `.spec-workflow/specs/{spec-name}/{tasks.md,Implementation Logs/**}` に差分があれば `git add` + `git commit -m "chore({spec-name}): bookkeeping for phase {N}"` を main 上で実行。<br>その後で worktree を切る |
| `spec-implement/SKILL.md` Step 8 (Per-task complete) | 同様に「main 側 bookkeeping を per-task で flush する」micro-commit を追加するか、PhaseReview 集約に統一するか選択。**集約方式推奨**（micro-commit はノイズ） |
| `review-worker/agent.md` PhaseReview 受け口 | bookkeeping commit の存在を前提として review 範囲から除外することを明記 |

### 影響範囲

- 既存のレビュー粒度には影響なし（bookkeeping は機械的更新なのでレビュー対象外）
- worktree merge 時のコンフリクト確率は微増（main 先行 commit があるため）。rebase or merge 戦略の選択が必要

---

## 根本原因 C: spec 間 semantic 整合性チェックの欠如

### 症状（issue #4, #6）

- design.md DES-3 が `pub async fn list_roots(&self) -> Result<Vec<RootEntry>, AppError>` と定義しているのに、test-design.md UT-3.4 と実装が `Vec<RootEntry>`（Result ラップなし）で書かれていた
- design.md DES-11/12/13/15 で `RelativePath` 型が interface に登場するが、Data Models セクション（MOD-1〜MOD-7）に型定義が無い

### 原因

- `spec-test-design/SKILL.md` は design.md の Components セクションを読むが、**型シグネチャの完全一致を強制する自動チェックが無い**
- `spec-design/SKILL.md` Step B self-review (Check) は「全 component が記載されているか」「frontmatter が valid か」までで、**「interface の引数・戻り値型に登場する型がすべて MOD-N で定義されているか」のチェックが無い**
- `spec-verify/SKILL.md` Check 2 (reference integrity) は ID（DES-N / MOD-N / API-N）レベルの参照のみ追跡し、**型シンボルレベルの整合性は対象外**

### 修正対象 / 提案変更

| 対象 | 変更内容 |
|------|----------|
| `spec-design/SKILL.md` Step B (self-review check) | 新規 Check 項目: 「`### DES-N:` 内 `Interfaces:` フィールドの型シグネチャに登場する全カスタム型（`Result<X, E>`, `Vec<T>`, `Signal<T>` の `X`/`T`/`E`）が、同じ design.md 内 `### MOD-N:` または既知の標準ライブラリ型として定義されているか」 |
| `spec-test-design/SKILL.md` Step B (Check 12: container consistency) の隣 | 新規 Check 13: 「test-design.md の各 UT/IT/E2E 仕様で参照される関数シグネチャ（戻り値型・引数型）が design.md DES-N の Interfaces 定義と完全一致するか」（**Check 13 は C-2 が確保**） |
| `spec-verify/SKILL.md` 新規 Check 8 | 「Type Reference Resolution」: design.md interface セクションを正規表現で型抽出し、MOD-N + 標準ライブラリの allowlist と突合。未定義型を `error: undefined_type_reference` として報告。test-design.md 側の関数シグネチャも design.md DES-N と diff し、不一致を `error: signature_mismatch` として報告 |

### 影響範囲

- spec-verify の処理時間が増加（design.md/test-design.md の type 抽出パース必要）。1 spec あたり数百ミリ秒程度の見積
- false positive: 標準ライブラリ allowlist の網羅性次第。Rust なら `std::*`, `core::*`, `alloc::*` + よく使うクレート（`tokio`, `serde`, `leptos`）を allowlist 化必要

---

## 根本原因 D: DES-N → tasks.md `_Prompt` 翻訳の欠落（最大レバレッジ）

### 症状（issue #7, #10, #12, #13 の予防）

- design.md DES-11 (FolderTreePane) の `Dependencies: server fn list_folder, list_roots` は `_Leverage` には載るが、tasks.md task の `_Prompt.Task` に「`list_roots` を呼び出して root ID を流入させる」が書かれず、配線が後続 Phase に punt された
- AppRoot のような「全 component を組み立てる top-level component」が design.md DES-10 にあるのに、tasks.md に「合成 task」が単独で起票されず、Phase 4 の各 component 実装後に wire-up 工程が宙に浮いた
- 各 component 実装 task の `_Prompt.Success` が「pure helper の unit test PASS」レベルで止まり、「実 view! が `<img>` をレンダリングする」「event listener を attach する」が Success 基準として強制されなかった

### 原因

- `spec-tasks/SKILL.md` Step 7 (self-review check) の `Check 3: CROSS-REFERENCE` は **「every design component must have at least one creating task」** までで、「component の Dependencies 列に列挙された依存が _Prompt の Task 文に明記されているか」までは追跡していない
- 同 Check に **「top-level component の合成 task が独立して存在するか」も無い**
- _Prompt template (Step 4 Generate _Prompt Fields, L258-318) は Role/Task/Restrictions/Success の構造のみ強制し、UI 配線特化（data-testid, event wiring, server fn 呼び出し）の Success 基準テンプレートを持たない

### 修正対象 / 提案変更

最大レバレッジ。13 件中 4 件をここで予防できる。

| 対象 | 変更内容 |
|------|----------|
| `spec-tasks/SKILL.md` Step 7 Check 3 拡張 | 「每 DES-N の `Dependencies:` 列に列挙された全 server fn / 外部 API / 兄弟 component が、対応 task の `_Prompt.Task` 文に **「{依存名} を呼び出す/統合する/受け取る」と明示文字列で記載されているか**」を追加 |
| `spec-tasks/SKILL.md` Step 7 新規 Check 14: COMPOSITION_TASK | 「design.md の Component List に top-level (root) component（例 AppRoot, MainShell, RootRoute）が存在する場合、その配下 component を子要素として組み立てる **専用の composition task** が tasks.md に存在するか。task の `_Prompt.Task` には『N 個の子 component を view! 内に配置し、prop / signal を配線する』ことと、`_Prompt.Success` には『すべての子 component が DOM tree に出現する E2E スモーク（後続 Phase で）が成立する前提を満たす』ことを明記」 |
| `spec-tasks/SKILL.md` Step 7 新規 Check 15: UI_OBSERVABILITY | 「UI component task の `_Prompt.Success` には『data-testid を {期待値} で付与する』『実 view! が {要求要素 (`<img>`, `<button>`, etc.)} をレンダリングする』が含まれているか。test-design.md の E2E 仕様で `getByTestId(...)` 参照されている testid が、対応する component task の `_Prompt.Success` に明示されているか」 |
| `spec-tasks/SKILL.md` Step 4 _Prompt template に **UI Component セクション** を追加 | UI component / 統合 task 用の _Prompt テンプレートを別 section として明示（既存の DevOps / Backend Developer の例の隣に「Frontend Component Engineer」テンプレを追加） |
| `spec-tasks/SKILL.md` Step 7 新規 Check 16: FIXTURE_REALIZATION | 「test-design.md の Test Data Requirements に列挙された fixture path（`tests/fixtures/...`, `photos/landscape/...`）が、いずれかの task の File 列または `_Prompt.Task` 文で生成・配置される旨が記載されているか」 |

### 影響範囲

- self-review 1 回あたりの opus check が重くなる（Check 12 〜 16 で 5 項目追加）が、これは spec-implement の rework サイクル数十回より遥かに安い
- 既存 spec の retrofit 圧力: 既存 tasks.md は新 Check で warn 多発する可能性。`spec-verify --legacy-tolerant` 相当のフラグで段階的移行を許す

---

## 根本原因 E: Smoke Gate の全面再設計（旧 E + G 統合）

### 症状（issue #5, #11, #13）

- **#5（旧 G）**: 「3.5.1.5 Smoke Test ⏭ SKIP (設計上不要) — Phase 2 には HTTP server なし」と silently SKIP された。ユーザーの違和感は当然で、3 つの問題が重なっている:
  1. **Smoke 定義が API プロジェクト限定**: Library / CLI / UI / WASM など HTTP server を持たないプロジェクトで smoke が「ない」扱い
  2. **HTTP server が無い Phase = SKIP 正解、という判定が誤り**: Phase 2 で何も smoke できる成果物が無いこと自体が **Phase 境界の設計問題**。silently SKIP は設計欠陥の隠蔽
  3. **API 実装時の smoke が薄い**: spec-implement L325 (Phase Review) は `/health` のみ。L1024 (Final E2E Gate Step 4) は実装済み endpoint も ping するが、Phase Review でその深さは無い。Phase 内で API endpoint の placeholder 実装が見逃される
- **#11**: component が `cargo build / clippy / unit test` PASS で `[x]` 完了するが、view! が `<img>` を出力しない placeholder 状態でも commit 可能
- **#13**: Phase 4 個別実装は通っても App ↔ FolderTree ↔ ThumbnailGrid の signal 連動 runtime バグが unit test で検出不能

### 原因

- `spec-implement/SKILL.md` L325（Phase Review smoke）と L1024（Final smoke）の両方で **「API プロジェクトのみ」と固定**
- `quality-checks.md` には smoke 自体の定義が無く、spec-implement にハードコードされている
- 「Smoke Test SKIP (設計上不要)」の判定基準が「`### IT-` 見出しがゼロ件」のような **存在ベース** のみ。「Phase の deliverable に対して smoke 可能か」という **能動評価** が無い
- Phase 単位の deliverable が design.md / tasks.md で明示的に宣言されていない → 「この Phase で何ができるべきか」が不明確 → smoke が空でも検出不能

### 修正対象 / 提案変更

最重要項目に格上げ。3 層で対策する:

#### E-1: Smoke 定義の project-type 別 + HTTP method 全覆 + 入力境界対応

##### E-1-a: API smoke の全 method 対応 + 入力境界 smoke

既存の Final E2E Gate (L1024) と Phase Review (L325) は **両方とも GET endpoint のみ ping** という重大な不足がある。POST/PUT/PATCH/DELETE は smoke から除外され、wiring バグや 5xx クラッシュは E2E まで気付けない。

API smoke を以下の 4 層で再定義する:

| 層 | 内容 | 期待結果 | 失敗の意味 |
|---|------|---------|----------|
| **L1: Health** | `/health`, `/api/health`, `/healthz` への GET | 200 | サーバ起動失敗 |
| **L2: Wiring smoke (全 method × 全 endpoint)** | design.md の各 `### API-N:` から path / method を抽出。method 別に最小リクエスト送信:<br>・**GET**: クエリなし<br>・**POST/PUT/PATCH**: 空ボディ `{}` または `{}` を `Content-Type: application/json` で送信<br>・**DELETE**: パス末尾にプレースホルダID（`/users/00000000-0000-0000-0000-000000000000`） | **2xx / 3xx / 4xx いずれか（5xx 禁止）**<br>・存在しない ID で 404 OK<br>・必須フィールド欠落で 400/422 OK<br>・正常入力で 2xx/3xx OK | **5xx は wiring バグ**: ハンドラ未配線 / DI 不整合 / DB connection 不通 / panic 不処理 |
| **L3: Auth smoke** | design.md の各 endpoint で「Auth: required」のもの → Authorization ヘッダなしで送信 | 401 | 401 以外 = 認可漏洩（200 が返ったらセキュリティ事故） |
| **L4: 入力境界 smoke** | design.md API 定義から各引数（path/query/body field）の **型境界値** を 1 件ずつ生成して送信:<br>・String 必須: 空文字 `""`<br>・String maxLength: 制限+1 文字<br>・int min/max: ±1 オーバーフロー<br>・enum: 未定義値<br>・Optional 省略 | **400/422（5xx 禁止）**<br>境界に応じて適切な validation error が返る | **5xx は validation 不足**: serde の `#[serde(deny_unknown_fields)]` 漏れ / 型変換 panic / null 処理漏れ |

**重要な責務分離**:
- L1〜L4 は **smoke の責務**（実装の "電源を入れて煙が出るか"）。最小入力 / 境界入力で 5xx を出さないことを確認するだけ
- **「正常系の business logic（POST で作成した entity が GET で取得できる）」は smoke の責務外**。これは IT (Integration Test) で test-design.md に従って検証
- **「複合境界 / 値ペアの境界（min × max の組合せ等）」も smoke の責務外**。IT/UT で検証
- L4 の境界 smoke は **「型に対する境界」だけ**で、ビジネス境界（例: `user.age` は 18〜120）は test-design.md の UT/IT 仕様で検証する

##### E-1-b: その他 project-type の smoke 定義

| project-type | Smoke 内容 |
|------|----------|
| **Library (Rust crate / npm package)** | `cargo build --lib --release` + `cargo doc` + 公開 API に対する「import + 1 メソッド呼び出し + 引数境界 1 件」doctest スモーク |
| **CLI** | `<binary> --help` / `<binary> --version` + 主要サブコマンドの `--help` + 必須引数欠落で exit code 非ゼロ + 不正引数で 5xx 相当の panic ではなく構造化エラーが返ること |
| **UI / Frontend (Leptos client-only / Blazor WASM)** | WASM bundle build + headless browser で初期 render + 全 `data-testid` 要素が DOM 出現 + 各 form input に「型境界値」入力で client-side validation が発火すること |
| **Full-stack (Leptos SSR / Next.js)** | 上記 API smoke (L1〜L4) + UI smoke の組み合わせ |
| **Worker / Daemon** | バイナリ起動 + 30 秒の crash-loop 監視 + 終了 + キュー入力で「不正メッセージ」を投入し dead letter queue / retry mechanism が機能すること |

##### E-1-c: spec-implement への組み込み

| 対象 | 変更内容 |
|------|----------|
| `quality-checks.md` 新規セクション「Smoke Test Definition」 | E-1-a / E-1-b の定義を一元記載。spec-implement / parallel-worker / review-worker から参照される |
| `spec-implement/SKILL.md` Step 3.5.1.5 Step D を全面改訂 | 「API プロジェクトのみ」という固定を撤廃。`quality-checks.md` の Smoke Test Definition を参照し、Step 0 で検出済みの project-type に応じた smoke を L1〜L4 全層で実行 |
| `spec-implement/SKILL.md` Step 9.2 Step 4 (Final Smoke) も同様に拡張 | Phase Review smoke と同じ深さを使う。「Phase Review は当該 Phase 実装分のみ」「Final Gate は全 deliverable」というスコープ差のみ |
| `spec-design/SKILL.md` API Design セクションの記述粒度強化 | 各 `### API-N:` で「Auth: required / public」「Path / Query / Body の各引数の型境界」を smoke runner が機械パース可能な形式で書く規約を追加（OpenAPI 風スキーマ参照を推奨） |
| 新規ツール `smoke-runner` (scripts) | quality-checks.md の Smoke Test Definition を読み込み、design.md API 定義から L1〜L4 のリクエストを自動生成して実行する utility |

#### E-2: Phase 別 smokeable 必須化（Phase Deliverable 定義は K-4 に統合済）

> **整合性メモ**: 「design.md Phase Deliverables セクション」自体の新設は **K-4 に統合**された。E-2 は smoke 観点（smokeable 必須化 + SKIP 禁止 + Final Gate レポート）のみを扱う。

| 対象 | 変更内容 |
|------|----------|
| `spec-tasks/SKILL.md` Step 7 新規 Check 17: PHASE_SMOKEABLE | 「各 Phase の最後の `_PhaseReview: true_` task の前に、その Phase で smoke 可能な deliverable が **少なくとも 1 件存在するか**。design.md の Phase Deliverables（K-4 で必須化）と突合し、Phase が deliverable ゼロの場合は **escalate**（Phase 境界の見直し提案）」 |
| `spec-implement/SKILL.md` Step 3.5.1.5 結果判定テーブルに新項目 | 「**`SKIP (設計上不要)` を許可しない**」（少なくとも Phase Review smoke では）。Phase に smoke 対象が無い場合は SKIP ではなく **escalate (Phase deliverable 不在)** として扱い、ユーザーに Phase 分割の見直しを提案 |
| Final E2E Gate (Step 9) 結果判定 | Final Gate では SKIP 許容するが、その理由を「design.md Phase Deliverables（K-4 定義）を実装フェーズで進めなかった理由」とともにレポートに残す |

#### E-3: UI / 配線特化 smoke と段階的成長

| 対象 | 変更内容 |
|------|----------|
| `quality-checks.md` 新規 QC14: UI Smoke Render | playwright で `await page.goto('/'); expect(await page.locator('[data-testid]').count()).toBeGreaterThan(N)` （N は design.md Phase Deliverables から計算）。Phase 進行に応じて要求 testid 数が増える |
| `parallel-worker/agent.md` の Success criteria | UI component task の場合、worktree 内で `cargo leptos build` 等の最終ビルド + 「対象 component の data-testid が compiled HTML に出現する」grep check を Success 条件に含める。E2E より軽量・worktree 内で完結 |
| Phase Review 失敗時の差し戻しルール（L292-294）に新規分類 | 「FAIL (placeholder detected)」: smoke gate で testid が想定数より少ない / 特定 testid が欠ける / view! が要求要素を出力していない場合、該当 component の実装 task を `[-]` に戻して rework |
| smoke の Phase 別成長を `quality-checks.md` に明示 | smoke は静的ではなく Phase 進行で深まる。各 Phase Review smoke は「**この Phase で新たに作った deliverable**」を smoke 対象に追加する増分方式。Phase 1: lib import / Phase 3: lib + API ping / Phase 5: lib + API + UI render |

### 影響範囲

- 既存 spec の retrofit 圧力: design.md に Phase Deliverables セクションが無い既存 spec は warning（spec-verify legacy-tolerant）。新規 spec から強制
- false positive のリスク: Phase 0 (Project Setup) のような構築系 Phase は「smokeable deliverable」を CI workflow / Dockerfile build success として扱う必要あり。例外規約を `quality-checks.md` に明記
- Phase Review の所要時間が増える（30 秒〜数分）。許容範囲
- **副作用として Phase 設計の質が向上する**: 「smokeable deliverable を持たない Phase は escalate」というルールは、Phase 境界の見直しを強制し、結果として spec-design の精度を上げる

### 「API 実装時に何をテストする？」への直接回答（改訂版）

ユーザー指摘で初版回答（GET ping のみ）が不足と判明。改訂版:

| 項目 | 既存仕様 | 改訂後 |
|------|---------|--------|
| **対象 method** | GET endpoint のみ（L325 / L1024） | **全 method (GET/POST/PUT/PATCH/DELETE)** に対して smoke を実行 |
| **L1 Health** | 既存 | 変更なし |
| **L2 Wiring smoke** | （存在しない） | 全 endpoint × 全 method で「最小リクエストで **5xx を出さない**」を確認。POST/PUT/PATCH は空ボディ `{}`、DELETE はプレースホルダ ID。期待は 2xx/3xx/4xx |
| **L3 Auth smoke** | 既存（GET のみ） | 全 method に拡張。Authorization なしで 401 が返ること |
| **L4 入力境界 smoke** | （存在しない） | 各 path / query / body field の **型境界値** を 1 件ずつ送信し、5xx ではなく適切な 400/422 が返ること。境界は「String empty / maxLength+1 / int overflow / enum 未定義値 / Optional 省略」 |
| **正常系 business logic** | IT 仕様 | smoke 責務外。IT で test-design.md に従って検証 |
| **複合境界・値ペア境界** | UT/IT 仕様 | smoke 責務外。UT/IT で検証 |
| **ビジネス境界（例: user.age 18〜120）** | UT/IT 仕様 | smoke 責務外（型境界とは区別）。UT/IT で検証 |

#### 「ping だけ」と「IT」の中間に smoke を置く設計意図

- **smoke の役割**: wiring 検証 + 5xx 防止 + 型境界の panic 検出。**実装の "電源を入れて煙が出るか"** という原義に忠実にする
- **「ping のみ」は smoke ではなく health check**。L1 だけでは smoke の役割を果たしていなかった
- **smoke は IT より速く、UT より広い**: UT は単一関数、IT は fixture と業務シナリオを必要とするが、smoke は「全 endpoint × 全 method × 型境界 1 セット」を fixture なしで一気に走る。所要 30 秒〜2 分

#### 「引数境界はチェックしないのか？」への回答

**型境界 (type-level boundary)** は smoke の責務に含める（L4）。**ビジネス境界 (business-rule boundary)** は IT/UT の責務。

- 型境界の例: String の空文字 / maxLength+1 / int overflow / enum 未定義値 / null / Optional 欠落 / 不正な UUID 形式
  - これらで **5xx が返ったら validation 層のバグ**。smoke で検出
- ビジネス境界の例: 年齢 18〜120、ユーザー名 3〜32 文字、注文数 1〜1000、割引率 0〜100%
  - これらは **アプリ仕様の境界**で、test-design.md の UT-N / IT-N 仕様で扱う

両者の差は「型システムが本来発見すべきもの」か「アプリ仕様が決めるもの」か。smoke は前者の漏れを fixture なしで検出するレイヤー。

---

## 根本原因 F: test-design self-review の薄さ

### 症状（issue #8, #9）

- 5.5 UT 検証で「photos/landscape のフィクスチャ記述が実態と不整合」「subfolder lazy-load 経路が到達不能」という乖離
- 5.2 E2E 検証で `snapshotPathTemplate` 未設定 / VRT-4 のシナリオ再現性 / `toMatchAriaSnapshot` ではなく `toContain` 部分一致など、**Playwright 固有のベストプラクティス違反**が複数発見

### 原因

- `spec-test-design/SKILL.md` Step B Check 1〜12 は構造（traceability / matrix / container consistency）が中心で、**E2E framework 固有の品質チェック（snapshot path / aria snapshot / シナリオ steps の DOM 検証粒度）が無い**
- Test Data Requirements は記述するが、実体ファイルとの照合は最終 E2E Gate でしか行われない（D 項目の Check 16 で前倒しする方向と整合）

### 修正対象 / 提案変更

| 対象 | 変更内容 |
|------|----------|
| `spec-test-design/SKILL.md` Step B Check 14〜16 を新設 | 14: 「E2E spec で snapshot 比較を使う場合、`snapshotPathTemplate` を `playwright.config.ts` で `tests/e2e/screenshots/{testFilePath}/{arg}.png` 等に固定する旨が test-design.md にも記載されているか」<br>15: 「DOM 構造比較は `toContain` の部分一致ではなく `toMatchAriaSnapshot` を使う旨を、構造的回帰検出が必要な仕様で明示する」<br>16: 「シナリオ steps が『中央 2 枚表示中、左開き』のような **複合状態** を要求する場合、その状態に至るまでの操作（NAV_NEXT N 回 + 設定変更）が test-design.md に明記されているか」<br>※ Check 13 は C-2 が確保済のため F は 14〜16 を使用 |
| `spec-test-design/SKILL.md` Step 5 Test Data Requirements | fixture を path だけでなく **「期待構造」**（ディレクトリツリー、ファイル数、特定の lazy-load 経路に必要な階層深さ）まで記述する規約を追加 |
| `quality-checks.md` E2E ベストプラクティス（任意の framework agnostic セクション） | playwright / cypress / playground 別に「snapshot 比較」「aria snapshot 推奨」「fixture 構造定義」のベストプラクティスを集約。test-design.md の self-review がこれを参照 |

### 影響範囲

- Playwright 以外の framework（Cypress, Selenium）でのチェック非対称化が発生。Framework 別チェックを framework-detect で切り替え

---

## 根本原因 H: テスト責務階層の再設計（テスト仕様作成プロセスの根本見直し）

### 症状（dojin-viewer 実テスト調査で判明）

`/home/arimakouyou/tmp/dojin-viewer/crates/app/src/components/` の各 component を直接調査して判明した事実:

| component | UT 件数 | テスト内容 | component reactivity 検証 |
|-----------|:------:|----------|:------------------------:|
| `detail_viewer.rs` | 39 件 | 100% pure helper (`next_index`, `build_image_url`, `compute_pan_offset` 等) | ❌ ゼロ |
| `folder_tree.rs` | 7 件 | 100% pure helper (`toggle_expanded`, `build_select_payload`) | ❌ ゼロ |
| `thumbnail_grid.rs` | 14 件 | 100% pure helper (`build_thumbnail_url`, `parse_iso8601_to_nanos`) | ❌ ゼロ |
| `info_panel.rs` | UT-15.x のみ | pure function (`panel_visible`, `format_exif_field`) | ❌ ゼロ |
| `page_navigator.rs` | UT-14.x のみ | pure function (`key_to_direction`, `wheel_to_direction`) | ❌ ゼロ |
| `toolbar.rs` | UT-16.x のみ | pure function (`apply_toolbar_action`) | ❌ ゼロ |

つまり **すべての component で「Resource / Signal / Effect / event handler の統合動作」テストがゼロ件**。これは個別実装者の怠慢ではなく、仕様（test-design.md / frontend-test-engineer / tasks.md）が **明示的に "view! と reactivity は E2E 責務" と定めているため発生した構造的結果**。

加えて `tasks.md` の `_Success` 基準が破壊的に弱い:

```
4.3 FolderTree _Success:
  「UT-11.1〜11.3 が PASS、Resource::new + <Suspense> + list_folder が
   実装されていることを grep で検証」
```

つまり **「文字列が存在する」= Success** という grep ベース判定。実装が `<p>"FolderTreePane (placeholder)"</p>` でも、別ファイルに `Resource::new` の文字列があれば PASS。

### 根本原因

`frontend-test-engineer/agent.md` L104-112 が **明示的に**「`view!` / DOM 配線 / Suspense / Resource / hydration は **すべて E2E の責務**」と定める。これは Leptos の `view!` がコンパイル時マクロでテスト不能という technical limitation への対処として始まったが、副作用として:

1. **Phase 内フィードバックループから component reactivity が完全に外れる**
2. **E2E は Final Gate でのみ走る** ため、Phase 4 完了時点で `[x]` が付き、E2E まで気付かない
3. **task の `_Success` が「pure UT PASS + grep」で完結**する構造が許容され、placeholder commit が可能

### 階層欠落の構造図

```
現状:                                        あるべき姿:
─────────────────────────────────────       ─────────────────────────────────────
UT (pure helper, ms 単位)                   UT (pure helper, ms 単位)
  ↓                                            ↓
[空白の谷 ← component reactivity]           CT (component reactivity, 秒単位) ★ 新層
  ↓                                            ↓
IT (HTTP API のみ, 秒〜十秒)                IT (HTTP API, 秒〜十秒)
  ↓                                            ↓
smoke (boot + wiring, 30 秒〜2 分)          smoke (boot + wiring, 30 秒〜2 分)
  ↓                                            ↓
E2E (UI フル, 分〜十数分・最終 gate のみ)   E2E (UI フル, 分〜十数分・最終 gate)
```

UT と E2E の間にあるべき **CT (Component Test) 層** が欠落していたため、`Resource::new` で list_folder を呼ぶ / `on_select` で signal を更新 / Suspense pending 状態の表示 / mounting 後の Effect 発火 が **どのテスト層の責務でもない** 状態だった。

### 修正対象 / 提案変更

#### H-1: Component Reactivity を Phase 内で継続検証する仕組み

> **重要な留保（advisor 指摘）**: 「wasm-bindgen-test で Leptos component を mount → signal 操作 → DOM 観測する CT 層が実現可能」は **未検証仮説** である。dojin-viewer に wasm-bindgen-test なし、`tdd-skills-rust/references/leptos-frontend-testing.md` にも言及なし、`frontend-test-engineer.md` L104-112 が **明示的に E2E 責務と排除している**（過去に「できない」と判断された可能性が高い）。
> 実装する spec の **Phase 0 で実証タスクを必須化** し、動かない場合は代替手段に pivot する。

##### Phase 0: 実証タスク（spec 化時に必須）

新規 spec の最初の Phase で:

1. 最も単純な component（例: `toolbar.rs` 相当）について以下を実装し動作確認:
   - `wasm-bindgen-test` + `wasm-pack test --headless --chrome` で component を mount
   - signal 操作（`signal.set(...)`）
   - DOM 観測（`document.query_selector(...)`）
2. 実測:
   - **実行時間** (1 test あたり数秒で済むか)
   - **セットアップ複雑度** (`Cargo.toml` の `[target.'cfg(target_arch = "wasm32")'.dev-dependencies]` 等)
   - **Leptos 0.7 でのエルゴノミクス** (`mount_to`, `Suspense`, `Resource` のモック方法)
3. 結果評価:
   - **動く / 実用的** → H-1〜H-5 の本実装に進む
   - **動かない / 実用的でない** → 代替案に pivot:
     - 代替 1: Storybook 風 component playground + Playwright Component Testing (Rust/WASM 対応版)
     - 代替 2: E2E を Phase 内で部分実行する軽量 gate (E-3 と統合)
     - 代替 3: Trunk + WebDriverIO + page object pattern

##### 本実装（Phase 0 で「動く」確認後）

| 対象 | 変更内容 |
|------|----------|
| `quality-checks.md` 新規セクション「Component Test (CT)」 | UT と E2E の中間層として CT を定義。実行時間 数秒/test、実 browser 起動不要を **目標** とし、Phase 0 実測で達成可能な水準に調整 |
| `tdd-skills-rust/references/leptos-frontend-testing.md` 全面改訂 | 既存の「ロジック抽出 + standard #[test]」セクションを保持しつつ、新セクション「Component Reactivity Test」を追加。Phase 0 で確立したパターンを記述 |
| 新規参考資料 `tdd-skills-dotnet/references/blazor-component-testing.md` | Blazor は bUnit で同等のことができる（こちらは枯れたツールなので実証不要）。`tdd-skills-rust` と対称的に整備 |
| 新規 hook / script `verify-ct-coverage.sh`（PostToolUse on parallel-worker） | UI component task の場合、worktree 内に CT 相当のテストが存在するか検査。Phase 0 で確立した「CT 相当」の判定基準を流用。ゼロ件なら warning（次バージョンで blocking） |

#### H-2: spec-test-design に CT 仕様セクションを追加

| 対象 | 変更内容 |
|------|----------|
| `spec-test-design/SKILL.md` 新規 Subagent D: CT spec deriver | design.md DES-N から、component が「Resource を呼ぶ」「Signal で再描画される」「event listener で signal を更新する」「Suspense で pending 状態を表示する」のような **統合動作を CT-N 仕様として導出**。UT 仕様と独立 |
| test-design.md テンプレート | 新規セクション `## Component Test Specifications` を追加。各 `### CT-N:` で `Mount Setup / Action / DOM Verification / Signal Verification` の 4 フィールドを必須化 |
| `spec-test-design/SKILL.md` Step B 新規 Check 17〜18 | 17: 「design.md DES-N の Component に対して UT と CT の両方が存在するか」<br>18: 「CT が pure logic ではなく統合動作（mount + signal + DOM）を verify しているか」<br>※ Check 13 は C-2、Check 14〜16 は F が確保済のため H-2 は 17〜18 を使用 |
| `spec-verify/SKILL.md` Check 6 拡張 | Test Coverage Symmetry に CT 系を追加。「全 DES-N に CT が存在するか」「CT が Traceability Matrix に登録されているか」 |

#### H-3: frontend-test-engineer の方針改訂

| 対象 | 変更内容 |
|------|----------|
| `frontend-test-engineer/agent.md` L104-112「ユニットテスト対象外」リスト | 大幅改訂。「`view!` の HTML 出力」「CSS クラス適用」「ルーティング遷移」「ハイドレーション」は引き続き E2E 責務。<br>**変更**: 「DOM イベント配線」「`Suspense` / `Resource` の表示切替」は **CT 責務に移管**（E2E 責務から除外） |
| 同 agent の「主なアクション」 | step 3〜5 を「pure logic UT 設計」と「component CT 設計」の **2 系統並列** に再構成 |
| `unit-test-engineer/agent.md` も対称的に改訂 | Rust 非 Leptos / .NET / 他言語 component test の責務分離を明示 |

#### H-4: spec-tasks の `_Success` 基準を厳格化

> **advisor 指摘**: 「`_Success` で grep を全面禁止」は強すぎる。実際の欠陥は **grep だけ** で完結していたこと。`grep + 何らかの行動検証` の合成 Success は健全（例: `UT PASS + view! 内で grep "<img src=" が hit する`）。grep 自体が悪ではなく、grep が **唯一の動作証跡** だったのが問題。

| 対象 | 変更内容 |
|------|----------|
| `spec-tasks/SKILL.md` Step 4 _Prompt template | UI component task の `_Success` を **「UT-N が PASS + CT-N が PASS（mount + signal 操作 + DOM 観測）+ grep などの補助検証 (任意)」** の構造で書く規約を追加。CT-N PASS が動作証跡の主柱、grep は補強 |
| `spec-tasks/SKILL.md` Step 7 新規 Check 18: SUCCESS_BEHAVIORAL_VERIFICATION | 「task の `_Success` フィールドが **grep / 文字列存在 / 実装されていることを確認 のような static check のみ** で完結している場合 error。最低 1 件の **動作証跡**（test PASS / smoke PASS / DOM 観測 等）を必須化」 |
| `parallel-worker/agent.md` の Success criteria | 「cargo build / clippy / unit test PASS」だけでなく「対応する CT-N が wasm-pack test で PASS（または Phase 0 で確立した代替手段で PASS）」を含める |

#### H-5: review-worker の判定挙動の改訂

> **advisor 指摘**: dojin-viewer の Phase 4 wave 2 では 4.3 FolderTree が `<p>"FolderTreePane (placeholder)"</p>` で escalate（**正しい判定**）、他の component は commit OK だった。**同じ review-worker が一方は捕捉、他方は見逃した**理由は、placeholder という **露骨な文字列の有無** に依存したヒューリスティックの可能性が高い。data-testid + pure helper があると「実装してる風」に見えて pass。

##### Phase 0 調査タスク（spec 化時に必須）

実装前に `.spec-workflow/specs/image-viewer/Implementation Logs/` および `reviews/` 配下の review-worker 出力を **3〜5 件 spot check** し:

- 「commit OK」と判定した根拠 (observations / category E のテキスト)
- 「placeholder」「未実装」のような **特定文字列**に依存していたか
- code path の到達可能性（view! 内に実 `<img src=...>` があるか / Resource の `.get()` が呼ばれているか / event listener が `on:click` で attach されているか）を **どこまで verify したか**

を抽出し、見逃しパターンを特定。それを踏まえて Category E 改訂内容を最終化する。

##### 本実装（Phase 0 結果を踏まえて）

| 対象 | 変更内容 |
|------|----------|
| `review-worker/agent.md` Category E (Final Check of Test Code) | 「テストは実装と同期しているか?」「値の検証があるか?」に追加して<br>「テストが component reactivity を実際に駆動しているか（mount → signal 操作 → DOM 観測の有無）」<br>「**pure helper UT のみで component task が完了している場合は明示的に reject**（CT が無いことが理由）」 |
| `review-worker/agent.md` Category D (Spec) 改訂 | 「`_Success` が **動作証跡を持たない** （grep / 文字列存在のみ）なら escalate」を追加。Phase 0 で特定した見逃しパターンに応じて文言を最終化 |
| `review-worker/agent.md` Category F (Design Conformance) 拡張 | 「placeholder ヒューリスティックに頼らず、code path の到達可能性で判断する」を明記。具体的には: <br>・design.md DES-N の `Dependencies:` に列挙された各 server fn / external API について、対応 component の view! / event handler 内で **実際に呼び出している箇所**を 1 件以上検出する<br>・data-testid が DOM 出力位置に付与されており、test_ids.rs 等で定数化されているか確認 |

### 影響範囲（大）

- **大規模変更**: spec-test-design / spec-tasks / frontend-test-engineer / unit-test-engineer / parallel-worker / review-worker / spec-verify すべてに改訂が及ぶ
- **CT 層の実装コスト**: 各 component に CT を書く必要があり、テスト件数が 1.5〜2 倍に増える
- **学習コスト**: `wasm-bindgen-test` / bUnit の使い方を参考資料に整備する必要あり
- **既存 spec の retrofit**: 旧 spec は CT-N 不在で warning。`spec-verify --legacy-tolerant` で段階移行
- **CI 時間の増加**: CT は wasm-pack test 起動オーバーヘッドあり。30 秒〜2 分程度増加見込み

### 副次効果

- review-worker の判定が **「pure UT PASS + grep」では絶対に commit に至らない** 構造になる
- `_Success` の grep ベース基準が排除され、「動作の正当性」基準に統一される
- D (spec-tasks 強化) との相乗効果で、Phase 4 の placeholder commit が **二重防止** される

---

## 根本原因 I: UT 品質特性の enforce（FIRST 原則 + Negative Assertions の明示化）

### 症状

ユーザーから「**実装時の UT はコードが動作するか（cargo test PASS）ではなく仕様の検証である**」「UT は仕様を満たすだけでなく **仕様外の挙動をしない** ことも確認する」「**外部依存を持たず**、**何回・どんな順で実行しても結果が同じ**」という基本原則の確認があり、現状の spec-workflow がこれらを **明示的には enforce していない** ことが判明。

具体例（dojin-viewer の `next_index` 関数）:

| 観点 | 現状の UT | ユーザー認識に沿った UT |
|------|----------|------------------------|
| Happy Path / Boundary | カバー（既存 4 カテゴリ） | 同じ |
| **仕様外の挙動をしない (Negative Assertions)** | ❌ 無し | `next_index` 呼出後に入力 `current` が変化していない / 副作用（log 等）を吐かない / clock / RNG に依存しない |
| **外部依存なし (Isolation)** | △ 暗黙（"pure logic 抽出"で副次的に成立） | env vars / 時刻 / file system / HTTP / DB に触れていないことを **明示的に確認** |
| **順序非依存 (Independent)** | ❌ 無し | `cargo nextest --shuffle` shuffle 実行で全件 PASS が CI gate |
| **冪等性 / 決定性 (Repeatable)** | ❌ 無し | clock / RNG モック強制が無い |

### 根本原因

- `spec-tasks/SKILL.md` Step 4 の `_TestFocus` フォーマット（L309-317）は **4 カテゴリ（Happy Path / Boundary Values / Error Handling / Edge Cases）** のみ。これらは positive assertion 寄りで、negative assertion / isolation / determinism の要求を含んでいない
- `frontend-test-engineer/agent.md` L69-92 の「Required Test Aspects」も同じ 4 カテゴリ。同上
- `quality-checks.md` には「UT Properties Gate」のような順序非依存・isolation 検証が存在しない
- 結果として: pure helper を書けば副次的に外部依存ゼロ・冪等になるが、それは **enforce されているのではなく副次効果**。pure helper でない通常関数（repository / scheduler 等）が UT 対象になった瞬間に破綻しやすい

### 修正対象 / 提案変更

#### I-1: `_TestFocus` フォーマット拡張（4 → 6 カテゴリ）

| 対象 | 変更内容 |
|------|----------|
| `spec-tasks/SKILL.md` Step 4 _TestFocus Format (L309-317) | 既存 4 カテゴリに以下 2 つを追加:<br>**Negative Assertions**: 仕様外の挙動が起きないことの明示確認（mutation 禁止 / 副作用ゼロ / 想定外入力で panic しない / 想定外フィールドを返さない）<br>**Isolation Properties**: 外部依存ゼロの確認方法（clock / RNG / env / fs / HTTP / DB に直接触れていないこと、または mock 経由のみであることの確認）<br>各カテゴリに該当しない場合は明示的に "N/A" と書く規約は既存通り |
| `spec-tasks/SKILL.md` Step 7 新規 Check 19: TESTFOCUS_NEGATIVE | 「`_TestFocus` の 6 カテゴリすべてが記述されているか。Negative Assertions / Isolation Properties が "N/A" になっている場合、その理由が妥当か（pure function の場合のみ許容）」 |
| `tasks-template.md` の例示 _TestFocus | 6 カテゴリ書式に更新 |

#### I-2: `quality-checks.md` に「UT Properties Gate」を新設

| 対象 | 変更内容 |
|------|----------|
| `quality-checks.md` 新規セクション「UT Properties Gate (QC15)」 | 以下を Phase Review および CI で gate 化:<br>**Order independence**: `cargo nextest --shuffle` で全 UT を shuffle 実行 → 1 件でも順序依存で fail したら CI block<br>**External dependency lint**: `#[cfg(test)]` 内で禁止される call の lint:<br>・`std::time::SystemTime::now()` / `chrono::Utc::now()` 等の clock 直接呼び出し<br>・`rand::thread_rng()` / `rand::random()` 等の RNG 直接使用<br>・`std::env::var()` の直接読取（`env_logger` 等のテスト基盤は除外）<br>・`std::fs::read*` / `std::fs::write*` の直接呼び出し（`tempfile` 経由は OK）<br>・`reqwest::*` / `tokio::net::*` の直接呼び出し<br>**実装手段**: cargo-deny の `[bans]` セクション + clippy の custom lint + workspace lints |
| .NET 側 | `dotnet test --blame-hang` + `xunit.runner.json` で並列実行、`Stryker.NET` のテスト独立性チェック |
| 既存 spec の retrofit | 旧 spec は warning（次バージョンで blocking） |

#### I-3: test-engineer agent の「Required Test Aspects」を 4 → 6 カテゴリに拡張

| 対象 | 変更内容 |
|------|----------|
| `unit-test-engineer/agent.md` Required Test Aspects | 既存 4 + Negative Assertions + Isolation Properties。各カテゴリの具体例を Rust / .NET / Node.js それぞれで提示 |
| `frontend-test-engineer/agent.md` Required Test Aspects | 同上 + Leptos signal/Resource 特有の例:<br>**Negative Assertions**: signal 更新後に `untracked()` で読んだ値が期待と一致 / Resource error 時に panic ではなく Error 状態で停止 / Effect が 1 回だけ実行される（連続発火しない）<br>**Isolation Properties**: WASM target で `js-sys::Date::now()` を直接呼ばず `MockClock` 経由 / fetch を `MockServer` 経由 |
| 両 agent の coverage_summary フォーマット | 4 → 6 カテゴリの coverage を報告 |

#### I-4: parallel-worker / review-worker の Success criteria 改訂

| 対象 | 変更内容 |
|------|----------|
| `parallel-worker/agent.md` の Success criteria | `cargo test PASS` を `cargo nextest run --shuffle PASS + UT Properties Gate (QC15) PASS` に置換 |
| `review-worker/agent.md` Category E (Final Check of Test Code) | 「テストが negative assertion を含むか」「テストが clock / RNG / env / fs / HTTP に依存していないか」を確認項目に追加 |

#### I-5: spec-workflow 全体の文言修正（"コードが動く" frame の排除）

| 対象 | 変更内容 |
|------|----------|
| `spec-implement/SKILL.md` 冒頭セクション | 「**実装時の UT は cargo test PASS（コードが動く）の確認ではなく、仕様の検証（仕様を満たし、仕様外の挙動をしない）の確認である**」を MUST_READ として明示 |
| `tdd-skills-rust/SKILL.md` / `tdd-skills-dotnet/SKILL.md` 冒頭 | 同様の原則を冒頭に置く |
| `_Prompt` template の Success フィールド ガイダンス | 「`Success: cargo test PASS`」ではなく「`Success: 仕様 X が UT-N の Negative Assertion 込みで verify される`」のような書き方を推奨 |

### 影響範囲

- **大**: spec-tasks / quality-checks / unit-test-engineer / frontend-test-engineer / parallel-worker / review-worker / tdd-skills-rust / tdd-skills-dotnet すべてに改訂
- **CI 時間**: `cargo nextest --shuffle` は通常の cargo test と同等。lint 追加で数秒〜十数秒の増加見込み
- **既存テストの retrofit**: clock / RNG / env を直接使う既存 UT は warning 表示。修正は `tdd-skills` の guidance に従って段階的に
- **学習コスト**: Mock パターンの参考資料を整備する必要あり

### 副次効果

- H (CT 層) の CT 自体が I の品質特性を満たすことになる（H と I は **直交的に補完**）
- `cargo-mutants` (既存 plan-redesign #7) で mutation 検出済みだが、I の Negative Assertions と組み合わさると mutation testing の効果が増幅（mutation で死ぬテストが negative assertion で構造化される）
- 「**仕様の検証 vs コードの動作確認**」という frame の明示で、Phase 4 placeholder commit の心理的根拠（"cargo test PASS したから OK"）を構造的に排除

---

## 根本原因 J: テスト分類の責務範囲明確化 + ST 層追加 + Regression 統合

### 症状（dojin-viewer 実テスト調査で判明）

ユーザー指摘「**E2E が IT になっている / E2E は全体の動作の流れを検証するもので個々の機能の確認は行わない / 現状 IT が無い**」を受けて確認した結果、テスト分類の責務範囲が複数層で混乱:

#### 1. E2E が個別機能テストになっている（11 件中 9 件）

```
e2e-04: ズーム / パン / 回転 / フィット / フルスクリーン  → 個別機能テスト（CT/ST 責務）
e2e-05: 情報パネル開閉                                   → 個別機能テスト（CT 責務）
e2e-07: 破損画像 / 403 / 415                              → backend エラー応答（IT 責務）
e2e-09: コンテナ起動 → API スモーク                       → smoke test（smoke 責務）
e2e-10: ViewSettings 永続化                               → 個別機能テスト（ST 責務）
```

E2E-1（フォルダツリー → サムネイル → 詳細表示ハッピーパス）と E2E-11（多階層 + 日本語ナビ）の 2 件のみ「真の E2E（user journey）」。

#### 2. IT 仕様自体が「server fn 経由」と「HTTP 経路」を混在

```
IT-1: フォルダ一覧正常取得 (server fn 経由)        ← フロント込み
IT-7: メタデータ取得 (server fn 経由)              ← フロント込み
IT-19: 多階層ネストフォルダの一覧取得 (HTTP 経路)  ← 純 backend IT
IT-20: 日本語・空白・記号パスを URL エンコード経由 ← 純 backend IT
```

ユーザー認識「IT は backend を **フロントとは別に** 行う」と照らすと、半数以上が **不純な IT**。

#### 3. ST (System Test) 層が完全に欠落

E2E を狭めた帰結として、「単一機能の full-stack テスト（UI + 実 server）」を書く層が無い。IT (backend のみ) でも CT (component のみ) でも E2E (user journey のみ) でもない位置に該当するテストが宙に浮く。

#### 4. Regression は既存 skill があるが taxonomy 統合が weak

`regression-test-policy/SKILL.md` で RT1（バグ→テスト変換）/ RT2（REQ-N の永続化）/ RT3（スイート健全性）が定義済。命名規則 `regression_issue_NNN_*` も標準化されている。しかし:

- **regression を「層」と「type」のどちらとして扱うか曖昧**（cross-cutting type が正解だが定義不在）
- **CI gate 化が weak**（PR 時に全層 + regression marked を必須実行する規定が無い）
- **新 taxonomy（UT/CT/IT/ST/smoke/E2E）への組込みが未実施**

### 根本原因

- `spec-test-design/SKILL.md` に「テスト分類の境界」を定義したセクションが無い。各 Subagent (A: UT / B: IT / C: E2E) が独立に仕様を導出するが、**境界違反のチェックが無い**
- `quality-checks.md` に「Test Taxonomy」セクションが無い。各テスト層の責務 / 範囲 / 実行時期 / fixture 要件が一元化されていない
- ST 層の概念がない（spec-workflow 全体で **System Test の言及ゼロ**）
- regression-test-policy skill は存在するが、**CI gate 化されていない / 新 taxonomy と未統合**

### 完全なテスト Taxonomy（J で確定する定義）

| 層 | 責務 | 範囲 | 実行時間目安 | fixture | 実行時期 |
|---|------|------|:--------:|:------:|:------:|
| **UT** | pure logic（仕様充足 + 仕様外不在） | 単関数 | ms | 不要 | TDD サイクル毎 / Phase Review / PR / merge |
| **CT** | component reactivity（mount → signal → DOM） | 単 component | 数秒 | mock signal | Phase Review / PR / merge |
| **IT** | **backend HTTP API only** | server crate | 秒〜十秒 | 実 DB / TempDir | Phase Review (backend Phase 完了後) / PR / merge |
| **ST** | **単一機能の full-stack** | UI + server (機能 1 個分) | 数秒〜十秒 | 実 server + fixture | 対象機能 Phase 末尾 / PR / merge |
| **smoke** | boot + wiring + 型境界 | system 全体 | 30s〜2m | 不要 | 各 Phase Review |
| **E2E** | **user journey only** | 全機能横断 | 分〜十数分 | 実 server + 完全 fixture | Final Gate のみ |
| **Regression**（type） | 既知バグの再発防止 | UT/CT/IT/ST/E2E すべての層に **横断的に**マーク | 各層と同じ | 各層と同じ | PR / merge（必須） |

### 修正対象 / 提案変更

#### J-1: IT 仕様を「backend HTTP API only」に厳格化

| 対象 | 変更内容 |
|------|----------|
| `spec-test-design/SKILL.md` Subagent B (IT spec deriver) | IT 仕様の責務を **「backend HTTP API only」** に厳格化。「server fn 経由」表記を禁止し、フロントの Resource → server fn 境界を含む統合動作は **CT 責務** または **ST 責務** で扱う旨を明示 |
| test-design.md template | `## Integration Test Specifications` セクション冒頭に「IT は backend HTTP API only。フロント Resource を含む統合動作は CT/ST で扱う」を必須コメントとして挿入 |

#### J-2: E2E 仕様を「user journey only」に厳格化

| 対象 | 変更内容 |
|------|----------|
| `spec-test-design/SKILL.md` Subagent C (E2E spec deriver) | E2E 仕様の責務を **「user journey only」** に厳格化。「個別機能のテスト」を E2E に書くことを禁止し、単一機能のテストは **ST 責務** に振る |
| test-design.md template | `## E2E Test Specifications` セクション冒頭に「E2E は user journey 専用。個別機能テストは ST で扱う」を必須コメントとして挿入 |

#### J-3: `quality-checks.md` 新規「Test Taxonomy」セクション

| 対象 | 変更内容 |
|------|----------|
| `quality-checks.md` 新規セクション「Test Taxonomy」 | 上記の 7 行（UT/CT/IT/ST/smoke/E2E/Regression）の表を **正規定義**として記載。各層の責務 / 範囲 / 実行時間 / fixture 要件 / 実行時期を一元化。spec-test-design / spec-tasks / parallel-worker / review-worker から参照される |
| 各テスト層の境界違反例集 | 「IT に UI 検証が混入した例」「E2E に個別機能テストが混入した例」「ST が CT で代替できないか確認すべき例」など、よくある違反パターンを記載 |

#### J-4: spec-test-design Step B に test layer boundary check

| 対象 | 変更内容 |
|------|----------|
| `spec-test-design/SKILL.md` Step B 新規 Check 19: TEST_LAYER_BOUNDARY | 各テスト仕様（UT-N / CT-N / IT-N / ST-N / E2E-N）が **責務範囲外**のことを verify していないか確認:<br>・IT-N が UI 操作 / DOM 検証を含んでいないか<br>・E2E-N が単一機能のみのテストになっていないか<br>・ST-N が user journey 全体になっていないか<br>・UT-N が外部依存を含んでいないか<br>※ Check 13 は C-2、Check 14〜16 は F、Check 17〜18 は H-2 が確保済のため J-4 は 19 を使用 |

#### J-5: spec-tasks の IT/E2E/ST task 配置ルール

| 対象 | 変更内容 |
|------|----------|
| `spec-tasks/SKILL.md` 3.6 (IT/E2E test tasks) を全面改訂 | 配置ルールを再定義:<br>**IT task**: 全 backend Phase 完了直後の Phase（PhaseReview の直前）<br>**ST task**: 対象機能の component / endpoint が実装済みの Phase 末尾<br>**E2E task**: 全 Phase 完了後の **最終 Phase** にのみ配置 |
| 既存 `### 3.6 Integration & E2E Test Tasks` を `### 3.6 IT / ST / E2E Test Tasks` に拡張 | ST 配置ルールも追加 |

#### J-6: spec-test-design に **ST 仕様セクション** 追加（新規）

| 対象 | 変更内容 |
|------|----------|
| `spec-test-design/SKILL.md` 新規 Subagent E (ST spec deriver) | requirements.md の各 REQ-N から **「機能テスト」**として ST-N を導出。各 ST-N は「単一機能の full-stack 動作（UI 操作 → backend 応答 → UI 反映）」を verify する仕様<br>※ Subagent D は H-2 で CT spec deriver として使用済のため、ST 用は Subagent E |
| test-design.md template | 新規セクション `## System Test Specifications` を追加。各 `### ST-N: {feature name}` で `Feature Scope / Test Path / Verification Points / Expected Outcome` の 4 フィールドを必須化 |
| `spec-test-design/SKILL.md` Step B Check 1〜4 拡張 | 「全 REQ-N に ST-N が対応するか」「各 ST-N が単一機能の full-stack 動作を verify しているか」を check |
| `spec-verify/SKILL.md` Check 6 拡張 | Test Coverage Symmetry に ST 系を追加。「全 REQ-N に ST が存在するか」「ST が Traceability Matrix に登録されているか」 |

#### J-7: spec-tasks に ST task 配置ルール追加（新規）

| 対象 | 変更内容 |
|------|----------|
| `spec-tasks/SKILL.md` 3.6 の中で ST task の特例 | ST task は「対象機能の component / endpoint がすべて実装済みの Phase 末尾」に配置。CT/IT 完了後、E2E より前 |
| `spec-tasks/SKILL.md` Step 7 新規 Check 20: ST_PLACEMENT | 「全 ST-N に対応する task が tasks.md に存在し、対象機能の依存関係が完了する Phase に配置されているか」 |
| 既存 task テンプレート 4.x の ST 例示 | 「### 4.X Implement ST-N happy path for {feature name}」のような ST task 例を spec-tasks SKILL.md L262 付近に追加 |

#### J-8: regression-test-policy を新 taxonomy に整合させる改訂（新規）

| 対象 | 変更内容 |
|------|----------|
| `regression-test-policy/SKILL.md` 全面改訂 | 「Regression は **層ではなく cross-cutting type**」を明示。RT1/RT2/RT3 を **UT/CT/IT/ST/E2E すべての層に適用可能** と再定義 |
| 既存命名規則 `regression_issue_NNN_*` の維持 | 各層で同じ命名規則を使用（UT は inline `#[test]` / CT は `*_ct.rs` 内 / IT は `it_regression_*.rs` / ST は `st_regression_*.rs` / E2E は `e2e-regression-NNN.spec.ts` のような統一） |
| 各 test-engineer agent と review-worker の連携 | 「regression marker が付いたテストは独立 verify」を agent ガイダンスに追記 |

#### J-9: `quality-checks.md` 新規 QC16: Regression Gate（新規）

| 対象 | 変更内容 |
|------|----------|
| `quality-checks.md` 新規 QC16: Regression Gate | PR / merge 時に **全層（UT + CT + IT + ST + E2E）+ regression marked テスト** を実行することを CI 必須化 |
| `setup-ci/SKILL.md` 改訂 | `regression_issue_*` パターンを git 履歴から自動収集する step を CI workflow テンプレに追加。全件 PASS を merge gate 化 |
| Phase Review 時の regression 確認 | 当該 Phase で修正したバグ系 task に対応する regression test が存在するか、spec-implement 3.5.2 (review-worker) で確認 |

#### J-10: `spec-tasks` でバグ修正 task に `_RegressionBugId` メタデータ強制（新規）

| 対象 | 変更内容 |
|------|----------|
| `spec-tasks/SKILL.md` Step 4 _Prompt template | バグ修正系 task（`_BugFix: true_` または `Role: Bug Fixer` のような明示）に `_RegressionBugId: BUG-NNN` メタデータを必須化 |
| `spec-tasks/SKILL.md` Step 7 新規 Check 21: REGRESSION_BUG_ID | 「`_BugFix: true_` task に `_RegressionBugId:` が付与されているか」を error 判定 |
| `parallel-worker/agent.md` の バグ修正 mode | RT1 フローを実装: 「修正前に必ず再現テストを RED phase で書き、修正後 GREEN にする。テストは regression marker を付けて永続化」 |

### 影響範囲（大）

- **大規模変更**: spec-test-design / spec-tasks / quality-checks / regression-test-policy / setup-ci / parallel-worker / review-worker / spec-verify すべてに改訂
- **既存 spec の retrofit**: dojin-viewer のような既存 spec は test-design.md / tasks.md で再分類が必要。e2e-04/05/07/09/10 は ST/IT/CT/smoke に移動、IT-1/IT-7 のような「server fn 経由」記述は CT/ST に書き換え。spec-verify legacy-tolerant flag で段階移行
- **学習コスト**: ST 層が新規概念なので、tdd-skills 系に「ST のテスト書き方」のリファレンス追加が必要
- **CI 時間の増加**: ST と全層 regression で +数分〜十数分。ST は単一機能のため E2E より速いが、件数が多くなる傾向

### 副次効果

- I (UT 品質) / H (CT 層) / E (smoke 再設計) / J (taxonomy 確定) が **直交補完**：各層が責務を持ち、層間の境界が明確化される
- E2E が user journey に絞られることで Final Gate の所要時間が大幅短縮（個別機能テストが ST に流れるため）
- regression が cross-cutting type として明確化され、CI gate 化で「修正による新バグ」の流入が機械的に防げる
- dojin-viewer の既存 e2e ファイルを ST/IT/CT/smoke に再分類することで、各層の本来責務が回復する（Dogfooding 候補）

---

## 根本原因 K: Upstream Spec Content Expansion（requirements.md / design.md の内容拡張）

### 症状

ユーザー指摘「仕様書作成は修正しなくても大丈夫？」を受けて確認した結果、既存項目（C/D/E/F/H/I/J）が **下流（test-design.md / tasks.md / spec-verify）に集中**しており、**上流（requirements.md / design.md）は薄い**ことが判明。dojin-viewer で起きた現象を再フレームすると、上流不足が原因の部分が複数:

| 現象 | 上流の不足 |
|------|----------|
| #6: RelativePath が MOD-N に未定義 | design.md MOD-N 網羅性の authoring 規約不在（C で **検出**できるが authoring 時に予防できない） |
| #4: design.md と test-design.md の `Result<Vec<T>, E>` vs `Vec<T>` 不整合 | design.md の Interface 定義が **「どの test 層が verify するか」を宣言していない**ため、test-design.md derivation が型を独自解釈 |
| ST 層が宙に浮いた | design.md の DES-N に「Test Layers」フィールドが無いため、spec-test-design Subagent が ST 仕様を導出する根拠が無い（J-6 で対応するが、根拠は heuristic） |
| #11/13: placeholder commit | design.md に「Architecture for Testability」が無く、mock 点 / clock 注入が未定義のため、I/H の testability 基準を当てる先が曖昧 |

### 根本原因

- `spec-requirements/SKILL.md` の REQ-N format には **Acceptance Criterion ごとの Test Layers 宣言が無い**。requirements.md → test-design.md / tasks.md の derivation が implicit
- `spec-design/SKILL.md` Wave 2 の DES-N format には **Required Test Layers フィールドが無い**。spec-test-design が component 性質を heuristic で判定
- design.md に **「Architecture for Testability」セクションが無い**。mock 点 / clock 注入 / DI 設計が記載されないため、I (Isolation Properties) を当てる対象が曖昧
- design.md に **「Phase Deliverables」セクションが無い**（E-2 で部分的に提案済）。各 Phase が「何を作る + どの test 層で検証する」を一元宣言できない
- requirements.md の Non-Functional Requirements に **Testability 観点が必須化されていない**

### 修正対象 / 提案変更

#### K-1: requirements.md の Acceptance Criterion に Test Layers フィールド追加 ✅ DONE (2026-04-28)

| 対象 | 変更内容 |
|------|----------|
| `spec-requirements/SKILL.md` Step 4 | 各 `### REQ-N:` の Acceptance Criterion 1〜M に **Test Layers** フィールドを追加。例:<br>`1. WHEN ... THEN ... SHALL ...` (REQ-N.1)<br>`   Test Layers: UT, ST-3, E2E-1`<br>UT/CT/IT-N/ST-N/E2E-N の組合せで宣言。`<!-- REQ-N.M -->` コメントの隣に置く |
| requirements-template.md | 同上の書式を例示 |
| `spec-verify/SKILL.md` 新規 Check 8: REQ_TEST_LAYERS_DECLARED | 「全 REQ-N.M に Test Layers が宣言されているか」「宣言された Test Layer が test-design.md に存在するか」を check<br>※ 当初 Check 9 で計画していたが、C (Check 8 予定) が未実装のため Check 8 に番号調整 |

#### K-2: design.md DES-N に Required Test Layers フィールド追加 ✅ DONE (2026-04-28)

| 対象 | 変更内容 |
|------|----------|
| `spec-design/SKILL.md` Wave 2 (Components and Interfaces セクション) | `### DES-N:` の format に **Test Layers** フィールドを追加。例:<br>```<br>### DES-11: FolderTreePane<br>- Purpose: ...<br>- Interfaces: ...<br>- Dependencies: ...<br>- Reuses: ...<br>- Satisfies: REQ-1.1, REQ-1.2<br>- **Test Layers: UT (toggle_expanded), CT (Resource + Suspense + on_select), ST-1 (folder navigation flow)**<br>```<br>UI component なら CT、backend service なら IT、機能の縦切りなら ST が含まれる |
| design-template.md | 同上の書式を例示。component 性質別の典型例（UI / backend / library / utility）も記載 |
| `spec-design/SKILL.md` Step B 拡張 | 新規 Check: 「全 DES-N に Test Layers が宣言されているか」「宣言された Test Layer が test-design.md にも対応する仕様があるか（spec-verify と協調）」 |

#### K-3: design.md に「Architecture for Testability」セクション新設 ✅ DONE (2026-04-28)

| 対象 | 変更内容 |
|------|----------|
| `spec-design/SKILL.md` Wave 2 新規セクション | `## Architecture for Testability` を必須化:<br>1. **Mock points**: trait 境界 / DI 注入点 / port-adapter 構造の設計図<br>2. **Clock injection**: `trait Clock` + `MockClock` の使用方針 / WASM target での `js-sys::Date` 取扱い<br>3. **RNG injection**: `trait Rng` + `MockRng` の使用方針<br>4. **External I/O isolation**: HTTP / fs / env の隔離設計（mockito / wiremock / tempfile / `dotenvy::from_path_override`）<br>5. **Test fixtures**: 共通 fixture の配置 / lifetime / clean-up 方針 |
| design-template.md | 同上の書式を例示。プロジェクト性質別の典型パターン（API / フルスタック / CLI / library）も記載 |
| `spec-design/SKILL.md` Step B 拡張 | 「Architecture for Testability セクションが存在し、Mock points / Clock / RNG / External I/O / Test fixtures の 5 サブセクションが揃っているか」を error 判定 |
| I (UT Properties Gate) との連携 | I-2 の lint（clock / RNG / env の直接呼出禁止）の **許可された逃げ口** が design.md K-3 で宣言された Mock 経由のみ、と紐付け |

#### K-4: design.md の「Phase Deliverables」セクション（E-2 を K に統合） ✅ DONE (2026-04-28)

| 対象 | 変更内容 |
|------|----------|
| `spec-design/SKILL.md` Wave 1 新規セクション | `## Phase Deliverables` を必須化。各 Phase で「**何を作るか** + **どの Test Layer で検証するか**」を一元宣言:<br>```<br>## Phase Deliverables<br>### Phase 1: Core domain (Rust crate)<br>- Deliverable: `crates/shared` の DTO + validation<br>- Test Layers: UT (Negative Assertions 含む)<br>- Smokeable: cargo build --lib<br>### Phase 2: HTTP server<br>- Deliverable: `crates/server` の axum endpoints<br>- Test Layers: UT, IT (HTTP), smoke (L1 + L2 wiring)<br>- Smokeable: server boot + /health<br>### Phase 3: ...<br>```<br>E-2 で提案した Phase Deliverables 概念を K に統合 |
| design-template.md | 同上の書式を例示 |
| `spec-design/SKILL.md` Step B 拡張 | 「全 Phase に Deliverable + Test Layers + Smokeable が記載されているか」を error 判定。E-2 の Phase Deliverable 検証も K-4 で統一 |
| 既存 E-2（Phase Deliverable 宣言部分） | K-4 に統合（E-2 内では「smoke 観点」を扱い、Phase Deliverable 全般は K-4） |

#### K-5: requirements.md NFR に「Testability」を必須項目として追加 ✅ DONE (2026-04-28)

| 対象 | 変更内容 |
|------|----------|
| `spec-requirements/SKILL.md` Step 4 | Non-Functional Requirements に **Testability** を必須項目として追加。既存（Code Architecture / Performance / Security / Reliability / Usability）に並ぶ第 6 観点。<br>記載内容:<br>・全 REQ が UT で verify 可能か（不可なら理由 + どの層で代替）<br>・External I/O / Clock / RNG / 並列性 / 状態を持つ component の testability 戦略<br>・Test fixture / mock の責任範囲 |
| requirements-template.md | NFR Testability セクションを必須化、書式例 |
| `spec-requirements/SKILL.md` Step 5 (self-review Check 3) | 「Non-Functional Requirements が **6 観点（Testability を含む）** をすべて記載しているか」を error 判定 |

#### K-6: `spec-design` Step B (self-review check) 拡張 ✅ DONE (2026-04-28)

| 対象 | 変更内容 |
|------|----------|
| `spec-design/SKILL.md` Step B 拡張 | 既存 check に追加:<br>・全 DES-N に **Required Test Layers** が宣言されているか<br>・**Architecture for Testability** セクションが存在し 5 サブセクションが揃っているか<br>・**Phase Deliverables** セクションが存在し全 Phase をカバーしているか<br>・各 Phase Deliverable の Test Layers が test-design.md と整合（forward reference）するか |

#### K-7: `spec-test-design` の各 Subagent を「明示宣言ベース」に切替

| 対象 | 変更内容 |
|------|----------|
| `spec-test-design/SKILL.md` 全 Subagent | derivation 入力で **「design.md の Required Test Layers 宣言」を最優先**で読み込み、**宣言外の層を導出しない**（heuristic 排除）。<br>例: DES-11 が `Test Layers: UT, CT, ST-1` と宣言されていれば、Subagent A は UT-11.x、Subagent D（H-2 で新設、CT spec deriver）は CT-11、Subagent E（J-6 で新設、ST spec deriver）は ST-1 を導出する。IT/E2E の独自解釈を抑止 |
| Subagent のフォールバック | design.md に Test Layers 宣言が無い（legacy）場合のみ heuristic で derivation する。新規 spec は宣言ベース必須 |

### 影響範囲（大）

- **大規模変更**: `spec-requirements/SKILL.md` + requirements-template.md / `spec-design/SKILL.md` (Wave 1 + Wave 2) + design-template.md / `spec-test-design/SKILL.md` の各 Subagent / `spec-verify/SKILL.md`
- **既存 spec の retrofit**: 既存 spec は K-1 / K-2 / K-3 / K-5 のフィールド不在で warning。`spec-verify --legacy-tolerant` で段階移行。dojin-viewer の image-viewer spec は Phase 0 で retrofit して運用感を測定（Dogfooding 候補）
- **既存 E-2 (Phase Deliverable 部分) との関係**: K-4 が Phase Deliverable 全般を担い、E-2 は smoke の文脈に絞る形で再構成
- **template 整備コスト**: requirements / design template の改訂と例示記載が必要

### 副次効果

- spec-test-design の derivation が heuristic から **明示宣言ベース**に変わり、再現性が高まる
- J/I/H/D/E/F の各 check が **当てる先が明確になる**（K で宣言された Test Layers / Architecture for Testability に対して check）
- design.md K-3 (Architecture for Testability) と I-2 (UT Properties Gate) が結合: I の lint で禁止される clock/RNG/env 直接呼出について、K-3 で宣言された Mock 経由のみ許可、という design ↔ enforcement の往復ループが成立
- requirements.md K-5 (Testability NFR) の存在で「実装時にこの REQ は UT 不可」と判明した場合の対応指針が明確になる（CT/ST/E2E への振り分け基準）
- K + J + I + H で **「上流が宣言 → 下流が実装 → 各層で品質 enforce」の一貫したパイプライン**が成立

---

## 根本原因 G: 廃止（E に統合）

旧 G「SKIP 判定の透明性欠如」は表面的な症状で、本質は E (Smoke Gate 全面再設計) の一部だった。
ユーザー指摘により以下の 3 点が同根と判明:

1. Smoke 定義が API プロジェクト限定 → narrow すぎる
2. HTTP server が無い Phase で smoke SKIP → Phase 設計の隠蔽
3. 「API 実装時に何をテストするか」が薄い → smoke の段階的成長がない

これらは E の E-1 / E-2 / E-3 で一括対応する。

---

## 優先度マトリクス

| 優先度 | 根本原因 | カバー issue | 検出時期の早さ | 推奨着手順 |
|:-----:|--------|:----------:|:-----------:|:-------:|
| **P0** | **K: Upstream Spec Content Expansion** | #4, #6, #11, #13 (上流予防) + 全下流項目の前提 | spec 著作段階 | 1 |
| **P0** | J: テスト分類責務範囲明確化 + ST 層 + Regression 統合 | #5, #7, #8, #9, #11, #12, #13 + テスト分類の根本確定 | spec 段階 / 全層 / PR | 2 |
| **P0** | I: UT 品質特性 enforce（FIRST + Negative Assertions） | #11, #12 + 全テスト品質の根本底上げ | UT 実行時（毎回） | 3 |
| **P0** | H: テスト責務階層再設計（CT 層導入） | #7, #11, #12, #13, #8, #9（再発予防） | Phase 4 中（継続検証） | 4 |
| **P0** | E: Smoke Gate 全面再設計 | #5, #11, #13 | Phase Review 時 | 5 |
| **P0** | D: spec-tasks 強化 | #7, #10, #12, #13(予防) | Phase 4 開始前 | 6 |
| **P1** | B: worktree bookkeeping | #3 | Phase 完了時 | 7 |
| **P1** | C: spec semantic 整合性 | #4, #6 | Phase 4 開始前 | 8 |
| **P2** | F: test-design 自己レビュー | #8, #9 | Phase 3 完了時 | 9 |
| **P3** | A: LLM 幻覚抑止 | #1, #2 | 任意 | 10 |

**順序の根拠**:

- **K を P0 最筆頭に**: ユーザー指摘で「上流仕様書（requirements.md / design.md）が薄い」ことが判明。下流の J/I/H/D/E は **K で宣言された Test Layers / Architecture for Testability に対して check を当てる**構造なので、上流が無いと下流の検証対象が曖昧。**仕様書 → テスト仕様 → タスク → 実装 → 検証**の最上流から固める必要
- **J**: テスト分類の正規定義（UT/CT/IT/ST/smoke/E2E + Regression cross-cutting）が無いと、I/H/E/D で各層の中身を作っても境界が壊れたまま。dojin-viewer で 4 重混乱が判明
- **I**: ユーザー指摘で「**実装時の UT はコードが動作するかではなく仕様の検証**」「仕様外の挙動をしないことも確認」「外部依存なし」「順序非依存」が現状 enforce されていないことが判明。spec-workflow 全体の **テスト品質の床**
- **H**: dojin-viewer 実テスト調査で「全 component の UT が 100% pure helper」「task `_Success` が grep ベース」「frontend-test-engineer が view!/Resource/Suspense を E2E 責務と明示」の 3 重構造的欠陥が判明。Phase 4 の placeholder commit パターンの **責務階層上の根因**
- **E**: ユーザー指摘で smoke gate の narrow 定義 + Phase deliverable 不在の隠蔽 + smoke 段階成長欠如の 3 重問題が判明。Phase 設計の質向上にも波及
- **D**: 「DES-N → tasks.md _Prompt 翻訳」の予防策。H と組み合わせて Phase 4 の placeholder commit を **二重防止**
- K / J / I / H / D / E は **六位一体**: K が上流宣言 / J が分類確定 / I が UT 品質の床 / D が予防（spec 段階）/ H が継続検証（実装段階）/ E が最終検出（Phase Review）。6 つで Phase 4 反パターンを完全カバー
- B は安全網として早期実施推奨（既に hook 整備済みの土壌があるため軽い）
- C は spec-verify 拡張で実装が中規模、影響大
- F は局所的、低リスクで段階的に追加
- A は behavior fix で再現テストが難しい。優先度低だが Hook 化は 1 セッションで完了

## 次セッションで個別 spec 化する単位

各根本原因を独立した spec として `/spec-request-spec` から立てる想定。spec name は kebab-case、例:

- `upstream-spec-content-expansion`（K 項目、requirements.md / design.md 内容拡張）
- `test-taxonomy-and-st-introduction`（J 項目、Test Taxonomy 確定 + ST 層導入 + Regression 統合）
- `ut-quality-properties-enforce`（I 項目、UT FIRST + Negative Assertions 強制）
- `component-test-layer-introduction`（H 項目、CT 層導入 + frontend-test-engineer 改訂 + spec-test-design 拡張をまとめる）
- `universal-smoke-gate-redesign`（E 項目、E-1/E-2/E-3 を 1 spec で扱う）
- `tasks-self-review-strengthening`（D 項目）
- `phase-review-bookkeeping-flush`（B 項目）
- `spec-verify-type-reference-check`（C 項目）
- `test-design-e2e-quality-checks`（F 項目）
- `phase-progression-confirm-hook`（A 項目）

**推奨**: K + J + I + H + D + E は密結合（上流宣言 / 分類確定 / 品質床 / 責務階層 / spec 予防 / 最終検出 の 6 軸）なので、**1 つの大型 spec `phase-4-antipattern-elimination` として扱う**選択肢を強く推奨。spec 内の Phase 構造で:

- **Phase 0**: K の Phase 0 実証（dojin-viewer の既存 design.md / requirements.md に K の新規フィールドを retrofit してみて運用感測定） + J の実証（既存 e2e/it ファイルを新 taxonomy で audit） + I の実証（cargo nextest --shuffle / lint 動作確認） + H の実証（wasm-bindgen-test の Leptos 0.7 実用性 + review-worker spot check）
- **Phase 1**: K-1〜K-7（上流仕様書の内容拡張）
- **Phase 2**: J-1〜J-10（テスト分類の正規定義 + ST 層 + Regression 統合）
- Phase 3: I-1〜I-5（UT 品質特性 enforce）
- Phase 4: H-1〜H-5（CT 層導入とテスト方針改訂）
- Phase 5: D（spec-tasks Step 7 強化）
- Phase 6: E-1〜E-3（smoke gate 再設計、ただし E-2 の Phase Deliverable は K-4 に統合済）
- Phase 7: 統合検証（dojin-viewer のような既存 spec を用いた Dogfooding）

を組むのが最も効率的。spec-workflow-mcp 自身が spec-driven にまとめて改訂を受ける形になる。

**Phase 順の必然性**:
- **K → J → I → H** が必然: 上流宣言が無いと分類を当てる先が無い (K)。分類が無いと品質基準を当てる対象が無い (J)。UT 品質基準が無いと CT/IT/ST の品質基準も保てない (I が H より前)
- D / E は K/J/I/H 後が自然: `_Success` 基準（D）と smoke 定義（E）は taxonomy（J）+ Architecture for Testability（K）に依存
- E-2（Phase Deliverable 部分）は K-4 に統合済。E は smoke の 4 層化（L1〜L4）と smoke の段階成長に絞られる

各項目の sub（K-1〜K-7 / J-1〜J-10 / I-1〜I-5 / H-1〜H-5 等）は修正対象が異なるので、Phase 内の独立 task として扱える。

## 関連ドキュメント

- `plan-redesign-overall-progress.md` — 既存の 16 項目クロージャ記録（本 plan は別線）
- `phase-3-9-role-consolidation.md` — agent 構成の変遷
- `.claude-plugin/rules/quality-checks.md` — QC1〜QC13 の品質チェック定義（QC14 を本 plan で提案）
- `.claude-plugin/rules/enforcement-levels.md` — 段階的 gate 化方針

## 更新方針

- 各根本原因について個別 spec が起票されたら、本 plan の該当セクションに「→ spec: `{spec-name}`」を追記
- 実装完了したら `STATUS: DONE` と完了日を追記
- 着手しないと判断した項目は「SKIP（理由）」を明記

## 全体進捗

> Branch: `refactor/plugin-redesign-phase-a`（既存、`plan-redesign` 16 項目クロージャ後の継続作業）
> 開発フロー: sub-plan + 直接 commit（個別 PR なし）。最終 PR は改良後ワークフローを再テストしてから判断
> 着手順: K → J → I → H → D → E（H と I は POC 完了待ち）

| 項目 | sub-plan | POC plan | Status | 開始日 | 完了日 |
|------|---------|---------|:------:|--------|--------|
| **J-3 先行**: Test Taxonomy セクション | （J 内に統合）| （不要）| **DONE** | 2026-04-28 | 2026-04-28 |
| **K**: 上流仕様書 content 拡張 | `upstream-spec-content-expansion.md` | （不要）| **DONE** (7/7、Subagent D 部分は H 後)| 2026-04-28 | 2026-04-28 |
| **J**: テスト分類 + ST + Regression（残り） | `test-taxonomy-and-st-introduction.md` | （不要）| **DONE** (10/10、setup-ci 改訂は後続)| 2026-04-28 | 2026-04-28 |
| **I**: UT 品質特性 enforce | `ut-quality-properties-enforce.md` | `nextest-shuffle-isolation-lints-poc.md` | **POC PENDING** | - | - |
| **H**: CT 層導入 | `component-test-layer-introduction.md` | `wasm-bindgen-test-leptos-poc.md` | **POC PENDING** | - | - |
| **D**: spec-tasks 強化 | `tasks-self-review-strengthening.md` | （不要）| TODO | - | - |
| **E**: Smoke Gate 再設計 | `universal-smoke-gate-redesign.md` | （不要）| TODO | - | - |

> γ 採用: J-3 (`quality-checks.md` の Test Taxonomy セクション) を先行で 1 commit 化済。これにより K-1/K-2/K-4 が参照する taxonomy 正規定義が確立。

## 進捗の更新方針

- sub-plan を作成したら本テーブルの sub-plan 欄に作成日を追記
- POC が完了したら POC plan に結果を記録、本テーブルの Status を `IN PROGRESS` または `BLOCKED` (POC で動かなかった場合) に変更
- 各項目完了時に Status を `DONE` + 完了日記入。マスター見取り図側のセクションにも完了マーク
