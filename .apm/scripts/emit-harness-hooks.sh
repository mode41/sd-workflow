#!/usr/bin/env bash
# emit-harness-hooks.sh — the PER-HARNESS HOOK RECONCILER.
#
# The check-*.sh guards are enforced at ONE boundary: the git pre-commit hook (see hooks/pre-commit).
# No harness session-end hook is emitted, and this script REMOVES any we wired in an earlier version.
#
# Why we stopped emitting one. We used to merge the checks into Claude Code's `Stop` hook, calling it a
# "finish boundary". It is not one: `Stop` fires when the agent finishes responding — i.e. at the end of
# EVERY turn, including a turn that only answered a question or discussed an open Q-N. No harness exposes
# a "the next workflow step was invoked" event, so there was nothing to bind to. And a `Stop` hook that
# exits 2 does not warn, it *blocks the agent from stopping* and feeds stderr back as an instruction to
# continue — so an ordinary conversational turn became a forced continuation. A commit is a real workflow
# boundary; a turn ending is not. The git floor is also agent-agnostic, which the Stop hook never was.
#
# This script stays as the SEAM: if a harness ever ships a genuine step-boundary event, its emitter
# belongs here. Until then its only job is cleanup, so an existing project stops being interrupted as
# soon as the installer runs.
#
# Usage: emit-harness-hooks.sh <ROOT> <SPEC_DIR>
#   ROOT     = consumer project root
#   SPEC_DIR = the deployed .spec-workflow dir (holds hooks/ and checks.spec.json)
set -euo pipefail
ROOT="$1"
SPEC_DIR="$2"
SPEC="$SPEC_DIR/checks.spec.json"
HOOKS_REL=".spec-workflow/hooks"       # overridden below from the spec's hooksDir
# The marker the OLD emitter stamped on every command it wrote. It is how we recognise our own
# leftovers in a user's settings.json — so it must keep this exact string forever, even though the
# "finish-hook" concept is gone. Renaming it would orphan every hook we ever wired.
SENTINEL="spec-workflow-finish-hook"

SELF="$(cd "$(dirname "$0")" && pwd -P)"
# shellcheck source=/dev/null
. "$SELF/config-lib.sh"   # for notice_add — contributes to the installer's shared MANUAL-STEPS sink

log() { printf '  [hooks] %s\n' "$1"; }

# --- Claude Code: remove any Stop hook a previous version of this installer merged in ---
# Untouched if we never wrote one, and other Stop entries (the user's own, another tool's) are preserved
# — we only ever drop commands carrying our sentinel.
unwire_claude() {
  local settings="$ROOT/.claude/settings.json"
  [ -f "$settings" ] || return 0
  grep -q "$SENTINEL" "$settings" 2>/dev/null || return 0
  if ! command -v jq >/dev/null 2>&1; then
    log "ERROR: a stale spec-workflow Stop hook is wired in .claude/settings.json, but jq is missing to remove it safely."
    notice_add "A stale spec-workflow Stop hook is still wired in .claude/settings.json — it fires at the end of every turn and can interrupt ordinary conversation. Install jq and re-run the installer, or delete the '$SENTINEL' entries from the hooks.Stop array by hand."
    return 0
  fi
  if jq --arg s "$SENTINEL" '
    .hooks.Stop = ((.hooks.Stop // [])
      | map(.hooks |= (map(select((.command // "") | contains($s) | not))))
      | map(select((.hooks // []) | length > 0)))
    | if (.hooks.Stop | length) == 0 then del(.hooks.Stop) else . end
    | if (.hooks | length) == 0 then del(.hooks) else . end
  ' "$settings" > "$settings.tmp"; then
    mv "$settings.tmp" "$settings"
    log "removed the stale spec-workflow Stop hook from .claude/settings.json (checks now run at git pre-commit)"
  else
    rm -f "$settings.tmp"
    log "ERROR: could not rewrite .claude/settings.json to drop the stale Stop hook (invalid JSON?)."
    notice_add "A stale spec-workflow Stop hook is still wired in .claude/settings.json and could not be removed automatically — it fires at the end of every turn and can interrupt ordinary conversation. Delete the '$SENTINEL' entries from the hooks.Stop array by hand."
  fi
  return 0
}

# The spec supplies the harness-neutral metadata (where the deployed hooks live). WHICH checks run is
# discovered from the deployed check-*.sh set by the pre-commit's own glob, so the two can never disagree.
if [ -f "$SPEC" ] && command -v jq >/dev/null 2>&1; then
  spec_hooks_dir=$(jq -r '.hooksDir // empty' "$SPEC" 2>/dev/null || true)
  [ -n "$spec_hooks_dir" ] && HOOKS_REL="$spec_hooks_dir"
fi

[ -d "$ROOT/.claude" ] && unwire_claude
log "checks are enforced at commit time by $HOOKS_REL/pre-commit — no session-end hook is installed for any harness"
exit 0
