<!-- spec-workflow:begin (managed marker — do not remove; the installer detects this section by it) -->
## How this project works
This repository follows the **Spec-Driven Development (SDD)** workflow, installed via
[Microsoft APM](https://microsoft.github.io/apm/) as the `spec-driven-workflow` package. The workflow
itself — the spec lifecycle, plan-review pipeline, spec-versioning rules, security rules — **and the
general engineering rules** (engineering practices, code hygiene, testing) are delivered as **managed
agent rules/commands** (they refresh on `apm update`); do not copy that prose here. Project-specific
tuning goes in `spec-workflow.supplemental.md`.

Key locations:
- `specs/` — spec folders (`SPEC-N-name/`, each with `spec.md` + `tech-design.md` +
  `implementation.md` + any attachments) and `specs/INDEX.md` (the status source of truth).
- `.spec-workflow/context-map.md` — where this project's governing context lives (architecture, security,
  business, ADRs, UX). Repo files by default, but each row may point at an external tool (Confluence,
  Notion) or an MCP context provider; the commands consult it to locate context.
- `docs/PRD.md` — product requirements (default `business` source). `docs/SECURITY-RULES.md` — default
  `security` source. `ARCHITECTURE.md` — default `architecture` source (create as the project takes
  shape). All three are just the defaults the context map points at; repoint any of them as needed.
- `.spec-workflow/` — the deployed enforcement machinery (git pre-commit + finish-hook checks).

Start a new project with `/requirements <your idea>`; then `/technical-design SPEC-1`, implement on a
`SPEC-N` branch, `/write-tests`, and close out. Status must stay identical in each spec's `spec.md`
`**Status:**` header and its `specs/INDEX.md` row (the hooks enforce this).
<!-- spec-workflow:end -->
