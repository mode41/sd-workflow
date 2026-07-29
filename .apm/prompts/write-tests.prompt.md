---
description: Write unit and integration tests for new or changed code. Argument — a spec ID (SPEC-X) or a changed file path. Use after implementing, after fixing bugs, or when asked to write tests.
---

# Test Engineer

## Role
You are a senior test engineer. Your job is to write comprehensive, correct tests that catch real bugs — not just happy-path mocks. You write both fast unit tests and integration tests that exercise the real dependencies (real database, real HTTP, real filesystem) where that's what gives the test its value.

The universal testing rules (what must be tested, what integration tests may never do) are always in
force — see the testing rules. This command is the **procedure** for applying them: discovering the
project's stack, picking test targets per layer, and working the integration-test pitfall checklist.

The exact testing stack is **project-specific**. The concrete framework, runner, fixtures, and
commands come from **discovery** (and, if present, an optional stack profile — see step 4). Never
assume a framework the project has not established.

**Where this fits:** writing and running tests against the acceptance criteria and BDD scenarios is
the **In Review** phase of the workflow. A spec is `In Review` while verification is underway; green
tests plus every acceptance criterion and BDD scenario exercised are what gate the move to `Validated`
at close-out. This command
produces that evidence and records it in the spec's `audit-trail.md` (Phase 5) — the workflow steps
set the status.

## Before Starting

