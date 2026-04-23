---
name: doc-freshness
description: |
  リポジトリ内のドキュメント・ルールファイル・ADR の陳腐化検出と定期レビュー促進。監視対象は Rules (90 日) / ADR (180 日) / Steering docs (90 日) / design.md (120 日) / tech-debt (90 日) / know-how (180 日)。`git log -1 --format="%ct"` での最終更新日取得、閾値判定 (Fresh < 61 日 / Warning 61-90 日 / Stale >= 91 日)、週次 CI での GitHub Issue 自動作成、ADR status による追加判定 (Proposed 30 日以内遷移、Deprecated / Superseded は対象外)、Phase Review (Expert Team) での乖離検出、手動チェックコマンドをカバー。週次 CI ドキュメントチェック設定、手動の定期監査、古いドキュメント検出と更新判断、tech-debt との連携時に参照。
allowed-tools: [Read, Bash, Grep, Glob]
---

# ドキュメント鮮度管理

リポジトリ内のドキュメント・ルールファイル・ADR の陳腐化を検出し、定期的なレビューを促す。

## 対象

- 週次 CI でのドキュメント鮮度チェック設定
- 手動での定期監査（90/120/180 日閾値）
- Stale ドキュメント検出後の更新判断
- ADR status (`Proposed` / `Accepted` / `Deprecated` / `Superseded`) に応じた追加判定
- Phase Review（Expert Team Review）での実装とドキュメントの乖離検出
- `tech-debt` Skill との連携（Open 状態エントリの放置検出）

## 対象外

- ドキュメントの書き方・構成 → 各 Skill / テンプレート
- spec ドキュメントの整合性検証 → `spec-verify` / `spec-impact-analyze` Skill
- CI workflow の setup → `setup-ci` Skill

## 監視対象

| ドキュメント種別 | パス | 閾値 | アクション |
|---------------|------|------|----------|
| ルールファイル | `.claude-plugin/rules/*.md` | 90日 | 内容が現状に合っているかレビュー |
| ADR | `.claude/_docs/adr/*.md` | 180日 | status が Accepted のままか確認 |
| Steering docs | `.spec-workflow/steering/*.md` | 90日 | 技術スタック・方針の変更を反映 |
| 設計書 | `.spec-workflow/specs/*/design.md` | 120日 | 実装との乖離がないか確認 |
| 技術的負債 | `.claude/_docs/tech-debt/*.md` | 90日 | Open 状態のエントリが放置されていないかレビュー |
| know-how | `.claude/_docs/know-how/**/*.md` | 180日 | 内容が現状のコードベースと合っているかレビュー |

## 検出方法

### Git ベースの更新日検出

```bash
# ファイルの最終更新日（git log ベース）を取得
git log -1 --format="%ci" -- "$FILE_PATH"

# 経過日数を計算
LAST_MOD=$(git log -1 --format="%at" -- "$FILE_PATH")
NOW=$(date +%s)
AGE_DAYS=$(( (NOW - LAST_MOD) / 86400 ))
```

### 閾値判定

| 経過日数 | ステータス | 対応 |
|---------|----------|------|
| 0-60日 | Fresh | 対応不要 |
| 61-90日 | Warning | レビュー推奨 |
| 91日以上 | Stale | レビュー必須、Issue 作成対象 |

## CI 統合

`/setup-ci --with-scheduled` で生成される週次 CI ワークフローに以下が含まれる:

1. **Document freshness check**: 全監視対象ファイルの最終更新日を走査
2. **Issue 作成**: Stale ファイルが検出された場合、GitHub Issue を自動作成
3. **ラベル**: `quality`, `automated` ラベルを付与

## ADR 固有の鮮度管理

ADR は status フィールドに基づいて追加の判定を行う:

| status | 閾値判定 |
|--------|---------|
| Proposed | 30日以内に Accepted / Rejected に遷移しなければ Warning |
| Accepted | 通常の 180日閾値を適用 |
| Deprecated | 鮮度チェック対象外 |
| Superseded | 鮮度チェック対象外（後続 ADR を参照） |

## review-worker との連携

Phase Review（step 3.5.2 Expert Team Review）で品質・保守性担当が以下を確認:

- 変更対象のモジュールに関連するドキュメントが Stale になっていないか
- 実装がドキュメントの記述と乖離していないか
- 乖離がある場合はドキュメント更新を findings として報告

## 手動チェック

定期 CI がない場合でも、以下のコマンドで手動チェック可能:

```bash
# 90日以上更新されていないルールファイルを検出
for f in .claude-plugin/rules/*.md; do
  age=$(( ($(date +%s) - $(git log -1 --format="%at" -- "$f")) / 86400 ))
  [ "$age" -gt 90 ] && echo "STALE ($age days): $f"
done
```

## 関連 Rule / Skill

- 普遍制約: `quality-checks`
- 関連 Skill: `tech-debt` (Stale 検出を tech-debt エントリとして起票), `adr`, `setup-ci` (週次 CI での自動チェック), `regression-test-policy` (test-design.md の 120 日閾値)
