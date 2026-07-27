# Product Requirements Document

## Vision
_Describe what you are building and why in 2-3 sentences. What is the core problem and the core principle that distinguishes this product?_

## Target Users

| Persona | Context | Primary Use Case |
|---------|---------|-----------------|
| **Persona A** | _Where they work, what tools they use_ | _What they need from this product_ |
| **Persona B** | _..._ | _..._ |

## Core Features (Roadmap)

> **Status lives in [`specs/INDEX.md`](../specs/INDEX.md), the single source of truth.**
> This roadmap intentionally carries no Status column — it would only drift. See INDEX for each
> spec's current lifecycle state (In Planning → Planned → In Progress → In Review → Validated).

| Priority | ID | Spec | File |
|----------|----|------|------|
| <!-- P0 (MVP) | SPEC-1 | Example Spec | [Spec](../specs/SPEC-1-example-spec/spec.md) | -->

## Success Metrics
- _How do we measure that this product works?_
- _What numbers signal product-market fit?_

## Constraints
- _Team size, timeline, budget_
- _Technical platform constraints (cloud, deployment target, etc.)_
- _Regulatory / compliance requirements_

## Non-Goals
- _What this product explicitly does NOT do_
- _Important to set boundaries: features that look adjacent but are out of scope_

## Open Questions
<!-- Project-level decisions nobody has settled. `/requirements` records them here — instead of
     asking the terminal — when `interaction.mode` is "file" in .spec-workflow/config.json, noting
     what it ASSUMED and built the PRD on; you fill in **Answer:** (your choice, or "confirmed").
     These are the widest-blast-radius questions there are ("is a backend needed?"), so while one is
     unanswered NO spec may advance past 🔵 In Planning — check-open-questions.sh enforces it.
     Answered questions STAY here as the decision record.
     Delete this section if there is nothing open.

### Q-1: _The decision, as a question_
- (a) _Option — trade-off_
- (b) _Option — trade-off_
**Assumed:** _(b), because …_
**Answer:**
-->
_None._

---

**Governing context:** see `.spec-workflow/context-map.md` for where this project's
architecture, security, and other context lives (repo files by default — e.g. `ARCHITECTURE.md` — or
an external tool / MCP provider).

Use `/requirements` to create a detailed spec for each item in the roadmap above.
