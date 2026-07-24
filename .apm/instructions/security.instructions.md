---
description: Security rules pointer — activate when editing environment files or API code; the rules live where docs/context-map.md (kind=security) points, defaulting to docs/SECURITY-RULES.md.
applyTo: "**/.env*,**/api/**"
---

# Security Rules

Consult `docs/context-map.md` for `kind=security` to find this project's security rules: query the
listed MCP context provider if one is connected, otherwise read the listed security source. **Default:**
[`docs/SECURITY-RULES.md`](../../docs/SECURITY-RULES.md) — seeded once into the consumer project and
owned by it — used when the context map is absent or lists no `security` row.

This scoped instruction is what makes your harness auto-inject the security rules when you touch
`.env*` files or files under `**/api/**`; the context map is what decides *where* those rules actually
live — a repo file, a Confluence/Notion page, or a provider.
