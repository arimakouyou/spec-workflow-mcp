# PR レビュー指摘パターン（PUSH 前チェックリスト）

## このファイルの使い方

- PUSH / PR 作成前に、このファイルのチェックリストを上から順に確認する
- 該当指摘が再発したら「代表例」セクションに追記し、成熟したら `.claude-plugin/rules/` への昇格を検討（feedback-loop.md の promotion path）
- チェック項目のうち機械判定できるものは `grep` / `rg` / hook で自動化する

## メタ情報

- **分析対象**: 全 merged PR 43 件（PR #1-#51、dependabot 3 件除く）
- **総レビューコメント数**: 約 450 件（bot/非レビュー除外後）
- **レビュアー**: ほぼ全件 GitHub Copilot bot（人間査読ほぼ不在 — これ自体が改善余地）
- **生成日**: 2026-04-16
- **再生成方法**: 末尾の「生成方法」節を参照

### カテゴリ別件数（概算）

| # | カテゴリ | 件数 | 割合 |
|---|---------|-----|------|
| 1 | 整合性 / 重複 | **約 158** | **35%** |
| 2 | シェル堅牢性（hook/CI） | 約 60 | 13% |
| 3 | ドキュメント乖離 | 約 45 | 10% |
| 4 | プロセス / CI | 約 30 | 7% |
| 5 | 設計適合 / スキーマ | 約 28 | 6% |
| 6 | セキュリティ | 約 22 | 5% |
| 7 | ID / 命名揺れ | 約 22 | 5% |
| 8 | テスト品質 | 約 15 | 3% |
| 9 | その他 | 約 70 | 16% |

---

## A. 整合性 / 重複（最優先カテゴリ — 全指摘の 35%）

同一概念を複数ファイル（rules / skills / agents / templates / docs）で定義していることに起因する齟齬。全レビュー指摘の最大の再発源。

### PUSH 前チェック

- [ ] 新規 ID 規約（QC/DR/FC/SD 等）を追加・変更したら、**リポジトリ全体を grep** して全参照箇所の用語・キー名・コマンドを揃える
- [ ] `.claude-plugin/rules/` を変更したら、`.claude-plugin/skills/` / `.claude-plugin/agents/` / `src/markdown/templates/` を全 grep で参照箇所洗い出し
- [ ] placeholder 命名が統一されている（`{N}` vs `{phase-number}`、`{skill-name}` vs `{skill name}`、snake vs kebab vs camel）
- [ ] 同一 prompt 内で矛盾指示がない（例: 「Review and fix」と「Mode: check — DO NOT modify」の共存）
- [ ] フィールド名 / キー名が統一されている（`responsible_files` vs `responsible`、`reviewOutcome` vs `outcome`）
- [ ] オプション名 / コマンド形式が統一されている（`-warnaserror` vs `--warnaserror`、`--no-restore` 付与漏れ）
- [ ] 「定義ファイル + 全参照ファイル」を 1 PR としてセット化（部分 PR で齟齬を残さない）

### 代表例

- **PR #41**: `-warnaserror`（MSBuild 形式）と `--warnaserror` が 5 箇所で不統一
- **PR #50**: `responsible_files`（wave-harness）vs `responsible`（parallel-worker / spec-implement）のキー名不統一
- **PR #22**: `quality-checks.md` Step C で「テスト無→SKIP」と「仕様あり→FAIL」が同時記述されルール矛盾
- **PR #29**: `feedback-loop.md:41` が `.claude/rules/` を指すが実体は `.claude-plugin/rules/`
- **PR #20**: `MAX_HEAVY` と `MAX_HEAVY_AGENTS` が同一ファイル内で混在（12 箇所指摘）
- **PR #50**: `diagnostic_history` が array / string で期待が不一致、`## Diagnosis` と DR2 フォーマットが齟齬
- **PR #49**: `/spec-implementation`（誤記）vs `/spec-implement`、`next:` プレースホルダの混乱
- **PR #12**: `integration-verification`（kebab）vs `integration_verification`（snake）vs `autoFixed`（camel）混在
- **PR #50**: `.claude-plugin/rules/INDEX.md` 総計 110 が実件数と齟齬

---

## B. シェル堅牢性（hook / CI / スクリプト — 13%）

shell スクリプト、GitHub Actions、hooks の堅牢性。継続的に再発。

### PUSH 前チェック

