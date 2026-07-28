#!/usr/bin/env bash
# SPEC status-sync guard (git pre-commit): keep each spec's status accurate and consistent. Blocks
# (exit 2) when the spec header status and the specs/INDEX.md row disagree, use an off-legend word, or
# lag reality (the audit trail implies a further state than the status claims).
# Validate-only: it never edits — the stderr message tells the agent to RESOLVE the drift (investigate
# the true state, then set the same status in BOTH places), because an agent can determine the correct
# value where a blind auto-sync would guess.
#
# WHICH spec does it judge? Never the branch name — nothing in this workflow reads it, so whatever
# convention your project requires (SPEC-4-glossary, userstory-1928, a ticket key, main itself)
# behaves identically. A change selects the specs it TOUCHES: any file under a spec folder, plus any
# spec whose specs/INDEX.md row changed. Keep the selector in sync with check-ac-closeout.sh.
# Silent (exit 0) when the change touches no spec, or when a selected spec has no file yet.
#
# Stale session-end hook safety net (see check-ac-closeout.sh).
if [ -z "${SPEC_WORKFLOW_ROOT:-}" ] && [ ! -t 0 ]; then
  read -r -t 1 -d '' _hookjson || true
  [[ "$_hookjson" =~ \"stop_hook_active\"[[:space:]]*:[[:space:]]*true ]] && exit 0
fi
#
# Agent-agnostic root resolution (see check-ac-closeout.sh).
dir="${SPEC_WORKFLOW_ROOT:-${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")}}"
index="$dir/specs/INDEX.md"
git -C "$dir" rev-parse --git-dir >/dev/null 2>&1 || exit 0
[[ -f "$index" ]] || exit 0

# Everything touched since HEAD under a pathspec, untracked files included (see check-ac-closeout.sh).
touched() { git -C "$dir" diff --name-only HEAD -- "$@" 2>/dev/null
            git -C "$dir" ls-files --others --exclude-standard -- "$@" 2>/dev/null; }

# THE SELECTOR — keep in sync with check-ac-closeout.sh. A changed specs/INDEX.md row selects its spec
# even when the spec folder itself is untouched: editing a status word in the INDEX alone is one of the
# two ways to introduce exactly the drift this check exists to catch.
ids=$( { touched specs | grep -oE '^specs/(backlog/)?SPEC-[0-9]+-'
         git -C "$dir" diff -U0 HEAD -- specs/INDEX.md 2>/dev/null | grep -oE '^[+-]\| *SPEC-[0-9]+ '
       } | grep -oE 'SPEC-[0-9]+' | sort -u)
[[ -n "$ids" ]] || exit 0

LEGAL='In Planning|In Progress|In Review|Validated|Planned|Deprecated'  # longest-first
bad=0
note() { echo "Status-sync check for ${id}: $1" >&2; bad=1; }
rank() { case "$1" in
  "In Planning") echo 0;; "Planned") echo 1;; "In Progress") echo 2;;
  "In Review") echo 3;; "Validated") echo 4;; "Deprecated") echo 9;; *) echo -1;; esac; }

while IFS= read -r id; do
  [[ -n "$id" ]] || continue
  # A spec is a FOLDER: specs/SPEC-N-name/spec.md (+ tech-design.md, audit-trail.md, attachments).
  # Resolve the folder main-tree first, then backlog (preserves "main before backlog"), then its
  # spec.md. The trailing '-' stops SPEC-2 matching SPEC-20. Keep in sync with check-spec-version.sh's
  # canonical-path regex.
  specdir=$(ls -d "$dir"/specs/"${id}"-*/ 2>/dev/null | head -1)
  [[ -n "$specdir" ]] || specdir=$(ls -d "$dir"/specs/backlog/"${id}"-*/ 2>/dev/null | head -1)
  file="${specdir}spec.md"
  [[ -n "$specdir" && -f "$file" ]] || continue
  # Display label: the file basename is always "spec.md", so show the folder name (SPEC-N-name).
  label="${specdir%/}"; label="${label##*/}"

  # --- Header status word ---
  hdr=$(grep -m1 '^\*\*Status:\*\*' "$file" | grep -oE "$LEGAL" | head -1)
  [[ -n "$hdr" ]] || { note "the '**Status:**' header in ${label} is missing or not one of: In Planning, Planned, In Progress, In Review, Validated. Set it to the legal token that matches the spec's true state, and set the same word in its specs/INDEX.md row."; continue; }

  # --- INDEX row status word (require exactly one row) ---
  rows=$(grep -cE "^\| ${id} \|" "$index")
  [[ "$rows" == "1" ]] || { note "expected exactly one specs/INDEX.md row for ${id}, found ${rows}. Fix the table (add the missing row or remove the duplicate) so ${id} appears once, with a status matching ${label}."; continue; }
  idx=$(grep -m1 -E "^\| ${id} \|" "$index" | awk -F'|' '{print $5}' | grep -oE "$LEGAL" | head -1)
  [[ -n "$idx" ]] || { note "the specs/INDEX.md row for ${id} has no legal status word. Set it to match the spec header ('${hdr}')."; continue; }

  # --- Header vs INDEX consistency ---
  [[ "$hdr" == "$idx" ]] || { note "status drift — ${label} header says '${hdr}' but specs/INDEX.md says '${idx}'. Resolve: determine the true state from the spec's sections, AC checkboxes and test evidence, then set the ONE correct status in BOTH places."; continue; }

  # --- Deprecated is a frozen terminal state: header==INDEX is enough, skip reality floors ---
  # (a deprecated spec keeps whatever sections it had; do not force it to In Review / Validated).
  [[ "$hdr" == "Deprecated" ]] && continue

  # --- Reality floors (strongest first) ---
  # ARTIFACT EVIDENCE ONLY. A floor fires when a file in the spec folder PROVES the work has moved past
  # the claimed status. The branch was never such evidence and is no longer read at all: cutting a
  # branch early — to plan on it, to park a draft, to answer an open question — is normal and says
  # nothing about whether implementation started. A branch-implies-'In Progress' floor also deadlocked
  # against check-open-questions.sh, which CAPS a spec with an unanswered Q-N at 'In Planning': on such
  # a branch no status could satisfy both, and the two checks handed the agent contradictory repair
  # instructions forever. Judging only artifacts keeps that trap structurally impossible.
  r=$(rank "$hdr")
  if [[ -f "${specdir}audit-trail.md" ]]; then
    # close-out complete = audit-trail.md exists AND no unchecked non-DESCOPED AC remains in spec.md
    if ! grep -E '^- \[ \] AC-' "$file" | grep -qvi 'descoped'; then
      [[ "$hdr" == "Validated" ]] || note "close-out is complete (audit-trail.md present, all ACs ticked/DESCOPED) but status is '${hdr}'. Set both ${label} and its INDEX row to 'Validated'."
    else
      (( r >= 3 )) || note "an audit-trail.md exists (verification underway) but status is '${hdr}'. Advance both ${label} and its INDEX row to at least 'In Review'."
    fi
  fi
done < <(printf '%s\n' "$ids")

exit $(( bad ? 2 : 0 ))
