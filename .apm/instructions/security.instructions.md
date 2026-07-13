---
description: Security rules pointer — activate when editing environment files or API code; the full rule set lives in docs/SECURITY-RULES.md.
applyTo: "**/.env*,**/api/**"
---

# Security Rules

See [`docs/SECURITY-RULES.md`](../../docs/SECURITY-RULES.md) for the full rule set. That file is the
single source of truth for this project's security rules. It is seeded once into the consumer project
(and owned by it), while this scoped instruction is what makes your harness auto-inject the rules when
you touch `.env*` files or files under `**/api/**`.
