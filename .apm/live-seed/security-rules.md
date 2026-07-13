# Security Rules

Applies whenever editing `.env*` files or files under `**/api/**`. These rules auto-inject for
matching paths via the workflow's `security` instruction, which your agent harness compiles to its
own rules location (e.g. `.claude/rules/`, `.cursor/rules/`) or loads via its instructions manifest
(e.g. opencode's `opencode.json`).

> This file is **seeded once** and owned by your project — `apm update` never overwrites it, so any
> org-specific rules you add are safe. The installer prints a drift notice when it diverges from the
> upstream default so you can pull in improvements deliberately.

## Secrets Management
- NEVER commit secrets, API keys, or credentials to git
- Use `.env.local` (or equivalent) for local development — keep it in `.gitignore`
- Document all required env vars in `.env.local.example` with dummy values

## Input Validation
- Never trust client-side validation alone
- Sanitize data before database insertion / external command execution

## Authentication
- Always verify authentication before processing API requests
- Implement rate limiting on authentication endpoints

## Security Headers
- X-Frame-Options: DENY
- X-Content-Type-Options: nosniff
- Referrer-Policy: origin-when-cross-origin
- Strict-Transport-Security with includeSubDomains

## Code Review Triggers
- Any changes to authentication flow require explicit user approval
- Any new environment variables must be documented in `.env.local.example`
