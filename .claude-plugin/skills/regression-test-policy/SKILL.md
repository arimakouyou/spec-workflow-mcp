---
name: regression-test-policy
description: |
  リグレッションテストの運用ポリシー。ユーザーバグレポートからテストケースへの変換フロー (RT1)、受け入れ基準 (REQ-N) の永続的リグレッションテスト化 (RT2)、リグレッションスイートの構成と健全性指標管理 (RT3) を定義。バグ修正時の再現テスト作成、Requirements-Test Traceability Matrix 維持、test suite の削除・変更判断、スイート健全性のレビュー時に参照。
allowed-tools: [Read, Edit, Write, Bash, Grep]
---

# Regression Test Policy Skill

## 対象

- ユーザーから報告されたバグの修正作業（RT1 に従って再現テストを先に作成）
- 受け入れ基準 (REQ-N) とテスト (UT / CT / IT / ST / E2E) の紐付け設計
- Traceability Matrix の更新・検証
- リグレッションスイートの構成レビュー

## Regression は層ではなく cross-cutting type（J-8 で明示化）

> 出典: `.claude/_docs/plans/dapper-hardening-orchestrator.md` 根本原因 J（J-8）。

Regression は **テスト層ではなく cross-cutting type**（横断的属性）として位置付ける:

- 既存のテスト分類（UT / CT / IT / ST / smoke / E2E、`quality-checks.md` の Test Taxonomy 参照）の **すべての層に regression marker を付けることができる**
- たとえば backend バグの再発防止なら IT-regression、UI の状態遷移バグなら CT-regression、user journey の壊れたシナリオなら E2E-regression

各層と regression の組合せ例:

| 層 | regression test の例 | ファイル配置 / 命名 |
|---|------|---|
| UT | `regression_issue_123_login_fails_with_special_chars` | inline `#[cfg(test)] mod tests` 内 |
| CT | `regression_issue_456_signal_does_not_fire_after_unmount` | `tests/component/` 内 |
| IT | `regression_issue_789_db_constraint_violation` | `tests/integration/it_regression_*.rs` |
| ST | `regression_issue_012_search_resets_after_filter_change` | `tests/system/st_regression_*.spec.ts` |
| E2E | `regression #345: full checkout flow breaks on coupon` | `tests/e2e/e2e-regression-NNN.spec.ts` |

RT1/RT2/RT3 はこれら **すべての層** に適用可能。バグの影響範囲が単一機能で UI を含むなら ST-regression、複数機能の連鎖が壊れる重大バグなら E2E-regression、というように層を選ぶ。

## 対象外

- テストコードそのものの書き方 → `tdd-skills` / `tdd-skills-rust` / `tdd-skills-dotnet`
- Flaky Test の扱い → `flaky-test-management` Rule
- CI 設定 → `setup-ci` Skill

## 主要観点

### 1. RT1: バグレポート → テストケース変換

ユーザーから報告されたバグは、**修正前に必ず**再現テストケースを作成する。修正後もテストを維持し、同一バグの再発を防ぐ。

#### 変換フロー

```text
1. バグレポート受領
   ↓
2. 再現条件の特定
   ↓
3. 失敗するテストケースを作成 (RED)
   ↓
4. バグ修正 (GREEN)
   ↓
5. テストをリグレッションスイートに追加
   ↓
6. CI で自動実行されることを確認
```

#### 命名規則

Issue 番号で追跡可能にする:

```rust
#[test]
fn regression_issue_123_login_fails_with_special_chars() {
    // GH#123: ユーザー名に特殊文字を含むとログインに失敗する
}
```

```typescript
it('regression #123: login fails with special chars in username', () => {
  // GH#123: ユーザー名に特殊文字を含むとログインに失敗する
});
```

#### テストレベル振り分け（J-8 で更新、新 taxonomy 反映）

| バグの影響範囲 | テストレベル | 配置先 |
|---|---|---|
| 単一関数 / メソッド | UT (Unit Test) | inline `#[cfg(test)] mod tests` |
| component reactivity（mount → signal → DOM） | **CT (Component Test)** | `tests/component/` または `*_ct.rs` |
| backend HTTP API endpoint | IT (Integration Test、backend HTTP only) | `tests/integration/` or `crates/server/tests/it_regression_*.rs` |
| 単一機能の full-stack 動作（UI → backend → UI） | **ST (System Test)** | `tests/system/` or `tests/e2e/st_regression_*.spec.ts` |
| 複数機能の連鎖を含む user journey | E2E (End-to-End) | `tests/e2e/e2e-regression-NNN.spec.ts` |

