# SPEC-X: Spec Name — Audit Trail

<!-- The verification record for this spec. Written at step 5 (verification) and completed at step 6
     (close-out). Its EXISTENCE is what tells check-status-sync.sh that verification is underway, so
     do not create this file before you have something real to put in it — an empty or stub trail
     forces the spec to 🟠 In Review while claiming evidence that does not exist.

     Two things live here, and only the second one is judgement:
       - facts you read out of git (branch, commit range, files touched) — transcribe, don't recall
       - the AC -> evidence mapping, which exists in NO other file: spec.md says a criterion is met,
         this says what proves it.

     check-ac-closeout.sh blocks the commit if any AC ticked in spec.md is never cited here.
     This file is NOT version-gated — writing it never requires a **Version:** bump. -->

**Branch:** SPEC-X
**Commits:** `<merge-base>..<head>`
**Verified:** YYYY-MM-DD

## Summary

_One paragraph: what was built, and anything a reader six months from now would need to know that
the code does not say on its own — a deviation from `tech-design.md`, a workaround, a known limit._

## Acceptance Criteria — evidence

<!-- One row per AC ticked in spec.md. Name the actual test, not a description of it: a reader must
     be able to open the named test and see the criterion checked. DESCOPED ACs stay unticked in
     spec.md and do not belong here — their reason lives there. -->

| AC | Evidence | Where |
|----|----------|-------|
| AC-1 | _what proves it_ | `path/to/test::test_name` |
| AC-2 | _what proves it_ | `path/to/test::test_name` |

## Edge Cases — evidence

| EC | Evidence | Where |
|----|----------|-------|
| EC-1 | _what proves it_ | `path/to/test::test_name` |

## Test run

<!-- The result as observed, not as expected. If something is skipped, flaky, or unverifiable in
     this environment, say so here — an honest gap is worth more than a green claim. -->

- Command: `<the project's test command>`
- Result: _N passed, N failed, N skipped_
- Run against: `<commit>`

## Deviations & follow-ups

_Anything that did not land as designed, and the SPEC-N (or issue) that now carries it. Delete this
section if there is nothing to record._
