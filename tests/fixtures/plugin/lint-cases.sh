#!/usr/bin/env bash
# spec-lint.sh の失敗フィクスチャ。
# 各 case_* 関数は todo-ok のコピー($ROOT)を 1 か所だけ書き換えて違反を入れ、
# 期待する lint コードを EXPECT に設定する。呼び出し側は ROOT を設定してから関数を実行する。
# F 系は specrail approval-gate で実際に起きた食い違い、S 系はシグネチャ境界の不一致を再現する。

SPEC_REL=".spec-workflow/specs/todo-api"
STEER_REL=".spec-workflow/steering"

_spec() { printf '%s/%s/%s' "$ROOT" "$SPEC_REL" "$1"; }
_steer() { printf '%s/%s/%s' "$ROOT" "$STEER_REL" "$1"; }

# --- specrail で起きた食い違い -------------------------------------------------

# F02: IT が design 改訂前の型名のまま(API の Response / Errors に無い型を期待する)
case_F02() { EXPECT=L08; sed -i 's/本文が `MOD-7:TodoResponse` で、title が "buy milk"/本文が `MOD-2:Todo` で、title が "buy milk"/' "$(_spec test-design.md)"; }

# F04: 行番号による参照
case_F04() { EXPECT=L03; sed -i 's/^#### UT-2.1: 前後の空白を除いたタイトルを受け入れる$/#### UT-2.1: 前後の空白を除いたタイトルを受け入れる(design.md:120 参照)/' "$(_spec test-design.md)"; }

# F05: test-design が design にないクレートを持ち込む
case_F05() { EXPECT=L04; sed -i 's/^  - status 201$/  - status が `reqwest::StatusCode::CREATED` である/' "$(_spec test-design.md)"; }

# F06: test-design が design にない関数を発明する
case_F06() { EXPECT=L06; sed -i '0,/^- Target: `DES-2:Title::parse`$/s//- Target: `DES-2:classify_size`/' "$(_spec test-design.md)"; }

# F07: どこにも定義されていないモジュールパス
case_F07() { EXPECT=L04; sed -i '0,/^  - `TST-1:spawn`$/s//  - `event_stream::testing::connect_with` で接続する/' "$(_spec test-design.md)"; }

# F10: IT に Technology 行(廃止した欄)がある
case_F10() { EXPECT=L16; sed -i 's/^### IT-1: 有効なタイトルで登録すると 201 を返す$/&\n- Technology: DES-4/' "$(_spec test-design.md)"; }

# F11: 同じテストの Category を二重に書く
case_F11() { EXPECT=L16; sed -i '0,/^- Category: Happy$/s//- Category: Happy\n- Category: Edge/' "$(_spec test-design.md)"; }

# F12a: design の散文にコードを書く(Ok と Err(Conflict) の食い違いの温床)
case_F12a() { EXPECT=L05; sed -i 's/^- Purpose: タイトルを検証して Todo を登録し、一覧を返す$/- Purpose: タイトルを検証して Todo を登録し、重複時は `Err(Conflict)` を返す/' "$(_spec design.md)"; }

# F12b: 廃止したエラー表の節を design に置く
case_F12b() { EXPECT=L15; printf '\n## Error Handling\n\n- 重複時は既存のレコードを返す\n' >> "$(_spec design.md)"; }

# --- シグネチャ境界の不一致 -----------------------------------------------------

# S-A1: Then の型が Target 関数の戻り値型・エラー型に無い
case_S_A1() { EXPECT=L08; sed -i 's/^  - `Ok` の値が `MOD-2:Todo` で、タイトルが "buy milk"、done が false である$/  - `Ok` の値が `MOD-7:TodoResponse` である/' "$(_spec test-design.md)"; }

# S-A2: 具象型をテストダブルにする(trait ではない)
case_S_A2() {
  EXPECT=L22
  cat >> "$(_spec design.md)" <<'EOF'

### TST-3: 偽のサービス
- Kind: double
- Phase: 1
- Files: src/domain/service_double.rs
- Depends: DES-4
- Implements: `DES-4:TodoService`
- Interfaces:
  ```rust
  pub struct FakeService;
  ```
EOF
}