各層の責務範囲詳細は `quality-checks.md` の Test Taxonomy 参照。バグの本質が UT で再現可能なら UT、UI 統合が必要なら CT/ST、user journey が必要なら E2E、というように **最も狭い適切な層** を選ぶ（テストの安定性とコストを両立）。

#### Issue テンプレート（推奨フィールド）

```markdown
## バグレポート

### 再現手順

1. ...
2. ...

### 期待される動作

...

### 実際の動作

...

### テストケース

- [ ] 再現テスト作成済み（テストファイル: ）
- [ ] リグレッションスイートに追加済み
```

### 2. RT2: 受け入れ基準の永続リグレッション化

`test-design.md` の Requirements-Test Traceability Matrix で定義された受け入れ基準は、実装後も**永続的なリグレッションテスト**として維持する。

#### 原則

1. **削除禁止**: 受け入れ基準テストは仕様変更なしに削除してはならない
2. **仕様変更時**: 削除ではなく更新で対応
3. **全件 CI 実行**: `cargo test` / `npm test` などのデフォルト実行対象に含める
4. **Traceability 維持**: 各テストに Requirement ID (REQ-N) をコメント or 命名で紐付け

#### Traceability Matrix 例（J-8 で CT/ST 列追加）

```markdown
| Requirement ID | UT Specs | CT Specs | IT Specs | ST Specs | E2E Specs | Notes |
|---|---|---|---|---|---|---|
| REQ-1 | UT-1.1, UT-1.2 | CT-1 | IT-1 | ST-1 | E2E-1 | |
```

**チェック方法**: 全 REQ-N に最低 1 つの UT + 関連する CT/IT/ST/E2E（責務に応じた層）が紐付く。未カバーは Phase Review で検出・追加要求。

### 3. RT3: リグレッションスイート管理

#### スイート構成（J-8 で CT/ST 列追加）

| スイート | 実行タイミング | 内容 |
|---|---|---|
| Unit Regression | コミット前 / PR CI | 全 UT（バグ由来含む） |
| **Component Regression** | Phase Review / PR CI | 全 CT（バグ由来含む） |
| Integration Regression | Phase Review / E2E Gate / PR CI | 全 IT（backend HTTP only） |
| **System Regression** | Phase Review / Final E2E Gate / PR CI | 全 ST（単一機能 full-stack） |
| E2E Regression | Final E2E Gate / PR CI | 全 E2E（user journey） |

**CI gate 化（J-9 で QC16 として確定）**: PR / merge 時に **全層 + regression marked テスト** の全件 PASS を必須化。`regression_issue_*` パターンを git 履歴から自動収集。詳細は `quality-checks.md` QC16 参照。

#### 健全性指標

| 指標 | 健全 | 要注意 |
|---|---|---|
| 全 PASS 率 | 100% | 99% 未満で即対応 |
| flaky テスト率 | 0-2% | 5% 超で FT5 隔離対象 |
| PR CI テスト実行時間 | 5 分以内 | 10 分超で並列化検討 |
| バグ再発率 | 0% | 再発はテスト不足を示す |

#### spec-workflow との連携

- **Phase 3 (test-design)**: 受け入れ基準を UT/IT/E2E 分解し Traceability Matrix に記録
- **Phase 5 (implement)**: TDD の RED フェーズでテスト先行作成
- **Phase Review**: Traceability Matrix の全 REQ カバレッジを検証
- **バグ修正時**: RT1 フロー（再現テスト → 修正 → リグレッション追加）を守る

## よくある落とし穴

1. **修正後にテストを書く**: RT1 フロー違反。修正前に RED テストを作成すること
2. **Traceability Matrix を更新しない**: REQ と test のマッピングが陳腐化し、カバレッジが可視化できなくなる
3. **受け入れ基準テストを「時代遅れ」として削除**: 仕様変更が伴わない削除は禁止
4. **flaky テストを放置**: 5% 超で `flaky-test-management` (FT5) に従い隔離対象

## プロジェクト固有の規約

- Traceability Matrix は `.spec-workflow/specs/{spec-id}/test-design.md` 内に配置
- `doc-freshness` の 120 日閾値で `test-design.md` の鮮度チェック対象
- 乖離検出時はテスト更新を優先する方針

## 関連 Rule / Skill

- 普遍制約: `quality-checks` (QC3), `diagnostic-reasoning` (DR1-DR6: テスト失敗診断)
- 関連 Skill: `tdd-skills`, `tdd-skills-rust`, `tdd-skills-dotnet`, `spec-test-design`, `flaky-test-management`

## 参考リンク

- spec-workflow テンプレート: `.claude-plugin/templates/` 配下
- `.spec-workflow/specs/{spec-id}/test-design.md` に Traceability Matrix を配置
