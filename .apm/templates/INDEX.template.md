# Spec Index

> Central tracking for all specs. Status is set at each workflow step — `requirements`
> (In Planning), `technical-design` (Planned), implementation on the `SPEC-N` branch
> (In Progress), and close-out (Validated) — and kept in lockstep with each spec's own
> `**Status:**` header by the shared `.spec-workflow/hooks/check-status-sync.sh` check (run as a
> per-harness finish-boundary hook and a git pre-commit hook).

## Status Legend
- **🔵 In Planning** — requirements being written (the WHAT); spec not yet complete
- **🟣 Planned** — tech design done (the HOW); ready to implement
- **🟡 In Progress** — implementation underway on the `SPEC-N` branch
- **🟠 In Review** — verification / QA underway (tests being written & run against the ACs)
- **🟢 Validated** — acceptance criteria met, tests green, complete
- **⚫ Deprecated** — spec dropped / superseded; kept as a tombstone (not rewritten) so its
  history stays traceable. Skipped in the build order below.

## Spec Versioning
Each spec carries a `**Version:**` (`v1`, `v2`, …) and an inline `## Changelog` — the **source of
truth** for how it evolved. Once a spec is Planned or later, any substantive change (or a
deprecation) must bump the version + add a changelog row naming the driving `SPEC-N`. The `Version`
column below is a convenience mirror the workflow commands keep updated; it is **not** hook-enforced
(only the spec's own header + changelog are).

## Backlog

A spec may live under `specs/backlog/SPEC-N-name/` instead of `specs/SPEC-N-name/` while it is parked.
The enforcement checks resolve the main tree first, then backlog, so a backlogged spec is held to the
same status, version and acceptance-criteria rules as any other.

## Specs

<!-- Column ORDER is load-bearing: the status-sync check reads Status as the 5th pipe-delimited
     field. Keep the 7 columns in this order (Status stays field $5). -->
| ID | Spec | Priority | Status | Version | File | Created |
|----|------|----------|--------|---------|------|---------|
| <!-- Add specs below; example row: -->
| <!-- SPEC-1 | Example Spec | P0 (MVP) | In Planning | v1 | [Spec](SPEC-1-example-spec/spec.md) | YYYY-MM-DD | -->

<!-- Add specs above this line -->

## Next Available ID: SPEC-1


## Recommended Build Order (MVP)

_Filled in by `/requirements` during Init Mode. Example structure:_

```
SPEC-1  Foundation spec                   (no deps)
  └─► SPEC-2  Builds on SPEC-1
        └─► SPEC-3  Builds on SPEC-2
```