# S-F: 後の Phase が必要とする引数を Setup が束縛していない
case_S_F() { EXPECT=L21; sed -i 's/^  pub async fn spawn() -> TestServer;$/  pub async fn spawn(port: u16) -> TestServer;/' "$(_spec design.md)"; }

# S-G: Given の引数名が Target のシグネチャと違う
case_S_G() { EXPECT=L21; sed -i '0,/^  - raw = "  buy milk  "$/s//  - text = "  buy milk  "/' "$(_spec test-design.md)"; }

# S-J1: Held-as があるのにコンストラクタが無い
case_S_J1() { EXPECT=L24; sed -i '/^      pub fn new(store: Arc<dyn TodoStore>) -> Self;$/d' "$(_spec design.md)"; }

# S-J2: 誰も返さないエラー variant
case_S_J2() { EXPECT=L25; sed -i 's/^      TitleTooLong { max: usize },$/&\n      #[error("duplicate")]\n      Duplicate,/' "$(_spec design.md)"; }

# S-L07: 存在しない variant を期待する
case_S_L07() { EXPECT=L07; sed -i 's/^  - `Err` の値が `MOD-3:TodoError::TitleTooLong` で、max が 100 である$/  - `Err` の値が `MOD-3:TodoError::TooLong` である/' "$(_spec test-design.md)"; }

# --- 各 lint コードの基本ケース ---------------------------------------------------

case_L01() { EXPECT=L01; sed -i 's/^### REQ-2: Todo の一覧$/### REQ-1: Todo の一覧/' "$(_spec requirements.md)"; }
case_L02() { EXPECT=L02; sed -i '0,/^- Verifies: REQ-1.1$/s//- Verifies: REQ-9.1/' "$(_spec test-design.md)"; }
case_L09() { EXPECT=L09; sed -i 's/^- Files: src\/http\/api.rs$/- Files: src\/http\/api.rs, src\/domain\/service.rs/' "$(_spec design.md)"; }
case_L10() { EXPECT=L10; sed -i '0,/^- Depends: DES-2$/s//- Depends: DES-2, DES-5/' "$(_spec design.md)"; }
case_L11_test() { EXPECT=L11; sed -i '/^#### UT-2.4: /,/^#### UT-2.5: /{/^#### UT-2.5: /!d}' "$(_spec test-design.md)"; }
case_L11_rq() { EXPECT=L11; sed -i '/^- RQ-3: /d' "$(_spec requirements.md)"; }
case_L12() { EXPECT=L12; sed -i '0,/^- Target: API-1$/s//- Target: `DES-5:create_todo`/' "$(_spec test-design.md)"; }
case_L13() { EXPECT=L13; sed -i 's/^  - `Err` の値が `MOD-3:TodoError::EmptyTitle` である$/  - `Err` の値が `MOD-3:TodoError::EmptyTitle` または `MOD-3:TodoError::TitleTooLong` である/' "$(_spec test-design.md)"; }
case_L14() { EXPECT=L14; sed -i 's/^#### UT-2.2: 100 文字ちょうどを受け入れる$/#### UT-2.2: [テストの名前]/' "$(_spec test-design.md)"; }
case_L15() { EXPECT=L15; printf '\n## 技術スタック選定\n\n- axum\n' >> "$(_spec request-spec.md)"; }
case_L17() { EXPECT=L17; printf '\n## Excluded Tests\n\n- E2E-1: CI で動かせない\n' >> "$(_spec design.md)"; }
case_L18() { EXPECT=L18; sed -i 's/^- Evidence: EV-lib-001$/- Evidence: EV-lib-002/' "$(_spec requirements.md)"; }
case_L19() { EXPECT=L19; sed -i '/^- Files: src\/domain\/todo.rs$/{n;s/^- Depends: -$/- Depends: DES-3/}' "$(_spec design.md)"; }
case_L20() { EXPECT=L20; sed -i 's/^- Depends: DES-3$/- Depends: DES-3, DES-5/' "$(_spec design.md)"; }
case_L23() { EXPECT=L23; sed -i '/^## Sigcheck$/,$d' "$(_steer tech.md)"; }
case_L26() { EXPECT=L26; sed -i '0,/^- Phase: 0$/s//- Phase: 1/' "$(_spec design.md)"; }

# すべてのケース名を列挙する
lint_cases() { declare -F | awk '{print $3}' | grep '^case_' | sed 's/^case_//'; }