- [ ] `pipefail` 有無（`| tee` する箇所は `set -o pipefail` または `${PIPESTATUS[@]}` で失敗検出）
- [ ] 外部コマンド依存は `command -v` ガード（`jq` 未導入環境で hook が 127 終了すると commit 自体が止まる）
- [ ] `|| true` が本番エラーを握りつぶしていないか（clippy 失敗がゲート通過する事例あり）
- [ ] `$1` / `$2` / `${N}` を未検証で参照していないか（`set -u` で unbound variable）
- [ ] **空入力 / exit ≠ 0 / 未初期化変数 / ディレクトリ不存在** の 4 条件で破綻しないか
- [ ] 移植性（BSD / macOS 差異: `xargs -r`、`shuf`、`vm_stat` ページサイズ、bash `RANDOM` レンジ、`dirname` ループ）
- [ ] `local` をトップレベルで宣言していないか（`local: can only be used in a function` で commit ブロック事故）
- [ ] `grep` の exit 2（エラー）を 0/1（マッチ有/無）と混同していないか
- [ ] tilde 展開（`${VAR:-~/foo}`）が実際に展開されているか確認

### 代表例

- **PR #45**: `lockfile-guard.sh` で `jq` 未導入環境だと hook が 127 終了、git commit 自体を阻害
- **PR #45**: `local` をトップレベルで宣言し、条件次第でスクリプトがクラッシュ
- **PR #42** 複数: `cargo test | tee` に pipefail なく失敗がマスクされる
- **PR #14**: `dirname "."` が相対パス入力で無限ループ
- **PR #19**: `${SCCACHE_DIR:-~/...}` で tilde 展開されない
- **PR #29**: `grep` exit 2 を 0/1 判定に混同
- **PR #49**: `--timeout` を末尾引数で指定時に `$2` 未定義で `set -u` 終了
- **PR #32**: `create-pr:211` で空入力時に `xargs grep` がハング
- **PR #2**: PostToolUse 末尾 `|| true` で clippy 失敗がゲート通過

---

## C. ドキュメント vs 実装の乖離（10%）

README / TOOLS-REFERENCE / guides.ts / INDEX の記述と、実際の配布物・コード・ツール登録の整合性。

### PUSH 前チェック

- [ ] 旧スキル名 / 旧パス / 旧コマンドが残っていないか（`/loop` 旧記述、`/spec-implementation` → `/spec-implement` 等）
- [ ] README の数値（「30 skills」等）が実体と一致（リファクタで変動するハードコード数字に注意）
- [ ] `TOOLS-REFERENCE.md` のサンプルが実際の handler schema と一致（`approvals` は `category` / `categoryName` 必須）
- [ ] Phase 0 legacy 互換（`request-spec.md` 無し spec を壊さないか）
- [ ] 言語混在していないか（英語 README 内の日本語残り）
- [ ] ネストフェンス（外側 ``` の中に内側 ``` がある場合、**長さを変える**）
- [ ] コード例の `import` / `defineConfig` / 擬似コード明示
- [ ] `package.json#files` に配布対象が含まれているか（`.claude-plugin/**`）

### 代表例

- **PR #9**: with-dashboard の「auto-started dashboard」説明と `.mcp.json` 実態の乖離（6 箇所で同趣旨）
- **PR #13**: TOOLS-REFERENCE に存在しない `create-spec-doc` tool を記載
- **PR #43**: `approvals` のリクエスト例が実際のスキーマと乖離しコピペで失敗
- **PR #41**: Playwright VRT 例が `defineConfig` / `test` / `expect` を import せず動かない
- **PR #43**: TOOLS-REFERENCE が legacy 機能を現役のように記述
- **PR #41**: `worker-prompt.md` / `auditor-prompt.md` のネストフェンスでレンダリング崩壊

---

## D. プロセス / CI / ワークフロー（7%）

GitHub Actions、publish フロー、PR コメント処理。

### PUSH 前チェック

- [ ] fork PR から動く job で `permissions` が必要な値を網羅（`issues: write` / `pull-requests: write` / `contents: write`）
- [ ] fork PR で secrets が使えないケースの fallback
- [ ] `listComments` / `listReviewComments` のページング（デフォルト 30 で sticky comment が重複投稿化）
- [ ] `workflow_dispatch` で `github.event.head_commit` が undefined になる扱い
- [ ] publish フローで `git push` のブランチ指定、detached HEAD 回避
- [ ] bump commit は publish 成功後に push（失敗時に version だけ進むリスク）
- [ ] `package-lock.json` の `git add` 漏れ
- [ ] CI テンプレと `.claude-plugin/rules/quality-checks.md` の parity（SSoT 崩壊が複数 PR で発生）
- [ ] `dtolnay/rust-toolchain@{{TOOLCHAIN}}` のようなプレースホルダ誤適用
- [ ] concurrency / 失敗時の rollback 戦略

