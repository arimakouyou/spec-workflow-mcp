# spec-workflow プラグイン再設計(v2)

## Context

specrail の approval-gate では、design.md / test-design.md / tasks.md の間で 12 件の食い違いが起きた。ID の対応は全件一致しており、ずれたのは書き写した中身だった。

原因は 3 つ。

- design の承認(v4、08-17)が下流の承認(08-14)より後で、下流への反映が手作業かつ部分的だった。
- tasks.md が test-design を書き写す構造になっている。
- TDD の RED が test-design.md を読まず、GREEN がテストの呼び方に合わせてシグネチャを変える。

**ユーザー判断**

- チェックの追加は限界なので、構造で防ぐ。
- 範囲はまず spec フローとテスト系。進め方は次の順:
  1. この repo の `.claude-plugin/` を置き換える
  2. 新フローで specrail(Rust 版 MCP)を作り直す
  3. 最終的にプラグインを specrail へ移す
- approval-gate は新フローで作り直す。

**確定した判断**

- 1 DES = 1 タスク。tasks.md は生成物で、承認不要・手編集禁止。
- Phase 境界で止まらない。人が介入するのは承認、design の骨格確認、escalate のときだけ。
- spec ブランチに直接コミットする。タスク worktree とマージコミット、bookkeeping コミットは廃止。
- test-design では型を限定参照で書く。そのうえで、引数・戻り値型の不一致への対策を境界ごとに明示する(§3)。

## 1. 設計の核

| # | 原則 | 仕組み |
|---|---|---|
| 1 | 1 つの事実を所有する文書は 1 つだけ。他は ID で参照し、書き写さない | 文書文法と決定的 lint(`spec-lint.sh`、Bash) |
| 2 | tasks.md は書かずに生成する | `spec-plan.sh` が design / test-design から導出 |
| 3 | 上流が変われば下流の承認は自動で失効する | MCP だけが書く承認台帳(sha256 と上流ハッシュ)。request の前提条件、hook、コミットゲートの 3 か所で拒否 |
| 4 | 実装はシグネチャを勝手に変えられない | RED で DES Interfaces をそのまま写して stub を作り、以後は変更禁止。テスト ID の集合を test-design と一致させる |
| 5 | コミット経路は 1 本、判定者は 1 人 | `spec-git.sh` 経由に限る。コードのコミットと commit / rework / escalate の判定は review-worker だけ |
| 6 | design のシグネチャは、承認前にコンパイラで実装可能性を確かめる | `spec-sigcheck.sh` が stub crate を生成して `cargo check` / `dotnet build` を実行する。成功を承認リクエストの前提条件にする(§3) |

## 2. 機能一覧と判定(現行の約 40 機構とインフラ)

