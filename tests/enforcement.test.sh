#!/usr/bin/env bash
# tests/enforcement.test.sh — behavioural tests for the spec-workflow enforcement machinery.
#
# Exercises the SHIPPED scripts in .apm/scripts/ (not a deployed copy) against throwaway git
# fixtures, so a regression shows up here before it reaches a consumer project. Covers:
#
#   1. Status / AC / open-question state machine  — the four check-*.sh guards
#   2. Spec versioning                            — check-spec-version.sh substantive-change rules
#   3. Stale session-end hook safety net          — the stop_hook_active guard in all four checks
#   4. The pre-commit wrapper                     — blocking, bypass, and the checks.sha256 gate
#   5. Installer reconciliation                   — Stop-hook unwiring + retired-file prune
#
# Usage:  bash tests/enforcement.test.sh          (exit 0 = all passed)
# Requires: git, bash 4+, sha256sum or shasum. Sections needing jq skip themselves without it.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
SCRIPTS="$ROOT/.apm/scripts"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/spec-workflow-tests.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

pass=0; fail=0; skipped=0
if [ -t 1 ]; then G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; B=$'\033[1m'; N=$'\033[0m'
else G=""; R=""; Y=""; B=""; N=""; fi

section() { printf '\n%s%s%s\n' "$B" "$1" "$N"; }
ok()      { pass=$((pass+1));    printf '  %sPASS%s  %s\n' "$G" "$N" "$1"; }
bad()     { fail=$((fail+1));    printf '  %sFAIL%s  %s\n' "$R" "$N" "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; }
skip()    { skipped=$((skipped+1)); printf '  %sSKIP%s  %s\n' "$Y" "$N" "$1"; }

# Assert the last run's exit code. 0 = the check stayed silent, 2 = it blocked.
is_rc()   { if [ "$RC" = "$1" ]; then ok "$2"; else bad "$2" "exit $RC, wanted $1${OUT:+ — output: ${OUT%%$'\n'*}}"; fi; }
# Assert the last run's output mentions something, so a check blocks for the RIGHT reason.
says()    { case "$OUT" in *"$1"*) ok "$2";; *) bad "$2" "output did not mention '$1'";; esac; }

# Run one deployed check against a fixture, the way the pre-commit does (SPEC_WORKFLOW_ROOT set,
# stdin closed). Sets RC and OUT.
run() { OUT=$(SPEC_WORKFLOW_ROOT="$1" bash "$1/.spec-workflow/hooks/$2" 2>&1 </dev/null); RC=$?; }

# Run one check the way a stale harness session-end hook would: no SPEC_WORKFLOW_ROOT, JSON on stdin.
# CLAUDE_PROJECT_DIR is scrubbed so the root resolves from the fixture's own git top-level.
run_as_hook() {
  OUT=$(printf '%s' "$3" | ( cd "$1" && env -u SPEC_WORKFLOW_ROOT -u CLAUDE_PROJECT_DIR \
        bash "$1/.spec-workflow/hooks/$2" 2>&1 ) ); RC=$?
}

deploy() {   # <dir> — put the shipped checks where a real install has them
  mkdir -p "$1/.spec-workflow/hooks"
  cp "$SCRIPTS"/check-*.sh "$SCRIPTS/pre-commit" "$1/.spec-workflow/hooks/"
  chmod +x "$1/.spec-workflow/hooks/"* 2>/dev/null || true
}
hash_checks() { ( cd "$1/.spec-workflow/hooks" && sha256sum check-*.sh > checks.sha256 2>/dev/null \
                  || shasum -a 256 check-*.sh > checks.sha256 ); }
git_init() { git -C "$1" init -q; git -C "$1" config user.email t@t.io; git -C "$1" config user.name tester; }

