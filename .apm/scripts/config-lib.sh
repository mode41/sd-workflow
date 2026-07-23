#!/usr/bin/env bash
# config-lib.sh — shared accessors for .spec-workflow/config.json.
#
# Sourced by init-and-wire.sh and emit-agent-models.sh; safe for any future config consumer.
# Every write goes through jq into a temp file and is then moved into place, so the config is
# never left half-written and stays valid JSON with consistent formatting.
#
# Callers must set CONFIG to the config.json path before calling anything but config_require_jq.
#
# NOTE: no associative arrays / bash-4-only syntax — this has to run on macOS's bash 3.2.

# Highest schemaVersion this package understands. Bump only on a breaking format change.
CONFIG_SCHEMA_VERSION=1

cfg_log() { printf '  [config] %s\n' "$1"; }

# --- jq preflight -----------------------------------------------------------
config_require_jq() {
  command -v jq >/dev/null 2>&1 && return 0
  echo "spec-driven-workflow: 'jq' is required but was not found on PATH." >&2
  echo "  The project config (.spec-workflow/config.json) is JSON; jq reads and writes it." >&2
  echo "  Install it (e.g. 'apt install jq', 'brew install jq', 'dnf install jq') and re-run." >&2
  return 1
}

# --- validation -------------------------------------------------------------
# config_validate <file>
# Parse check + schemaVersion check + structural checks. Prints the offending path on failure.
# Returns: 0 ok · 1 invalid (abort) · 2 schemaVersion too new (skip stamping, don't abort)
config_validate() {
  local f="$1"

  if ! jq -e . "$f" >/dev/null 2>&1; then
    cfg_log "ERROR: $f is not valid JSON — fix it (or delete it to re-seed) and re-run."
    return 1
  fi

  local sv
  sv=$(jq -r '.schemaVersion // empty' "$f")
  if [ -z "$sv" ]; then
    cfg_log "ERROR: $f has no 'schemaVersion'."
    return 1
  fi
  case "$sv" in
    ''|*[!0-9]*) cfg_log "ERROR: $f has a non-integer 'schemaVersion' ($sv)."; return 1;;
  esac

  # Every model value must be a string or null — catches e.g. a list or a nested object.
  local bad
  bad=$(jq -r '
    [ (.agents // {}), (.retiredAgents // {}) ]
    | to_entries[] as $section
    | $section.value | to_entries[] as $agent
    | ($agent.value.model // {}) | to_entries[]
    | select((.value | type) as $t | $t != "string" and $t != "null")
    | "\($agent.key).model.\(.key)"
  ' "$f" 2>/dev/null | head -3)
  if [ -n "$bad" ]; then
    cfg_log "ERROR: $f has non-string model value(s): $(echo "$bad" | tr '\n' ' ')"
    cfg_log "       Model values are written verbatim into agent frontmatter; use a string or null."
    return 1
  fi

  if [ "$sv" -gt "$CONFIG_SCHEMA_VERSION" ]; then
    cfg_log "config schema $sv is newer than this package understands ($CONFIG_SCHEMA_VERSION) — skipping model stamping."
    return 2
  fi
  return 0
}

# --- reads ------------------------------------------------------------------
# config_model_for <agent> <harness> — resolves model.<harness>, falling back to model.default.
# Empty output means "leave this agent's frontmatter alone".
config_model_for() {
  jq -r --arg a "$1" --arg h "$2" '
    (.agents[$a].model // {}) as $m
    | ($m[$h] // $m.default // "")
    | if . == null then "" else . end
  ' "$CONFIG" 2>/dev/null
}

# config_agent_known <agent> — true if the agent has an entry (even an empty one).
config_agent_known() {
  jq -e --arg a "$1" 'has("agents") and (.agents | has($a))' "$CONFIG" >/dev/null 2>&1
}

# config_agent_names — one per line.
config_agent_names() { jq -r '(.agents // {}) | keys[]' "$CONFIG" 2>/dev/null; }

# --- writes -----------------------------------------------------------------
# All writes funnel through here: jq to a temp file, then move. A jq failure leaves the
# original untouched rather than truncating it.
cfg_write() {
  local tmp="$CONFIG.tmp.$$"
  if jq "$@" "$CONFIG" > "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
    mv "$tmp" "$CONFIG"
    return 0
  fi
  rm -f "$tmp"
  cfg_log "ERROR: failed to update $CONFIG (left unchanged)."
  return 1
}

# config_set_model <agent> <harness|default> <value>   ("" clears the key)
config_set_model() {
  if [ -z "$3" ]; then
    cfg_write --arg a "$1" --arg h "$2" 'del(.agents[$a].model[$h])'
  else
    cfg_write --arg a "$1" --arg h "$2" --arg v "$3" \
      '.agents[$a].model = ((.agents[$a].model // {}) + {($h): $v})'
  fi
}

# config_add_agent <agent> — adds an empty entry, restoring a retired one if present.
config_add_agent() {
  cfg_write --arg a "$1" '
    .agents = ((.agents // {}) + {($a): ((.retiredAgents // {})[$a] // {"model": {}})})
    | .retiredAgents = ((.retiredAgents // {}) | del(.[$a]))
  '
}

# config_retire_agent <agent> — moves the entry to retiredAgents; never deletes.
config_retire_agent() {
  cfg_write --arg a "$1" '
    .retiredAgents = ((.retiredAgents // {}) + {($a): .agents[$a]})
    | .agents = (.agents | del(.[$a]))
  '
}

# config_was_retired <agent> — true if the agent has a stored entry under retiredAgents.
config_was_retired() {
  jq -e --arg a "$1" '(.retiredAgents // {}) | has($a)' "$CONFIG" >/dev/null 2>&1
}
