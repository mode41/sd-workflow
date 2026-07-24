<!-- spec-workflow:begin (managed marker — do not remove; the installer detects this section by it) -->
## How this project works
This repository follows the **Spec-Driven Development (SDD)** workflow, installed via
[Microsoft APM](https://microsoft.github.io/apm/) as the `spec-driven-workflow` package. The workflow
itself — the spec lifecycle, plan-review pipeline, spec-versioning rules, security rules — **and the
general engineering rules** (engineering practices, code hygiene, testing) are delivered as **managed
agent rules/commands** (they refresh on `apm update`); do not copy that prose here. Project-specific
tuning goes in `spec-workflow.supplemental.md`.

Key locations:
- `specs/` — spec files (`SPEC-N-*.md`) and `specs/INDEX.md` (the status source of truth).
- `docs/PRD.md` — product requirements. `docs/SECURITY-RULES.md` — security rules.
- `.spec-workflow/` — the deployed enforcement machinery (git pre-commit + finish-hook checks).
- `ARCHITECTURE.md` — architectural constraints and invariants (create as the project takes shape).

Start a new project with `/requirements <your idea>`; then `/technical-design SPEC-1`, implement on a
`SPEC-N` branch, `/write-tests`, and close out. Status must stay identical in each spec's `**Status:**`
header and its `specs/INDEX.md` row (the hooks enforce this).
<!-- spec-workflow:end -->
