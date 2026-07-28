---
description: The Spec-Driven Development (SDD) workflow — the required sequence, per-spec status machine, and enforcement every implementation task must follow.
---

# Spec-Driven Development Workflow

All implementation work follows this sequence per spec. Each step also advances the spec's
**status**, which must be kept identical in the spec's `**Status:**` header **and** its
`specs/INDEX.md` row. The five states are `In Planning → Planned → In Progress → In Review →
Validated`, plus a terminal `Deprecated` reachable from any state (see the legend in
`specs/INDEX.md`). Each spec is also **versioned** — see the spec-versioning rules.

1. **Spec** (`/requirements`) — defines WHAT (user stories, acceptance criteria, edge cases). Cuts the spec's branch first, if you are still on the repo's default branch. → status **🔵 In Planning**
2. **Technical Design** (`/technical-design SPEC-X`) — defines HOW (DB schema, API contracts, components). → status **🟣 Planned**
3. **Technical Design Refinement** — execute the Plan Review Workflow for the tech design. (stays **Planned**)
4. **Implementation** — code against the tech design, on the spec's branch. Stay on the branch step 1 cut; only cut one now if you are somehow still on the default branch. → set status to **🟡 In Progress** in both the spec header and `specs/INDEX.md`. If your implementation changes another spec that is already **Planned or later** (a shared schema, API, or contract), update that spec too — bump its version + add a changelog row, or deprecate it if its feature no longer exists.
5. **Verification** — write/run tests against the acceptance criteria (via `/write-tests`), results written to `audit-trail.md` in the spec folder, from `.spec-workflow/templates/audit-trail.template.md`. → status **🟠 In Review**
6. **Close-out** — in `spec.md`, tick every satisfied acceptance-criterion checkbox (`- [x] AC-N`), mark any intentionally-skipped one `DESCOPED` with a reason (leave it `- [ ]`), complete `audit-trail.md`, then set status to **🟢 Validated** in **both** the `spec.md` header and `specs/INDEX.md`.

The audit trail is the spec's verification record, and the only place the **AC → evidence** mapping
exists: `spec.md` says a criterion is met, `audit-trail.md` says what proves it. `check-ac-closeout.sh`
blocks the commit if any AC ticked in `spec.md` is never cited there. Read the mechanical facts out of
git rather than from memory — `git branch --show-current`, `git merge-base <default-branch> HEAD`,
`git log --oneline <base>..HEAD`, `git diff --name-only <base>..HEAD` — and record the test run as
observed, including skips and failures. Do not create the file before there is real evidence for it: its mere existence pushes the
status floor to **In Review**.

Four checks enforce this — the shared scripts in `.spec-workflow/hooks/` (`check-ac-closeout.sh`:
every AC ticked or DESCOPED once a close-out section exists; `check-status-sync.sh`: spec header and
INDEX row agree, use a legal status word, and match reality; `check-spec-version.sh`: a
Planned-or-later spec that changed substantively — or was deprecated — must bump its version + add a
changelog row; `check-open-questions.sh`: an unanswered `## Open Questions` entry holds the spec at
the phase that raised it). They run as a git `pre-commit` hook — blocking a drifted commit from any
tool or human; bypass a single commit with `git commit --no-verify`. That commit boundary is the only
one they run at: no session-end hook is installed, because no harness has an event that means "the
next workflow step was invoked".

How they pick which spec to judge: the ones your change **touches** — any file under a spec folder,
or a changed `specs/INDEX.md` row. Never the branch name. So a commit of pure source code is silent,
drift is caught wherever it happens (including on the default branch), and a commit spanning two
specs is judged for both.

Note what `check-status-sync.sh` does **not** claim: having cut the branch is not evidence that
implementation has started. Cutting it early — to plan on it, or to work through an open question —
is fine, and the spec may legitimately still be `In Planning`. Only artifacts in the spec folder (an
`audit-trail.md`) push the status floor up.

When implementing a spec, always read these files first:
- The spec folder `specs/SPEC-X-*/`: `spec.md` (the contract) and `tech-design.md` (the HOW)
- `.spec-workflow/context-map.md` to locate the architecture & security sources (`kind=architecture` /
  `kind=security`): query a connected provider, else read the listed file, else discover from the
  codebase — defaults to `ARCHITECTURE.md` and `docs/SECURITY-RULES.md`. Honor its `context-schema:`
  front-matter — this core supports `1`; on an unsupported value note `context schema N unsupported`
  and run on discovery alone
- `specs/INDEX.md` for dependency order

Never start implementing a spec that has no `tech-design.md`. Run `/technical-design SPEC-X` first.

## Branches

Spec work belongs on a branch, never the repo's default branch (`main`, `master`, whatever
`git symbolic-ref refs/remotes/origin/HEAD` reports). `/requirements` checks this and offers to cut
one before it writes anything; if you arrive at a later phase still on the default branch, cut one
first. Everything for a spec — `spec.md`, `tech-design.md`, the code, `audit-trail.md` — belongs on
that one branch.

**The name is yours.** Nothing in this workflow reads it: no command parses it and no check is gated
on it, so `SPEC-4-glossary`, `userstory-1928`, a ticket key or a release-train name all behave
identically. Use whatever your project's development process requires, and record project-specific
branch-naming rules in `.spec-workflow/spec-workflow.supplemental.md`. Because the name carries no
meaning to the tooling, record the branch you actually used in `audit-trail.md` — that line is the
only durable link from a spec back to the work that closed it.

## Related rules

This rule covers the workflow only. Deployed alongside it, in the same rules directory:

- **spec-versioning** — when to bump a spec's `**Version:**`, what counts as substantive, deprecation.
- **plan-review-workflow** — the two-round architecture + security review to run before presenting a plan.
- **interaction-mode** — where a command's questions go (terminal, or a `## Open Questions` block in
  the spec for unattended runs) and the status ceiling an unanswered one imposes on the next step.
- **testing** — universal testing rules (step 5 produces the evidence; these rules govern how).
- **code-hygiene** — what "done" means for a change: no zombie code, docs and the architecture source kept true.
- **engineering-practices** — discovery before assumption, KISS/DRY/YAGNI, what not to introduce.
- **security** — when you touch `.env*` or `**/api/**`, injects the security rules located via `.spec-workflow/context-map.md` (`kind=security`; defaults to `docs/SECURITY-RULES.md`).

The workflow is stack- and design-agnostic. Optional stack/design profiles
(`.spec-workflow/profiles/`), and the **context map** (`.spec-workflow/context-map.md`) that says where
your governing context lives (architecture, security, business, ADRs, UX — repo files or external
tools/providers), are extension points the commands consult when present. Full contract:
<https://github.com/mode41/sd-workflow/blob/main/docs/extending-with-bundles.md>
