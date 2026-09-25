# Test Taxonomy (v2)

This is the single definition of the test layers, the test categories and where each layer runs. test-design.md uses these layers (`doc-format.md` §4.4). The implementation agents and `spec-phase-check.sh` run the layers at the points listed here.

## 1. Layers

| Layer | Verifies | Scope | Fixtures | Target in test-design |
|---|---|---|---|---|
| **UT** | The specification of one function: the specified behaviour **and** the absence of unspecified behaviour | One `DES:fn` of Kind logic / types | None. Clock, RNG, env, fs, HTTP and DB only through doubles declared in design `TST` | `` `DES-N:fn` `` |
| **CT** | Component reactivity: mount → signal / event → DOM | One DES of Kind ui | Mock signals | `DES-N` (ui) |
| **IT** | One backend HTTP API: status, body, persisted state, auth | Server only. No UI, no frontend-to-server-fn boundary | Real DB / TempDir | `API-N` |
| **ST** | One feature end to end: UI action → backend → UI update | UI + server, one feature | Real server + fixtures | `REQ-N` |
| **smoke** | Boot and wiring. L1 health; L2 every API × method never 5xx; L3 `Auth: required` without credentials → 401; L4 type-boundary inputs → 400/422 | Whole system | None | generated `SMK-*` |
| **E2E** | One user journey across features | Whole system | Real server + complete fixtures | `JRN-N` |

**Regression** is a marker, not a layer. A test that guards a known bug carries `Regression: BUG-x` in test-design. Its name follows the language convention (Rust `regression_bug_x_<what>`, TS `it('regression BUG-x: …')`). All regression tests must pass at every commit gate.

Tests outside a layer's scope belong to another layer:

- A per-feature check written as E2E belongs in ST.
- DOM assertions inside an IT belong in CT or ST.
- Business rules inside smoke belong in UT or IT.

## 2. Categories (UT and CT)

Every UT / CT has exactly one `Category`.

| Category | Meaning |
|---|---|
| Happy | Specified input produces the specified output |
| Boundary | Values at and just beyond each limit |
| Error | Each specified failure produces its specified error (one test per `Raises` entry) |
| Edge | Empty, maximum-size, unicode, duplicated or unordered inputs |
| Negative | Unspecified behaviour is absent: no mutation of inputs, no extra side effects, no panic on unexpected input, no extra keys |

Isolation is not a category. It is a property every UT must have (§3).

## 3. UT properties (FIRST)

| Property | Rule |
|---|---|
| Fast | Milliseconds. No sleeps, no real I/O |
| Isolated | No shared mutable state between tests. Order-independent. Parallel-safe |
| Repeatable | No wall clock, no unseeded randomness, no environment dependency. Only doubles declared in design `TST` |
| Self-validating | Asserts on the observable outcome named in `Then`. Asserting only "no error" or `is_ok()` is not enough |
| Timely | Written in RED, before the implementation, against the stub copied from DES Interfaces |

## 4. Where each layer runs

| Layer | Inside the task that owns it | `P{n}-REVIEW` | `FINAL` |
|---|---|---|---|
| UT | Its DES task | All UTs so far | All |
| CT | Its DES task (ui) | All CTs so far | All |
| IT | `P{n}-IT` | All ITs so far | All |
| ST | `P{n}-ST` | All STs so far | All |
| smoke | `P{n}-SMK` | Server started, L1–L4 | L1–L4 |
| E2E | — | — | Every `JRN` |

Commands come from tech.md `Test Commands`. A layer is never silently skipped. It is skipped only when tech.md declares it `-`, or when design `Excluded Tests` lists it with a reason and an alternative. Either way the reason is printed in the report.

## 5. Mutation testing

- UT verification runs mutation testing on the diff of the task (Rust: `cargo mutants --in-diff`, .NET: `dotnet stryker`) when the tool is declared in design `TOOL`.
- Every surviving mutant is a finding, and the verifier names the missing assertion.
- If the tool is declared `Required: yes` but is not installed, the run stops (see `spec-tools-check.sh`).
