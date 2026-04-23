---
name: regression-test-policy
description: |
  リグレッションテストの運用ポリシー。ユーザーバグレポートからテストケースへの変換フロー (RT1)、受け入れ基準 (REQ-N) の永続的リグレッションテスト化 (RT2)、リグレッションスイートの構成と健全性指標管理 (RT3) を定義。バグ修正時の再現テスト作成、Requirements-Test Traceability Matrix 維持、test suite の削除・変更判断、スイート健全性のレビュー時に参照。
allowed-tools: [Read, Edit, Write, Bash, Grep]
---

# Regression Test Policy Skill

## 対象

- ユーザーから報告されたバグの修正作業（RT1 に従って再現テストを先に作成）
- 受け入れ基準 (REQ-N) とテスト (UT / IT / E2E) の紐付け設計
- Traceability Matrix の更新・検証
- リグレッションスイートの構成レビュー

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

#### テストレベル振り分け

| バグの影響範囲 | テストレベル | 配置先 |
|---|---|---|
| 単一関数 / メソッド | Unit Test | `src/` 内のテストモジュール |
| コンポーネント間結合 | Integration Test | `tests/` |
| ユーザージャーニー | E2E Test | `e2e/` or `tests/e2e/` |

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

#### Traceability Matrix 例

```markdown
| Requirement ID | UT Specs | IT Specs | E2E Specs | Notes |
|---|---|---|---|---|
| REQ-1 | UT-1.1, UT-1.2 | IT-1 | E2E-1 | |
```

**チェック方法**: 全 REQ-N に最低 1 つの UT + 関連する IT or E2E が紐付く。未カバーは Phase Review で検出・追加要求。

### 3. RT3: リグレッションスイート管理

#### スイート構成

| スイート | 実行タイミング | 内容 |
|---|---|---|
| Unit Regression | コミット前 / PR CI | 全 UT（バグ由来含む） |
| Integration Regression | Phase Review / E2E Gate | 全 IT |
| E2E Regression | Final E2E Gate | 全 E2E |

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