| 機能 | 現行の場所 | 判定 | 新しい置き場所 |
|---|---|---|---|
| 承認ゲートと自動遷移 | approvals MCP、check-approval | 作り直し | 台帳付き MCP と check-approval の遷移表 |
| 2 段のセルフレビュー | 各 phase skill の Step A/B(4 系統で分岐) | 統合 | spec-review(lint と spec-reviewer)の 1 本 |
| task_type 分岐 | request-spec、rules/task-types | 統合 | rules/doc-format.md の表 |
| 根拠収集(EV) | spec-investigate | 維持 | 同じ skill(Explore は直列で起動) |
| 引用予算 EC2/EC3 | rules/evidence-coverage | 廃止 | EV の存在確認だけ lint に残す |
| frontmatter 依存グラフ SD1-7 | rules/spec-dependency-graph | 作り直し | 固定 DAG と ID 文法 |
| AC / DES の Test Layers 宣言 | requirements、design | 廃止 | DES の `Kind` と API から必須の層を導出。層の所有は test-design |
| トレーサビリティ 3 系統 | design の行列、Satisfies、test-design の行列 | 統合 | `Satisfies:` と `Verifies:` のみ。行列は生成ビュー |
| Wave1 / Wave2 | spec-design | 維持(改名) | Skeleton → 確認 → Detail |
| バージョン鮮度 / ADR | spec-design | 維持 | spec-author の生成手順 |
| テスト容易性・seam | design | 統合 | design の `TST-N`(ハーネス、フィクスチャ、テストダブル) |
| モジュール境界と arch テスト | design、ヒント hook | 作り直し | DES `Layer:` と lint、PhaseReview で実行 |
| 必要ツール / Step0 | design、spec-implement | 作り直し | `TOOL-N` と `spec-tools-check.sh` |
| Phase 0 自動タスク / TDDSkip | spec-tasks | 作り直し / 廃止 | spec-plan.sh が生成 / DES `Kind` から導出 |
| PhaseRefactor と RF backlog | spec-tasks、rules | 維持 | 生成タスク `P{n}-REFACTOR` |
| PhaseReview | spec-implement 3.5 | 作り直し | 生成タスク `P{n}-REVIEW`(機械検査と review-worker) |
| セッション管理 / 自動再開 | session-manage.sh、auto-resume.sh(終了コード 42/43 を返す実装がない) | 作り直し | コミット trailer を正とする。StopFailure / SessionStart hook、`spec-resume-loop.sh` |
| タスク worktree とマージ | spec-implement 3.7 / 8 | 廃止 | spec ブランチへ直接コミット。失敗時は `.spec-workflow` を除外して破棄 |
| TDD と mutation testing | parallel-worker、spec-impl-*、cargo-mutants | 作り直し | spec-impl-tdd(stub ロック)。mutation は検証役が実行 |
| UT 品質検証 | unit-test-engineer、frontend-test-engineer | 維持(契約を追加) | 読み取り専用、JSON で出力 |
| レビューとコミット | review-worker | 維持 | `spec-git.sh commit` を呼べる唯一の主体 |
| rework / escalate / 診断 | spec-implement、review-worker、rules の 3 か所で食い違い | 統合 | rules/verdict.md の単一定義 |
| Phase Reset | rules/design-conformance | 作り直し | spec-change と `spec-reopen.sh`(差分のあるタスクだけ再オープン) |
| task-log | log-implementation、Stop hook(ほぼ発火しない) | 作り直し | SubagentStart / SubagentStop で記録し、コミットに同梱 |
| Final E2E Gate / PR / archive | spec-implement | 維持 | 生成タスク `FINAL`(CT / ST も必ず実行) |
| IT / E2E の 2 経路 | integration-test(-dotnet)、spec-e2e-implement | 統合 | `P{n}-IT/ST/SMK` と `FINAL` を integ-test-worker → auditor → review-worker で処理 |
| tasks メタ(_Prompt / _TestFocus / _Leverage ほか) | tasks.md | 廃止 | 承認済み文書の断片から brief を生成 |
| ヒント hook 7 本 | PreToolUse / PostToolUse の stdout | 廃止 | stdout はモデルに届かない(公式で確認済み)。必要なものはゲートへ移す |
| inject-spec / verify-tests-run / log-implementation / confirm-phase-progression | UserPromptSubmit / Stop hook | 廃止 | brief、コミットゲート、承認で代替 |
| コミットガード 3 種 | PreToolUse Bash(`^git commit` のみ判定し、`cd x && git commit` を素通しする) | 作り直し | guard-git.sh と spec-git.sh のゲート |
| spec-verify / graph / impact / status | 手動 skill | 統合 | spec-status(表示のみ)と lint |
| MCP のテンプレートコピー / prompts / task-validator | TS サーバー | 廃止 | テンプレートはプラグインが所有 |
| 死んだ rule(hybrid-inspection、spec-workflow-enforcement)、`_disabled/` | — | 廃止 | — |
| style 系 rule、フレームワーク参照 skill、create-pr、adr | — | 流用 | そのまま |

## 3. 引数・戻り値の型の不一致への対策

**specrail での発生実績(17 件)**

| 分類 | 件数 | 例 |
|---|---|---|
| I design のシグネチャが言語やクレートの制約上そもそも成り立たない | 5 | thiserror の `source` フィールド、async fn を `Arc<dyn>` で持つと E0038、Send+Sync の不足、rmcp `call_tool` の戻り値、axum の Json rejection |
| D 実装が design から逸脱した | 3 | `to_dto` が Result を返すようにした、status 応答にキーを追加した |
| H design の中で矛盾している | 2 | 依存方向の表と DES-8 / DES-11 の型が衝突した(ADR-0009) |
| J design の記述が欠けている | 2 | `ApprovalService::new` が未規定、delete 応答のキーが列挙されていない |
| A design と test-design の不一致 | 2 | test-design が FileProber を独自に追加した、具象型の ApprovalService をモックにしている |
| F フェーズをまたぐ呼び出し元と呼び出し先の不一致 | 2 | `SpawnedProcess::spawn` に、後の Phase で必要になる `--port` の受け口がない |
| E tasks と design の不一致 | 1(ほかに潜在 1) | tasks.md:700 が design の改訂に追従していない |
| B / C(テスト設計と RED、テストと実装) | 0 | tasks にシグネチャを逐語でコピーして固定していたため起きていない |

