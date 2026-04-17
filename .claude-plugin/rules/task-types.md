---
always_apply: true
---

# Task Types for Spec Investigation

Taxonomy of task types used by the spec workflow to scope pre-investigation depth and validate evidence coverage. Declared in Phase 0 (`request-spec.md` frontmatter `task_type:`), consumed by the `spec-investigate` skill and the Step B check validators of subsequent phases.

Use these rules to decide (1) which evidence categories must be collected before requirements work begins, and (2) whether a spec can legitimately skip investigation (legacy / unclassified specs).

## TT1: Declaration

Every new spec must declare a `task_type` in the frontmatter of `request-spec.md`:

```yaml
---
task_type: feature-add   # one of the values in TT2
---
```

If `task_type` is absent, the spec is treated as `legacy` (see TT5). `spec-request-spec` prompts for this value and its Step B check verifies that the value is one of the allowed set.

## TT2: Canonical Task Types

Five built-in types. Each has a fixed set of **required evidence categories** that the Phase 0.5 `spec-investigate` skill must produce and that the Step B check of subsequent phases must verify.

| `task_type` | When to use | Required evidence categories |
|-------------|-------------|------------------------------|
| `feature-add` | Adding a new API endpoint, a new screen, a new command, etc. — net-new surface area | `entry-points` / `domain-models` / `cross-cutting` / `test-harness` |
| `feature-modify` | Changing the behavior or contract of an existing feature (API response shape, UI flow change, new field) | `callers` / `contract-current` / `branches` / `regressions` |
| `bugfix` | Fixing a defect without changing intended behavior | `repro` / `root-cause-paths` / `callers` / `regressions` |
| `refactor` | Restructuring code without changing external behavior | `api-surface` / `callers` / `invariants` / `test-coverage-gap` |
| `legacy-migration` | Porting an existing feature from a legacy codebase while preserving current behavior | `entry-points` / `domain-models` / `cross-cutting` / `test-harness` / `legacy-source` |

## TT3: Evidence Category Definitions

The categories above are the vocabulary evidence files and manifests use. One evidence file covers one *topic* inside a category (not one file per source file). See `evidence-coverage.md` for the EV-ID format and file layout.

| Category | What it captures | Typical sources |
|----------|------------------|-----------------|
| `entry-points` | How user/system requests reach code that needs to change (routes, handlers, CLI commands, event subscribers) | Router definitions, controller/handler files, command registries |
| `domain-models` | Data shapes and aggregates in the neighborhood of the change | Entity/DTO/schema files, migration history, ORM mapping |
| `cross-cutting` | Shared concerns that any new code must respect | Auth/authz middleware, logging, error mapping, i18n, feature flags |
| `test-harness` | Existing test scaffolding the new feature should reuse | Integration test base classes, fixtures, factories, seed scripts |
| `callers` | Code paths that invoke the symbol(s) being modified | Grep results for the function/endpoint/type, reverse dependency graph |
| `contract-current` | Exact current external behavior (request/response, UI states) | OpenAPI fragments, sample recordings, existing unit/IT assertions |
| `branches` | Conditional logic and state transitions inside the change target | if/match/switch blocks, state machines, feature flag branches |
| `regressions` | Existing tests that will detect behavioral drift after the change | Test files that currently exercise the target paths |
| `repro` | Deterministic reproduction of the defect | Failing input/URL/payload, step-by-step repro, failing test if one exists |
| `root-cause-paths` | Suspected code paths that produce the defect | Stack trace walk, hypothesis list with file:line anchors |
| `api-surface` | Public surface being restructured (signatures, module exports) | Exported symbols, public method lists, typed interfaces |
| `invariants` | Behaviors that must not change during refactor | Contract tests, doc-stated guarantees, SLOs |
| `test-coverage-gap` | Areas where a refactor would be unsafe without added tests first | Coverage report deltas, untested branches |
| `legacy-source` | Canonical citations from the legacy codebase being ported | File paths and line ranges in the legacy repo or archived snapshot |

## TT4: Extension and Override

Projects may override the built-in mapping at `.spec-workflow/user-config/task-types.yml`:

```yaml
# .spec-workflow/user-config/task-types.yml
types:
  feature-add:
    required_categories:
      - entry-points
      - domain-models
      - cross-cutting
      - test-harness
      - security-posture   # project-specific addition
  # New project-defined type
  ops-change:
    required_categories:
      - infra-surface
      - observability
      - rollback-plan
categories:
  security-posture:
    description: "Threat model and authz checks in the neighborhood"
  infra-surface:
    description: "Terraform/Helm/config files that will be touched"
```

Rules:

- A type defined in the YAML overrides the built-in definition with the same key (full replacement of `required_categories`).
- New types may be added; they must ship `required_categories`.
- Any category referenced by a type must either be a built-in (TT3) or appear in the `categories:` map with a `description`.
- Category キー名は `[a-z0-9_-]+` の範囲（小文字 ASCII、数字、ハイフン、アンダースコアのみ）に限定する。これは EV-ID 構文 `EV-{category}-{NNN}` が 3 桁連番と category を区切るために必要な制約で、パーサ側もこの範囲のみを EV-ID として受理する。
- Unknown types cause `spec-request-spec` Step B to FAIL with a message listing valid values.

## TT5: Legacy and Unclassified Specs

- Specs whose `request-spec.md` has no `task_type` are treated as `legacy` and **skip** the Phase 0.5 investigation and all evidence-coverage checks in downstream Step B validators. This preserves the behavior documented in `spec-workflow-enforcement.md` for specs that predate this mechanism.
- Explicit `task_type: legacy` is allowed as an opt-out for the current spec only (e.g. prototype work). It must carry a one-line `legacy_reason:` adjacent to it. Step B warns but does not FAIL.
- Do not use `legacy` as a shortcut to bypass investigation for real work. `feature-modify` or `bugfix` almost always fits better.

## TT6: Interaction with Existing Rules

- TT is orthogonal to `spec-dependency-graph.md` (SD1-SD7). SD1 identifiers (REQ-N.M, DES-N, MOD-N, UT-N.M, IT-N, E2E-N) continue to label spec content; TT categories label evidence files that back those identifiers.
- `enforcement-levels.md` (L1-L5) is unchanged: evidence-coverage FAILures surface as L4 (blocking Step B) in phases where the check is active (see `evidence-coverage.md`). Opt-in phases surface them as L2 advisories.
- Downstream skills reference TT via `task_type` read from `request-spec.md` frontmatter; they must not hardcode category lists.
