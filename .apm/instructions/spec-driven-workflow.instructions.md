---
description: The Spec-Driven Development (SDD) workflow — the required sequence, per-spec status machine, and enforcement every implementation task must follow.
---

# Spec-Driven Development Workflow

All implementation work follows this sequence per spec. Each step also advances the spec's
**status**, which must be kept identical in the spec's `**Status:**` header **and** its
`specs/INDEX.md` row. The five states are `In Planning → Planned → In Progress → In Review →
Validated`, plus a terminal `Deprecated` reachable from any state (see the legend in
`specs/INDEX.md`). Each spec is also **versioned** — see the spec-versioning rules.

1. **Spec** (`/requirements`) — defines WHAT (user stories, acceptance criteria, edge cases). → status **🔵 In Planning**
2. **Technical Design** (`/technical-design SPEC-X`) — defines HOW (DB schema, API contracts, components). → status **🟣 Planned**
3. **Technical Design Refinement** — execute the Plan Review Workflow for the tech design. (stays **Planned**)
4. **Implementation** — code against the tech design, one branch per SPEC-X. When implementation begins, make sure you are on the spec's `SPEC-N` branch — **if the current branch is already a `SPEC-N` branch for this spec (e.g. a git worktree already checked out for parallel implementation), use it and do NOT create a new branch**; only create one if you are not already on it. → set status to **🟡 In Progress** in both the spec header and `specs/INDEX.md`. If your implementation changes another spec that is already **Planned or later** (a shared schema, API, or contract), update that spec too — bump its version + add a changelog row, or deprecate it if its feature no longer exists.
5. **Verification** — write/run tests against the acceptance criteria (via `/write-tests`), results appended to the spec file. → status **🟠 In Review**
6. **Close-out** — in the spec file, tick every satisfied acceptance-criterion checkbox (`- [x] AC-N`), mark any intentionally-skipped one `DESCOPED` with a reason (leave it `- [ ]`), append an `## Implementation & Verification` section noting the test evidence, then set status to **🟢 Validated** in **both** the spec header and `specs/INDEX.md`.

Three checks enforce this — the shared scripts in `.spec-workflow/hooks/` (`check-ac-closeout.sh`:
every AC ticked or DESCOPED once a close-out section exists; `check-status-sync.sh`: spec header and
INDEX row agree, use a legal status word, and match reality; `check-spec-version.sh`: a
Planned-or-later spec that changed substantively — or was deprecated — must bump its version + add a
changelog row). They run **both** as a per-harness finish-boundary hook (e.g. a Claude Code `Stop`
hook — blocks finishing on a `SPEC-*` branch) **and** as a git `pre-commit` hook (blocks a drifted
commit from any tool or human; bypass with `git commit --no-verify`).

When implementing a spec, always read these files first:
- The spec file: `specs/SPEC-X-*.md` (including its Tech Design section)
- `ARCHITECTURE.md` for architectural constraints and security invariants
- `specs/INDEX.md` for dependency order

Never start implementing a spec that has no Tech Design section. Run `/technical-design SPEC-X` first.

## Testing

Write tests whenever introducing new logic, features, or significant changes. Prefer existing test
fixtures / sample data over ad-hoc fixtures. The `/write-tests` command provides detailed guidance;
it discovers the project's actual test stack (and consults an optional stack profile — see below).

## Keep it Clean

After finishing and testing a change, make sure no zombie code or old workarounds remain. Keep the
code clean. Update `ARCHITECTURE.md` if it is inconsistent with the codebase. Update user
documentation and spec files whenever changes make them outdated.

## Stack & Design Profiles (optional extension seam)

The workflow itself is stack- and design-agnostic — a static website uses the exact same workflow as
a complex information-management system. Stack- or design-specific guidance is **optional** and lives
in a profile a capability bundle (or your own stack-init tool) may provide:

- `docs/stack-profile.md` — stack specifics (test framework, migration tool, layering) with a
  `profile-schema:` version. `/write-tests` and `/technical-design` consult it if present.
- Design specifics (component/design-system conventions) likewise; `/frontend-architecture` consults
  a design profile if present, and is otherwise inert.

If no profile exists, the commands run purely on discovery of the project's own patterns. Do not
invent stack/design rules the project has not established.