主因は design の段階にある。シグネチャが実際にコンパイルできるか、必要な情報がそろっているかを、承認前に確かめる手段がない。問題はいずれも RED の最初のコンパイル、GREEN、レビューのどこかで初めて表に出ている。

**対策 1: design 段階のシグネチャ・コンパイルゲート(I、H、F の一部を承認前に検出)**

- `spec-sigcheck.sh <spec>` を新設する。
  - design の DES Interfaces、MOD 定義、DEP のバージョンから使い捨ての crate(.NET なら project)を生成する。
  - 本体はすべて `todo!()` にして、`cargo check`(.NET は `dotnet build`)を通す。
  - 合否はコンパイラが判定し、LLM は判定に関わらない。
- DES に `Held-as:` 欄を設ける(例: `Arc<dyn ApprovalStore>`)。sigcheck はこの保持形で型付けし、`Send + Sync` を満たすかを検査する。E0038 や trait 境界の不足はここで検出される。
- 外部クレートの trait を実装する DES(rmcp の `ServerHandler`、axum の handler など)には `Implements: rmcp::ServerHandler::call_tool` の記載を必須にする。sigcheck は実際のクレートに対して空の impl を生成するので、シグネチャが違えばコンパイルが通らない。
- Module Boundaries の Layer ごとに sigcheck 内でモジュールを分け、許可された方向の `use` だけを生成する。依存方向の規則とシグネチャが矛盾していれば、名前解決できずにエラーになる(1.3 の型)。
- sigcheck の成功を承認リクエストの前提条件にする。guard-approval-request.sh が lint と sigcheck を実行する。旧 spec-design の Check 19(LLM による捨てコンパイル判定)はこれで置き換える。

**対策 2: DES を完全に書かせる文法(J と、J が原因の D を防ぐ)**

- 他の DES が構築する型は、Interfaces にコンストラクタを書くことを必須にする(lint)。
- 失敗しうる操作は `Result` を必須にし、`Raises:` でエラーとの対応を書く(lint)。
- API-N の Request / Response は、MOD の DTO を参照し、全フィールドを列挙する(応答キーの漏れを防ぐ)。
- 外部クレートのエラーの意味(axum の rejection、rmcp のエラー写像)は、`DEP-N` の `Contract:` 欄に EV 付きで書く。これを検証する IT を test-design に必須にする(L11 の網羅対象に加える)。

**対策 3: 下流での固定(B / C の 0 件を維持し、A / D / E / F を防ぐ)**

| 境界 | 防ぎ方 |
|---|---|
| design と test-design | 限定参照を必須にする(L04 / L06 / L07)。Then に書く型は、Target の戻り値型かエラー型に含まれること(L08)。Given は Target の引数名で束縛し、個数と名前を照合する(L21)。テストダブルにできるのは TST-N か、Interfaces 上の trait だけ(L22。FileProber の独自追加や具象型のモックを防ぐ) |
| フェーズをまたぐ呼び出し | ST / IT が使う TST-N の関数も、Given の引数束縛で照合する。後の Phase で必要な引数が欠けていれば、test-design の時点で lint エラーになる(2.4 → 3.6 の型) |
| tasks と design | tasks.md にはシグネチャを書かない(生成物にする)。brief は承認済みの design の断片から生成する |
| test-design とテストコード / テストコードと実装 | RED で DES Interfaces を写した stub に対してコンパイルが通ることを必須にし、シグネチャ行とテストの変更を禁止する(G4 / G5 / G6) |
| design と実装 | G4 でシグネチャ行の存在を確認する。Interfaces を表向き保ったまま手書きで迂回するような実装は禁止する。その場合 worker は `blocked(spec_conflict)` を返し、spec-change で design を直す |

## 4. 新フロー

### 4a. フェーズと文書

