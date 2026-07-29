# SPEC-X: Spec Name

<!-- Canonical status tokens (use verbatim; keep this header and the specs/INDEX.md row equal):
     🔵 In Planning · 🟣 Planned · 🟡 In Progress · 🟠 In Review · 🟢 Validated · ⚫ Deprecated
     Set by: requirements → In Planning, technical-design → Planned,
     implementation (on the spec's branch) → In Progress, verification → In Review,
     close-out → Validated.
     ⚫ Deprecated is terminal and reachable from ANY state: set it when the spec's feature no longer
     exists (superseded/dropped by another spec). Deprecate — don't rewrite; keep this file as a
     tombstone. -->
**Status:** 🔵 In Planning
**Version:** v1
**Created:** YYYY-MM-DD
**Last Updated:** YYYY-MM-DD

## Overview
_One paragraph describing what this spec delivers and why it matters._

## Changelog
<!-- Bump **Version:** (v1 → v2 → …) and add a row on any substantive change once this spec is
     Planned or later. Driver = the SPEC-N whose work caused the change, or "self" for an in-spec
     revision. Deprecating this spec is also a bump + row (Driver = the obsoleting SPEC-N).
     Editing this section, ticking ACs, or advancing status is NOT a substantive change. -->
| Version | Date | Change | Driver |
|---------|------|--------|--------|
| v1 | YYYY-MM-DD | Initial spec | — |

## Dependencies
- Requires: SPEC-Y (Spec Name) — reason

## User Stories

### US-1: _Story title_
**As a** [user type] **I want to** [action] **so that** [goal].

### US-2: _Story title_
**As a** [user type] **I want to** [action] **so that** [goal].

### US-3: _Story title_
**As a** [user type] **I want to** [action] **so that** [goal].

## Acceptance Criteria

- [ ] AC-1: _Concrete, testable criterion_
- [ ] AC-2: _Concrete, testable criterion_
- [ ] AC-3: _Concrete, testable criterion_
- [ ] AC-4: _Concrete, testable criterion_
- [ ] AC-5: _Concrete, testable criterion_

## Edge Cases

| # | Scenario | Expected Behavior |
|---|----------|-------------------|
| EC-1 | _What happens when..._ | _Expected outcome_ |
| EC-2 | _What happens when..._ | _Expected outcome_ |
| EC-3 | _What happens when..._ | _Expected outcome_ |

## BDD Scenarios

<!-- Behavioural scenarios in Given/When/Then. Each is citable by its BDD-N id and, once this spec's
     audit-trail.md exists, must be proven there — check-bdd-closeout.sh blocks the commit for any
     declared BDD-N never cited in the trail. A scenario that will NOT ship stays here with
     "(DESCOPED)" in its heading and a one-line reason; it is then exempt from the gate, the same way
     a DESCOPED AC is. Delete this section if the spec has no behavioural scenarios. -->

### BDD-1: _Scenario title_
**Given** _initial context_
**When** _action occurs_
**Then** _expected outcome_

### BDD-2: _Scenario title_
**Given** _..._
**When** _..._
**Then** _..._

## Out of Scope
_What this spec explicitly does NOT cover._

## Open Questions
<!-- Decisions this spec could not settle on its own. A command running with
     `interaction.mode: "file"` records them here instead of asking the terminal, notes what it
     ASSUMED and built on, and carries on; you fill in **Answer:** (your choice, or "confirmed").
     An empty **Answer:** holds this spec at 🔵 In Planning — check-open-questions.sh blocks the
     advance to 🟣 Planned until it is filled in. Answered questions STAY here: this is the
     decision record. Editing this section is NOT a substantive change (no version bump); what an
     answer then changes in the contract is — cite the Q-N in the changelog row.
     Delete this section if the spec has no open questions.

### Q-1: _The decision, as a question_
- (a) _Option — trade-off_
- (b) _Option — trade-off_
**Assumed:** _(b), because …_
**Answer:**
-->
_None._