# ---------------------------------------------------------------------------
# Fixture A — the status / AC / open-question state machine.
#   fixture_state <name> <hdr-status> <index-status> <ac-box> <answer> <impl?> <branch>
# The baseline is committed BEFORE audit-trail.md is written and before the branch is cut, so
# audit-trail.md stays untracked — which is what the checks see in real use. The seeded trail cites
# AC-1, so it satisfies the close-out citation gate; tests that exercise that gate overwrite it.
# ---------------------------------------------------------------------------
fixture_state() {
  local d="$WORK/$1"; rm -rf "$d"; mkdir -p "$d/specs/SPEC-36-glossary"
  git_init "$d"; deploy "$d"
  cat > "$d/specs/SPEC-36-glossary/spec.md" <<EOF
# SPEC-36 Glossary
**Status:** $2
**Version:** v1

## Acceptance Criteria
- [$4] AC-1 the glossary exists

## Open Questions
### Q-1: which glossary source wins?
**Assumed:** the PRD
**Answer:**$5
EOF
  printf '| ID | Title | V | Status |\n|---|---|---|---|\n| SPEC-36 | Glossary | v1 | %s |\n' "$3" > "$d/specs/INDEX.md"
  git -C "$d" add -A >/dev/null; git -C "$d" commit -qm baseline
  [ "$6" = yes ] && echo "AC-1 closed by tests/test_glossary.py::test_exists" \
                       > "$d/specs/SPEC-36-glossary/audit-trail.md"
  git -C "$d" checkout -q -b "$7"
  echo "$d"
}

# ---------------------------------------------------------------------------
# Fixture B — spec versioning. Commits a baseline at <status>/v1 so later edits are diffed vs HEAD.
#   fixture_version <name> <status> [with-td]
# ---------------------------------------------------------------------------
fixture_version() {
  local d="$WORK/$1"; rm -rf "$d"; mkdir -p "$d/specs/SPEC-7-widget"
  git_init "$d"; deploy "$d"
  cat > "$d/specs/SPEC-7-widget/spec.md" <<EOF
# SPEC-7 Widget
**Status:** $2
**Version:** v1
**Last Updated:** 2026-01-01

## Requirements
The widget must render the original way.

## Acceptance Criteria
- [ ] AC-1 the widget renders

## Changelog
| Version | Date | Change | Driver |
|---|---|---|---|
| v1 | 2026-01-01 | initial | self |
EOF
  if [ "${3:-}" = with-td ]; then
    cat > "$d/specs/SPEC-7-widget/tech-design.md" <<EOF
# SPEC-7 Tech Design
**Designed:** 2026-01-01

## Approach
The original approach.
EOF
  fi
  printf '| ID | Title | V | Status |\n|---|---|---|---|\n| SPEC-7 | Widget | v1 | %s |\n' "$2" > "$d/specs/INDEX.md"
  git -C "$d" add -A >/dev/null; git -C "$d" commit -qm baseline
  echo "$d"
}

bump_to_v2() {   # <dir> — a proper bump: version header + a new changelog row
  local s="$1/specs/SPEC-7-widget/spec.md"
  sed -i.bak 's/^\*\*Version:\*\* v1/**Version:** v2/' "$s" && rm -f "$s.bak"
  sed -i.bak 's#^| v1 | 2026-01-01 | initial | self |#| v2 | 2026-02-01 | reworked | self |\n| v1 | 2026-01-01 | initial | self |#' "$s" && rm -f "$s.bak"
}

###############################################################################
section "1. Status / AC / open-question state machine"
###############################################################################

echo "  -- the reported bug: In Planning, open question, no audit-trail.md"
d=$(fixture_state s1 "In Planning" "In Planning" " " "" no SPEC-36-work)
for h in check-status-sync check-ac-closeout check-open-questions check-spec-version; do
  run "$d" "$h.sh"; is_rc 0 "$h stays silent"
done

echo "  -- the same, on a branch named to a company convention"
d=$(fixture_state s2 "In Planning" "In Planning" " " "" no userstory-1928)
for h in check-status-sync check-ac-closeout check-open-questions; do
  run "$d" "$h.sh"; is_rc 0 "$h stays silent"
done

echo "  -- open-questions CEILING still bites, with no floor to deadlock against"
d=$(fixture_state s3 "In Progress" "In Progress" " " "" no SPEC-36-work)
printf '\n<!-- touched so the spec differs from HEAD -->\n' >> "$d/specs/SPEC-36-glossary/spec.md"
run "$d" check-open-questions.sh; is_rc 2 "ceiling blocks In Progress with an open Q-1"
says "Q-1" "and names the blocking question"
run "$d" check-status-sync.sh;   is_rc 0 "status-sync imposes no conflicting floor"

