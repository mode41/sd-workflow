# Spec-Driven Workflow

Keep AI coding agents on rails. Every change starts from a written spec with testable acceptance
criteria, gets a design that two reviewer agents have argued with, and **cannot be marked done** until
the criteria are ticked and the evidence is recorded — enforced by git hooks, not good intentions.

It is **agent-agnostic**: one source of truth, compiled by
[Microsoft APM](https://microsoft.github.io/apm/) (Agent Package Manager) into whichever coding-agent
harness your project uses — `.claude/`, `.opencode/`, `.cursor/`, `.github/`, … A static website and a
complex information-management system use the **exact same workflow**; stack- and design-specific
guidance is optional and lives in separate
[bundles](docs/extending-with-bundles.md).

## The loop

One spec per unit of work. Each step advances that spec's **status**, which must stay identical in the
spec file and in `specs/INDEX.md` — the hooks fail your commit if they drift.

| What happens | You run | Status becomes |
|---|---|---|
| Define **what** — user stories, acceptance criteria, edge cases | `/requirements <your idea>` | 🔵 In Planning |
| Design **how** — schema, API contracts, components | `/technical-design SPEC-1` | 🟣 Planned |
| Two rounds of independent architecture + security review | *(automatic)* | 🟣 Planned |
| Build it, on a `SPEC-1` branch | — | 🟡 In Progress |
| Prove it against the acceptance criteria | `/write-tests SPEC-1` | 🟠 In Review |
| Tick every criterion, record the test evidence | — | 🟢 Validated |

A spec whose feature no longer exists becomes ⚫ Deprecated and stays as a tombstone — dropped, never
rewritten, so the history stays traceable. Every spec is versioned with an inline changelog, so you can
see *why* it changed and which other spec forced it.

📄 **[See a finished spec](docs/example-spec.md)** — one worked example, `Validated` and closed out,
showing the status header, changelog, ticked acceptance criteria, a descoped one, and the tech design.

## What you get

- **`specs/INDEX.md`** — one table with every spec's status, version, file, and the recommended build
  order, kept in lockstep with the specs themselves.
- **Slash commands** — `/requirements`, `/technical-design`, `/write-tests`, `/frontend-architecture`.
- **Reviewer agents** — `architecture-reviewer`, `security-reviewer`, driving the Plan Review Workflow.
  Pick a model per agent (any model your harness understands, including local ones) — see
  *Choosing models for the reviewer agents*.
- **Security rules** — auto-injected when you touch `.env*` or `**/api/**`.
- **General engineering rules** — `engineering-practices` (discovery before assumption, KISS/DRY/YAGNI,
  what not to introduce), `code-hygiene` (no zombie code; docs and `ARCHITECTURE.md` kept true), and
  `testing` (universal, stack-agnostic testing law). These are the rules you would otherwise hand-write
  into `CLAUDE.md` / `AGENTS.md`; here they ship as managed rules that refresh on `apm update`.
- **Self-enforcing checks** — spec status, acceptance-criteria close-out, and spec versioning are
  enforced two ways (see *Enforcement* below).

What it deliberately does **not** contain: language/framework/design specifics. Those live in
optional bundles, discovered through a frozen profile seam.

## Requirements

- [APM](https://microsoft.github.io/apm/) installed (`apm --version`).
- `git` (for the enforcement floor).
- `jq` — **required**. The project config (`.spec-workflow/config.json`) is JSON, and `jq` is what
  reads and writes it and merges agent hooks safely. The setup script checks for it up front and
  stops before touching anything if it's missing.

## Install (two steps)

APM deploys the shared primitives automatically, but — by design — it does **not** run a
dependency's setup script in your project (that would be a supply-chain footgun). So setup is an
explicit second step you can read before running.

**1. Install the primitives.** Pin by **immutable commit SHA** (not a floating tag) so installs are
reproducible and can't be silently moved under you:

```bash
apm install mode41/sd-workflow#<commit-sha>
```

This deploys the rules, commands, and reviewer agents to **whichever harness markers your repo has** —
`.claude/`, `.opencode/`, `.cursor/`, `.github/`, … (auto-detected; nothing pinned). Verified:
instructions → each harness's rules dir, commands → its commands dir, agents → its agents dir.

**2. Run the one-time setup** (idempotent; re-run after every `apm update`). Read it first if you
like — it's short, does **no** network access, and shells out to nothing but `git` and `jq`:

```bash
bash "$(find apm_modules -path '*/.apm/scripts/init-and-wire.sh' | head -1)"
```

This:
- deploys the enforcement machinery into a committed `.spec-workflow/` directory,
- **seeds** the living files **only if absent** — `specs/INDEX.md`, `docs/PRD.md`,
  `docs/SECURITY-RULES.md`, `AGENTS.md`, `spec-workflow.supplemental.md`,
  `.spec-workflow/config.json` — never clobbering your data,
- **adopts an existing `AGENTS.md`**: if you already have one (most existing projects do), the
  installer never rewrites it — it offers to *append* a marked workflow section (interactively), or
  records it as a manual step if you decline or run non-interactively. Opt out with
  `touch .spec-workflow/.no-agents-merge`,
- merges the config forward (adds entries for newly-shipped reviewer agents, retires dropped ones)
  and prompts for any model you haven't chosen — see *Choosing models* below,
- wires `git config core.hooksPath` (detect-and-preserve — see below),
- emits each present harness's native finish hook (e.g. a Claude `Stop` hook) and stamps each
  agent's configured model into the deployed agent files,
- writes **`.spec-workflow/MANUAL-STEPS.md`** — a regenerated checklist of everything the installer
  could *not* do for you (an existing `AGENTS.md` to extend, a foreign `core.hooksPath` to chain, an
  unsupported harness, etc.). Check the file after each run; resolved items drop off automatically.

Update later with `apm update`, then re-run the step-2 command: managed primitives and templates
refresh; your seeded living files are left untouched (a drift notice prints if your
`docs/SECURITY-RULES.md` diverges from upstream), and `.spec-workflow/MANUAL-STEPS.md` is
regenerated. In CI, use `apm install --frozen` and run `apm audit`.

> **Verified against APM 0.25.0.** Auto-detect deploy works; a dependency's `lifecycle:` block is
> project-scoped and does **not** auto-run in a consumer (hence the explicit step 2); project
> lifecycle scripts are **untrusted by default** (`apm lifecycle trust` required) and executable
> primitives are gated by `apm approve` — so nothing of ours runs without your explicit action.

## Start here

In your coding agent, not the shell:

```
/requirements a CLI that converts CSV files to Parquet
```

That interviews you about the project, fills in `docs/PRD.md`, and splits the work into
`specs/SPEC-N-*.md` files with a recommended build order. Then, per spec:

```
/technical-design SPEC-1     → design reviewed by both reviewer agents, appended to the spec
                             → implement it on a SPEC-1 branch
/write-tests SPEC-1          → tests written and run against the acceptance criteria
                             → tick the criteria, record the evidence, done
```

Adding a feature to a project that already has a PRD? Same entry point — `/requirements <the feature>`
adds a single spec instead of bootstrapping everything.

Not sure what you're aiming at? [`docs/example-spec.md`](docs/example-spec.md) is a complete spec at
the end of that journey, annotated with which hook enforces which convention.

## Deployed layout (in your project)

```
.spec-workflow/            # installer-managed (refreshed each install) — commit this
  hooks/                   #   check-*.sh, pre-commit, checks.sha256 (the git enforcement)
  templates/               #   current spec/INDEX/PRD templates (reference for migrations)
  finish-hook.spec.json    #   the one neutral hook spec compiled per harness
  config.schema.json       #   managed: describes config.json (drives editor validation)
  config.json              #   ← YOURS. Seeded once; values never overwritten. See below.
  MANUAL-STEPS.md          #   generated per-machine checklist of what the installer couldn't do
                           #   (git-ignored via a managed .spec-workflow/.gitignore — don't commit)
specs/                     # your specs (SPEC-N-*.md) + INDEX.md   ← living data, seeded once
                           #   (what one looks like: docs/example-spec.md)
docs/PRD.md                # living data, seeded once
docs/SECURITY-RULES.md     # living data, seeded once (drift-notified on update)
AGENTS.md                  # neutral project memory, seeded once (or workflow section appended if it exists)
spec-workflow.supplemental.md  # your workflow tuning, seeded once, never overwritten
.claude/ .opencode/ ...    # APM-deployed rules/commands/agents + our finish hooks & agent models
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

## Choosing models for the reviewer agents

`.spec-workflow/config.json` decides which model each reviewer subagent runs on:

```json
{
  "$schema": "./config.schema.json",
  "schemaVersion": 1,
  "agents": {
    "architecture-reviewer": { "model": { "default": "opus" } },
    "security-reviewer":     { "model": { "claude": "sonnet", "opencode": "ollama/qwen2.5-coder" } }
  }
}
```

- **Values are written verbatim** into the deployed agent file's `model:` frontmatter — the package
  never translates them, so any model your harness understands works, local ones included
  (`ollama/qwen2.5-coder`, `devstral`, …).
- **`default`** covers every harness without its own key; add a per-harness key only where they differ.
- **Omit a model** (or set it to `null`) and that agent just inherits the harness default.
- The setup script **prompts** for anything unset when run interactively, and simply leaves it unset
  in CI or with no TTY — `apm install --frozen` never blocks. Re-run with `SPEC_WORKFLOW_CONFIGURE=1`
  to change your answers, or edit the JSON directly (the `$schema` pointer gives you editor
  validation and completion).

**Stamped today:** Claude Code (`.claude/agents/`) and opencode (`.opencode/agents/`). Copilot's
`model:` is a list of UI display names and Codex agents are TOML without a model field, so those
harnesses are reported as unsupported and their agents inherit the harness default.

**Why step 2 re-runs every time:** `apm update` overwrites the deployed agent files, so the setup
command re-applies your models afterwards. That is also why your choices live in `config.json` rather
than in the agent files themselves.

Your settings survive package updates: when a new version adds a reviewer agent, its entry is added
(and prompted for) with your existing values untouched; when one is dropped, its entry moves to
`retiredAgents` rather than being deleted, and is restored if the agent ever returns.

## Security notes (read before first install)

- **Setup runs no code without your action.** Unlike npm-style postinstall hooks, APM does **not**
  auto-run a dependency's script in your project — you invoke the step-2 bootstrap explicitly, it is
  short, and it does **no** network access (it shells out only to `git` and `jq`), so you can read
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

## License

MIT — see [LICENSE](LICENSE).
