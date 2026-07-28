#!/usr/bin/env bash
# SPEC spec-version guard (git pre-commit): once a spec is Planned-or-later,
# any *substantive* change to its CONTRACT (spec.md) or its DESIGN (tech-design.md) must bump the
# spec's '**Version:**' (vN) and add a '## Changelog' row — both of which live in spec.md — so the
# spec's evolution stays traceable. Deprecating a spec (status -> Deprecated) likewise requires a
# bump + changelog row. A spec is a FOLDER (specs/SPEC-N-name/): spec.md + tech-design.md gate;
# audit-trail.md (the verification trail) and any attachments (mockups/, source/, …) are NOT gated.
# NON-substantive edits never trigger it: the Status / Last Updated / Version / Designed header lines,
# the whole '## Changelog' and '## Open Questions' sections, and acceptance-criterion checkbox ticking
# ([ ] <-> [x]) are all exempt — so the normal requirements -> design -> implement -> verify ->
# close-out journey runs untouched. (Raising or answering a question is bookkeeping; whatever the
# answer then CHANGES in the contract or design is substantive and still demands a bump.) A commit touching both spec.md and tech-design.md needs only ONE bump (grouped per folder).
#
# Validate-only (it never edits): the stderr message tells the agent to bump spec.md + add a changelog
# row, citing the driving SPEC-N. Silent (exit 0) when: not a git repo, no gated doc changed vs HEAD,
# the spec is new (spec.md absent at HEAD — still drafting toward v1), it was still 'In Planning' at
# HEAD, or it is already 'Deprecated' at HEAD (a frozen tombstone). Runs on any branch — unlike the
# other two hooks it is not branch-gated, because cross-spec edits are the whole point; it stays quiet
# by only acting on specs that actually changed.
#
# Stale session-end hook safety net (see check-ac-closeout.sh).
if [ -z "${SPEC_WORKFLOW_ROOT:-}" ] && [ ! -t 0 ]; then
  read -r -t 1 -d '' _hookjson || true
  [[ "$_hookjson" =~ \"stop_hook_active\"[[:space:]]*:[[:space:]]*true ]] && exit 0
fi
#
# Agent-agnostic root resolution (see check-ac-closeout.sh).
dir="${SPEC_WORKFLOW_ROOT:-${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")}}"
git -C "$dir" rev-parse --git-dir >/dev/null 2>&1 || exit 0

LEGAL='In Planning|In Progress|In Review|Validated|Planned|Deprecated'
rank() { case "$1" in
  "In Planning") echo 0;; "Planned") echo 1;; "In Progress") echo 2;;
  "In Review") echo 3;; "Validated") echo 4;; "Deprecated") echo 9;; *) echo -1;; esac; }

status_of()  { grep -m1 '^\*\*Status:\*\*'  | grep -oE "$LEGAL" | head -1; }
version_of() { grep -m1 '^\*\*Version:\*\*' | grep -oE 'v[0-9]+' | head -1; }

# Strip the exempt (non-substantive) parts so only meaningful spec content remains for comparison.
# Applied to both spec.md and tech-design.md; rules that don't match one file are simply inert.
normalize() {
  awk '
    /^## Changelog/       { skip=1; next }   # drop the whole Changelog section (spec.md) ...
    /^## Open Questions/  { skip=1; next }   # ... and the Q&A ledger (both files) ...
    /^## /                { skip=0 }         # ... until the next top-level heading.
    skip                  { next }
    /^\*\*Status:\*\*/       { next }
    /^\*\*Last Updated:\*\*/ { next }
    /^\*\*Version:\*\*/      { next }
    /^\*\*Designed:\*\*/     { next }         # tech-design.md date stamp — re-stamping is not a change
    { gsub(/^- \[[ xX]\] /, "- [ ] "); print }   # neutralize AC checkbox state (ticking != change)
  '
}
# Count changelog version rows ("| vN | ... |") inside the Changelog section.
changelog_rows() {
  awk '
    /^## Changelog/     { c=1; next }
    c && /^## /         { c=0 }
    c && /^\| *v[0-9]+ / { n++ }
    END { print n+0 }
  '
}

