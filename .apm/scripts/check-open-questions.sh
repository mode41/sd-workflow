#!/usr/bin/env bash
# SPEC open-questions guard (git pre-commit): a question a command could not
# ask you — recorded as a '### Q-N' block under '## Open Questions' with an empty '**Answer:**' —
# holds the spec at the phase that raised it. This is what makes unattended runs safe: a command in
# `interaction.mode: "file"` proceeds on a flagged assumption so nothing hangs, but the NEXT phase
# cannot start until a human confirms or overrides it.
#
# It is a STATUS CEILING — the mirror image of check-status-sync.sh's reality floors:
#
#   unanswered question in ...      | status may not exceed
#   specs/**/spec.md                | In Planning   (so /technical-design cannot advance it)
#   specs/**/tech-design.md         | Planned       (so implementation cannot start)
#   docs/PRD.md                     | In Planning, for every spec (project-level questions —
#                                   |   "is a backend needed?" — invalidate any design beneath them)
#
# This is a state invariant, not a transition rule: while the question is open the spec does not
# BELONG at that status, so any commit touching it is blocked. Resolve it by filling in the
# '**Answer:**' line (write your choice, or 'confirmed' to accept the assumption), or by deleting the
# question if it no longer matters. Answered questions stay in the file as the decision record.
#
# Validate-only (it never edits). Runs on ANY branch — like check-spec-version.sh and unlike the two
# branch-gated checks — because questions are raised by /requirements and /technical-design, which run
# before a SPEC-N branch exists. It stays quiet by acting only on specs that actually changed vs HEAD.
# Deprecated specs are exempt (a tombstone keeps whatever it had).
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

status_of() { grep -m1 '^\*\*Status:\*\*' | grep -oE "$LEGAL" | head -1; }

# Print the ID of every UNANSWERED question in the file on stdin (empty output = none open).
# Walks the '## Open Questions' section only; each '### Q-N' opens a block, and a block counts as
# unanswered when its '**Answer:**' line is blank OR missing entirely. Prose-only sections (no Q-N
# heading) yield nothing, so a hand-written free-text Open Questions section never blocks.
# HTML comments are stripped first: the shipped templates carry a commented-out example question, and
# a commented question must never gate a spec.
unanswered() {
  awk '
    function close_block() { if (id != "" && !answered) print id; id=""; answered=0 }
    {
      line = $0
      if (c) {                                   # inside a multi-line <!-- ... -->
        p = index(line, "-->")
        if (p == 0) next
        line = substr(line, p + 3); c = 0
      }
      while ((p = index(line, "<!--")) > 0) {
        rest = substr(line, p + 4)
        q = index(rest, "-->")
        if (q == 0) { line = substr(line, 1, p - 1); c = 1; break }
        line = substr(line, 1, p - 1) substr(rest, q + 3)
      }
      $0 = line
    }
    /^## Open Questions/ { close_block(); s=1; next }
    /^## / {
      if (s) { close_block(); s=0 }
      next
    }
    !s        { next }
    /^### Q-/ { close_block(); id=$2; sub(/:$/, "", id); next }
    /^\*\*Answer:\*\*/ {
      a=$0; sub(/^\*\*Answer:\*\*/, "", a); gsub(/[ \t]/, "", a)
      if (a != "") answered=1
      next
    }
    END { close_block() }
  '
}

bad=0
note() { echo "Open-questions check: $1" >&2; bad=1; }
fmt()  { printf '%s' "$1" | tr '\n' ' ' | sed 's/ $//'; }   # "Q-1 Q-3"

# Everything touched since HEAD under a pathspec. Untracked files are included deliberately: an agent
# often writes tech-design.md as a brand-new file and stages only part of the spec folder, and
# `git diff HEAD` alone would not see it.
touched() { git -C "$dir" diff --name-only HEAD -- "$@" 2>/dev/null
            git -C "$dir" ls-files --others --exclude-standard -- "$@" 2>/dev/null; }

# Project-level questions gate every spec, so resolve them once up front.
prd_open=""
[[ -f "$dir/docs/PRD.md" ]] && prd_open=$(unanswered < "$dir/docs/PRD.md")

# Same canonical-path regex and folder grouping as check-spec-version.sh — keep them in sync.
folders=$(touched specs \
          | grep -E '^specs/(backlog/)?SPEC-[0-9]+-[^/]+/(spec|tech-design)\.md$' \
          | sed 's#/[^/]*$##' | sort -u)

# The project-level ceiling applies to EVERY spec, so when the PRD itself just gained (or still has)
# open questions, widen the scope to all of them — that is the moment to say so. Otherwise stay
# quiet and judge only the specs this change actually touches.
if [[ -n "$prd_open" ]] && touched docs/PRD.md | grep -q .; then
  folders=$( { printf '%s\n' "$folders"
               (cd "$dir" && ls -d specs/SPEC-*-*/ specs/backlog/SPEC-*-*/ 2>/dev/null | sed 's#/$##')
             } | grep -v '^[[:space:]]*$' | sort -u)
fi
[[ -n "$folders" ]] || exit 0

while IFS= read -r folder; do
  [[ -n "$folder" ]] || continue
  specmd="$folder/spec.md"
  [[ -f "$dir/$specmd" ]] || continue                       # spec.md deleted -> nothing to gate
  label="${folder##*/}"
  status=$(status_of < "$dir/$specmd")
  r=$(rank "$status")
  (( r == 9 )) && continue                                  # Deprecated: frozen tombstone

  # --- spec.md questions: ceiling In Planning ---
  open=$(unanswered < "$dir/$specmd")
  if [[ -n "$open" && $r -gt 0 ]]; then
    note "${specmd} is '${status}' but has unanswered question(s): $(fmt "$open"). A spec cannot advance past 'In Planning' while its contract is undecided — fill in the '**Answer:**' line for each (your choice, or 'confirmed' to accept the '**Assumed:**' value), or roll ${label} and its specs/INDEX.md row back to 'In Planning'."
  fi

  # --- tech-design.md questions: ceiling Planned ---
  td="$folder/tech-design.md"
  if [[ -f "$dir/$td" ]]; then
    open=$(unanswered < "$dir/$td")
    if [[ -n "$open" && $r -gt 1 ]]; then
      note "${td} has unanswered question(s): $(fmt "$open") but ${label} is '${status}'. Implementation cannot start on an undecided design — answer each one, or roll ${label} and its specs/INDEX.md row back to 'Planned'."
    fi
  fi

  # --- PRD questions: ceiling In Planning, for every spec ---
  if [[ -n "$prd_open" && $r -gt 0 ]]; then
    note "docs/PRD.md has unanswered project-level question(s): $(fmt "$prd_open"), so no spec may be past 'In Planning' — but ${label} is '${status}'. Answer them in docs/PRD.md (or delete the ones that no longer matter)."
  fi
done < <(printf '%s\n' "$folders")

exit $(( bad ? 2 : 0 ))
