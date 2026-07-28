#!/usr/bin/env bash
# init-and-wire.sh — post-install PER-AGENT COMPILER + seeder for the Spec-Driven Workflow package.
#
# Runs on every `apm install` / `apm update`. Fully auditable, no network access. It:
#   1. Resolves the consumer project ROOT robustly (never trusts the post-install CWD).
#   2. Deploys the enforcement machinery into a committed .spec-workflow/ dir (MANAGED: overwritten).
#   3. Seeds LIVE instances (specs/INDEX.md, docs/PRD.md, docs/SECURITY-RULES.md, .spec-workflow/context-map.md,
#      AGENTS.md, the supplemental-rules escape hatch, config.json) only if ABSENT — never clobbers
#      living data.
#      For an EXISTING AGENTS.md it offers to append the workflow section (or records a manual step).
#   4. Prints a drift notice for seed-once security rules that diverge from upstream.
#   5. MERGES the project config forward: migrates an older schemaVersion additively, adds entries for
#      subagents this version introduces, retires (never deletes) entries for ones it no longer ships,
#      and prompts for any model left unset.
#   6. Wires git core.hooksPath with DETECT-AND-PRESERVE (never silently steals an existing value).
#   7. Reconciles each present harness's native hooks (today: removes the session-end hook older
#      versions wired — see emit-harness-hooks.sh) and stamps each agent's configured model
#      (delegates to emit-harness-hooks.sh / emit-agent-models.sh).
#   8. Collects every thing it could NOT do (via a cross-process notice sink shared with the emit-*.sh
#      scripts) into a persisted checklist at .spec-workflow/MANUAL-STEPS.md, and prints a summary.
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

# Is this an interactive run? Decided once, reused for prompts (AGENTS.md merge, model choices).
INTERACTIVE=0; [ -t 0 ] && [ -t 1 ] && [ -z "${CI:-}" ] && INTERACTIVE=1

# --- 2. Deploy enforcement machinery (MANAGED — overwrite each run) ---
SW="$ROOT/.spec-workflow"
mkdir -p "$SW/hooks" "$SW/templates"

# Manual-steps sink: a transient file every part of the installer (incl. the delegated emit-*.sh
# subprocesses) appends to via notice_add. Rendered into .spec-workflow/MANUAL-STEPS.md at the end.
SPEC_WORKFLOW_NOTICES="$(mktemp 2>/dev/null || echo "$SW/.install-notices.$$")"; export SPEC_WORKFLOW_NOTICES
: > "$SPEC_WORKFLOW_NOTICES"
trap 'rm -f "$SPEC_WORKFLOW_NOTICES"' EXIT
# The SHIPPED check-*.sh set is the single source of truth for which checks exist. pre-commit and
# emit-harness-hooks.sh both discover them by the same glob, so adding or dropping a check is a
# one-file change here with no list to keep in sync.
#
# PRUNE FIRST: a check this version no longer ships must not survive in the deployed hooks dir — the
# glob in pre-commit would keep running it and the regenerated checks.sha256 would bless it. Safe:
# hooks/ is MANAGED (overwritten every run) by design.
for deployed in "$SW/hooks/"check-*.sh; do
  [ -e "$deployed" ] || continue
  [ -e "$SELF/$(basename "$deployed")" ] || { rm -f "$deployed"; echo "  [prune]  removed stale hook $(basename "$deployed")"; }
done

# Managed files this package USED to deploy into .spec-workflow/ and no longer ships. The check-*.sh
# prune above is glob-driven and cannot see these, so retired names are listed explicitly — one line
# per retirement, removed again once no install can plausibly still carry it. Only ever list files
# that were MANAGED (installer-owned); never a seeded/living one.
for retired in finish-hook.spec.json; do
  [ -e "$SW/$retired" ] || continue
  rm -f "$SW/$retired"; echo "  [prune]  removed retired $retired (renamed to checks.spec.json)"
done

cp "$SELF"/check-*.sh "$SELF/pre-commit" "$SW/hooks/"
cp "$SELF/checks.spec.json" "$SW/"
cp "$PKG/templates/spec.template.md" "$PKG/templates/INDEX.template.md" "$PKG/templates/PRD.template.md" "$PKG/templates/context-map.template.md" "$PKG/templates/audit-trail.template.md" "$SW/templates/" 2>/dev/null || true
chmod +x "$SW/hooks/"*.sh "$SW/hooks/pre-commit" 2>/dev/null || true

# MANAGED: MANUAL-STEPS.md is regenerated per environment (it reflects the machine that ran the
# installer), so keep it out of version control. Written each run so the ignore stays in place.
printf '%s\n' 'MANUAL-STEPS.md' '.install-notices.*' > "$SW/.gitignore"

