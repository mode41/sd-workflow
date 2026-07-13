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

# Resolve the spec (main tree, then backlog).
file=$(ls "$dir"/specs/"${id}"-*.md 2>/dev/null | head -1)
[[ -n "$file" ]] || file=$(ls "$dir"/specs/backlog/"${id}"-*.md 2>/dev/null | head -1)
[[ -n "$file" && -f "$file" ]] || exit 0
[[ -f "$index" ]] || exit 0

LEGAL='In Planning|In Progress|In Review|Validated|Planned|Deprecated'  # longest-first
block() { echo "Status-sync check for ${id}: $1" >&2; exit 2; }
rank() { case "$1" in
  "In Planning") echo 0;; "Planned") echo 1;; "In Progress") echo 2;;
  "In Review") echo 3;; "Validated") echo 4;; "Deprecated") echo 9;; *) echo -1;; esac; }

# --- Header status word ---
hdr=$(grep -m1 '^\*\*Status:\*\*' "$file" | grep -oE "$LEGAL" | head -1)
[[ -n "$hdr" ]] || block "the '**Status:**' header in ${file##*/} is missing or not one of: In Planning, Planned, In Progress, In Review, Validated. Set it to the legal token that matches the spec's true state, and set the same word in its specs/INDEX.md row."

# --- INDEX row status word (require exactly one row) ---
rows=$(grep -cE "^\| ${id} \|" "$index")
[[ "$rows" == "1" ]] || block "expected exactly one specs/INDEX.md row for ${id}, found ${rows}. Fix the table (add the missing row or remove the duplicate) so ${id} appears once, with a status matching ${file##*/}."
idx=$(grep -m1 -E "^\| ${id} \|" "$index" | awk -F'|' '{print $5}' | grep -oE "$LEGAL" | head -1)
[[ -n "$idx" ]] || block "the specs/INDEX.md row for ${id} has no legal status word. Set it to match the spec header ('${hdr}')."

# --- Header vs INDEX consistency ---
[[ "$hdr" == "$idx" ]] || block "status drift — ${file##*/} header says '${hdr}' but specs/INDEX.md says '${idx}'. Resolve: determine the true state from the spec's sections, AC checkboxes and test evidence, then set the ONE correct status in BOTH places."

# --- Deprecated is a frozen terminal state: header==INDEX is enough, skip reality floors ---
# (a deprecated spec keeps whatever sections it had; do not force it to In Review / Validated).
[[ "$hdr" == "Deprecated" ]] && exit 0

# --- Reality floors (strongest first) ---
r=$(rank "$hdr")
closeout=0; grep -qE '^## Implementation' "$file" && closeout=1
# close-out complete = an Implementation section exists AND no unchecked non-DESCOPED AC remains
if [[ "$closeout" == "1" ]] && ! grep -E '^- \[ \] AC-' "$file" | grep -qvi 'descoped'; then
  [[ "$hdr" == "Validated" ]] || block "close-out is complete (Implementation section present, all ACs ticked/DESCOPED) but status is '${hdr}'. Set both ${file##*/} and its INDEX row to 'Validated'."
elif [[ "$closeout" == "1" ]]; then
  (( r >= 3 )) || block "an '## Implementation & Verification' section exists (verification underway) but status is '${hdr}'. Advance both ${file##*/} and its INDEX row to at least 'In Review'."
else
  # On a SPEC-N branch with no verification section yet ⇒ implementation has started.
  (( r >= 2 )) || block "you are on the ${id} implementation branch but status is '${hdr}'. Set both ${file##*/} and its INDEX row to 'In Progress' (or further, if verification/close-out has begun)."
fi
exit 0