### 代表例

- **PR #43**: PR コメント投稿に `issues: write` 権限欠落で 403
- **PR #15**: publish detached HEAD、bump commit が publish 前に push、`package-lock.json` 未 add
- **PR #42**: `listComments` per_page デフォルトで sticky comment が重複投稿化
- **PR #29**: `ci-rust.yml` で `cargo-audit` 未導入時に無条件実行、`npm test -- --run` が Vitest 固有
- **PR #42**: fork PR で GITHUB_TOKEN の権限制限への fallback なし

---

## E. 設計適合 / スキーマ（6%）

既存マネージャ / パーサ / design.md との乖離。**dashboard で silent drop する類のバグが最も危険**。

### PUSH 前チェック

- [ ] 出力形式が既存パーサ（`task-parser.ts` / `ImplementationLogManager` 等）の期待と一致
- [ ] design.md の API 契約（エンドポイント / 型 / ステータスコード / 必須フィールド）と実装の一致
- [ ] dashboard / VSCode 拡張が silent drop しないか（`JSON.parse()` 失敗で `reviewProcess` が消える等）
- [ ] 不変条件（`findings.length === reworkCount + 1` 等）が markdown シリアライザまで貫通しているか
- [ ] unicode / 改行 / escape の扱いが silently 破壊していないか
- [ ] REST vs GraphQL の前提違い（resolved 判定は REST では取れない、GraphQL `reviewThreads` 必須）

### 代表例

- **PR #21**: `log-implementation` の出力が `ImplementationLogManager.entryToMarkdown()` と不一致で dashboard で silent drop
- **PR #32**: `handle-pr-comments` の resolved 判定が REST `/comments` 前提だが GraphQL 必須
- **PR #4**: `reviewProcess.findings.length === reworkCount + 1` 不変条件と markdown シリアライザの未同期
- **PR #42**: `extract_dependencies` が nested dir / group import 未対応
- **PR #43**: `approvals` の request schema に `category` / `categoryName` 未記載

---

## F. セキュリティ（5% — 頻度低いが深刻）

### PUSH 前チェック

- [ ] path 境界: `safeJoin` の `startsWith` は `/base` と `/base2` を区別できない → normalized path + separator 境界で比較
- [ ] 外部入力の JSON escape（log injection / JSON 破壊）
- [ ] 外部入力の regex 検証（`.` ワイルドカード誤マッチ、lockfile 部分一致）
- [ ] ハードコードされた認証情報・トークン
- [ ] fork PR からの secrets 露出
- [ ] permissive な glob 許可（`Read(**/*key*)` 等）
- [ ] CORS 拒否を `callback(new Error(...))` で返すと 500 になりポリシー判断が error 化

### 代表例

- **PR #1**: `safeJoin()` が `/base2` を `/base` と誤判定（path traversal 近似）
- **PR #3**: CORS 拒否で 500 を返し、ポリシー判断がサーバーエラー扱いに
- **PR #49**: `approvalId` を未 escape で JSON エラーメッセージに埋め込み log injection 余地
- **PR #45**: regex `.` ワイルドカードが予期せぬマッチ、lockfile 部分一致誤判定
- **PR #2**: `.claude/settings.json` の `Read(**/*key*)` permissive 設定

---

## G. ID / 命名揺れ（5%）

- [ ] 同一概念の変数が複数名で登場していないか（例: `MAX_HEAVY` / `MAX_HEAVY_AGENTS`、`responsible_files` / `responsible`）
- [ ] ネームスペース prefix（`spec-workflow-mcp:` 等）の統一
- [ ] 新規 ID 体系（REQ-N.M / DES-N / UT-N.M / FC1-FC6 / DR1-DR6 / SD1-SD7）の一貫性
- [ ] 新規スキル名がリポジトリ内 grep で一意か（旧名が本文に残っていないか）

---

## H. テスト品質（3% — 頻度低いが改善余地）