echo "  -- REGRESSION GUARD: a branch-derived floor would make this state unsatisfiable"
d=$(fixture_state s3b "In Planning" "In Planning" " " "" no SPEC-36-work)
printf '\n<!-- touched -->\n' >> "$d/specs/SPEC-36-glossary/spec.md"
run "$d" check-open-questions.sh; rc_q=$RC
run "$d" check-status-sync.sh;   rc_s=$RC
if [ "$rc_q" = 0 ] && [ "$rc_s" = 0 ]; then ok "In Planning on a SPEC branch with an open Q is a legal, quiet state"
else bad "In Planning on a SPEC branch with an open Q is a legal, quiet state" \
         "open-questions=$rc_q status-sync=$rc_s — a floor/ceiling deadlock is back"; fi

echo "  -- artifact-evidence floors still fire"
d=$(fixture_state s4 "In Planning" "In Planning" " " " confirmed" yes SPEC-36-work)
run "$d" check-status-sync.sh; is_rc 2 "audit-trail.md forces at least In Review"
says "In Review" "and says which status to set"
run "$d" check-ac-closeout.sh; is_rc 2 "unticked AC at close-out blocks"

d=$(fixture_state s5 "In Review" "In Review" x " confirmed" yes SPEC-36-work)
run "$d" check-status-sync.sh; is_rc 2 "complete close-out forces Validated"
says "Validated" "and says which status to set"
run "$d" check-ac-closeout.sh; is_rc 0 "ticked ACs cited in the trail pass close-out"

echo "  -- the trail must say what closed each ticked AC"
d=$(fixture_state s5b "In Review" "In Review" x " confirmed" yes SPEC-36-work)
echo "all tests pass" > "$d/specs/SPEC-36-glossary/audit-trail.md"   # a stub trail, no AC cited
run "$d" check-ac-closeout.sh; is_rc 2 "a ticked AC absent from the trail blocks"
says "AC-1" "and names the uncited criterion"

d=$(fixture_state s5c "In Review" "In Review" x " confirmed" yes SPEC-36-work)
echo "AC-10 closed by tests/test_other.py" > "$d/specs/SPEC-36-glossary/audit-trail.md"
run "$d" check-ac-closeout.sh; is_rc 2 "AC-10 in the trail does not satisfy a ticked AC-1"

echo "  -- DESCOPED criteria owe the trail nothing"
d=$(fixture_state s5d "In Review" "In Review" " " " confirmed" yes SPEC-36-work)
s="$d/specs/SPEC-36-glossary/spec.md"
sed -i.bak 's/- \[ \] AC-1 the glossary exists/- [ ] AC-1 DESCOPED — moved to SPEC-40/' "$s"; rm -f "$s.bak"
echo "nothing was closed here" > "$d/specs/SPEC-36-glossary/audit-trail.md"
run "$d" check-ac-closeout.sh; is_rc 0 "an unticked DESCOPED AC is exempt from both gates"

echo "  -- header vs INDEX drift"
d=$(fixture_state s6 "In Review" "Validated" x " confirmed" yes SPEC-36-work)
run "$d" check-status-sync.sh; is_rc 2 "drift between spec header and INDEX blocks"
says "drift" "and reports it as drift"

echo "  -- terminal states"
d=$(fixture_state s7 "Validated" "Validated" x " confirmed" yes SPEC-36-work)
for h in check-status-sync check-ac-closeout check-open-questions; do
  run "$d" "$h.sh"; is_rc 0 "$h silent on a fully closed-out spec"
done
d=$(fixture_state s8 "Deprecated" "Deprecated" " " "" yes SPEC-36-work)
run "$d" check-status-sync.sh; is_rc 0 "Deprecated tombstone exempt from status floors"
run "$d" check-ac-closeout.sh; is_rc 0 "Deprecated tombstone exempt from AC close-out"

###############################################################################
section "1b. Which spec gets judged — never the branch name"
###############################################################################
# The checks used to read the branch and bail unless it matched SPEC-[0-9]+, so a project with its
# own convention ("userstory-1928") silently lost two of the four guards. Selection is now driven by
# what the change TOUCHES: any file under a spec folder, or a changed specs/INDEX.md row.