# checks.sha256 generated over the DEPLOYED check scripts (post-compile) for the S6 integrity gate.
# Same glob as the deploy above, so the hashed set is exactly the deployed set.
( cd "$SW/hooks" \
  && { command -v sha256sum >/dev/null 2>&1 && sha256sum check-*.sh > checks.sha256; } \
  || { command -v shasum >/dev/null 2>&1 && shasum -a 256 check-*.sh > checks.sha256; } ) 2>/dev/null || true
echo "  [deploy] enforcement scripts -> .spec-workflow/hooks/ (+ checks.sha256)"

# --- 3. Seed LIVE instances only if absent ---
seed_if_absent() {   # <src> <dest-rel>
  local src="$1" dest="$ROOT/$2"
  if [ -e "$dest" ]; then skipped+=("$2"); return; fi
  mkdir -p "$(dirname "$dest")"
  cp "$src" "$dest" && seeded+=("$2")
}

# AGENTS.md is workflow-managed guidance, not a plain scaffold: seed it whole when absent, and when it
# already exists, offer to APPEND just the workflow section (guarded by a sentinel) so an existing
# project's own AGENTS.md gains the SDD context. Never rewrites the user's own prose.
handle_agents_md() {
  local dest="$ROOT/AGENTS.md"
  local header="$PKG/live-seed/AGENTS.md.stub" snippet="$PKG/live-seed/AGENTS.snippet.md"
  if [ ! -e "$dest" ]; then
    { sed "s/{{PROJECT_NAME}}/$(basename "$ROOT")/g" "$header"; echo; cat "$snippet"; } > "$dest" \
      && seeded+=("AGENTS.md")
    return
  fi
  # Existing file already carries our section? Leave it entirely alone (keeps `apm update` quiet).
  if grep -qF "spec-workflow:begin" "$dest"; then skipped+=("AGENTS.md"); return; fi
  # Permanently opted out of the merge?
  if [ -f "$SW/.no-agents-merge" ]; then skipped+=("AGENTS.md"); return; fi
  # Offer to append the section interactively; otherwise record it as a manual step.
  if [ "$INTERACTIVE" -eq 1 ]; then
    printf '\n  Your AGENTS.md exists but has no spec-driven-workflow section.\n'
    printf '    Append it now? (keeps your content; adds one marked section) [y/N] '
    local reply; read -r reply || reply=""
    case "$reply" in
      [yY]|[yY][eE][sS])
        [ -n "$(tail -c1 "$dest" 2>/dev/null)" ] && printf '\n' >> "$dest"   # ensure a trailing newline first
        { printf '\n'; cat "$snippet"; } >> "$dest"
        echo "  [agents] appended workflow section to existing AGENTS.md — review it"
        return ;;
    esac
  fi
  skipped+=("AGENTS.md")
  notice_add "AGENTS.md exists without the workflow section — append the block from $PKG/live-seed/AGENTS.snippet.md (or 'touch .spec-workflow/.no-agents-merge' to silence)."
}

