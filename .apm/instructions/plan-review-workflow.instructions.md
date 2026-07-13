---
description: The mandatory iterative plan-review pipeline (two rounds of independent architecture + security review) to run before presenting any non-trivial plan.
---

# Plan Review Workflow

Before presenting any plan to the user, run the full iterative review pipeline below.
Do not skip, abbreviate, or present the plan before the pipeline completes.

A "plan" includes: proposed architecture, new features, API design, data model changes,
infrastructure changes, and any change touching auth, data storage, or external services.
For small isolated changes (typo fixes, renaming, minor refactors) this is optional.

The two reviewer agents (`architecture-reviewer` and `security-reviewer`) are deployed with this
package; invoke them the way your harness invokes subagents (from its agents directory).

---

## Round 1 — Independent Review

Run both agents in parallel on the original plan:

- **Task A — Architecture Review** — agent `architecture-reviewer`, input: the full proposed plan +
  relevant codebase context.
- **Task B — Security Review** — agent `security-reviewer`, input: the full proposed plan + relevant
  codebase context.

Do not pass either agent's output to the other in Round 1. Independence is the point.

---

## Refinement — Revise the Plan

Once both Round 1 reviews are complete:

1. Collect all critical issues and concerns from both reviews.
2. Revise the plan to address them — cross-discipline first:
   - Apply security fixes that affect architectural decisions.
   - Apply architectural changes that have security implications.
   - Then address remaining single-discipline issues.
3. Note every change made and which finding it resolves.
4. Note any issues you chose not to address and why.

This produces a **Revised Plan** and a **Change Log**.

---

## Round 2 — Cross-Informed Review

Run both agents again on the Revised Plan, with full context from Round 1:

- **Task C — Architecture Review (Round 2)** — input: revised plan + change log + Round 1
  architecture review + Round 1 security review. Focus: do the security-driven changes introduce
  architectural problems? Are Round 1 architecture concerns resolved?
- **Task D — Security Review (Round 2)** — input: revised plan + change log + Round 1 security review
  + Round 1 architecture review. Focus: do the architecture-driven changes introduce security
  problems? Are Round 1 security concerns resolved?

---

## Evaluate Round 2 Verdicts

| State | Action |
|---|---|
| Both Round 2 verdicts PASS or PASS WITH CONCERNS, all critical issues resolved | Proceed to Present — clean |
| PASS WITH CONCERNS remain but no critical issues | Proceed to Present — flag concerns to user |
| Any Round 2 FAIL, or any Round 1 critical issue unresolved after revision | **Stop — escalate to user before proceeding** |

An issue counts as "resolved" only if the reviewing agent in Round 2 explicitly confirms it. Do not
self-certify resolution.

---

## Present to User

**If the pipeline completed cleanly:** present the revised plan in full; a brief change log tied to
the findings that drove each change; any open concerns (not critical) with your recommendation on
each; and a recommendation (proceed / proceed with caveats / needs further design).

**If the pipeline has unresolved critical issues:** **Stop.** Present the unresolved issues clearly.
Do not present the plan as ready. Ask the user how they want to proceed — redesign, accept the risk
explicitly, or descope the change. Do not bury failures in a long summary; lead with the blocker.
