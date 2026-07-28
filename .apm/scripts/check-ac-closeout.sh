#!/usr/bin/env bash
# SPEC close-out guard (git pre-commit): once a spec's close-out writeup exists, block until its
# acceptance-criteria boxes are ticked or explicitly marked DESCOPED. Stays silent during
# requirements/design/mid-implementation (no implementation.md yet).
#
# STALE SESSION-END HOOK SAFETY NET. These checks are enforced at the git pre-commit boundary, and the
# installer no longer wires any harness session-end hook (a Claude Code `Stop` hook fires at the end of
# EVERY turn, not at a workflow step, so it blocked ordinary conversation). An older install may still
# have one wired. When such a hook re-invokes us after a previous block, the harness passes
# stop_hook_active:true on stdin — honor it, so a condition we cannot repair can never become an
# unbounded block loop. Skipped under the pre-commit, which sets SPEC_WORKFLOW_ROOT and never feeds us
# JSON on stdin; the `-t 0` test keeps an interactive invocation from waiting on a terminal.
if [ -z "${SPEC_WORKFLOW_ROOT:-}" ] && [ ! -t 0 ]; then
  read -r -t 1 -d '' _hookjson || true
  [[ "$_hookjson" =~ \"stop_hook_active\"[[:space:]]*:[[:space:]]*true ]] && exit 0
fi
#
# Agent-agnostic root resolution: honor an explicit SPEC_WORKFLOW_ROOT / a harness project-dir env
# (e.g. CLAUDE_PROJECT_DIR), else the git top-level, else PWD.
dir="${SPEC_WORKFLOW_ROOT:-${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")}}"
branch=$(git -C "$dir" branch --show-current 2>/dev/null) || exit 0
[[ "$branch" =~ (SPEC-[0-9]+) ]] || exit 0
id="${BASH_REMATCH[1]}"
# A spec is a FOLDER: specs/SPEC-N-name/ with a canonical spec.md (+ tech-design.md, implementation.md,
# attachments). Resolve the folder main-tree first, then backlog (preserves "main before backlog"),
# then its spec.md. The trailing '-' in the glob stops SPEC-2 from matching SPEC-20. Keep this in sync
# with check-status-sync.sh's resolver and check-spec-version.sh's canonical-path regex — a backlogged
# spec is status- and version-gated, so it must be AC-gated too.
specdir=$(ls -d "$dir"/specs/"${id}"-*/ 2>/dev/null | head -1)
[[ -n "$specdir" ]] || specdir=$(ls -d "$dir"/specs/backlog/"${id}"-*/ 2>/dev/null | head -1)
file="${specdir}spec.md"
[[ -n "$specdir" && -f "$file" ]] || exit 0
# Deprecated (abandoned) spec: its feature no longer exists, so unticked ACs are expected — skip.
grep -m1 '^\*\*Status:\*\*' "$file" | grep -qi 'Deprecated' && exit 0
# Only at close-out: implementation.md (the close-out evidence doc) has been written.
[[ -f "${specdir}implementation.md" ]] || exit 0
# Fire only if an unchecked AC remains that is NOT marked descoped.
if grep -E '^- \[ \] AC-' "$file" | grep -qvi 'descoped'; then
  echo "Close-out check for ${id} (${file}): unchecked AC boxes remain. Before committing, tick each satisfied AC as [x], mark any intentionally-skipped one DESCOPED (leave it [ ]), and update the specs/INDEX.md status." >&2
  exit 2
fi
exit 0