| Phase | 成果物 | 承認 | 上流 |
|---|---|---|---|
| S | steering(product / tech / structure)。tech.md に技術スタック / Test Commands / Test Layout / Wiring Files / Health / Sigcheck を追加。greenfield では対話で計画値を決める(§4f)。未承認の間は request-spec に進めない | 要 | — |
| 0 | request-spec.md(`RQ-N`、task_type。`greenfield` を追加し、技術選定・実行環境の節は廃止)。skill が `spec/{name}` ブランチを作る | 要 | steering |
| 0.5 | evidence/(`EV-{cat}-NNN`) | 不要 | — |
| 1 | requirements.md(`REQ-N` / `REQ-N.M` / `NFR-N` / `JRN-N`) | 要 | request-spec |
| 2 | design.md(`DES` / `MOD` / `API` / `TST` / `DEP` / `TOOL` / `KD`) | 要 | requirements |
| 3 | test-design.md(`UT-{DES}.M` / `CT-{DES}.M` / `IT` / `ST` / `E2E`) | 要 | requirements、design |
| 4 | tasks.md(`spec-plan.sh` が生成) | 不要 | 派生 |
| 5 | コード、task-logs、refactor-backlog.md | — | — |
| 変更 | changes.md(`CHG-NNN`) | 記録のみ | — |

### 4b. 事実の所有表(所有者以外は ID で参照するだけ)

| 事実 | 所有者 |
|---|---|
| 要求 / 受入基準 / NFR / ジャーニー | request-spec `RQ` / requirements `REQ-N.M`、`NFR`、`JRN` |
| コンポーネント、本番ファイルパス、層、フェーズ、依存 | design `DES`(`Files:` / `Layer:` / `Phase:` / `Depends:`) |
| 関数シグネチャ | DES `Interfaces:` のコードブロックだけ |
| 型 / エラーとその発生条件 | design `MOD`(`Owner:` / `Raises:`) |
| エンドポイント | design `API` |
| テストハーネス / フィクスチャ / テストダブル | design `TST` |
| 依存クレート / ツール | design `DEP` / `TOOL` |
| テストコマンド / 配置規約 | steering tech.md |
| テストケース仕様 / IT・ST・E2E のファイルパス | test-design |
| タスクと完了状態 | tasks.md(生成)とコミット trailer の `Spec-Task:` |

ID と参照の規則:

- ID は振り直さず、欠番を再利用しない。
- 定義は見出し `### ID: Name` で書く。
- 行番号による参照は禁止(L03)。

### 4c. 承認台帳と変更伝播(specrail へ渡す MCP 契約 v1)

- **台帳**:
  - 場所は `.spec-workflow/approvals/{spec}/ledger.json`。
  - 文書ごとに `{sha256, approvalId, approvedAt, upstream:{doc:sha256}}` を記録する。
  - 承認された本文は `content/{sha}.md` に保存する。
  - 書き込むのは MCP サーバーだけ。
- **request と approve**:
  - request は、上流がすべて承認済みかつ未変更であることを前提条件にする。
  - approve は、request 時点の sha と現在の sha が異なれば拒否する。
- **状態**:
  - unapproved / pending / modified / stale / approved の 5 つ。
  - 判定は Bash と TS の両方で実装し、共有フィクスチャで両者の結果が一致することを確認する。
- **上流が再承認されたとき**:
  - 下流は stale になる。
  - check-approval が、DAG 順で最初の stale 文書を修正モードで開く。入力は旧版との diff と lint エラー。
  - 全文書が approved に戻ったら、plan を再生成し、`spec-reopen.sh` を実行する。
- **実装中に出た情報の行き先**(承認済み文書には書かない):
  - 申し送りは JSON の `handoffs`。
  - リファクタ候補は `rf`。
  - 仕様の矛盾は `blocked(spec_conflict)` として返し、review-worker が escalate して spec-change へ回す。

### 4d. 実装ループ(直列。オーケストレーターは文書本文を読まない)

