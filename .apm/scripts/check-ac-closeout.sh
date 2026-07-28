#!/usr/bin/env bash
# SPEC close-out guard (git pre-commit): once a spec's audit trail exists, block until (1) its
# acceptance-criteria boxes are ticked or explicitly marked DESCOPED, and (2) the trail actually cites
# every ticked AC. Stays silent during requirements/design/mid-implementation (no audit-trail.md yet).
#
# WHICH spec does it judge? Never the branch name — nothing in this workflow reads it, so whatever
# convention your project requires (SPEC-4-glossary, userstory-1928, a ticket key, main itself)
# behaves identically. A change selects the specs it TOUCHES: any file under a spec folder, plus any
# spec whose specs/INDEX.md row changed. Keep the selector in sync with check-status-sync.sh.
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
git -C "$dir" rev-parse --git-dir >/dev/null 2>&1 || exit 0

# Everything touched since HEAD under a pathspec. Untracked files are included deliberately: an agent
# writes audit-trail.md as a brand-new file and often stages only part of the spec folder, and
# `git diff HEAD` alone would not see it. Same helper as check-open-questions.sh.
touched() { git -C "$dir" diff --name-only HEAD -- "$@" 2>/dev/null
            git -C "$dir" ls-files --others --exclude-standard -- "$@" 2>/dev/null; }

# THE SELECTOR. Any file inside a spec folder counts (spec.md, tech-design.md, audit-trail.md,
# attachments) — this check validates an invariant over the whole folder, so a touch anywhere in it is
# reason to re-verify. A changed specs/INDEX.md row selects its spec too, so status bookkeeping done
# in the INDEX alone is still judged. Keep the canonical-path regex in sync with the other checks.
ids=$( { touched specs | grep -oE '^specs/(backlog/)?SPEC-[0-9]+-'
         git -C "$dir" diff -U0 HEAD -- specs/INDEX.md 2>/dev/null | grep -oE '^[+-]\| *SPEC-[0-9]+ '
       } | grep -oE 'SPEC-[0-9]+' | sort -u)
[[ -n "$ids" ]] || exit 0

bad=0
note() { echo "Close-out check for ${id} ($1): $2" >&2; bad=1; }

while IFS= read -r id; do
  [[ -n "$id" ]] || continue
  # A spec is a FOLDER: specs/SPEC-N-name/ with a canonical spec.md (+ tech-design.md, audit-trail.md,
  # attachments). Resolve the folder main-tree first, then backlog (preserves "main before backlog"),
  # then its spec.md. The trailing '-' in the glob stops SPEC-2 from matching SPEC-20. Keep this in
  # sync with check-status-sync.sh's resolver and check-spec-version.sh's canonical-path regex — a
  # backlogged spec is status- and version-gated, so it must be AC-gated too.
  specdir=$(ls -d "$dir"/specs/"${id}"-*/ 2>/dev/null | head -1)
  [[ -n "$specdir" ]] || specdir=$(ls -d "$dir"/specs/backlog/"${id}"-*/ 2>/dev/null | head -1)
  file="${specdir}spec.md"
  [[ -n "$specdir" && -f "$file" ]] || continue
  # Deprecated (abandoned) spec: its feature no longer exists, so unticked ACs are expected — skip.
  grep -m1 '^\*\*Status:\*\*' "$file" | grep -qi 'Deprecated' && continue
  # Only at close-out: audit-trail.md (the verification trail) has been written.
  trail="${specdir}audit-trail.md"
  [[ -f "$trail" ]] || continue

  # (1) Fire only if an unchecked AC remains that is NOT marked descoped.
  if grep -E '^- \[ \] AC-' "$file" | grep -qvi 'descoped'; then
    note "$file" "unchecked AC boxes remain. Before committing, tick each satisfied AC as [x], mark any intentionally-skipped one DESCOPED (leave it [ ]), and update the specs/INDEX.md status."
    continue
  fi

  # (2) Every ticked AC must be cited in the trail. spec.md holds the criteria; the mapping from a
  # criterion to the test that PROVES it exists nowhere else, and that mapping is the whole reason the
  # trail is worth keeping — a ticked box with no evidence is an unfalsifiable claim. DESCOPED ACs are
  # unticked, so they never reach this gate (their reason already lives in spec.md).
  # The '([^0-9]|$)' guard stops a mention of AC-10 from satisfying AC-1.
  missing=()
  while read -r ac; do
    [[ -n "$ac" ]] || continue
    grep -qE "${ac}([^0-9]|\$)" "$trail" || missing+=("$ac")
  done < <(grep -oE '^- \[[xX]\] AC-[0-9]+' "$file" | grep -oE 'AC-[0-9]+' | sort -u)
  if (( ${#missing[@]} )); then
    note "${trail#"$dir/"}" "${missing[*]} ticked in spec.md but never cited in the audit trail. Record what closed each one — the test, fixture or commit that proves it — then commit again."
  fi
done < <(printf '%s\n' "$ids")

exit $(( bad ? 2 : 0 ))
