---
name: tech-debt
description: >
  Record and manage tech debt as a register under .claude/_docs/tech-debt/.
  Track priority, effort, and status with ID-tagged entries (TD-NNNN), and
  maintain a remediation plan via periodic review.
  Managed separately from ADRs: ADRs record "decisions"; tech-debt records
  "known issues and improvement plans".
  Triggers on: 'record tech debt', 'tech debt', 'add debt', '/tech-debt', '技術的負債'.
argument-hint: "[add|list|update <TD-ID> --status <status>|audit]"
user-invokable: true
---

# Tech Debt Register

A skill that records and manages tech debt as a register under `.claude/_docs/tech-debt/`.
Addresses P5-02 (tech debt is managed as a list inside the repo).

## Directory Structure

```
.claude/_docs/tech-debt/
  INDEX.md              # Index (priority-ordered table)
  TD-0001-slug.md       # Individual entries
  TD-0002-slug.md
```

## Argument Parsing

| Subcommand | Arguments | Description |
|------------|-----------|-------------|
| `add` | (none — collected interactively) | Create a new entry |
| `list` | (none) | Read INDEX.md and show the list |
| `update` | `<TD-ID> --status <status>` | Update status |
| `audit` | (none) | Scan the codebase to detect potential tech debt |

## Operation: add

### Step 1: Information Gathering

Collect the following from the user (ask interactively if omitted):

| Field | Required | Description |
|-------|----------|-------------|
| Title | Yes | Concise description of the debt |
| Summary | Yes | What the debt is and where it lives |
| Impact | Yes | Problems this debt causes |
| Priority | Yes | Critical / High / Medium / Low |
| Effort estimate | Yes | S(1-2h) / M(half-day) / L(1-3d) / XL(1w+) |
| Remediation plan | No | How to fix it (can be added later) |
| Related ADR | No | Related ADR ID (e.g., ADR-0003) |

### Step 2: ID Assignment

Scan existing files in `.claude/_docs/tech-debt/` and assign max ID + 1:

```bash
# Get the existing max ID
MAX_ID=$(ls .claude/_docs/tech-debt/TD-*.md 2>/dev/null | \
  grep -oP 'TD-\K\d+' | sort -n | tail -1)
NEXT_ID=$(printf "%04d" $((${MAX_ID:-0} + 1)))
```

### Step 3: File Creation

Following the template in `${CLAUDE_PLUGIN_ROOT}/skills/tech-debt/references/tech-debt-template.md`,
create `.claude/_docs/tech-debt/TD-{NEXT_ID}-{slug}.md`.

The slug is derived from the title converted to kebab-case (e.g., "Legacy auth middleware" -> `legacy-auth-middleware`).

### Step 4: INDEX.md Update

Append a row to `.claude/_docs/tech-debt/INDEX.md`. If INDEX.md does not exist, create it:

```markdown
# Tech Debt Register

| ID | Title | Status | Priority | Effort | Created | Related ADR |
|----|-------|--------|----------|--------|---------|-------------|
| TD-0001 | [Title] | Open | High | M | 2026-04-08 | — |
```

Sort the table by priority (Critical > High > Medium > Low).

## Operation: list

Read INDEX.md, filter by status, and display:

```
Tech Debt Register:
  Open: 3 entries (Critical: 1, High: 1, Medium: 1)
  In-Progress: 1 entry
  Resolved: 2 entries
  Accepted: 0 entries

[Display the INDEX.md table]
```

## Operation: update

Update the frontmatter of the entry file specified by TD-ID:

| Status transition | Allowed | Notes |
|-------------------|---------|-------|
| Open -> In-Progress | Yes | Work started |
| Open -> Accepted | Yes | Decision to tolerate the debt (intentionally not fixing) |
| In-Progress -> Resolved | Yes | Fill in the `resolved` field with the date |
| In-Progress -> Open | Yes | Work paused |
| Resolved -> Open | Yes | When recurrence is observed |

Also update the status column in INDEX.md.

## Operation: audit

Scan the codebase to detect potential tech debt.

### Detection Signals

```bash
# Detect TODO/FIXME/HACK comments
grep -rn 'TODO\|FIXME\|HACK\|XXX\|WORKAROUND' src/ --include='*.rs' --include='*.ts' --include='*.js' 2>/dev/null

# Large files over 300 lines (complexity signal)
find src/ -name '*.rs' -o -name '*.ts' -o -name '*.js' 2>/dev/null | while read f; do
  lines=$(wc -l < "$f")
  [ "$lines" -gt 300 ] && echo "LARGE_FILE ($lines lines): $f"
done

# Outdated dependencies (Rust)
cargo outdated --depth 1 2>/dev/null | grep -v "Up to date"

# Outdated dependencies (Node.js)
npx npm-check-updates 2>/dev/null | grep -v "All dependencies"
```

### Report

```markdown
## Tech Debt Audit Report — {DATE}

### Detected Potential Debt

| # | Signal | File/Location | Existing Entry | Recommended Action |
|---|--------|---------------|----------------|--------------------|
| 1 | TODO comments (5) | src/handlers/auth.rs | None | `/tech-debt add` |
| 2 | Large file (450 lines) | src/services/payment.rs | TD-0003 | Tracked under existing entry |
| 3 | Outdated deps (3) | Cargo.toml | None | `/tech-debt add` |
```

For each item, ask the user whether to register it via `/tech-debt add`.
Skip items already covered by an existing tech-debt entry.

## Relationship with ADRs

| Recorded subject | Where used | Example |
|------------------|------------|---------|
| Decisions and their rationale | ADR (`/adr`) | "Selected PostgreSQL; rejected DynamoDB" |
| Known issues and improvement plans | Tech Debt (`/tech-debt`) | "Auth middleware is dated; session-token storage does not meet compliance requirements" |

Tech debt arising from an ADR should be linked via the `related-adr` field.

## Promotion from Know-how

Among know-how recorded by `/knowhow-capture`, items that are structural / chronic problems
rather than individual tips should be promoted via `/tech-debt add`.
Refer to the FL4 promotion path in the `feedback-loop` Skill.

## Notes

- Run staging/commit only when the user explicitly requests it after file creation
- Accepted status is an intentional "do not fix" decision; record the reason in the Summary section
- The `doc-freshness` Skill flags entries that have been Open for 90+ days for review