| タスク種別 | 実装 | 検証(読み取り専用) | 判定とコミット |
|---|---|---|---|
| DES(logic / types) | impl-worker(spec-impl-tdd) | unit-test-engineer | review-worker |
| DES(ui) | impl-worker(CT も TDD で書く) | frontend-test-engineer | review-worker |
| DES(wiring / config) | impl-worker(ビルドとスモーク) | — | review-worker |
| TST、`P{n}-IT/ST/SMK` | integ-test-worker | integ-test-auditor | review-worker |
| `P{n}-REFACTOR` | impl-worker(テストファイルの変更は禁止) | unit-test-engineer | review-worker |
| `P{n}-REVIEW` | `spec-phase-check.sh`(それまでの UT/CT/IT/ST、スモーク L1-L4、arch テスト、CVE、シグネチャ適合) | — | review-worker |
| `FINAL` | JRN ごとの E2E → 全層を一括実行 | integ-test-auditor | review-worker → archive → create-pr |

- **brief**: `spec-brief.sh` が生成する。中身は次のとおり。
  - 対象 DES の断片と、それが所有する MOD
  - 依存先 DES の Interfaces
  - テストの断片(test-design からのみ取る)
  - AC
  - 自分宛ての handoffs
- **情報源と食い違ったとき**:
  - テストケースの源は test-design だけ、シグネチャの源は DES だけ。
  - 両者が食い違ったら、worker はどちらかを選ばずに `blocked(spec_conflict)` を返す。
- **コミットゲート** `spec-git.sh commit`:

  | # | 条件 |
  |---|---|
  | G0 | 開始時に作業ツリーがクリーン |
  | G1 | 台帳の全文書が approved |
  | G2 | 実行記録がそろっている |
  | G3 | 変更範囲が DES Files、テストファイル、Wiring Files に収まる |
  | G4 | シグネチャ行が Files に存在する |
  | G5 | `@test ID` の集合が test-design と一致する |
  | G6 | RED 以降にテストが変更されていない |
  | G7 | テストが通る |
  | G8 | fmt / lint が通り、依存が DEP の範囲内で、audit が通る |
  | G9 | tasks.md と task-log を同梱し、trailer 付きの 1 コミットにする |

- **判定**(rules/verdict.md に一本化):
  - commit
  - rework(上限 3 回): 要件未達、設計を超える余剰、シグネチャ逸脱、弱いテスト、品質違反
  - escalate: 仕様内の矛盾、design の変更が必要、rework 上限到達、の 3 条件のみ
- **再開**:
  1. StopFailure で `.resume` を書く。
  2. SessionStart で状態を注入する。
  3. trailer から現在位置を再計算し、途中だったタスクは破棄してやり直す。

### 4e. セルフレビュー

- spec-review を唯一の検査器にする。手順は `spec-lint.sh`(決定的)→ spec-reviewer(LLM、文書ごとに 5 項目以内)→ 修正で、最大 3 回。
- LLM によるチェックを現行の 82 件から 12 件に減らし、約 30 件を lint に移す。tasks の 26 件は、tasks を生成物にするので不要になる。

### 4f. 新規プロジェクト(greenfield)と steering が未作成の場合

**入口の判定**

spec-request-spec は起動時に 2 点を判定する。

- steering 3 文書が承認済みか
- 既存コードがあるか(Cargo.toml / *.csproj / package.json などのマニフェストとソースディレクトリの有無)

steering が未承認なら、steering-doc を先に実行させる。steering が承認されるまで request-spec へは進めない(guard で拒否する)。

| 状況 | steering-doc のモード | 内容 |
|---|---|---|
| 既存コードあり、steering なし | 抽出 | 現行どおりコードから導出する(EV 付き) |
| 既存コードなし(greenfield) | 決定 | ユーザーとの対話で決める。product は目的・利用者・Non-Goals。tech は言語・フレームワーク・ツールチェーンの最小版・テストコマンド・テスト配置規約・Wiring Files・Health を**計画値**として決める(バージョンはレジストリで鮮度を確認する)。structure はディレクトリ構成。steering の承認をもって正本とする |

**所有の整理**

- request-spec の「技術選定」「実行環境」節は廃止する。プロジェクト全体の技術的事実は tech.md が所有し、request-spec は参照するだけにする。
- spec 固有の追加依存・追加ツールは design の DEP / TOOL が所有する。

**task_type `greenfield` の追加**

- spec-investigate はコード調査をしない。
- DEP `Contract:` の根拠となる外部クレートの API 契約だけを、`EV-lib-NNN` として収集する。情報源は docs.rs / context7 / `cargo fetch` 後のベンダーソース。

**ブートストラップ**