bad=0
head_spec_content=""; work_spec=""; specmd=""
note() { echo "Spec-version check: $1" >&2; bad=1; }

# Require spec.md to have bumped its '**Version:**' AND grown its '## Changelog' vs HEAD. The bump
# always lands in spec.md, even when the substantive change was in tech-design.md. Uses the globals
# head_spec_content (HEAD spec.md), work_spec (working spec.md path), specmd (repo-rel spec.md).
enforce() {
  local reason="$1" hv wv hn wn hr wr
  hv=$(printf '%s\n' "$head_spec_content" | version_of); wv=$(version_of < "$work_spec")
  hr=$(printf '%s\n' "$head_spec_content" | changelog_rows); wr=$(changelog_rows < "$work_spec")
  if [[ -z "$hv" ]]; then
    [[ -n "$wv" ]] || { note "${specmd}: ${reason} but spec.md has no '**Version:**' header — add '**Version:** v1' (or higher) and a '## Changelog' row."; return; }
  else
    hn=${hv#v}; wn=${wv#v}
    if [[ -z "$wv" || ! "$wn" =~ ^[0-9]+$ || "$wn" -le "$hn" ]]; then
      note "${specmd}: ${reason} but spec.md '**Version:**' is still ${hv} — bump it (e.g. v$((hn+1))) and add a '## Changelog' row citing the driving SPEC-N."
      return
    fi
  fi
  (( wr > hr )) || note "${specmd}: ${reason} but spec.md '## Changelog' gained no new row — add a row for the new version (cite the driving SPEC-N, or 'self')."
}

# Collect changed GATED docs (spec.md / tech-design.md) and group them by spec folder — the version +
# changelog live once per folder, in spec.md. Keep this canonical-path regex in sync with the folder
# resolver in check-ac-closeout.sh / check-status-sync.sh.
changed=$(git -C "$dir" diff --name-only HEAD -- specs 2>/dev/null \
          | grep -E '^specs/(backlog/)?SPEC-[0-9]+-[^/]+/(spec|tech-design)\.md$')
[[ -n "$changed" ]] || exit 0

while IFS= read -r folder; do
  [[ -n "$folder" ]] || continue
  specmd="$folder/spec.md"
  work_spec="$dir/$specmd"
  head_spec_content=$(git -C "$dir" show "HEAD:$specmd" 2>/dev/null) || continue  # spec.md new -> drafting, skip
  [[ -f "$work_spec" ]] || continue                                              # spec.md deleted -> ignore
  head_status=$(printf '%s\n' "$head_spec_content" | status_of)
  work_status=$(status_of < "$work_spec")

  [[ "$head_status" == "Deprecated" ]] && continue                               # frozen tombstone

  if [[ "$work_status" == "Deprecated" ]]; then                                  # deprecation must be recorded
    enforce "is being deprecated"
    continue
  fi

  (( $(rank "$head_status") >= 1 )) || continue                                  # only enforce once Planned+

  # Did any gated doc in this folder change substantively vs HEAD? (spec.md and/or tech-design.md)
  substantive=0
  for docrel in "$specmd" "$folder/tech-design.md"; do
    printf '%s\n' "$changed" | grep -qxF "$docrel" || continue                   # only docs that actually changed
    work="$dir/$docrel"
    if [[ ! -f "$work" ]]; then substantive=1; continue; fi                      # deleted gated doc -> substantive
    head_doc=$(git -C "$dir" show "HEAD:$docrel" 2>/dev/null || true)            # empty if newly added
    [[ "$(printf '%s\n' "$head_doc" | normalize)" == "$(normalize < "$work")" ]] || substantive=1
  done
  (( substantive )) && enforce "changed substantively"
done < <(printf '%s\n' "$changed" | sed 's#/[^/]*$##' | sort -u)

exit $(( bad ? 2 : 0 ))