- [ ] hook / shell スクリプトに対するユニットテスト（現状はほぼ未着手）
- [ ] アサーションが `is_ok()` / `!is_empty()` だけでなく値を検証しているか（review-worker E2-3 相当）
- [ ] 境界値・エラーパス・エッジケースが happy path だけにとどまらないか
- [ ] 統合テストで `UseInMemoryDatabase` 等の禁止パターンを使っていないか

---

## 特筆すべき単発指摘（頻度低・影響大）

| PR | 指摘 | なぜ重要 |
|----|------|---------|
| #21 | スキル出力と `ImplementationLogManager.entryToMarkdown()` の乖離 | dashboard で silent drop、運用中に欠損が気付かれにくい |
| #32 | `handle-pr-comments` resolved 判定が REST 前提、GraphQL 必須 | スキルの中核機能が動作しない |
| #15 | publish CI の根本設計欠陥（detached HEAD、bump 先行 push） | main の version だけ進む運用事故 |
| #4 | `reviewProcess` 不変条件と markdown シリアライザ未同期 | データ整合の致命的バグ |
| #1 | `safeJoin` containment が `startsWith` のみ | path 境界のセキュリティ問題 |
| #45 | `lockfile-guard.sh` の `local` が関数外宣言で commit ブロック | 品質 hook がむしろ開発を止める重大レグレッション |
| #18 | legacy spec で Read 必失で spec-design/tasks/test-design 全停止 | 既存破壊 |
| #49 | `poll-approval.sh` の `$2` 未検証 / script exit code と skill 解釈の不一致 | 承認フロー基盤のロバストネス欠如 |
| #41 | .NET AspNetCore 例が `UseInMemoryDatabase` 推奨、整合性ポリシーに反する | 同 PR 内で方針矛盾 |

---

## 全期間を通じた所見

1. **人間レビュアーがほぼ不在**で、機械的パターンマッチ型の Copilot 指摘が大半。重要な設計欠陥と文言の揺れが同列に並ぶため、本来の優先度フィルタが効いていない
2. **整合性 / 重複が圧倒的 1 位**（35%）— ルール追加時の波及漏れが最大のリスク。**定義ファイル + 全参照ファイルをセットで PR 化**する運用が必要
3. **shell / CI / hook 系の堅牢性欠如**（エラー処理 + セキュリティ + CI で約 40%）が第 2 の多発領域。CI テンプレ用チェックリストと shell スニペットのライブラリ化が有効
4. **Single Source of Truth の崩壊**（quality-checks.md ⇔ CI テンプレ、`ImplementationLogManager` ⇔ log-implementation、design.md の Required Tools ⇔ test-design.md）が複数 PR で反復
5. **macOS/BSD 環境差**（`xargs -r`、`shuf`、`vm_stat`、`dirname`、bash `RANDOM`）が一貫した盲点
6. **テスト品質カテゴリが少ない**のは、対象 PR の多くがドキュメント / プラグイン設定 / スクリプトだったため。hook スクリプト自身に対するテストは今後の改善余地

---

## 歴史的指摘（現在は解消済み、参考）

以下はプラグイン移行期（PR #1-#10）に集中した指摘で、現 main では解消済み。継続監視対象ではない。

- **PR #7**: `package.json#files` が `.claude-plugin/**` を含まず → PR #10 で修正
- **PR #9**: with-dashboard の「auto-started dashboard」説明と実態乖離 → marketplace/README 整備済み
- **PR #2**: `.claude/settings.json` の `Read(**/*key*)` 等の permissive glob → プラグイン側 `.claude-plugin/hooks/` 配置で整理済み
- **PR #46**: `spec-workflow-mcp-with-dashboard` プラグイン削除に伴う残存記述 → 削除済み

---

## 生成方法（再生成する場合）

本ファイルは以下の手順で再生成できる（2026-04-16 時点、Claude Code 経由）:

1. `gh pr list --state merged --limit 60 --json number,title,comments` で merged PR の一覧取得
2. コメント 0 件の dependabot PR を除外
3. 3 Agent 並列で期間分担（#1-#17 / #18-#39 / #40-#51）
4. 各 Agent が `gh api repos/arimakouyou/spec-workflow-mcp/pulls/{N}/comments` と `/reviews` を取得、指摘をカテゴリ分類し Top 5 パターン + 特筆指摘を返す
5. メインエージェントが 3 Agent の結果を統合し、本ファイルに書き出す
6. 新規 PR が増えたら「メタ情報」と「生成日」を更新し、頻出パターン / 代表例 / 単発指摘に追記する