- greenfield の design では、Phase 0 にブートストラップ用の DES(`Kind: config`)を必須にする。対象はワークスペースの Cargo.toml、rust-toolchain.toml、CI、コンテナ。
- spec-plan は `P0-TOOLS` → ブートストラップ DES を先頭に生成する。
- P0 の完了条件は、tech.md のテストコマンドが空のテストスイートで exit 0 になること。この時点で、tech.md の計画値が実体になる。

**sigcheck はプロジェクトのコードに依存しない**

| モード | 条件 | 動作 |
|---|---|---|
| standalone | greenfield、または Interfaces が既存コードの型を参照しない | 一時ディレクトリに scratch workspace を生成する。DEP の crate / version を Cargo.toml に書き、DES Files の crate root ごとに member を作り、その中に Layer ごとの module を置く |
| overlay | Interfaces が既存コードの型(EV で引用されたもの)を参照する | base commit の一時 worktree に stub module を追加して `cargo check` を実行する |

- 前提として TOOL-N(cargo / rustc、dotnet)が必要。sigcheck の前に spec-tools-check を実行し、ツールが無ければ導入手順を示して停止する(黙って SKIP しない)。
- crate の取得にはネットワークが必要。取得に失敗したら sigcheck の失敗として扱い、承認リクエストを止める。オフライン環境では、vendor 済みキャッシュの場所を tech.md に書く。
- 対応言語は Rust と .NET。それ以外の言語では、tech.md に `Sigcheck: unsupported(<理由>)` を宣言することを必須にし、承認リクエストの結果に明示する。宣言のない SKIP は lint エラーにする。

## 5. 新構成(`.claude-plugin/`)

**skills**

| 区分 | skill |
|---|---|
| 仕様作成 | steering-doc、spec-request-spec、spec-investigate、spec-requirements、spec-design、spec-test-design |
| 検査・承認・変更 | spec-review、check-approval、spec-change、spec-status、spec-archive |
| 実装 | spec-implement、spec-impl-tdd、spec-impl-integ、spec-impl-review |
| 小修正で維持 | tdd-skills(-rust / -dotnet)、regression-test-policy、flaky-test-management、cargo-mutants |
| 削除 | spec-tasks、spec-verify、spec-graph、spec-impact-analyze、spec-e2e-implement、spec-impl-test-write / code / test-run、log-implementation、integration-test(-dotnet) |

**agents**

- impl-worker(旧 parallel-worker)
- integ-test-worker
- unit-test-engineer、frontend-test-engineer、integ-test-auditor(いずれも読み取り専用。auditor からは TaskUpdate を外す)
- review-worker
- spec-author、spec-reviewer(新設)

出力はすべて最終メッセージ末尾の JSON。SubagentStop hook が runs/ に記録する。

**rules**(skill が明示的に Read する。自動ロードはされない)

- 新設: doc-format.md、test-taxonomy.md、verdict.md
- 流用: style 系、security、type-safety、quality-checks
- それ以外は削除。enforcement-levels は docs/ へ移す。

**hooks**

- session-start.sh(SessionStart。stdout がモデルに届く)
- guard-edit.sh、guard-approval-request.sh、guard-agent.sh、guard-git.sh(exit 2 で拒否)
- record-subagent.sh(SubagentStart / SubagentStop)
- stop-failure.sh
- post-edit.sh(維持)

**scripts**(Bash。依存は jq / sha256sum / tsort / gawk)

lib/common.sh、spec-slice、spec-index、spec-lint、spec-sigcheck(Rust / .NET の stub を生成してコンパイル)、spec-state、spec-ledger-rebuild、spec-plan、spec-next、spec-brief、spec-trace、spec-git、spec-tools-check、spec-run-tests、spec-phase-check、spec-reopen、spec-resume-loop

**templates と契約**

- テンプレートは `.claude-plugin/templates/docs/*.md`。連鎖する文書は user-templates による上書きを禁止する。
- 台帳の契約は `.claude-plugin/contract/approval-ledger-v1.md` とフィクスチャ。TS、Bash、将来の Rust で共有する。

## 6. 構築順序(このブランチ `worktree-redesign-v2`、1 ステップ 1 コミット)

