#!/usr/bin/env bash
# spec-sigcheck.sh の失敗フィクスチャ。specrail approval-gate で design 段階に作り込まれ、
# 実装時に初めて表に出たシグネチャの欠陥(I / H 型)を todo-ok に 1 つずつ入れる。
# 各 case_* は $ROOT を書き換え、EXPECT_ID(エラーを対応づける ID)と EXPECT(メッセージの一部)を設定する。

SPEC_REL=".spec-workflow/specs/todo-api"
_design() { printf '%s/%s/design.md' "$ROOT" "$SPEC_REL"; }

# I: thiserror は source という名前のフィールドを error source とみなす(String は Error ではない)
case_thiserror_source() {
  EXPECT_ID=MOD-3; EXPECT="E0599"
  sed -i 's/^      TitleTooLong { max: usize },$/&\n      #[error("storage failed")]\n      Storage { source: String },/' "$(_design)"
}

# I: async fn を持つ trait は dyn にできない(E0038)
case_async_dyn() {
  EXPECT_ID="DES-3 (Held-as)"; EXPECT="E0038"
  sed -i '0,/^      fn insert(&self, title: Title) -> Todo;$/s//      async fn insert(\&self, title: Title) -> Todo;/' "$(_design)"
}

# I: Held-as の Arc<dyn TodoStore> を共有するには Send + Sync が要る
case_missing_send_sync() {
  EXPECT_ID="DES-3 (Held-as)"; EXPECT="E0277"
  sed -i 's/^  pub trait TodoStore: Send + Sync {$/  pub trait TodoStore {/' "$(_design)"
}

# H: 依存方向の規則に反して domain が http の型を参照する
case_layer_violation() {
  EXPECT_ID=DES-2; EXPECT="E0425"
  sed -i 's/^      pub fn as_str(&self) -> &str;$/&\n      pub fn to_response(\&self) -> TodoResponse;/' "$(_design)"
}

# I: 外部 trait のメソッドとシグネチャが違う(IntoResponse::into_response は self を取る)
case_external_trait_mismatch() {
  EXPECT_ID=DES-5; EXPECT="E0053"
  sed -i 's/^      fn into_response(self) -> Response;$/      fn into_response(\&self) -> Response;/' "$(_design)"
}

sigcheck_cases() { declare -F | awk '{print $3}' | grep '^case_' | sed 's/^case_//'; }
