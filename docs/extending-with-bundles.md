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

## Context sources (files & MCP providers)

Separate from the profile seam — and equally frozen in core v1 — is the **context-source seam**: how
the workflow discovers *where a project's governing context lives* (architecture docs, security rules,
business/product context, ADRs, UX guidelines). The core no longer hardcodes those locations; it reads
them from one fixed-path manifest.

| File | Consumed by | Purpose |
|------|-------------|---------|
| `docs/context-map.md` | `/requirements`, `/technical-design`, `/frontend-architecture`, the plan-review pipeline, the `security` rule | Says where each `kind` of governing context lives — as repo files, external URLs, or an MCP provider. |

Unlike the bundle-owned profile files, **`docs/context-map.md` is a *living* file** — the installer
seeds it once (from the shipped template) and never clobbers it; the consumer owns and edits it. It
carries front-matter **`context-schema: N`**, range-checked exactly like `profile-schema` (core v1
supports `context-schema: 1`; on an unsupported value a consumer prints `context schema N unsupported`
and runs on discovery alone).

The manifest lists two kinds of **source**:

- **File** — a repo path *or* an external URL (Confluence, Notion, a wiki page). Read directly.
- **Provider** — an MCP tool that serves governing context **scoped** to the part of the system a
  piece of work touches, queried live. Declared in the manifest; connected in the harness's MCP
  settings (`.mcp.json` / `apm.yml` `dependencies.mcp`), **never** in the manifest — no endpoints or
  credentials live in the living file.

Rules the core guarantees:

- **Fixed path.** Exactly `docs/context-map.md` — no alternates. This is the whole contract.
- **`kind` vocabulary (closed set).** `business`, `architecture`, `adr`, `security`, `ux`, `design`,
  `other`.
- **Precedence, per kind.** Query a connected **provider** that serves the kind → else read the listed
  **file(s)** → else **discover** the project's own patterns from the codebase. Every layer is
  optional; an absent or empty manifest just means "discover."
- **Defaults, not assumptions.** The seeded manifest ships default rows (`architecture` →
  `ARCHITECTURE.md`, `business` → `docs/PRD.md`, `security` → `docs/SECURITY-RULES.md`) so a greenfield
  project works untouched. Any row may be repointed at an external tool, replaced by a provider, or
  deleted — the workflow follows the map, not the filename.

### The provider contract

A **context provider** is an MCP tool matching this shape:

- **Input:** a *scope key* (the services/system the current work touches — the workflow passes the
  free-text `**Services:**` value a tech design already computes) plus the requested `kind`(s).
- **Output:** the governing context for that scope and those kinds.
- **Degradation:** if the tool is not connected, the consumer silently falls back to files, then
  discovery. A missing provider never blocks the workflow.

The seam is **vendor-neutral**: any MCP tool matching this contract works, named in the manifest's
Providers table. The **reference provider is [architrace.io](https://architrace.io)**, which serves an
organisation's governing context (Confluence, Notion, git, …) scoped to each system. Connect its MCP
server in your harness settings and add (or uncomment) its row in `docs/context-map.md`.

## Authoring a bundle (constraints)

A bundle is a normal APM package that a consumer adds alongside the core:

```yaml
# consumer apm.yml
dependencies:
  apm:
    - mode41/sd-workflow#<commit-sha>
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
