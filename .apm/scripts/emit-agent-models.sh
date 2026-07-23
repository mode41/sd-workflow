#!/usr/bin/env bash
# emit-agent-models.sh — the PER-AGENT MODEL STAMPER.
#
# Writes each agent's configured model into the *deployed* agent file of every PRESENT harness that
# has an emitter. Runs on EVERY install/update, which is the point: APM tracks deployed agent files
# in apm.lock and overwrites them on `apm update`, so a model stamped last time is gone by the time
# this runs. Re-stamping from .spec-workflow/config.json repairs that automatically.
#
# Model values are written VERBATIM — the package never translates them, so any model the harness
# understands works (including local ones like ollama/qwen2.5-coder). An empty value means "leave
# this agent's frontmatter alone" (it inherits the harness default).
#
# Usage: emit-agent-models.sh <ROOT> <PKG> <CONFIG>
#   ROOT   = consumer project root
#   PKG    = the deployed .apm dir (agents/ lives here — the list of agents to stamp)
#   CONFIG = path to .spec-workflow/config.json
set -uo pipefail
ROOT="$1"
PKG="$2"
CONFIG="$3"

SELF="$(cd "$(dirname "$0")" && pwd -P)"
# shellcheck source=/dev/null
. "$SELF/config-lib.sh"

log() { printf '  [models] %s\n' "$1"; }

# Set `model:` inside the frontmatter of <file>, idempotently: replace an existing model line,
# else insert right after the description line. Leaves the file alone if it has no frontmatter.
stamp_model() {   # <file> <value>
  local file="$1" value="$2" tmp="$1.tmp.$$"

  head -1 "$file" 2>/dev/null | grep -q '^---[[:space:]]*$' || {
    log "WARNING: $(basename "$file") has no YAML frontmatter — not stamping."
    return 0
  }
  # Already correct? Don't rewrite (keeps runs idempotent and diffs clean).
  if awk 'NR>1 && /^---[[:space:]]*$/{exit} NR>1' "$file" | grep -q "^model:[[:space:]]*${value}[[:space:]]*$"; then
    return 0
  fi

  awk -v val="$value" '
    NR == 1 { print; next }                      # opening ---
    !done && /^---[[:space:]]*$/ {               # closing --- : insert before it if not yet placed
      if (!placed) { print "model: " val; placed = 1 }
      done = 1; print; next
    }
    !done && /^model:/ {                          # replace an existing model line
      if (!placed) { print "model: " val; placed = 1 }
      next
    }
    !done && /^description:/ { print; if (!placed) { print "model: " val; placed = 1 } next }
    { print }
  ' "$file" > "$tmp" && [ -s "$tmp" ] || { rm -f "$tmp"; log "WARNING: failed to stamp $(basename "$file")"; return 0; }
  mv "$tmp" "$file"
  return 1   # 1 = "changed", for the caller's counter
}

# emit <harness-key> <agents-dir> <extension>
emit() {
  local harness="$1" dir="$2" ext="$3" src stem value file changed=0 skipped=0
  for src in "$PKG"/agents/*.agent.md; do
    [ -e "$src" ] || continue
    stem="$(basename "$src" .agent.md)"
    value="$(config_model_for "$stem" "$harness")"
    [ -n "$value" ] || { skipped=$((skipped + 1)); continue; }
    file="$dir/$stem$ext"
    [ -f "$file" ] || { log "WARNING: $harness agent $stem$ext not deployed — skipping."; continue; }
    stamp_model "$file" "$value" || changed=$((changed + 1))
  done
  if [ "$changed" -gt 0 ]; then
    log "$harness: stamped $changed agent file(s) from config.json"
  elif [ "$skipped" -gt 0 ]; then
    log "$harness: $skipped agent(s) have no model set — inheriting the harness default"
  else
    log "$harness: already up to date"
  fi
}

emit_unsupported() {
  log "$1 detected but has no model emitter yet — its agents inherit the harness default."
}

[ -f "$CONFIG" ] || { log "no config.json found; skipping model stamping"; exit 0; }
command -v jq >/dev/null 2>&1 || { log "jq unavailable; skipping model stamping"; exit 0; }

[ -d "$ROOT/.claude/agents" ]   && emit claude   "$ROOT/.claude/agents"   ".md"
[ -d "$ROOT/.opencode/agents" ] && emit opencode "$ROOT/.opencode/agents" ".md"
# Copilot's `model:` is a YAML *list* of UI display names, not a string — needs a list-shaped
# config value before we can stamp it safely.
[ -d "$ROOT/.github/agents" ]   && emit_unsupported "Copilot"
# Codex agents are .toml built by APM from name/description/body only — no frontmatter to stamp.
[ -d "$ROOT/.codex/agents" ]    && emit_unsupported "Codex"
exit 0
