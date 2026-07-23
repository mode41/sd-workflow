# Extending the workflow with stack/design bundles

The `spec-driven-workflow` core is deliberately **generic** — it carries the workflow, enforcement,
reviewer agents, and security rules, but **no** language, framework, or design specifics. The workflow
itself is stack- and design-agnostic: a static website uses the exact same workflow as a complex
information-management system. Stack- and design-specific guidance is instead provided by optional
**capability bundles** (separate APM packages) through a small, **frozen** extension contract. This
document is that contract. Freezing it means a bundle — or your own stack-init tool — can be built
later **without ever forcing a change to the core**.

This document is the human-facing source of truth for the seam; the core's commands carry only the
one-line consult step they need.

## The profile seam (frozen in core v1)

Core commands look for two optional profile files at fixed paths. A bundle (or your own tooling)
creates them; nothing else in the core needs to change.

| File | Consumed by | Purpose |
|------|-------------|---------|
| `docs/stack-profile.md`  | `/write-tests`, `/technical-design` | Stack specifics: test framework, runner, assertion lib, integration-test strategy, fixtures, migration tool, layering, build/test commands. |
| `docs/design-profile.md` | `/frontend-architecture` | Design specifics: visual language, design tokens, component conventions, the design system / corporate design. |

Rules the core guarantees (and a bundle must honor):

- **Fixed paths.** Exactly the two paths above — no alternates. This is the whole contract.
- **Schema version.** Each profile carries front-matter `profile-schema: N` (integer). The core reads
  it and **range-checks** it. On an unsupported schema it **degrades gracefully** — runs on discovery
  alone and prints a one-line `profile schema N unsupported` notice — so an old bundle + new core (or
  vice versa) never silently mis-reads. Core v1 supports `profile-schema: 1`.
- **Optional by design.** No profile ⇒ commands discover the project's own patterns and never invent
  stack/design rules. A plain static website needs **zero** bundles. `/frontend-architecture` on a
  project with no frontend and no design profile is inert (it says so and stops).
- **These are managed, not living data.** A bundle owns its profile files; treat them like the core's
  managed primitives.

### Minimal profile example

```markdown
---
profile-schema: 1
kind: stack            # or: design
---
# Stack Profile — Python service

- Test framework: pytest (+ pytest-asyncio)
- Integration DB: real Postgres via testcontainers-python
- Fixtures: tests/conftest.py factories
- Commands: `uv run pytest -q` (unit), `uv run pytest -m integration` (integration)
```

## Authoring a bundle (constraints)

A bundle is a normal APM package that a consumer adds alongside the core:

```yaml
# consumer apm.yml
dependencies:
  apm:
    - nodeline/spec-driven-workflow#<commit-sha>
    - your-org/spec-bundle-python#<commit-sha>
```

Constraints the core assumes (stated here as the governing precedent):

- **Bundles are data-only.** A bundle ships a profile (and optionally extra instructions/skills). Only
  the **core** package may wire `git config core.hooksPath`. If a bundle ever needs to run install
  code, it must **chain** — never replace — any existing hook wiring, using the same
  detect-and-preserve logic the core uses.
- **Same supply-chain discipline as the core.** Any bundle dependency is subject to the same rules:
  pin by **immutable commit SHA**, run `apm audit`, and install with `--frozen` in CI.
- **Don't fork the workflow.** A bundle adds stack/design specifics; it does not restate or override
  the spec lifecycle, versioning, or enforcement. Project-local workflow tweaks go in the consumer's
  seeded `spec-workflow.supplemental.md`, not in a bundle.

## The stack-init tool idea

Because the seam is just "write a file at a fixed path with a known schema", a lightweight
**stack-init tool** (its own APM package, or a small CLI) can interview a project and generate the
right `docs/stack-profile.md` / `docs/design-profile.md`. It plugs into exactly this contract; the
core never needs to know it exists.

## Migration when the core evolves

The core's **templates and primitives are managed** — `apm update` refreshes them. Your **living
files are not** (`specs/INDEX.md`, your specs, `docs/PRD.md`, `docs/SECURITY-RULES.md`). When a core
update changes a template's format (say a new status word, or a new INDEX column):

1. The core spec-version rules and this changelog flag what changed (read the release notes / diff the
   refreshed `.spec-workflow/templates/` against your living files).
2. Have your agent reconcile your living files against the updated template on your own schedule — the
   refreshed template in `.spec-workflow/templates/` is the clean reference to diff against.

Because living files are never auto-clobbered, this migration is deliberate and non-destructive:
routine `apm update` never rewrites your tracking table, specs, or security rules.
