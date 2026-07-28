---
description: The Spec-Driven Development (SDD) workflow — the required sequence, per-spec status machine, and enforcement every implementation task must follow.
---

# Spec-Driven Development Workflow

All implementation work follows this sequence per spec. Each step also advances the spec's
**status**, which must be kept identical in the spec's `**Status:**` header **and** its
`specs/INDEX.md` row. The five states are `In Planning → Planned → In Progress → In Review →
Validated`, plus a terminal `Deprecated` reachable from any state (see the legend in
`specs/INDEX.md`). Each spec is also **versioned** — see the spec-versioning rules.

1. **Spec** (`/requirements`) — defines WHAT (user stories, acceptance criteria, edge cases). → status **🔵 In Planning**
2. **Technical Design** (`/technical-design SPEC-X`) — defines HOW (DB schema, API contracts, components). → status **🟣 Planned**
3. **Technical Design Refinement** — execute the Plan Review Workflow for the tech design. (stays **Planned**)
4. **Implementation** — code against the tech design, one branch per SPEC-X. When implementation begins, make sure you are on the spec's `SPEC-N` branch — **if the current branch is already a `SPEC-N` branch for this spec (e.g. a git worktree already checked out for parallel implementation), use it and do NOT create a new branch**; only create one if you are not already on it. → set status to **🟡 In Progress** in both the spec header and `specs/INDEX.md`. If your implementation changes another spec that is already **Planned or later** (a shared schema, API, or contract), update that spec too — bump its version + add a changelog row, or deprecate it if its feature no longer exists.
5. **Verification** — write/run tests against the acceptance criteria (via `/write-tests`), results written to `implementation.md` in the spec folder. → status **🟠 In Review**
6. **Close-out** — in `spec.md`, tick every satisfied acceptance-criterion checkbox (`- [x] AC-N`), mark any intentionally-skipped one `DESCOPED` with a reason (leave it `- [ ]`), write the test evidence to `implementation.md` in the spec folder, then set status to **🟢 Validated** in **both** the `spec.md` header and `specs/INDEX.md`.

Four checks enforce this — the shared scripts in `.spec-workflow/hooks/` (`check-ac-closeout.sh`:
every AC ticked or DESCOPED once a close-out section exists; `check-status-sync.sh`: spec header and
INDEX row agree, use a legal status word, and match reality; `check-spec-version.sh`: a
Planned-or-later spec that changed substantively — or was deprecated — must bump its version + add a
changelog row; `check-open-questions.sh`: an unanswered `## Open Questions` entry holds the spec at
the phase that raised it). They run as a git `pre-commit` hook — blocking a drifted commit from any
tool or human; bypass a single commit with `git commit --no-verify`. That commit boundary is the only
one they run at: no session-end hook is installed, because no harness has an event that means "the
next workflow step was invoked".

Note what `check-status-sync.sh` does **not** claim: being on the `SPEC-N` branch is not evidence that
implementation has started. Cutting the branch early — to plan on it, or to work through an open
question — is fine, and the spec may legitimately still be `In Planning`. Only artifacts in the spec
folder (an `implementation.md`) push the status floor up.

When implementing a spec, always read these files first:
- The spec folder `specs/SPEC-X-*/`: `spec.md` (the contract) and `tech-design.md` (the HOW)
- `.spec-workflow/context-map.md` to locate the architecture & security sources (`kind=architecture` /
  `kind=security`): query a connected provider, else read the listed file, else discover from the
  codebase — defaults to `ARCHITECTURE.md` and `docs/SECURITY-RULES.md`. Honor its `context-schema:`
  front-matter — this core supports `1`; on an unsupported value note `context schema N unsupported`
  and run on discovery alone
- `specs/INDEX.md` for dependency order

Never start implementing a spec that has no `tech-design.md`. Run `/technical-design SPEC-X` first.

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
