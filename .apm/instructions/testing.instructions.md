---
description: Universal testing rules that apply to any stack — what must be tested, and what integration tests may never do.
---

# Testing

Stack-agnostic rules. The concrete framework, runner, and fixtures come from the project itself — see
Discovery First in the engineering-practices rules.

- **Write tests whenever introducing new logic, features, or significant changes.** Tests accompany the
  implementation; they are never deferred to "later".
- **Prefer what the project already has** — existing fixtures, sample data, base classes, and helpers —
  over ad-hoc ones you invent.
- **Test names describe behavior, not implementation** (`rejectsLoginWithEmptyPassword`, not `testLogin`).
- **Integration tests must exercise the real thing.** Never mock the database. Never substitute an
  in-memory engine for the production one when the production engine has features the substitute lacks.
  Never wrap test methods in framework-wide auto-rollback transactions — they hide lazy-loading and
  transaction-boundary bugs.
- **Do mock third-party external services** (payment gateways, identity providers, upstream APIs) —
  they are not yours to control in tests.
- **Never skip integration tests because "unit tests cover it."** They test different things.
- **Verify secrets and credentials are never included in API responses.**

The `/write-tests` command carries the full procedure — stack discovery, per-layer test targets, and
the pitfall checklist for integration tests.
