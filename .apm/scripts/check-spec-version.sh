#!/usr/bin/env bash
# SPEC spec-version guard (finish-boundary hook + git pre-commit): once a spec is Planned-or-later,
# any *substantive* change to it must bump the '**Version:**' (vN) and add a '## Changelog' row so
# the spec's evolution stays traceable inline. Deprecating a spec (status -> Deprecated) likewise
# requires a bump + changelog row. NON-substantive edits never trigger it: the Status / Last Updated
# / Version header lines, the whole '## Changelog' and '## Implementation & Verification' sections,
# and acceptance-criterion checkbox ticking ([ ] <-> [x]) are all exempt — so the normal
# requirements -> design -> implement -> verify -> close-out journey runs untouched.
#
# Validate-only (it never edits): the stderr message tells the agent to bump + add a changelog row,
# citing the driving SPEC-N. Silent (exit 0) when: not a git repo, no spec changed vs HEAD, the spec
# is new (still drafting toward v1), it was still 'In Planning' at HEAD, or it is already
# 'Deprecated' at HEAD (a frozen tombstone). Runs on any branch — unlike the other two hooks it is
# not branch-gated, because cross-spec edits are the whole point; it stays quiet by only acting on
# specs that actually changed.
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
normalize() {
  awk '
    /^## Changelog/       { skip=1; next }   # drop the whole Changelog section ...
    /^## Implementation/  { skip=1; next }   # ... and the close-out evidence section ...
    /^## /                { skip=0 }         # ... until the next top-level heading.
    skip                  { next }
    /^\*\*Status:\*\*/       { next }
    /^\*\*Last Updated:\*\*/ { next }
    /^\*\*Version:\*\*/      { next }
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
head_content=""; work=""; f=""
note() { echo "Spec-version check: $1" >&2; bad=1; }

# Require the working spec to have bumped its version AND grown its changelog vs HEAD.
enforce() {
  local reason="$1" hv wv hn wn hr wr
  hv=$(printf '%s\n' "$head_content" | version_of); wv=$(version_of < "$work")
  hr=$(printf '%s\n' "$head_content" | changelog_rows); wr=$(changelog_rows < "$work")
  if [[ -z "$hv" ]]; then
    [[ -n "$wv" ]] || { note "${f}: ${reason} but it has no '**Version:**' header — add '**Version:** v1' (or higher) and a '## Changelog' row."; return; }
  else
    hn=${hv#v}; wn=${wv#v}
    if [[ -z "$wv" || ! "$wn" =~ ^[0-9]+$ || "$wn" -le "$hn" ]]; then
      note "${f}: ${reason} but '**Version:**' is still ${hv} — bump it (e.g. v$((hn+1))) and add a '## Changelog' row citing the driving SPEC-N."
      return
    fi
  fi
  (( wr > hr )) || note "${f}: ${reason} but its '## Changelog' gained no new row — add a row for the new version (cite the driving SPEC-N, or 'self')."
}

while IFS= read -r f; do
  [[ -n "$f" ]] || continue
  work="$dir/$f"
  [[ -f "$work" ]] || continue                                  # deleted in worktree -> ignore
  head_content=$(git -C "$dir" show "HEAD:$f" 2>/dev/null) || continue   # new file -> drafting, skip
  head_status=$(printf '%s\n' "$head_content" | status_of)
  work_status=$(status_of < "$work")

  [[ "$head_status" == "Deprecated" ]] && continue              # frozen tombstone

  if [[ "$work_status" == "Deprecated" ]]; then                 # deprecation must be recorded
    enforce "is being deprecated"
    continue
  fi

  (( $(rank "$head_status") >= 1 )) || continue                 # only enforce once Planned+

  if [[ "$(printf '%s\n' "$head_content" | normalize)" != "$(normalize < "$work")" ]]; then
    enforce "changed substantively"
  fi
done < <(git -C "$dir" diff --name-only HEAD -- specs 2>/dev/null | grep -E '^specs/(backlog/)?SPEC-[0-9]+-.*\.md$')

exit $(( bad ? 2 : 0 ))