echo "  -- a company-convention branch is enforced exactly like a SPEC-N one"
d=$(fixture_state b1 "In Review" "Validated" x " confirmed" yes userstory-1928)
run "$d" check-status-sync.sh; is_rc 2 "header/INDEX drift blocks on userstory-1928"
says "drift" "and reports it as drift"
d=$(fixture_state b2 "In Planning" "In Planning" " " " confirmed" yes userstory-1928)
run "$d" check-ac-closeout.sh; is_rc 2 "an unticked AC at close-out blocks on userstory-1928"
run "$d" check-status-sync.sh; is_rc 2 "the audit-trail floor fires on userstory-1928"

echo "  -- and on the default branch, where no branch was ever cut"
d=$(fixture_state b3 "In Review" "Validated" x " confirmed" yes scratch)
git -C "$d" checkout -q -                      # back to whatever this repo's default branch is
run "$d" check-status-sync.sh; is_rc 2 "drift is caught on the default branch too"

echo "  -- a status edit made in specs/INDEX.md ALONE still selects its spec"
d=$(fixture_state b4 "In Planning" "In Planning" " " " confirmed" no userstory-1928)
sed -i.bak 's/| v1 | In Planning |/| v1 | Validated |/' "$d/specs/INDEX.md"; rm -f "$d/specs/INDEX.md.bak"
run "$d" check-status-sync.sh; is_rc 2 "INDEX-only drift blocks (spec folder untouched)"
says "drift" "and reports it as drift"

echo "  -- a source-only change selects nothing (the deliberate loosening)"
# Drift already committed at HEAD: this commit touches no spec folder and no INDEX row, so there is
# nothing to re-judge. The commit that INTRODUCED the drift was blocked; the next one touching the
# spec will be too.
d=$(fixture_state b5 "In Review" "Validated" x " confirmed" no userstory-1928)
echo "print('hi')" > "$d/app.py"
for h in check-status-sync check-ac-closeout check-open-questions check-spec-version; do
  run "$d" "$h.sh"; is_rc 0 "$h silent on a source-only change"
done

echo "  -- one commit spanning two drifted specs reports BOTH"
d=$(fixture_state b6 "In Review" "In Review" x " confirmed" yes userstory-1928)
mkdir -p "$d/specs/SPEC-40-atlas"
printf '# SPEC-40 Atlas\n**Status:** In Planning\n**Version:** v1\n\n## Acceptance Criteria\n- [x] AC-1 the atlas exists\n' \
  > "$d/specs/SPEC-40-atlas/spec.md"
echo "AC-1 closed by tests/test_atlas.py::test_exists" > "$d/specs/SPEC-40-atlas/audit-trail.md"
printf '| SPEC-40 | Atlas | v1 | In Planning |\n' >> "$d/specs/INDEX.md"
run "$d" check-status-sync.sh; is_rc 2 "two drifted specs in one change block"
says "SPEC-36" "and names the first"
says "SPEC-40" "and names the second"

###############################################################################
section "2. Spec versioning (check-spec-version.sh)"
###############################################################################

echo "  -- a substantive change to a Planned spec demands a bump + changelog row"
d=$(fixture_version v1 Planned)
sed -i.bak 's/render the original way/render a completely different way/' "$d/specs/SPEC-7-widget/spec.md"; rm -f "$d/specs/SPEC-7-widget/spec.md.bak"
run "$d" check-spec-version.sh; is_rc 2 "substantive spec.md change without a bump blocks"
says "Version" "and points at the Version header"

echo "  -- bumping the version alone is not enough"
sed -i.bak 's/^\*\*Version:\*\* v1/**Version:** v2/' "$d/specs/SPEC-7-widget/spec.md"; rm -f "$d/specs/SPEC-7-widget/spec.md.bak"
run "$d" check-spec-version.sh; is_rc 2 "bump without a changelog row still blocks"
says "Changelog" "and asks for the changelog row"

echo "  -- bump + changelog row satisfies it"
d=$(fixture_version v2 Planned)
sed -i.bak 's/render the original way/render a completely different way/' "$d/specs/SPEC-7-widget/spec.md"; rm -f "$d/specs/SPEC-7-widget/spec.md.bak"
bump_to_v2 "$d"
run "$d" check-spec-version.sh; is_rc 0 "bump + new changelog row passes"

