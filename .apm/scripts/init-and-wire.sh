#!/usr/bin/env bash
# init-and-wire.sh — post-install PER-AGENT COMPILER + seeder for the Spec-Driven Workflow package.
#
# Runs on every `apm install` / `apm update`. Fully auditable, no network access. It:
#   1. Resolves the consumer project ROOT robustly (never trusts the post-install CWD).
#   2. Deploys the enforcement machinery into a committed .spec-workflow/ dir (MANAGED: overwritten).
#   3. Seeds LIVE instances (specs/INDEX.md, docs/PRD.md, docs/SECURITY-RULES.md, AGENTS.md,
#      the supplemental-rules escape hatch, config.json) only if ABSENT — never clobbers living data.
#   4. Prints a drift notice for seed-once security rules that diverge from upstream.
#   5. MERGES the project config forward: adds entries for subagents this version introduces, retires
#      (never deletes) entries for ones it no longer ships, and prompts for any model left unset.
#   6. Wires git core.hooksPath with DETECT-AND-PRESERVE (never silently steals an existing value).
#   7. Emits each present harness's native finish hook and stamps each agent's configured model
#      (delegates to emit-harness-hooks.sh / emit-agent-models.sh).
#   8. Prints a one-line-per-item summary.
#
# Requires jq: the project config is JSON. Checked up front so we fail before touching anything.
set -uo pipefail