| # | 内容 |
|---|---|
| B-1 | 旧ファイルを先に一括削除する。対象は §5 の削除対象の skill、置き換える agent / rule / hook / script、`_disabled/`。あわせて TS 側のテンプレートコピーと MCP prompts を停止し、`src/markdown/templates` を削除する。旧版の動作は保たない |
| B0 | hook の入力を記録するプローブで次を実測し、docs/ に記録する: Agent ツールの matcher 名、プラグイン agent の `agent_type` の書式、SubagentStop でブロックできるか |
| B1 | doc-format.md、test-taxonomy.md、新テンプレート、正常な見本 spec、失敗フィクスチャ F01-F15 |
| B2 | spec-slice / index / lint、vitest から Bash を呼ぶテスト、`npm run lint:sh`(shellcheck) |
| B2b | spec-sigcheck.sh(Rust を先に作り、.NET は後続)。specrail で起きた I / H 型の再現フィクスチャ(thiserror の `source`、async fn と dyn の E0038、Send+Sync の不足、依存方向の違反、外部 trait のシグネチャ違い)が、いずれもコンパイルエラーになること |
| B3 | TS 側の台帳(`src/core/spec-ledger.ts` を新設、`src/tools/approvals.ts` と `src/dashboard/approval-storage.ts` を改修)、spec-state.sh、ledger-rebuild、contract/ |
| B4 | spec-plan / next / brief / trace |
| B5 | spec-author / spec-reviewer、spec-review、check-approval、仕様フェーズの skill 群 |
| B6 | guard-edit、guard-approval-request、session-start |
| B7 | サンドボックスで仕様フェーズを通しで実行 |
| B8 | spec-git.sh(G0-G9)、tools-check、run-tests、phase-check |
| B9 | 実装系 agent 6 体、spec-impl-tdd / integ / review |
| B10 | spec-implement、guard-agent、guard-git、record-subagent、stop-failure、resume-loop |
| B11 | spec-change、spec-reopen、spec-status、spec-archive |
| B12 | サンドボックスで全工程を実行し、途中で design の変更を注入する |
| B13 | メジャーバージョンに上げ、README と PLUGIN_FLOWS を新フローの内容に書き直す |
| B14 | main へマージし、specrail の approval-gate を新フローで作り直す。旧 spec は archive へ移す。specrail には steering 文書が存在しない(`.spec-workflow/steering/` には `logs/` しかない)。§4f の入口判定から始める。既存コードを残して作り直すなら抽出モード、ゼロから作るなら greenfield の決定モードで始める(どちらにするかは B14 の時点で決める) |

- サンドボックスでの検証では、新しいプラグインを `--plugin-dir` で読み込む。
- specrail 側へ先送りするもの: 台帳契約 v1 の Rust 実装、最小限の承認 UI、MDX 検証から markdown lint への置き換え。

## 7. 検証

- テストは `npm test`(vitest。TS の台帳と、子プロセスで起動する Bash スクリプト)と `npm run lint:sh`。
- 失敗フィクスチャ F01-F15(specrail で実際に起きた食い違いを再現したもの)が、それぞれ固有のエラーコードで失敗すること。
- シグネチャ不一致の 17 件(§3)について、design 段階で検出できるもの(I / H / J / A / F)は sigcheck または lint のフィクスチャで失敗すること。検出できないもの(axum の rejection のような実行時の意味論)は、DEP `Contract:` に対応する IT が必須になっていること。
- 実データで読み取りだけ行う確認: specrail の snapshot から台帳を再構築したとき、test-design と tasks が stale と判定されること。
- greenfield の確認は、空のディレクトリから始める。
  1. steering-doc が決定モードで起動する
  2. request-spec が steering の承認前には拒否される
  3. sigcheck が standalone モードで通る
  4. P0 のブートストラップ後に tech.md のテストコマンドが exit 0 になる
- ツールが無い場合、sigcheck と tools-check が黙って SKIP せず、停止すること。
- サンドボックス(小さな Rust API、DES 4 つ・API 2 つ程度)で全工程を通し、途中で design を変更する。確認すること:
  1. 実装が止まる
  2. 下流が修正に回る
  3. 再オープンされるのが差分のあるタスクだけ
  4. 中断から再開できる
- 成功基準(specrail で作り直すとき):
  - 承認時点の lint エラーが 0 件
  - design の再承認から下流の再承認までの間に、コードのコミットが 0 件
  - `\.md:\d+` 形式の参照と、限定参照になっていないコード表記が 0 件
  - マージコミットと bookkeeping コミットが 0 件
