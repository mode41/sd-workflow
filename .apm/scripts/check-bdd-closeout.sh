#!/usr/bin/env bash
# SPEC BDD-scenario close-out guard (git pre-commit): once a spec's audit trail exists, block until
# every BDD scenario declared in spec.md is cited in audit-trail.md. spec.md holds the Given/When/Then;
# the mapping from a scenario to the test that WALKS it exists nowhere else, and that mapping is the
# whole reason the trail is worth keeping. A scenario whose heading is marked DESCOPED won't ship, so
# it owes the trail nothing. Stays silent during requirements/design/mid-implementation (no
# audit-trail.md yet). Companion to check-ac-closeout.sh — same selector, same boundary, same shape.
#
# WHICH spec does it judge? Never the branch name — a change selects the specs it TOUCHES: any file
# under a spec folder, plus any spec whose specs/INDEX.md row changed. Keep the selector in sync with
# check-ac-closeout.sh and check-status-sync.sh.
#
# STALE SESSION-END HOOK SAFETY NET. See check-ac-closeout.sh for the full rationale: when a stale
# harness Stop hook re-invokes us after a previous block, the harness passes stop_hook_active:true on
# stdin — honor it, so a condition we cannot repair can never become an unbounded block loop. Skipped
# under the pre-commit, which sets SPEC_WORKFLOW_ROOT and never feeds us JSON on stdin.
if [ -z "${SPEC_WORKFLOW_ROOT:-}" ] && [ ! -t 0 ]; then
  read -r -t 1 -d '' _hookjson || true
  [[ "$_hookjson" =~ \"stop_hook_active\"[[:space:]]*:[[:space:]]*true ]] && exit 0
fi
#
# Agent-agnostic root resolution: honor an explicit SPEC_WORKFLOW_ROOT / a harness project-dir env
# (e.g. CLAUDE_PROJECT_DIR), else the git top-level, else PWD.
dir="${SPEC_WORKFLOW_ROOT:-${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")}}"
git -C "$dir" rev-parse --git-dir >/dev/null 2>&1 || exit 0

# Everything touched since HEAD under a pathspec, untracked included (audit-trail.md is often a
# brand-new, partly-staged file). Same helper as check-ac-closeout.sh.
touched() { git -C "$dir" diff --name-only HEAD -- "$@" 2>/dev/null
            git -C "$dir" ls-files --others --exclude-standard -- "$@" 2>/dev/null; }

# THE SELECTOR. Any file inside a spec folder counts; a changed specs/INDEX.md row selects its spec
# too. Keep the canonical-path regex in sync with the other checks.
ids=$( { touched specs | grep -oE '^specs/(backlog/)?SPEC-[0-9]+-'
         git -C "$dir" diff -U0 HEAD -- specs/INDEX.md 2>/dev/null | grep -oE '^[+-]\| *SPEC-[0-9]+ '
       } | grep -oE 'SPEC-[0-9]+' | sort -u)
[[ -n "$ids" ]] || exit 0

bad=0
note() { echo "BDD close-out check for ${id} ($1): $2" >&2; bad=1; }

while IFS= read -r id; do
  [[ -n "$id" ]] || continue
  # A spec is a FOLDER: resolve main-tree first, then backlog (preserves "main before backlog").
  # The trailing '-' in the glob stops SPEC-2 from matching SPEC-20. Keep in sync with the resolvers
  # in check-ac-closeout.sh / check-status-sync.sh.
  specdir=$(ls -d "$dir"/specs/"${id}"-*/ 2>/dev/null | head -1)
  [[ -n "$specdir" ]] || specdir=$(ls -d "$dir"/specs/backlog/"${id}"-*/ 2>/dev/null | head -1)
  file="${specdir}spec.md"
  [[ -n "$specdir" && -f "$file" ]] || continue
  # Deprecated (abandoned) spec: its feature no longer exists, so uncited scenarios are expected — skip.
  grep -m1 '^\*\*Status:\*\*' "$file" | grep -qi 'Deprecated' && continue
  # Only at close-out: audit-trail.md (the verification trail) has been written.
  trail="${specdir}audit-trail.md"
  [[ -f "$trail" ]] || continue

  # Every non-DESCOPED BDD-N heading declared in spec.md must be cited in the trail. Scenarios are
  # multi-line Given/When/Then blocks, so the unit of declaration is the '### BDD-N:' heading, not a
  # checkbox. A DESCOPED marker in the heading exempts it (mirrors a DESCOPED AC). The
  # '([^0-9]|$)' guard stops a mention of BDD-10 from satisfying BDD-1.
  missing=()
  while read -r bdd; do
    [[ -n "$bdd" ]] || continue
    grep -qE "${bdd}([^0-9]|\$)" "$trail" || missing+=("$bdd")
  done < <(grep -iE '^#+ BDD-[0-9]+' "$file" | grep -vi 'descoped' | grep -oE 'BDD-[0-9]+' | sort -u)
  if (( ${#missing[@]} )); then
    note "${trail#"$dir/"}" "${missing[*]} declared in spec.md but never cited in the audit trail. Add a BDD-evidence row naming the test that walks each scenario's Given/When/Then, then commit again."
  fi
done < <(printf '%s\n' "$ids")

exit $(( bad ? 2 : 0 ))