mkdir -p "$ROOT/specs" "$ROOT/docs"
seed_if_absent "$PKG/templates/INDEX.template.md"  "specs/INDEX.md"
seed_if_absent "$PKG/templates/PRD.template.md"    "docs/PRD.md"
seed_if_absent "$PKG/live-seed/security-rules.md"  "docs/SECURITY-RULES.md"
seed_if_absent "$PKG/templates/context-map.template.md" ".spec-workflow/context-map.md"
handle_agents_md
seed_if_absent "$PKG/templates/supplemental-rules.md" "spec-workflow.supplemental.md"
seed_if_absent "$PKG/live-seed/config.stub.json"    ".spec-workflow/config.json"
[ ${#seeded[@]}  -gt 0 ] && echo "  [seed]   created: ${seeded[*]}"
[ ${#skipped[@]} -gt 0 ] && echo "  [seed]   kept existing (not clobbered): ${skipped[*]}"

# One-time nudge: a freshly-seeded context map still holds only the default rows. Invite the user to
# point it at where their real governing context lives (or connect an MCP context provider). Gated on
# fresh-seed so it fires once and never re-nags — seed_if_absent won't recreate an existing file.
if [ ${#seeded[@]} -gt 0 ]; then
  case " ${seeded[*]} " in
    *" .spec-workflow/context-map.md "*)
      notice_add "Populate .spec-workflow/context-map.md — point it at where your architecture, security, business, ADR, and UX context actually lives (repo files, Confluence/Notion URLs, or an MCP context provider such as architrace). Contract: https://github.com/mode41/sd-workflow/blob/main/docs/extending-with-bundles.md" ;;
  esac
fi

# The schema is MANAGED (refreshed each run) — it describes the format, not your choices.
cp "$PKG/live-seed/config.schema.json" "$SW/config.schema.json" 2>/dev/null || true

# --- 4. Drift notice for seed-once security rules (S3) ---
if [ -f "$ROOT/docs/SECURITY-RULES.md" ] && ! cmp -s "$ROOT/docs/SECURITY-RULES.md" "$PKG/live-seed/security-rules.md"; then
  echo "  [drift]  docs/SECURITY-RULES.md differs from upstream — review changes (diff against $PKG/live-seed/security-rules.md). Not modified."
  notice_add "docs/SECURITY-RULES.md diverges from upstream — review the diff: diff docs/SECURITY-RULES.md $PKG/live-seed/security-rules.md"
fi

# --- 5. Merge the project config forward, then prompt for anything unset ---
# The shipped agent files ARE the schema: a new subagent upstream becomes a new config entry with no
# script change, and because the new entry has no model, the prompt below fires for exactly it.
CONFIG="$SW/config.json"
CONFIG_OK=1
config_validate "$CONFIG"; case $? in
  1) exit 1 ;;          # malformed — abort before compounding a user typo
  2) CONFIG_OK=0        # schema newer than we understand — leave it alone, skip stamping
     notice_add "config schema in .spec-workflow/config.json is newer than this package understands — upgrade spec-driven-workflow ('apm update'); reviewer models were NOT stamped this run." ;;
esac

# Bring an older config forward first (additive: new keys get their defaults, set values are kept),
# so everything below reads a config in this version's shape.
[ "$CONFIG_OK" -eq 1 ] && config_migrate

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
  if [ "$INTERACTIVE" -eq 1 ]; then
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
        notice_add "One or more reviewer subagents have no model set — edit .spec-workflow/config.json (or re-run this installer interactively) to choose; unset agents inherit the harness default."
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
      notice_add "git core.hooksPath is already '$existing' — the spec-workflow pre-commit gate is NOT active. Chain it from your existing pre-commit (SPEC_WORKFLOW_ROOT=\"\$(git rev-parse --show-toplevel)\" bash \"\$(git rev-parse --show-toplevel)/$target/pre-commit\") or 'touch $SW/.no-git-hooks' to opt out."
    fi
  fi
else
  echo "  [git]    not a git work-tree — skipped core.hooksPath wiring (run 'apm install' again after 'git init')"
  notice_add "Not a git work-tree — the pre-commit gate could not be wired. Run 'git init' then re-run the installer."
fi

# --- 7. Reconcile per-harness native hooks, then stamp each agent's configured model ---
bash "$SELF/emit-harness-hooks.sh" "$ROOT" "$SW" || { echo "  [hooks]  per-harness hook reconcile reported an issue (git pre-commit still enforces)"; notice_add "Per-harness hook reconcile failed — the git pre-commit gate still enforces the checks. If an older install wired a spec-workflow 'Stop' hook into .claude/settings.json it may still be there, firing at the end of every turn; re-run the installer after resolving the error above, or remove those entries by hand."; }
# Runs every time on purpose: apm update overwrites the deployed agent files, so this re-applies
# the configured models afterwards.
[ "$CONFIG_OK" -eq 1 ] && { bash "$SELF/emit-agent-models.sh" "$ROOT" "$PKG" "$CONFIG" || { echo "  [models] model stamping reported an issue (agents fall back to the harness default)"; notice_add "Model stamping failed — reviewer agents fall back to the harness default. Re-run the installer after resolving the error above."; }; }

# --- 8. Render the collected manual steps into a persisted checklist ---
render_manual_steps() {
  local out="$SW/MANUAL-STEPS.md"
  if [ ! -s "$SPEC_WORKFLOW_NOTICES" ]; then
    { echo "# Spec-Driven Workflow — Manual Steps"; echo; echo "_✓ No outstanding manual steps as of the last install/update._"; } > "$out"
    return
  fi
  # Preserve any items the user already ticked off (best-effort match on the item text against the
  # previous file). Read the sink line by line and emit one checkbox per notice.
  {
    echo "# Spec-Driven Workflow — Manual Steps"
    echo
    echo "_Regenerated by the installer on each \`apm install\` / \`apm update\`. Resolved items drop off"
    echo "automatically next run; check off the rest as you complete them. Wording may change across"
    echo "package versions, which can reset a checkmark._"
    echo
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      local box="- [ ]"
      # Was this exact item previously checked? Keep it checked. -e is required because the pattern
      # begins with "-", which grep would otherwise parse as options.
      if [ -f "$out" ] && grep -qxF -e "- [x] $line" "$out" 2>/dev/null; then box="- [x]"; fi
      echo "$box $line"
    done < "$SPEC_WORKFLOW_NOTICES"
  } > "$out.tmp" && mv "$out.tmp" "$out"
  local n; n=$(grep -c '^- \[' "$out" 2>/dev/null || echo 0)
  echo "  [manual] $n step(s) need your attention — see .spec-workflow/MANUAL-STEPS.md"
}
render_manual_steps

echo "spec-driven-workflow: done."
