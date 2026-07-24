#!/usr/bin/env bash
# SPEC status-sync guard (finish-boundary hook + git pre-commit): on a SPEC-* branch, keep the spec's
# status accurate and consistent. Blocks (exit 2) when the spec header status and the specs/INDEX.md
# row disagree, use an off-legend word, or lag reality (a section/close-out implies a further state
# than the status claims). Validate-only: it never edits — the stderr message tells the agent to
# RESOLVE the drift (investigate the true state, then set the same status in BOTH places), because an
# agent can determine the correct value where a blind auto-sync would guess.
# Silent (exit 0) off a SPEC-* branch or when the spec has no file yet.
#
# Agent-agnostic root resolution (see check-ac-closeout.sh).
dir="${SPEC_WORKFLOW_ROOT:-${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")}}"
index="$dir/specs/INDEX.md"
branch=$(git -C "$dir" branch --show-current 2>/dev/null) || exit 0
[[ "$branch" =~ (SPEC-[0-9]+) ]] || exit 0
id="${BASH_REMATCH[1]}"

# A spec is a FOLDER: specs/SPEC-N-name/spec.md (+ tech-design.md, implementation.md, attachments).
# Resolve the folder main-tree first, then backlog (preserves "main before backlog"), then its
# spec.md. The trailing '-' stops SPEC-2 matching SPEC-20. Keep in sync with check-spec-version.sh's
# canonical-path regex.
specdir=$(ls -d "$dir"/specs/"${id}"-*/ 2>/dev/null | head -1)
[[ -n "$specdir" ]] || specdir=$(ls -d "$dir"/specs/backlog/"${id}"-*/ 2>/dev/null | head -1)
file="${specdir}spec.md"
[[ -n "$specdir" && -f "$file" ]] || exit 0
[[ -f "$index" ]] || exit 0
# Display label: the file basename is always "spec.md", so show the folder name (SPEC-N-name) instead.
label="${specdir%/}"; label="${label##*/}"

LEGAL='In Planning|In Progress|In Review|Validated|Planned|Deprecated'  # longest-first
block() { echo "Status-sync check for ${id}: $1" >&2; exit 2; }
rank() { case "$1" in
  "In Planning") echo 0;; "Planned") echo 1;; "In Progress") echo 2;;
  "In Review") echo 3;; "Validated") echo 4;; "Deprecated") echo 9;; *) echo -1;; esac; }

# --- Header status word ---
hdr=$(grep -m1 '^\*\*Status:\*\*' "$file" | grep -oE "$LEGAL" | head -1)
[[ -n "$hdr" ]] || block "the '**Status:**' header in ${label} is missing or not one of: In Planning, Planned, In Progress, In Review, Validated. Set it to the legal token that matches the spec's true state, and set the same word in its specs/INDEX.md row."

# --- INDEX row status word (require exactly one row) ---
rows=$(grep -cE "^\| ${id} \|" "$index")
[[ "$rows" == "1" ]] || block "expected exactly one specs/INDEX.md row for ${id}, found ${rows}. Fix the table (add the missing row or remove the duplicate) so ${id} appears once, with a status matching ${label}."
idx=$(grep -m1 -E "^\| ${id} \|" "$index" | awk -F'|' '{print $5}' | grep -oE "$LEGAL" | head -1)
[[ -n "$idx" ]] || block "the specs/INDEX.md row for ${id} has no legal status word. Set it to match the spec header ('${hdr}')."

# --- Header vs INDEX consistency ---
[[ "$hdr" == "$idx" ]] || block "status drift — ${label} header says '${hdr}' but specs/INDEX.md says '${idx}'. Resolve: determine the true state from the spec's sections, AC checkboxes and test evidence, then set the ONE correct status in BOTH places."

# --- Deprecated is a frozen terminal state: header==INDEX is enough, skip reality floors ---
# (a deprecated spec keeps whatever sections it had; do not force it to In Review / Validated).
[[ "$hdr" == "Deprecated" ]] && exit 0

# --- Reality floors (strongest first) ---
r=$(rank "$hdr")
closeout=0; [[ -f "${specdir}implementation.md" ]] && closeout=1
# close-out complete = implementation.md exists AND no unchecked non-DESCOPED AC remains in spec.md
if [[ "$closeout" == "1" ]] && ! grep -E '^- \[ \] AC-' "$file" | grep -qvi 'descoped'; then
  [[ "$hdr" == "Validated" ]] || block "close-out is complete (implementation.md present, all ACs ticked/DESCOPED) but status is '${hdr}'. Set both ${label} and its INDEX row to 'Validated'."
elif [[ "$closeout" == "1" ]]; then
  (( r >= 3 )) || block "an implementation.md (close-out evidence) exists (verification underway) but status is '${hdr}'. Advance both ${label} and its INDEX row to at least 'In Review'."
else
  # On a SPEC-N branch with no implementation.md yet ⇒ implementation has started.
  (( r >= 2 )) || block "you are on the ${id} implementation branch but status is '${hdr}'. Set both ${label} and its INDEX row to 'In Progress' (or further, if verification/close-out has begun)."
fi
exit 0
