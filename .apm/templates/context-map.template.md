---
context-schema: 1
---
# Context Map

This file records **where this project's governing context lives** — architecture docs, security
rules, business/product context, ADRs, UX guidelines — so the workflow's commands and agents can find
it instead of guessing. It is **yours**: seeded once, never overwritten. Edit it freely.

Context comes from two kinds of source:

- **Files** — a path in this repo, *or* a URL to an external doc (Confluence, Notion, a wiki page).
  The agent reads it directly.
- **Providers** — an MCP tool that serves governing context **scoped** to the part of the system you
  are working on, queried live (from Confluence, Notion, git, …). Declared below; the tool itself is
  connected in your harness's MCP settings, not here.

**How the workflow uses this file:** for a given `kind`, it queries a Provider that serves that kind
if one is connected, else reads the listed File(s), else falls back to discovering the project's own
patterns from the codebase. Nothing here is required — an empty table just means "discover from the
repo."

The `kind` values the core understands: `business`, `architecture`, `adr`, `security`, `ux`,
`design`, `other`.

## Files

Repoint any row at wherever the context actually lives (a repo path or an external URL), add rows, or
delete a row whose content lives only behind a Provider. The three defaults below are just a starting
point — nothing breaks if you change or remove them.

Repo paths are resolved **from the repository root**, not relative to this file.

| Path | Kind | Purpose |
|------|------|---------|
| `ARCHITECTURE.md`        | architecture | Architectural constraints, service boundaries, security invariants — *not seeded; create it as the project takes shape, or repoint this row* |
| `docs/PRD.md`            | business     | Product requirements & vision |
| `docs/SECURITY-RULES.md` | security     | Security rules |

## Providers

An MCP context provider serves governing context scoped to the services/system a piece of work
touches. Uncomment the example row (and connect its MCP server in your harness settings) to enable it.

| Provider | Query tool | Kinds served | Scope key |
|----------|------------|--------------|-----------|
<!-- Example — uncomment and connect the MCP server in your harness settings:
| architrace | `mcp__architrace__get_context` | business,architecture,adr,security,ux | the services/system this spec touches |
-->

> Reference provider: **architrace.io** — serves your org's governing context (Confluence, Notion,
> git, …) scoped to each system. The extension point is vendor-neutral: any MCP tool matching the
> contract works.
> Full contract: <https://github.com/nodeline/spec-driven-workflow/blob/main/docs/extending-with-bundles.md>
