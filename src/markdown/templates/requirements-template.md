---
spec_id: {spec-name}
phase: requirements
version: 1
depends_on: []
---

# Requirements Document

> **ID 規則**（`.claude-plugin/rules/spec-dependency-graph.md` SD1）: 各 Requirement の見出しは `### REQ-N: タイトル` 形式で書く（N は Requirement 番号）。Acceptance Criteria はフラットに 1, 2, 3 と列挙し、各行末に `<!-- REQ-N.M -->` コメントを付与して機械可読な `REQ-N.M` 識別子を明示する。下流仕様書（design.md / test-design.md / tasks.md）は `REQ-N`（全体）または `REQ-N.M`（個別 AC）で参照する。

> **Evidence 引用**（`.claude-plugin/rules/evidence-coverage.md` EC1/EC2, 非 legacy 類型のみ）: `request-spec.md` で宣言された `task_type` の必須 evidence category は、本ドキュメント全体で各 1 件以上引用すること。Acceptance Criteria 行に `<!-- EV-{category}-{NNN} -->` を追記するか、該当 REQ の直下で括弧内引用 `(EV-{category}-{NNN})` を使う。該当 category が本当にこの spec に適用されない場合は、ドキュメント冒頭に `<!-- no-evidence: {category} — {理由} -->` を置けば Step B チェックは WARN で済む。

## Introduction

[Provide a brief overview of the feature, its purpose, and its value to users]

## Alignment with Product Vision

[Explain how this feature supports the goals outlined in product.md]

## Requirements

### REQ-1: [Requirement Name]

**User Story:** As a [role], I want [feature], so that [benefit]

#### Acceptance Criteria

各 AC には **Test Layers** を必ず宣言する（K-1）。Layer 値は `quality-checks.md` の Test Taxonomy 参照。test-design.md 確定前は layer 名（UT / CT / IT / ST / E2E）のみでも可、確定後に具体 ID へ back-fill。
さらに、非 legacy 類型では各 AC 行末に `<!-- EV-{category}-{NNN} -->` を付けて Evidence 引用を行う（evidence-coverage.md EC1/EC2）。

1. WHEN [event] THEN [system] SHALL [response]  <!-- REQ-1.1 --> <!-- EV-{category}-{NNN} -->
   - Test Layers: UT, IT-1
2. IF [precondition] THEN [system] SHALL [response]  <!-- REQ-1.2 -->
   - Test Layers: UT, CT, ST-1
3. WHEN [event] AND [condition] THEN [system] SHALL [response]  <!-- REQ-1.3 -->
   - Test Layers: UT, IT, E2E-1

### REQ-2: [Requirement Name]

**User Story:** As a [role], I want [feature], so that [benefit]

#### Acceptance Criteria

1. WHEN [event] THEN [system] SHALL [response]  <!-- REQ-2.1 -->
   - Test Layers: UT, IT-2
2. IF [precondition] THEN [system] SHALL [response]  <!-- REQ-2.2 -->
   - Test Layers: UT, ST-2

## Non-Functional Requirements

### Code Architecture and Modularity
- **Single Responsibility Principle**: Each file should have a single, well-defined purpose
- **Modular Design**: Components, utilities, and services should be isolated and reusable
- **Dependency Management**: Minimize interdependencies between modules
- **Clear Interfaces**: Define clean contracts between components and layers

### 品質特性方針

[数値目標を記述する場合は、その根拠（計測方法、比較対象、ユーザー体験への影響）を
 併記すること。根拠のない数値は記載しない]

#### パフォーマンス
- **方針**: [例: ユーザー操作に対して体感上の遅延なくレスポンスすること]
- **計測対象と基準**（根拠がある場合のみ）:

#### セキュリティ
- **方針**: [例: 認証・認可の要件、データ保護の方針]
- **適用基準・規格**（該当する場合）:

#### 信頼性
- **方針**: [例: データの整合性保証、障害時の挙動]
- **回復方針**:

#### ユーザビリティ
- **方針**: [例: アクセシビリティ基準、多言語対応の要否]
- **対象ユーザーの前提条件**:

#### テスタビリティ（K-5、必須項目）
- **方針**: 全 REQ が UT で verify 可能であること。UT で覆えない部分は CT/IT/ST/E2E のどこで覆うかを明示
- **External I/O 戦略**: clock / RNG / env / fs / HTTP / DB の依存を Mock 経由に隔離する設計方針（詳細は design.md の Architecture for Testability セクションで定義）
- **並列性 / 状態共有**: 状態を持つ component / シングルトン / グローバル mut の testability 戦略
- **Test fixture / mock の責任範囲**: fixture の配置 / lifetime / clean-up 方針
