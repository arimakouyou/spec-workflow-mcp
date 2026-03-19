---
always_apply: true
---

# Feedback Loop

## 組み込み memory との棲み分け

- **know-how** (`.claude/_docs/know-how/`): プロジェクト固有の実践知。Git 管理下でチーム共有する。技術的判断・落とし穴・ベストプラクティス。
- **組み込み memory** (`~/.claude/projects/.../memory/`): 個人の好み・作業スタイル。Git 管理外。

迷ったら「チームメンバーも知るべきか？」で判断する。Yes → know-how、No → memory。

## タスク開始時の参照

タスクに着手する前に `.claude/_docs/know-how/INDEX.md` を確認し、関連する know-how があれば該当ファイルを Read する。

参照フロー:
1. INDEX.md でドメイン一覧を確認
2. タスクのキーワード（例: "テスト", "マイグレーション", "キャッシュ"）に一致するドメインを特定
3. 該当 know-how の「チェックリスト」と「反例」を実装判断に反映

INDEX.md が空、または該当ドメインがない場合はスキップしてよい。

## フィードバック検出と記録

以下を検出したら `/knowhow-capture` スキルを使用して know-how を記録する:

- ユーザーが「覚えておいて」「次回から〜して」等と発言した → スキルの Pattern A（即座に記録）
- ユーザーが AI の判断を修正・否定した → スキルの Pattern B（提案型）
- 同じ指摘を2回以上受けた → スキルの Pattern B（提案型）

記録の手順・フォーマット・ルール昇格はすべて `/knowhow-capture` スキルに従う。
