#!/usr/bin/env bash
# emit-harness-hooks.sh — the PER-AGENT HOOK COMPILER.
#
# Reads the one neutral finish-hook.spec.json and writes each PRESENT harness's *native*
# finish-boundary hook (idempotent merge — never blind-overwrites a harness's other settings).
# Where a harness has no finish-hook concept (or we have no emitter for it yet), it is skipped —
# the git pre-commit floor covers it. This is invoked by init-and-wire.sh.
#
# Usage: emit-harness-hooks.sh <ROOT> <SPEC_DIR>
#   ROOT     = consumer project root
#   SPEC_DIR = the deployed .spec-workflow dir (holds hooks/ and finish-hook.spec.json)
set -euo pipefail
ROOT="$1"
SPEC_DIR="$2"
SPEC="$SPEC_DIR/finish-hook.spec.json"
HOOKS_REL=".spec-workflow/hooks"
SENTINEL="spec-workflow-finish-hook"   # marker so we can detect our own entries idempotently

SELF="$(cd "$(dirname "$0")" && pwd -P)"
# shellcheck source=/dev/null
. "$SELF/config-lib.sh"   # for notice_add — contributes to the installer's shared MANUAL-STEPS sink

log() { printf '  [hooks] %s\n' "$1"; }

# jq is a hard requirement of the installer (the project config is JSON), so the old jq-less
# fallback is gone. Guard here too — this script is also runnable standalone, and a half-merged
# settings.json is worse than a loud failure.
command -v jq >/dev/null 2>&1 || { log "ERROR: jq is required to merge harness hooks safely; install it and re-run."; notice_add "jq is missing — per-harness finish hooks were not merged. Install jq and re-run the installer."; exit 1; }

# --- Claude Code: merge a Stop hook into .claude/settings.json ---
emit_claude() {
  local settings="$ROOT/.claude/settings.json"
  local cmds=(
    "bash \"\$CLAUDE_PROJECT_DIR/$HOOKS_REL/check-ac-closeout.sh\"  # $SENTINEL"
    "bash \"\$CLAUDE_PROJECT_DIR/$HOOKS_REL/check-status-sync.sh\"  # $SENTINEL"
    "bash \"\$CLAUDE_PROJECT_DIR/$HOOKS_REL/check-spec-version.sh\" # $SENTINEL"
  )
  local hookobjs; hookobjs=$(printf '%s\n' "${cmds[@]}" | jq -R '{type:"command",command:.}' | jq -s '.')
  local base='{}'
  [ -f "$settings" ] && base=$(cat "$settings")
  # Idempotent: drop any existing entries carrying our sentinel, then add ours back.
  printf '%s' "$base" | jq \
    --argjson add "$hookobjs" '
    .hooks.Stop = ((.hooks.Stop // [])
      | map(.hooks |= (map(select((.command // "") | contains("'"$SENTINEL"'") | not))))
      | map(select((.hooks // []) | length > 0)))
    + [ { hooks: $add } ]
  ' > "$settings.tmp" && mv "$settings.tmp" "$settings"
  log "Claude Stop hook merged into .claude/settings.json"
}

# --- Emitters for other harnesses can be added here (Cursor, etc.). Until then those harnesses
#     rely on the git pre-commit floor; we log that honestly rather than pretend parity. ---
emit_unsupported() {
  log "$1 detected but has no finish-hook emitter yet — git pre-commit floor covers it."
  notice_add "$1 detected, but there is no native finish-hook emitter for it — the git pre-commit floor still enforces the checks at commit time, but no session-end hook was installed."
}

[ -f "$SPEC" ] || { log "no finish-hook.spec.json found; skipping per-harness hooks"; exit 0; }

[ -d "$ROOT/.claude" ]   && emit_claude
[ -d "$ROOT/.cursor" ]   && emit_unsupported "Cursor"
# opencode has no finish/session-end hook today — intentionally nothing to emit.
exit 0