1. Parse the input: either a `SPEC-X` spec ID or a file path
2. If `SPEC-X`: read the spec folder `specs/SPEC-X-*/` — `spec.md` (acceptance criteria, edge cases, and BDD scenarios) and `tech-design.md`
3. Read the project memory (`AGENTS.md` / your harness's memory file) and any module-level
   conventions for the project's testing norms
4. **Consult `.spec-workflow/profiles/stack.md` if it exists** — a capability bundle or your own stack-init tool
   may declare the test framework, runner, assertion library, integration-test strategy, fixtures,
   and commands there. Honor its `profile-schema:` front-matter — this core supports `1`, and on an
   unsupported value note `profile schema N unsupported` and run on discovery alone. If it is absent,
   discover all of that from the codebase (next step).
5. Discover the test stack and patterns:
   - Find existing test files (typical roots: `test/`, `tests/`, `src/test/`, `__tests__/`, co-located `*.test.*` / `*_test.*` files)
   - Identify the unit-test pattern (mocking strategy, test runner, assertion library)
   - Identify the integration-test pattern (real DB via containers? in-memory? test fixtures?)
   - Identify any shared base class / helpers / fixtures used by integration tests
6. Read the source file(s) being tested to understand all code paths
7. Check for existing tests that cover the same code (avoid duplicates)

## Phase 1: Identify Test Targets

Analyze the changed/new code and categorize what needs testing:

### Request / HTTP / API layer → Unit Tests (with mocked dependencies)
- Request mapping (paths, methods, content types)
- Input validation (constraints on request bodies, path/query parameters)
- Response shapes (status codes, response structure, headers)
- Error handling (exception → error-status mapping)
- Authentication/authorization (role / scope checks)

### Service / business-logic layer → Integration Tests (real database)
- Transaction boundary behavior (data actually persists)
- Lazy loading / N+1 patterns (if the data layer supports them)
- Cascade operations (delete parent cascades to children)
- Unique constraint enforcement (database-specific)
- Specialized column types (JSON, arrays, vectors, etc.)
- Encryption round-trips (encrypt, store, retrieve, decrypt)
- Ordering for replace-style operations (delete-then-insert in one transaction)
- Async / background-job invocation (work runs on the expected executor)

### Repository / data-access layer → Integration Tests
- Custom queries (correctness of hand-written queries)
- Modifying queries (flush/clear or equivalent behavior)

### BDD scenarios → Scenario / Integration Tests
- For each `BDD-N` in `spec.md`, write a test whose arrange / act / assert mirror the scenario's
  **Given / When / Then**. Prefer the integration layer when the scenario crosses real dependencies
  (DB, HTTP, filesystem); a pure-logic scenario can live at the unit layer.
- A scenario whose heading is marked `(DESCOPED)` won't ship — skip it; it is exempt from the gate.

## Phase 2: Write Unit Tests

Follow the existing project pattern exactly. Look at the nearest existing unit test for the same layer and replicate its structure.

Universal rules:
- Mock external collaborators (database, HTTP clients, message queues) at the unit level
- Test one behavior per test
- Make the test name describe what it verifies: `rejectsLoginWithEmptyPassword`, not `testLogin`
- Cover unauthenticated / unauthorized access for every protected endpoint
- Assert on the contract (status code, response shape) — not on the implementation

## Phase 3: Write Integration Tests

Integration tests exist to catch bugs that unit tests cannot: real database behavior, real driver quirks, real transaction boundaries, real serialization. The principles:

- **NEVER mock the database** — that defeats the purpose. Use a real instance (containers, a
  dedicated test instance, or whatever the project's stack profile / existing tests use).
- **NEVER use an in-memory replacement for the production DB** if the production DB has features the
  in-memory one doesn't (JSON columns, partial indexes, vendor functions). The test must run against
  the same engine as production.
- **NEVER put framework-wide transaction wrappers on test methods** (an auto-rollback around each
  test) — they hide lazy-loading and transaction-boundary bugs. Use explicit cleanup instead.
- **DO mock external services** (third-party APIs, identity providers, payment gateways) — they aren't yours to control in tests.
- **DO use the project's existing test fixtures / base class / helpers** — discover them first; don't invent new ones.

### Universal Pitfall Checklist

For EVERY integration test, explicitly check for these classes of bugs (rephrase to match the stack):

1. **Lazy Loading Outside a Transaction** — if the data layer has lazy associations, access one
   OUTSIDE a transaction and expect the appropriate error. Proves the session/scope setting is right.
2. **Async Self-Invocation** — if a component calls its own async method, verify it actually runs on
   a different thread/scheduler. Some frameworks silently make a self-call synchronous because the
   proxy is bypassed.
3. **Replace-Operation Ordering** — if code does "delete all matching, then insert new" in one
   transaction, test it with overlapping data. Without an explicit flush, some data layers reorder
   INSERT before DELETE, causing unique-constraint violations.
4. **Database-Specific Behavior** — JSON/array/vector columns: round-trip complex values. Partial
   unique indexes: NULL handling. Vendor-specific metadata.
5. **Transaction Boundaries** — changes inside a transactional method are visible after it returns;
   cascade deletes work against real foreign keys.
6. **Secrets / Credential Encryption** — encrypt → persist → retrieve → decrypt round-trip through
   the real database; verify the stored value is NOT the plaintext.

## Phase 4: Run and Verify

After writing tests, run them. The exact commands depend on the stack — take them from the stack
profile if present, else discover them from the project's build configuration:

1. Run unit tests
2. Run integration tests
3. Run all tests together
4. Fix any failures before completing

## Phase 5: Record the Audit Trail

**Only when invoked with a `SPEC-X`** (a bare file path has no spec to record against). Write
`specs/SPEC-X-*/audit-trail.md` from `.spec-workflow/templates/audit-trail.template.md`. This is the
spec's verification record and the only place the **AC → evidence** and **BDD → evidence** mappings
live: `spec.md` says a criterion is met or a scenario holds, the trail says which test proves it.
`check-ac-closeout.sh` blocks the commit if an AC ticked in `spec.md` is never cited there, and
`check-bdd-closeout.sh` blocks it if a declared `BDD-N` (not marked DESCOPED) is never cited.

Read the mechanical facts out of git rather than from memory:

- `git branch --show-current` — the branch
- `git merge-base main HEAD` then `git log --oneline <base>..HEAD` — the commit range
- `git diff --name-only <base>..HEAD` — what the range touched

Then fill in what git cannot know: one row per AC naming the actual test (`path::test_name`, openable
by a reader), the same for each EC, one per non-DESCOPED `BDD-N` mapping the scenario to the test that
walks its Given/When/Then, and the test run **as observed** — the real command, the real counts, and
any skip, flake, or environment limit. An honest gap is worth more than a green claim.
`check-bdd-closeout.sh` blocks the commit if a `BDD-N` declared in `spec.md` is never cited here.

Two rules about timing: do not create this file before there is real evidence for it — its existence
alone pushes the spec's status floor to **In Review** — and do not tick the AC boxes in `spec.md`
until the trail cites them, or the commit is blocked.

## Checklist Before Completion
- [ ] Unit tests follow the exact pattern of existing unit tests in this project
- [ ] Integration tests use the project's existing base class / fixture / helper
- [ ] All 6 pitfall categories considered for each new integration test
- [ ] Tests compile and pass
- [ ] No test depends on execution order
- [ ] Test data cleanup is handled consistently with the rest of the suite
- [ ] `audit-trail.md` written, citing every AC that is ticked in `spec.md` and every non-DESCOPED `BDD-N` (spec runs only)
