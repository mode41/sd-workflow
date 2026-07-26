---
description: Security rules pointer — activate when editing environment files or API code; the rules live where .spec-workflow/context-map.md (kind=security) points, defaulting to docs/SECURITY-RULES.md.
applyTo: "**/.env*,**/api/**"
---

# Security Rules

Consult `.spec-workflow/context-map.md` for `kind=security` to find this project's security rules:
query the listed MCP context provider if one is connected, else read the listed security source, else
discover the project's own security conventions from the codebase. Honor its `context-schema:`
front-matter — this core supports `1`; on an unsupported value note `context schema N unsupported` and
run on discovery alone. **Default:** `docs/SECURITY-RULES.md` — seeded once into the consumer project
and owned by it — used when the context map is absent or lists no `security` row.

This scoped instruction is what makes your harness auto-inject the security rules when you touch
`.env*` files or files under `**/api/**`; the context map is what decides *where* those rules actually
live — a repo file, a Confluence/Notion page, or a provider.