echo "  -- non-substantive edits are exempt (the normal workflow must not need a bump)"
exempt() {  # <label> <sed-expression>
  local d; d=$(fixture_version "ex$RANDOM$1" Planned) || return
  sed -i.bak "$2" "$d/specs/SPEC-7-widget/spec.md"; rm -f "$d/specs/SPEC-7-widget/spec.md.bak"
  run "$d" check-spec-version.sh; is_rc 0 "exempt: $1"
}
exempt "status change"      's/^\*\*Status:\*\* Planned/**Status:** In Progress/'
exempt "last-updated stamp" 's/^\*\*Last Updated:\*\* 2026-01-01/**Last Updated:** 2026-06-06/'
exempt "ticking an AC"      's/^- \[ \] AC-1/- [x] AC-1/'
exempt "changelog edit"     's/| initial | self |/| initial rewrite | self |/'

d=$(fixture_version v3 Planned)
cat >> "$d/specs/SPEC-7-widget/spec.md" <<'EOF'

## Open Questions
### Q-9: a brand new question
**Assumed:** something
**Answer:**
EOF
run "$d" check-spec-version.sh; is_rc 0 "exempt: raising an Open Question"

echo "  -- lifecycle exemptions"
d=$(fixture_version v4 "In Planning")
sed -i.bak 's/render the original way/render a completely different way/' "$d/specs/SPEC-7-widget/spec.md"; rm -f "$d/specs/SPEC-7-widget/spec.md.bak"
run "$d" check-spec-version.sh; is_rc 0 "a spec still In Planning at HEAD is exempt"

d=$(fixture_version v5 Planned)
mkdir -p "$d/specs/SPEC-8-brandnew"
printf '# SPEC-8\n**Status:** In Planning\n**Version:** v1\n\n## Requirements\nnew.\n' > "$d/specs/SPEC-8-brandnew/spec.md"
git -C "$d" add -A >/dev/null
run "$d" check-spec-version.sh; is_rc 0 "a brand-new spec (absent at HEAD) is exempt"

d=$(fixture_version v6 Deprecated)
sed -i.bak 's/render the original way/render a completely different way/' "$d/specs/SPEC-7-widget/spec.md"; rm -f "$d/specs/SPEC-7-widget/spec.md.bak"
run "$d" check-spec-version.sh; is_rc 0 "an already-Deprecated spec is a frozen tombstone"

echo "  -- deprecating a spec must itself be recorded"
d=$(fixture_version v7 Planned)
sed -i.bak 's/^\*\*Status:\*\* Planned/**Status:** Deprecated/' "$d/specs/SPEC-7-widget/spec.md"; rm -f "$d/specs/SPEC-7-widget/spec.md.bak"
run "$d" check-spec-version.sh; is_rc 2 "deprecation without a bump blocks"
says "deprecated" "and says it is the deprecation that needs recording"
bump_to_v2 "$d"
run "$d" check-spec-version.sh; is_rc 0 "deprecation with a bump + changelog row passes"

echo "  -- tech-design.md is gated too, and ONE bump in spec.md covers the folder"
d=$(fixture_version v8 Planned with-td)
sed -i.bak 's/The original approach./A fundamentally different approach./' "$d/specs/SPEC-7-widget/tech-design.md"; rm -f "$d/specs/SPEC-7-widget/tech-design.md.bak"
run "$d" check-spec-version.sh; is_rc 2 "substantive tech-design.md change without a bump blocks"
says "spec.md" "and directs the bump to spec.md"
bump_to_v2 "$d"
run "$d" check-spec-version.sh; is_rc 0 "one spec.md bump covers a tech-design.md change"

d=$(fixture_version v9 Planned with-td)
sed -i.bak 's/^\*\*Designed:\*\* 2026-01-01/**Designed:** 2026-06-06/' "$d/specs/SPEC-7-widget/tech-design.md"; rm -f "$d/specs/SPEC-7-widget/tech-design.md.bak"
run "$d" check-spec-version.sh; is_rc 0 "exempt: re-stamping the tech-design Designed date"

###############################################################################
section "3. Stale session-end hook safety net (stop_hook_active)"
###############################################################################
# The installer no longer wires a harness session-end hook, but an older install may still have one.
# Every check must go quiet when the harness reports it is re-invoking us after a previous block,
# so an unrepairable condition can never become an unbounded block loop.