# --- 1. Resolve SELF (this package's script dir) and ROOT (consumer project root) ---
SELF="$(cd "$(dirname "$0")" && pwd -P)"     # .../apm_modules/spec-driven-workflow/.apm/scripts
PKG="$(cd "$SELF/.." && pwd -P)"             # the deployed .apm dir (templates/, live-seed/ live here)
ROOT="${APM_PROJECT_DIR:-$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || echo "$PWD")}"
# If we resolved to somewhere inside apm_modules, climb out to the real project root.
case "$ROOT" in */apm_modules/*) ROOT="${ROOT%%/apm_modules/*}";; esac
[ -n "$ROOT" ] && [ -d "$ROOT" ] || { echo "spec-driven-workflow: could not resolve project root; aborting." >&2; exit 1; }

# shellcheck source=/dev/null
. "$SELF/config-lib.sh"
config_require_jq || exit 1

echo "spec-driven-workflow: installing into $ROOT"
seeded=(); skipped=()

# --- 2. Deploy enforcement machinery (MANAGED — overwrite each run) ---
SW="$ROOT/.spec-workflow"
mkdir -p "$SW/hooks" "$SW/templates"
cp "$SELF/check-ac-closeout.sh" "$SELF/check-status-sync.sh" "$SELF/check-spec-version.sh" "$SELF/pre-commit" "$SW/hooks/"
cp "$SELF/finish-hook.spec.json" "$SW/"
cp "$PKG/templates/spec.template.md" "$PKG/templates/INDEX.template.md" "$PKG/templates/PRD.template.md" "$SW/templates/" 2>/dev/null || true
chmod +x "$SW/hooks/"*.sh "$SW/hooks/pre-commit" 2>/dev/null || true

# checks.sha256 generated over the DEPLOYED check scripts (post-compile) for the S6 integrity gate.
( cd "$SW/hooks" \
  && { command -v sha256sum >/dev/null 2>&1 && sha256sum check-ac-closeout.sh check-status-sync.sh check-spec-version.sh > checks.sha256; } \
  || { command -v shasum >/dev/null 2>&1 && shasum -a 256 check-ac-closeout.sh check-status-sync.sh check-spec-version.sh > checks.sha256; } ) 2>/dev/null || true
echo "  [deploy] enforcement scripts -> .spec-workflow/hooks/ (+ checks.sha256)"

# --- 3. Seed LIVE instances only if absent ---
seed_if_absent() {   # <src> <dest-rel>
  local src="$1" dest="$ROOT/$2"
  if [ -e "$dest" ]; then skipped+=("$2"); return; fi
  mkdir -p "$(dirname "$dest")"
  cp "$src" "$dest" && seeded+=("$2")
}
mkdir -p "$ROOT/specs" "$ROOT/docs"
seed_if_absent "$PKG/templates/INDEX.template.md"  "specs/INDEX.md"
seed_if_absent "$PKG/templates/PRD.template.md"    "docs/PRD.md"
seed_if_absent "$PKG/live-seed/security-rules.md"  "docs/SECURITY-RULES.md"
seed_if_absent "$PKG/live-seed/AGENTS.md.stub"     "AGENTS.md"
seed_if_absent "$PKG/templates/supplemental-rules.md" "spec-workflow.supplemental.md"
seed_if_absent "$PKG/live-seed/config.stub.json"    ".spec-workflow/config.json"
[ ${#seeded[@]}  -gt 0 ] && echo "  [seed]   created: ${seeded[*]}"
[ ${#skipped[@]} -gt 0 ] && echo "  [seed]   kept existing (not clobbered): ${skipped[*]}"

# The schema is MANAGED (refreshed each run) — it describes the format, not your choices.
cp "$PKG/live-seed/config.schema.json" "$SW/config.schema.json" 2>/dev/null || true

# --- 4. Drift notice for seed-once security rules (S3) ---
if [ -f "$ROOT/docs/SECURITY-RULES.md" ] && ! cmp -s "$ROOT/docs/SECURITY-RULES.md" "$PKG/live-seed/security-rules.md"; then
  echo "  [drift]  docs/SECURITY-RULES.md differs from upstream — review changes (diff against .spec-workflow reference or the package). Not modified."
fi

# --- 5. Merge the project config forward, then prompt for anything unset ---
# The shipped agent files ARE the schema: a new subagent upstream becomes a new config entry with no
# script change, and because the new entry has no model, the prompt below fires for exactly it.
CONFIG="$SW/config.json"
CONFIG_OK=1
config_validate "$CONFIG"; case $? in
  1) exit 1 ;;          # malformed — abort before compounding a user typo
  2) CONFIG_OK=0 ;;     # schema newer than we understand — leave it alone, skip stamping
esac

shipped=""
if [ "$CONFIG_OK" -eq 1 ]; then
  for src in "$PKG"/agents/*.agent.md; do
    [ -e "$src" ] || continue
    stem="$(basename "$src" .agent.md)"
    shipped="$shipped $stem"
    if ! config_agent_known "$stem"; then
      if config_was_retired "$stem"; then
        config_add_agent "$stem" && echo "  [config] restored $stem (agent ships again; prior model kept)"
      else
        config_add_agent "$stem" && echo "  [config] added $stem"
      fi
    fi
  done

  # Entries whose agent no longer ships: retire (keep the value), never delete.
  for known in $(config_agent_names); do
    case " $shipped " in
      *" $known "*) ;;
      *) config_retire_agent "$known" && echo "  [config] retired $known (agent no longer ships; value kept)" ;;
    esac
  done
fi

# --- 5b. Prompt for unset models (interactive only; never blocks CI) ---
prompt_hint() {   # <harness>
  case "$1" in
    claude)   echo "opus · sonnet · haiku · inherit · or a full ID like claude-opus-4-8" ;;
    opencode) echo "anthropic/claude-opus-4-8 · ollama/qwen2.5-coder · ollama/devstral" ;;
    *)        echo "any model string this harness understands" ;;
  esac
}
harness_label() { case "$1" in claude) echo "Claude Code";; opencode) echo "opencode";; *) echo "$1";; esac; }

harnesses=""
[ -d "$ROOT/.claude/agents" ]   && harnesses="$harnesses claude"
[ -d "$ROOT/.opencode/agents" ] && harnesses="$harnesses opencode"

if [ "$CONFIG_OK" -eq 1 ] && [ -n "$harnesses" ]; then
  if [ -t 0 ] && [ -t 1 ] && [ -z "${CI:-}" ]; then
    asked=0
    for stem in $shipped; do
      for h in $harnesses; do
        current="$(config_model_for "$stem" "$h")"
        # Ask only when unset — unless explicitly re-configuring.
        [ -z "$current" ] || [ "${SPEC_WORKFLOW_CONFIGURE:-}" = "1" ] || continue
        [ "$asked" -eq 0 ] && printf '\n  Choose the model for each reviewer subagent (empty = inherit the harness default).\n'
        asked=1
        printf '\n  %s on %s\n    e.g. %s\n' "$stem" "$(harness_label "$h")" "$(prompt_hint "$h")"
        [ -n "$current" ] && printf '    current: %s\n' "$current"
        printf '    model> '
        read -r reply || reply=""
        [ -n "$reply" ] && config_set_model "$stem" "$h" "$reply"
      done
    done
    [ "$asked" -eq 1 ] && printf '\n  [config] saved to .spec-workflow/config.json (edit any time; re-run with SPEC_WORKFLOW_CONFIGURE=1 to change)\n'
  else
    for stem in $shipped; do
      for h in $harnesses; do
        [ -z "$(config_model_for "$stem" "$h")" ] || continue
        echo "  [config] non-interactive — models unset; edit .spec-workflow/config.json to choose"
        break 2
      done
    done
  fi
fi

# --- 6. Wire git hooks: DETECT-AND-PRESERVE (S2) ---
if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  target=".spec-workflow/hooks"
  if [ -f "$SW/.no-git-hooks" ]; then
    echo "  [git]    core.hooksPath wiring opted out (.spec-workflow/.no-git-hooks present) — left unchanged"
  else
    existing="$(git -C "$ROOT" config --local --get core.hooksPath 2>/dev/null || true)"
    if [ -z "$existing" ] || [ "$existing" = "$target" ]; then
      git -C "$ROOT" config core.hooksPath "$target"
      echo "  [git]    core.hooksPath -> $target (spec-workflow pre-commit gate active)"
    else
      echo "  [git]    WARNING: core.hooksPath is already '$existing' — NOT overwriting."
      echo "           To also run the spec-workflow checks, chain them from your existing pre-commit:"
      echo "             SPEC_WORKFLOW_ROOT=\"\$(git rev-parse --show-toplevel)\" bash \"\$(git rev-parse --show-toplevel)/$target/pre-commit\""
      echo "           Or opt out permanently: touch $SW/.no-git-hooks"
    fi
  fi
else
  echo "  [git]    not a git work-tree — skipped core.hooksPath wiring (run 'apm install' again after 'git init')"
fi

# --- 7. Emit per-harness native finish hooks, then stamp each agent's configured model ---
bash "$SELF/emit-harness-hooks.sh" "$ROOT" "$SW" || echo "  [hooks]  per-harness hook emit reported an issue (git floor still enforces)"
# Runs every time on purpose: apm update overwrites the deployed agent files, so this re-applies
# the configured models afterwards.
[ "$CONFIG_OK" -eq 1 ] && { bash "$SELF/emit-agent-models.sh" "$ROOT" "$PKG" "$CONFIG" || echo "  [models] model stamping reported an issue (agents fall back to the harness default)"; }

echo "spec-driven-workflow: done."
