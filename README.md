# Spec-Driven Workflow

An **agent-agnostic Spec-Driven Development (SDD) workflow**, packaged for
[Microsoft APM](https://microsoft.github.io/apm/) (Agent Package Manager). One source of truth; APM
compiles the shared primitives into whichever coding-agent harness your project uses. A static
website and a complex information-management system use the **exact same workflow** — stack- and
design-specific guidance is provided separately by optional bundles (see
[`docs/extending-with-bundles.md`](docs/extending-with-bundles.md)).

## What you get

- **The spec lifecycle** — `In Planning → Planned → In Progress → In Review → Validated` (+ terminal
  `Deprecated`), one spec per unit of work, tracked in `specs/INDEX.md`.
- **Slash commands** — `/requirements`, `/technical-design`, `/write-tests`, `/frontend-architecture`.
- **Reviewer agents** — `architecture-reviewer`, `security-reviewer`, driving the Plan Review Workflow.
- **Security rules** — auto-injected when you touch `.env*` or `**/api/**`.
- **Self-enforcing checks** — spec status, acceptance-criteria close-out, and spec versioning are
  enforced two ways (see *Enforcement* below).

What it deliberately does **not** contain: language/framework/design specifics. Those live in
optional bundles, discovered through a frozen profile seam.

## Requirements

- [APM](https://microsoft.github.io/apm/) installed (`apm --version`).
- `git` (for the enforcement floor). `jq` is recommended (for clean agent-hook merges; there's a
  fallback without it).

## Install (two steps)

APM deploys the shared primitives automatically, but — by design — it does **not** run a
dependency's setup script in your project (that would be a supply-chain footgun). So setup is an
explicit second step you can read before running.

**1. Install the primitives.** Pin by **immutable commit SHA** (not a floating tag) so installs are
reproducible and can't be silently moved under you:

```bash
apm install nodeline/spec-driven-workflow#<commit-sha>
```

This deploys the shared primitives to **whichever harness markers your repo has** — `.claude/`,
`.opencode/`, `.cursor/`, `.github/`, … (auto-detected; nothing pinned). Verified: instructions →
each harness's rules dir, commands → its commands dir, agents → its agents dir.

**2. Run the one-time setup** (idempotent; re-run after every `apm update`). Read it first if you
like — it's a short, dependency-free, no-network script:

```bash
bash "$(find apm_modules -path '*/.apm/scripts/init-and-wire.sh' | head -1)"
```

This:
- deploys the enforcement machinery into a committed `.spec-workflow/` directory,
- **seeds** the living files **only if absent** — `specs/INDEX.md`, `docs/PRD.md`,
  `docs/SECURITY-RULES.md`, `AGENTS.md`, `spec-workflow.supplemental.md` — never clobbering your data,
- wires `git config core.hooksPath` (detect-and-preserve — see below),
- emits each present harness's native finish hook (e.g. a Claude `Stop` hook).

Update later with `apm update`, then re-run the step-2 command: managed primitives and templates
refresh; your seeded living files are left untouched (a drift notice prints if your
`docs/SECURITY-RULES.md` diverges from upstream). In CI, use `apm install --frozen` and run `apm audit`.

> **Verified against APM 0.25.0.** Auto-detect deploy works; a dependency's `lifecycle:` block is
> project-scoped and does **not** auto-run in a consumer (hence the explicit step 2); project
> lifecycle scripts are **untrusted by default** (`apm lifecycle trust` required) and executable
> primitives are gated by `apm approve` — so nothing of ours runs without your explicit action.

## Deployed layout (in your project)

```
.spec-workflow/            # managed by the installer (refreshed each install) — commit this
  hooks/                   #   check-*.sh, pre-commit, checks.sha256 (the git enforcement)
  templates/               #   current spec/INDEX/PRD templates (reference for migrations)
  finish-hook.spec.json    #   the one neutral hook spec compiled per harness
specs/                     # your specs (SPEC-N-*.md) + INDEX.md   ← living data, seeded once
docs/PRD.md                # living data, seeded once
docs/SECURITY-RULES.md     # living data, seeded once (drift-notified on update)
AGENTS.md                  # neutral project memory, seeded once
spec-workflow.supplemental.md  # your workflow tuning, seeded once, never overwritten
.claude/ .opencode/ ...    # APM-deployed primitives + our emitted finish hooks
```

## Enforcement — what runs where

The three checks (`check-ac-closeout`, `check-status-sync`, `check-spec-version`) run on two layers:

- **git pre-commit — the agent-agnostic floor.** Works for any agent (or none), because it's git,
  not an agent feature. This is the guaranteed layer.
- **Per-harness finish hooks — a bonus.** Where a harness has a finish/stop concept (e.g. Claude
  Code's `Stop` hook), our installer emits it natively. Harnesses without one (e.g. opencode today)
  rely on the git floor alone.

Known, accepted asymmetries — documented, not hidden:

- **`git commit --no-verify` bypasses the git floor.** A harness without a finish hook has no second
  net, so a bypassed commit there is unchecked.
- **`core.hooksPath` is per-clone.** `git clone` does **not** copy `.git/config`, so a fresh clone has
  no git enforcement until someone re-runs `apm install`. (The `.spec-workflow/` scripts are
  committed and travel with the repo; only the *activation* is local.)
- **`core.hooksPath` detect-and-preserve.** If your repo already sets `core.hooksPath` (Husky,
  lefthook, an org secret-scanner), the installer will **not** overwrite it — it warns and prints how
  to chain the spec-workflow checks from your existing hook. Opt out permanently with
  `touch .spec-workflow/.no-git-hooks`.

## Security notes (read before first install)

- **Setup runs no code without your action.** Unlike npm-style postinstall hooks, APM does **not**
  auto-run a dependency's script in your project — you invoke the step-2 bootstrap explicitly, and it
  is short, dependency-free, and does **no** network access, so you can read
  `.apm/scripts/init-and-wire.sh` (or `apm_modules/.../init-and-wire.sh`) before running it. If you
  ever add it to your own `apm.yml` `lifecycle:` block, APM keeps it **untrusted until you run
  `apm lifecycle trust`**. Still: pin by commit SHA, and use `--frozen` + `apm audit` in CI.
- **`docs/SECURITY-RULES.md` is yours.** It is seeded once and never overwritten, so org-specific
  rules survive updates; the installer prints a drift notice when it diverges from upstream so you can
  pull in improvements deliberately.
- **Check-script integrity.** The pre-commit hook verifies the three check scripts against a pinned
  `checks.sha256` before running them, and fails loudly if one was tampered with.

## Extending with stack/design bundles

The core is bundle-ready via a **frozen profile seam**: `/write-tests` and `/technical-design` consult
`docs/stack-profile.md`; `/frontend-architecture` consults `docs/design-profile.md`. If no profile is
present, commands run on discovery of your project's own patterns. See
[`docs/extending-with-bundles.md`](docs/extending-with-bundles.md).