# One fixture that makes ALL FOUR checks block at once:
#   status-sync   -> audit-trail.md present but status is In Planning
#   ac-closeout   -> audit-trail.md present with an unticked AC
#   open-questions-> spec.md changed vs HEAD and carries an unanswered Q-1  (ceiling is fine at
#                    In Planning, so we raise the status via the INDEX-matching header below)
#   spec-version  -> Planned at HEAD, substantive body change, no bump
d="$WORK/guard"; rm -rf "$d"; mkdir -p "$d/specs/SPEC-36-glossary"
git_init "$d"; deploy "$d"
cat > "$d/specs/SPEC-36-glossary/spec.md" <<'EOF'
# SPEC-36 Glossary
**Status:** Planned
**Version:** v1

## Requirements
The glossary must list the original terms.

## Acceptance Criteria
- [ ] AC-1 the glossary exists

## Changelog
| Version | Date | Change | Driver |
|---|---|---|---|
| v1 | 2026-01-01 | initial | self |
EOF
printf '| ID | Title | V | Status |\n|---|---|---|---|\n| SPEC-36 | Glossary | v1 | Planned |\n' > "$d/specs/INDEX.md"
git -C "$d" add -A >/dev/null; git -C "$d" commit -qm baseline
git -C "$d" checkout -q -b SPEC-36-work
echo "evidence" > "$d/specs/SPEC-36-glossary/audit-trail.md"
sed -i.bak 's/list the original terms/list a totally different set of terms/' "$d/specs/SPEC-36-glossary/spec.md"; rm -f "$d/specs/SPEC-36-glossary/spec.md.bak"
cat >> "$d/specs/SPEC-36-glossary/spec.md" <<'EOF'

## Open Questions
### Q-1: which source wins?
**Assumed:** the PRD
**Answer:**
EOF
sed -i.bak 's/^\*\*Status:\*\* Planned/**Status:** In Progress/' "$d/specs/SPEC-36-glossary/spec.md"; rm -f "$d/specs/SPEC-36-glossary/spec.md.bak"
sed -i.bak 's/| v1 | Planned |/| v1 | In Progress |/' "$d/specs/INDEX.md"; rm -f "$d/specs/INDEX.md.bak"

for h in check-status-sync check-ac-closeout check-open-questions check-spec-version; do
  run_as_hook "$d" "$h.sh" '{"session_id":"a","stop_hook_active":false}'
  is_rc 2 "$h blocks on the first fire"
  run_as_hook "$d" "$h.sh" '{"session_id":"a","stop_hook_active":true}'
  is_rc 0 "$h goes quiet when stop_hook_active is true"
done

echo "  -- the guard must be precise, not a substring match on 'true'"
run_as_hook "$d" check-status-sync.sh '{"stop_hook_active":false,"transcript":"/x","other":true}'
is_rc 2 "an unrelated true elsewhere in the payload does not trip the guard"
run_as_hook "$d" check-status-sync.sh '{"a":true,"stop_hook_active": false}'
is_rc 2 "a true BEFORE the flag does not trip the guard"
run_as_hook "$d" check-status-sync.sh '{"stop_hook_active" : true}'
is_rc 0 "whitespace around the colon is tolerated"

echo "  -- the guard must never weaken the pre-commit path"
OUT=$(printf '{"stop_hook_active":true}' | SPEC_WORKFLOW_ROOT="$d" bash "$d/.spec-workflow/hooks/check-status-sync.sh" 2>&1); RC=$?
is_rc 2 "SPEC_WORKFLOW_ROOT set: stdin is ignored and the check still blocks"

echo "  -- reading stdin must never hang a commit"
mkfifo "$WORK/stalled"; exec 9<>"$WORK/stalled"      # open, and deliberately never written to
t0=$SECONDS
OUT=$( cd "$d" && env -u SPEC_WORKFLOW_ROOT -u CLAUDE_PROJECT_DIR \
       bash "$d/.spec-workflow/hooks/check-status-sync.sh" <&9 2>&1 ); RC=$?
elapsed=$((SECONDS - t0)); exec 9>&-; rm -f "$WORK/stalled"
if [ "$elapsed" -le 3 ]; then ok "a stalled stdin times out (${elapsed}s) instead of hanging"
else bad "a stalled stdin times out instead of hanging" "took ${elapsed}s"; fi
is_rc 2 "and the check still runs to its real verdict afterwards"

###############################################################################
section "4. The pre-commit wrapper"
###############################################################################

d=$(fixture_state pc "In Planning" "In Planning" " " " confirmed" yes SPEC-36-work)
hash_checks "$d"; git -C "$d" config core.hooksPath .spec-workflow/hooks
git -C "$d" add -A >/dev/null

