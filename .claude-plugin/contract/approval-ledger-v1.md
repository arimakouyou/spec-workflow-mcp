# Approval Ledger Contract v1

This is the contract every approval server implementation must satisfy: the current TypeScript MCP server (`src/core/spec-ledger.ts`), the Bash state reader (`scripts/spec-state.sh`), and the future Rust server (specrail). `contract/fixtures/` holds shared cases. Each implementation must produce the same states for them.

## 1. Documents

The server identifies a document by the approval request's `filePath` (relative to the project root). The `categoryName` argument is not used for this.

| filePath | Ledger key | Doc |
|---|---|---|
| `.spec-workflow/specs/{spec}/request-spec.md` | `{spec}` | `request-spec` |
| `.spec-workflow/specs/{spec}/requirements.md` | `{spec}` | `requirements` |
| `.spec-workflow/specs/{spec}/design.md` | `{spec}` | `design` |
| `.spec-workflow/specs/{spec}/test-design.md` | `{spec}` | `test-design` |
| `.spec-workflow/steering/{product,tech,structure}.md` | `steering` | `product` / `tech` / `structure` |
| `.spec-workflow/specs/{spec}/tasks.md` | — | request is refused with `TASKS_GENERATED` |
| anything else | — | not ledgered, handled as before |

## 2. Fixed dependency order

| Doc | Upstream (recorded) | Also required before request |
|---|---|---|
| request-spec | — | steering `product`, `tech`, `structure` approved and unmodified |
| requirements | request-spec | |
| design | requirements | |
| test-design | requirements, design | |
| product / tech / structure | — | |

Steering is a gate, not a recorded upstream. Changing steering does not make a spec stale. It only blocks new request-spec requests until steering is re-approved.

## 3. Storage

```
.spec-workflow/approvals/{key}/ledger.json
.spec-workflow/approvals/{key}/content/{sha256}.md
```

`ledger.json`:

```json
{
  "version": 1,
  "entries": {
    "design": {
      "sha256": "<hex>",
      "approvalId": "<id>",
      "approvedAt": "<ISO 8601>",
      "upstream": { "requirements": "<hex>" }
    }
  },
  "history": [
    { "event": "approved", "doc": "design", "sha256": "<hex>", "approvalId": "<id>", "at": "<ISO 8601>", "upstream": { "requirements": "<hex>" } },
    { "event": "reverted", "doc": "design", "approvalId": "<id>", "at": "<ISO 8601>" }
  ]
}
```

- `sha256` is the lowercase hex SHA-256 of the file's bytes, the same as `sha256sum`.
- `content/{sha256}.md` holds exactly those bytes.
- Only the approval server writes under `.spec-workflow/approvals/`. Writes are atomic: write a temporary file, then rename it.

## 4. Operations

### request (MCP tool `approvals`, action `request`)

1. If the document is `tasks.md`, refuse with `TASKS_GENERATED`.
2. For every recorded upstream `u`:
   - no entry → refuse `UPSTREAM_NOT_APPROVED:<u>`
   - current sha of `u`'s file ≠ entry sha → refuse `UPSTREAM_MODIFIED:<u>`
3. For request-spec, check each steering doc the same way → refuse `STEERING_NOT_APPROVED:<doc>` / `STEERING_MODIFIED:<doc>`.
4. Store `metadata.ledger = { key, doc, contentSha256, upstream: { u: sha } }` on the approval request.

### approve (dashboard, including batch)

1. If the current sha of the file ≠ `metadata.ledger.contentSha256`, refuse `CONTENT_CHANGED`. Nobody approves bytes they did not review.
2. Re-run the upstream checks of `request`.
3. Write `content/{sha}.md`, set `entries[doc]`, and append an `approved` history event.

Reject and needs-revision do not touch the ledger.

### undo (revert to pending)

- If `entries[doc].approvalId` is the reverted approval:
  - restore the most recent earlier `approved` history event for `doc` that is not itself reverted,
  - or remove the entry when there is none.
- Append a `reverted` event.

### status (MCP tool `approvals`, action `status`)

Returns `metadata.ledger` in addition to the existing fields.

## 5. Document state

Evaluate documents in dependency order.

| State | Condition (first match wins) |
|---|---|
| `pending` | an approval request with this `filePath` has status `pending` |
| `unapproved` | no ledger entry |
| `modified` | current file sha ≠ entry sha |
| `stale` | some upstream `u` is not `approved`, or entry.upstream[u] ≠ entries[u].sha256 |
| `approved` | otherwise |

A spec is **ready** for implementation when request-spec, requirements, design and test-design are all `approved`.

## 6. Error codes

`TASKS_GENERATED`, `UPSTREAM_NOT_APPROVED:<doc>`, `UPSTREAM_MODIFIED:<doc>`, `STEERING_NOT_APPROVED:<doc>`, `STEERING_MODIFIED:<doc>`, `CONTENT_CHANGED`.
