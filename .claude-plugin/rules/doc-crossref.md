# Cross-Document Reference Verification

Verifies referential consistency across spec-workflow documents.

## Verification Targets

### References Between Spec Documents

| Source | Target | Verification |
|--------|--------|---------|
| requirements.md | request-spec.md | Whether the requirements are based on the request specification |
| design.md | requirements.md | Whether the Requirement IDs in the Requirements Traceability Matrix exist |
| test-design.md | design.md | Whether the test-target components are defined in design.md |
| tasks.md | design.md | Whether the IDs in the `_Requirements` field exist in requirements.md |
| tasks.md | test-design.md | Whether the references in `_Prompt` exist in test-design.md |

### Code <-> Documentation References

| Source | Target | Verification |
|--------|--------|---------|
| design.md API Design | Source code | Whether the defined endpoints are implemented |
| design.md Error Handling | Source code | Whether the defined error codes are used |
| test-design.md | Test files | Whether test files corresponding to the test specifications exist |
| docs/openapi.yaml | Source code | Whether the OpenAPI definition matches the source |

## Verification Commands

### Markdown Internal Link Verification

```bash
# Extract file references in spec documents and verify their existence
grep -roP '\[.*?\]\((\.spec-workflow/[^)]+)\)' .spec-workflow/specs/ | while IFS=: read -r file match; do
  ref=$(echo "$match" | grep -oP '\(([^)]+)\)' | tr -d '()')
  [ ! -f "$ref" ] && echo "BROKEN: $file → $ref"
done
```

### Requirements Traceability Matrix Verification

```bash
# Whether the Requirement IDs in design.md exist in requirements.md
SPEC_DIR=".spec-workflow/specs/{spec-name}"
if [ -f "$SPEC_DIR/design.md" ] && [ -f "$SPEC_DIR/requirements.md" ]; then
  grep -oP 'REQ-\d+' "$SPEC_DIR/design.md" | sort -u | while read -r req_id; do
    grep -q "$req_id" "$SPEC_DIR/requirements.md" || echo "MISSING: $req_id in requirements.md"
  done
fi
```

### Test Specification <-> Test File Verification

```bash
# Whether tests corresponding to IT-/UT- IDs in test-design.md exist
grep -oP '(IT|UT)-\d+' "$SPEC_DIR/test-design.md" | sort -u | while read -r test_id; do
  grep -rq "$test_id" tests/ src/ || echo "UNIMPLEMENTED: $test_id"
done
```

## Workflow Integration

### During Phase Review (step 3.5.2 Expert Team Review)

The implementation owner verifies:

- Whether `_Requirements` in tasks.md exist in requirements.md
- Whether the implementation covers every Requirement ID

### Weekly Scheduled Check (`--with-scheduled`)

Run the following in scheduled CI:

- Broken-link check for Markdown internal links
- Consistency check for the Requirements Traceability Matrix

### When `/generate-api-docs` Runs

- Diffs against the design.md API Design section are detected in Step 6 (existing feature)

## Relationship with QC10

Mechanical format verification and broken-link detection are handled by QC10 (Documentation Lint) in `quality-checks.md`.
This rule covers spec-workflow-specific semantic referential consistency (Requirements Traceability Matrix, correspondence between test specifications and test files, and so on).