OUT=$(cd "$d" && git commit -m "drifted" 2>&1); RC=$?
if [ "$RC" != 0 ]; then ok "a drifted spec is blocked at commit time"; else bad "a drifted spec is blocked at commit time" "commit succeeded"; fi
says "spec-workflow check failed" "and the wrapper explains why"
says "--no-verify" "and names the documented bypass"

OUT=$(cd "$d" && git commit --no-verify -m "bypassed" 2>&1); RC=$?
if [ "$RC" = 0 ]; then ok "--no-verify bypasses the gate (documented asymmetry)"; else bad "--no-verify bypasses the gate" "$OUT"; fi

echo "  -- a resolved spec commits cleanly"
d=$(fixture_state pc2 "In Planning" "In Planning" " " " confirmed" yes SPEC-36-work)
hash_checks "$d"; git -C "$d" config core.hooksPath .spec-workflow/hooks
sed -i.bak 's/^- \[ \] AC-1/- [x] AC-1/;s/^\*\*Status:\*\* In Planning/**Status:** Validated/' "$d/specs/SPEC-36-glossary/spec.md"; rm -f "$d/specs/SPEC-36-glossary/spec.md.bak"
sed -i.bak 's/| v1 | In Planning |/| v1 | Validated |/' "$d/specs/INDEX.md"; rm -f "$d/specs/INDEX.md.bak"
git -C "$d" add -A >/dev/null
OUT=$(cd "$d" && git commit -m "closed out" 2>&1); RC=$?
if [ "$RC" = 0 ]; then ok "a consistent, closed-out spec commits"; else bad "a consistent, closed-out spec commits" "$OUT"; fi

echo "  -- the checks.sha256 integrity gate"
echo "# tampered by the test" >> "$d/.spec-workflow/hooks/check-status-sync.sh"
echo "change" > "$d/scratch.txt"; git -C "$d" add -A >/dev/null
OUT=$(cd "$d" && git commit -m "after tampering" 2>&1); RC=$?
if [ "$RC" != 0 ]; then ok "a modified check script blocks the commit"; else bad "a modified check script blocks the commit" "commit succeeded"; fi
says "integrity" "and reports it as an integrity failure"
hash_checks "$d"
OUT=$(cd "$d" && git commit -m "after re-hashing" 2>&1); RC=$?
if [ "$RC" = 0 ]; then ok "re-generating checks.sha256 clears the gate"; else bad "re-generating checks.sha256 clears the gate" "$OUT"; fi

###############################################################################
section "5. Installer reconciliation (emit-harness-hooks.sh)"
###############################################################################

if ! command -v jq >/dev/null 2>&1; then
  skip "Stop-hook unwiring and the retired-file prune (jq not installed)"
