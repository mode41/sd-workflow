#!/usr/bin/env bash
# SPEC close-out guard (finish-boundary hook + git pre-commit): once a spec's close-out writeup
# exists, block until its acceptance-criteria boxes are ticked or explicitly marked DESCOPED. Stays
# silent during requirements/design/mid-implementation (no "## Implementation" section yet).
#
# Agent-agnostic root resolution: honor an explicit SPEC_WORKFLOW_ROOT / a harness project-dir env
# (e.g. CLAUDE_PROJECT_DIR), else the git top-level, else PWD.
dir="${SPEC_WORKFLOW_ROOT:-${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")}}"
branch=$(git -C "$dir" branch --show-current 2>/dev/null) || exit 0
[[ "$branch" =~ (SPEC-[0-9]+) ]] || exit 0
id="${BASH_REMATCH[1]}"
file=$(ls "$dir"/specs/"${id}"-*.md 2>/dev/null | head -1)
[[ -n "$file" && -f "$file" ]] || exit 0
# Deprecated (abandoned) spec: its feature no longer exists, so unticked ACs are expected — skip.
grep -m1 '^\*\*Status:\*\*' "$file" | grep -qi 'Deprecated' && exit 0
# Only at close-out: an "## Implementation…" section has been written.
grep -qE '^## Implementation' "$file" || exit 0
# Fire only if an unchecked AC remains that is NOT marked descoped.
if grep -E '^- \[ \] AC-' "$file" | grep -qvi 'descoped'; then
  echo "Close-out check for ${id} (${file}): unchecked AC boxes remain. Before finishing, tick each satisfied AC as [x], mark any intentionally-skipped one DESCOPED (leave it [ ]), and update the specs/INDEX.md status." >&2
  exit 2
fi
exit 0