else
  SENTINEL="spec-workflow-finish-hook"
  d="$WORK/unwire"; rm -rf "$d"; mkdir -p "$d/.claude" "$d/.spec-workflow/hooks"
  cp "$SCRIPTS/checks.spec.json" "$d/.spec-workflow/"
  # What a 0.4.x install left behind: our two Stop entries, alongside settings the user owns.
  cat > "$d/.claude/settings.json" <<EOF
{
  "permissions": { "allow": ["Bash(npm test)"] },
  "hooks": {
    "PreToolUse": [ { "hooks": [ { "type": "command", "command": "echo mine" } ] } ],
    "Stop": [
      { "hooks": [ { "type": "command", "command": "notify-send done" } ] },
      { "hooks": [
        { "type": "command", "command": "bash check-ac-closeout.sh  # $SENTINEL" },
        { "type": "command", "command": "bash check-status-sync.sh  # $SENTINEL" }
      ] }
    ]
  }
}
EOF
  bash "$SCRIPTS/emit-harness-hooks.sh" "$d" "$d/.spec-workflow" >/dev/null 2>&1; RC=$?
  if [ "$RC" = 0 ]; then ok "the reconciler exits cleanly"; else bad "the reconciler exits cleanly" "exit $RC"; fi
  if ! grep -q "$SENTINEL" "$d/.claude/settings.json"; then ok "our Stop entries are removed"
  else bad "our Stop entries are removed" "sentinel still present"; fi
  got=$(jq -r '[.hooks.Stop[].hooks[].command] | join(",")' "$d/.claude/settings.json" 2>/dev/null)
  if [ "$got" = "notify-send done" ]; then ok "the user's own Stop hook survives"
  else bad "the user's own Stop hook survives" "Stop is now: $got"; fi
  got=$(jq -r '.hooks.PreToolUse[0].hooks[0].command + "|" + .permissions.allow[0]' "$d/.claude/settings.json" 2>/dev/null)
  if [ "$got" = "echo mine|Bash(npm test)" ]; then ok "unrelated settings are untouched"
  else bad "unrelated settings are untouched" "got: $got"; fi

  before=$(cat "$d/.claude/settings.json")
  bash "$SCRIPTS/emit-harness-hooks.sh" "$d" "$d/.spec-workflow" >/dev/null 2>&1
  if [ "$before" = "$(cat "$d/.claude/settings.json")" ]; then ok "re-running changes nothing (idempotent)"
  else bad "re-running changes nothing (idempotent)" "settings.json changed on the second run"; fi

  echo "  -- when ours were the ONLY hooks, the empty scaffolding goes too"
  d="$WORK/unwire2"; rm -rf "$d"; mkdir -p "$d/.claude" "$d/.spec-workflow"
  cp "$SCRIPTS/checks.spec.json" "$d/.spec-workflow/"
  printf '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"bash x  # %s"}]}]}}' "$SENTINEL" > "$d/.claude/settings.json"
  bash "$SCRIPTS/emit-harness-hooks.sh" "$d" "$d/.spec-workflow" >/dev/null 2>&1
  got=$(jq -c . "$d/.claude/settings.json")
  if [ "$got" = "{}" ]; then ok "empty hooks.Stop and hooks are deleted, leaving {}"
  else bad "empty hooks.Stop and hooks are deleted, leaving {}" "got: $got"; fi

  echo "  -- fresh projects with nothing to unwire"
  rm -f "$d/.claude/settings.json"
  bash "$SCRIPTS/emit-harness-hooks.sh" "$d" "$d/.spec-workflow" >/dev/null 2>&1
  is_rc 0 "no settings.json: exits cleanly"
  rm -rf "$d/.claude"
  bash "$SCRIPTS/emit-harness-hooks.sh" "$d" "$d/.spec-workflow" >/dev/null 2>&1
  is_rc 0 "no .claude directory: exits cleanly"

  echo "  -- the installer prunes files it has retired"
  d="$WORK/prune"; rm -rf "$d"; mkdir -p "$d/.spec-workflow/hooks" "$d/.claude/agents"
  git_init "$d"
  : > "$d/.spec-workflow/finish-hook.spec.json"          # the 0.4.x name
  : > "$d/.spec-workflow/hooks/check-obsolete.sh"        # a check we no longer ship
  OUT=$(cd "$d" && CI=1 APM_PROJECT_DIR="$d" bash "$SCRIPTS/init-and-wire.sh" </dev/null 2>&1); RC=$?
  if [ "$RC" = 0 ]; then ok "the installer completes on an upgraded project"; else bad "the installer completes on an upgraded project" "exit $RC"; fi
  if [ ! -e "$d/.spec-workflow/finish-hook.spec.json" ]; then ok "the retired finish-hook.spec.json is pruned"
  else bad "the retired finish-hook.spec.json is pruned" "still present"; fi
  if [ -e "$d/.spec-workflow/checks.spec.json" ]; then ok "checks.spec.json is deployed in its place"
  else bad "checks.spec.json is deployed in its place" "missing"; fi
  if [ ! -e "$d/.spec-workflow/hooks/check-obsolete.sh" ]; then ok "a check we no longer ship is pruned"
  else bad "a check we no longer ship is pruned" "still present"; fi
  if [ -e "$d/.spec-workflow/hooks/checks.sha256" ] && ( cd "$d/.spec-workflow/hooks" && sha256sum -c --quiet checks.sha256 2>/dev/null ); then
    ok "checks.sha256 is regenerated over exactly the deployed set"
  else bad "checks.sha256 is regenerated over exactly the deployed set" "missing or does not verify"; fi
fi

###############################################################################
printf '\n%s%d passed, %d failed, %d skipped%s\n' "$B" "$pass" "$fail" "$skipped" "$N"
[ "$fail" -eq 0 ]
