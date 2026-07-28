# A worked example: what a spec actually looks like

This is one complete spec at the end of its life — `🟢 Validated`, version `v3`, close-out written.
It is the same CSV→Parquet CLI the README's *Start here* section uses.

A spec is a **folder**, not a single file. Reading a finished one is the fastest way to understand
the workflow, because every convention the hooks enforce is visible at once: the status header, the
inline changelog, the ticked acceptance criteria, the one deliberately descoped criterion, and the
verification evidence that justifies calling it done.

You don't write this by hand. `/requirements` creates the folder and `spec.md`, `/technical-design
SPEC-2` writes `tech-design.md`, and `/write-tests SPEC-2` plus close-out produce `audit-trail.md`.

```
specs/SPEC-2-parquet-writer/
  spec.md              # the contract — WHAT (written by /requirements)
  tech-design.md       # the HOW (written by /technical-design)
  audit-trail.md       # the verification record (written at verification/close-out)
  # …and any attachments the spec refers to can live here too, e.g.
  #   mockups/         # wireframes, diagrams
  #   source/          # the raw Jira/issue text a spec was distilled from
```

---

## `specs/SPEC-2-parquet-writer/spec.md`

The contract. It carries the `**Status:**` and `**Version:**` header and the inline `## Changelog` —
those live only here, and govern the whole spec.

````markdown
# SPEC-2: Parquet Writer

**Status:** 🟢 Validated
**Version:** v3
**Created:** 2026-03-02
**Last Updated:** 2026-03-14

## Overview
Writes the typed row stream produced by SPEC-1 to a Parquet file, preserving column types and
applying a caller-selected compression codec. This is the half of the CLI that produces output;
without it the reader has nowhere to write.

## Changelog
| Version | Date | Change | Driver |
|---------|------|--------|--------|
| v1 | 2026-03-02 | Initial spec | — |
| v2 | 2026-03-09 | Writer contract takes a compression codec; added AC-3 (answers Q-1) | SPEC-4 |
| v3 | 2026-03-14 | AC-5 descoped — row-group sizing moved to its own spec | SPEC-6 |

## Dependencies
- Requires: SPEC-1 (CSV Reader) — supplies the typed row stream and the inferred column schema.

## User Stories

### US-1: Convert a file
**As a** data engineer **I want to** run one command against a CSV **so that** I get a Parquet file
I can load into my warehouse.

### US-2: Keep my types
**As a** data engineer **I want** the inferred column types preserved in the output **so that**
numeric columns don't arrive as strings.

### US-3: Control the size/speed trade-off
**As a** data engineer **I want to** choose the compression codec **so that** I can trade file size
against write speed.

## Acceptance Criteria

- [x] AC-1: `csv2parquet in.csv out.parquet` writes a Parquet file readable by a standard reader.
- [x] AC-2: Column types from the reader's schema survive the round trip — a numeric column reads
      back numeric, not as a string.
- [x] AC-3: `--compression {none,snappy,gzip,zstd}` selects the codec; the default is `snappy`, and
      an unrecognized value exits 2 without writing anything.
- [x] AC-4: An unwritable output path fails with a non-zero exit and an error naming the path.
- [ ] AC-5: DESCOPED — row-group size is tunable via `--row-group-size`. Profiling showed the
      default is correct for files under 2 GB, which covers every current use case; moved to SPEC-6.

## Edge Cases

| # | Scenario | Expected Behavior |
|---|----------|-------------------|
| EC-1 | Input CSV has a header but zero data rows | Write a valid Parquet file carrying the schema and no rows; exit 0 |
| EC-2 | Output file already exists | Fail with exit 1 and leave the existing file untouched, unless `--force` is passed |
| EC-3 | A column is empty in every row | Type it as string rather than failing inference |

## Out of Scope
Reading Parquet, partitioned output, and writing to object storage. Local file → local file only.

## Open Questions

### Q-1: Which compression codec should be the default?
- (a) `none` — fastest, largest files
- (b) `snappy` — fast, ~40% smaller
- (c) `zstd` — ~2× slower to write, ~55% smaller
**Assumed:** (b) `snappy` — it is what every warehouse reader supports without extra configuration.
**Answer:** (b) snappy. zstd stays available via the flag; revisit when cold-storage cost matters.
````

---

## `specs/SPEC-2-parquet-writer/tech-design.md`

The HOW, its own file beside `spec.md`. Adding it the first time flips the spec `🔵 In Planning →
🟣 Planned` with no version bump; editing it *after* Planned is a substantive change that bumps
`spec.md`'s version. (Its sections are `###`, but `## Open Questions` is deliberately `##` — the
version check exempts that section by `##` boundary and cannot see a `###` one.)

````markdown
# SPEC-2: Parquet Writer — Tech Design

**Designed:** 2026-03-05
**Services:** CLI entry point, writer module

### Component Architecture
`Writer` takes the reader's `Schema` plus a byte sink, and exposes `WriteRows(rows) error`. The CLI
owns opening and closing the output file, so the writer itself stays testable against an in-memory
buffer and never touches the filesystem.

### Contracts

| Flag | Type | Default | Notes |
|------|------|---------|-------|
| `--compression` | enum | `snappy` | `none,snappy,gzip,zstd`; invalid value exits 2 (AC-3) |
| `--force` | bool | `false` | Overwrite an existing output file (EC-2) |

### Security Considerations
The output path is caller-supplied: resolve it to its canonical form and refuse to follow a symlink
that escapes the working directory. No network access and no credentials are involved.

## Open Questions

### Q-1: Should row-group size be tunable in this spec?
- (a) Add `--row-group-size` here
- (b) Ship the library default and split the tuning work out
**Assumed:** (a) — AC-5 asked for it.
**Answer:** (b). Profiling showed the default is right below 2 GB; AC-5 descoped into SPEC-6.
````

---

## `specs/SPEC-2-parquet-writer/audit-trail.md`

The verification record. Its existence tells the status hook verification has happened; it is **not**
version-gated, so writing it never demands a bump. The AC rows are the point of the file — `spec.md`
says each criterion is met, this says what proves it.

````markdown
# SPEC-2: Parquet Writer — Audit Trail

**Branch:** SPEC-2
**Commits:** `a1c9f02..7d3e118`
**Verified:** 2026-03-14

## Summary

Writer built on the reader's schema object rather than re-inferring types, which is the one
deviation from `tech-design.md` — re-inference lost the reader's empty-column decision (EC-3), so
the schema is now threaded through instead.

## Acceptance Criteria — evidence

| AC | Evidence | Where |
|----|----------|-------|
| AC-1 | Writes a file that `pyarrow.parquet.read_table` opens and reads back row-for-row | `tests/test_writer.py::test_writes_readable_parquet` |
| AC-2 | 50k-row fixture round-trips write → read; every column's type asserted equal to the input schema | `tests/integration/test_roundtrip.py::test_types_survive` |
| AC-3 | All four codecs write successfully; default asserted `snappy`; unknown codec exits 2 with no file created | `tests/test_cli.py::test_compression_flag`, `::test_rejects_unknown_codec` |
| AC-4 | Write into a read-only dir exits non-zero and the message contains the path | `tests/test_cli.py::test_unwritable_path` |

AC-5 is unticked and marked DESCOPED in `spec.md` — SPEC-6 carries it. Descoped criteria are not
listed here; their reason belongs in the contract.

## Edge Cases — evidence

| EC | Evidence | Where |
|----|----------|-------|
| EC-1 | Header-only CSV produces a valid file with the schema and zero rows, exit 0 | `tests/integration/test_roundtrip.py::test_empty_input` |
| EC-2 | Existing output left byte-identical on exit 1; overwritten on exit 0 with `--force` | `tests/test_cli.py::test_refuses_overwrite` |
| EC-3 | All-empty column types as string, not a failed inference | `tests/integration/test_roundtrip.py::test_empty_column` |

## Test run

- Command: `pytest`
- Result: 41 passed, 0 failed, 1 skipped
- Run against: `7d3e118`

The skip is `test_zstd_level_tuning` — it needs a zstd build with level support that CI's wheel does
not carry. AC-3 does not depend on it; codec selection is covered by the four-codec test above.

## Deviations & follow-ups

- Row-group sizing (AC-5) → SPEC-6.
- The schema-threading change above widened the reader's public return type; SPEC-1 was bumped to v2
  with a changelog row citing SPEC-2.
````

---

## The matching `specs/INDEX.md` row

The `spec.md` header and its INDEX row are the same fact stored twice, so they must agree — a hook
fails your commit if they drift. The `File` link points at the folder's `spec.md`:

````markdown
| ID | Spec | Priority | Status | Version | File | Created |
|----|------|----------|--------|---------|------|---------|
| SPEC-1 | CSV Reader | P0 (MVP) | Validated | v2 | [Spec](SPEC-1-csv-reader/spec.md) | 2026-03-01 |
| SPEC-2 | Parquet Writer | P0 (MVP) | Validated | v3 | [Spec](SPEC-2-parquet-writer/spec.md) | 2026-03-02 |
| SPEC-6 | Row-Group Tuning | P2 (Later) | In Planning | v1 | [Spec](SPEC-6-row-group-tuning/spec.md) | 2026-03-14 |
````

---

## What to notice

**The status is stored twice, on purpose.** `**Status:** 🟢 Validated` in `spec.md`'s header and
`Validated` in the INDEX row. `check-status-sync.sh` blocks the commit if they disagree, if the word
isn't one of the six legal tokens, or if the status *lags reality* — a spec whose folder has an
`audit-trail.md` can't still claim `In Progress`.

**Acceptance criteria are the definition of done.** Once `audit-trail.md` exists,
`check-ac-closeout.sh` blocks the commit while any `- [ ] AC-N` remains unticked in `spec.md` —
unless that line says `DESCOPED`. That's the only escape hatch, and it costs you a written reason,
which is why AC-5 explains itself and names the spec that inherited it.

**A ticked box must say what closed it.** The same check also blocks the commit if an AC ticked in
`spec.md` is never cited in `audit-trail.md`. That's why the trail carries a row per AC naming a real
test path: `spec.md` records the *claim*, the trail records the *evidence*, and neither file can
assert done on its own. It's also what stops the trail from decaying into a one-line "tests pass" —
the mapping from criterion to test exists in no other file, so if it isn't written here it is lost.

**The changelog records why, not just what.** The `Driver` column names the `SPEC-N` whose work
forced the change — `SPEC-4` widened the writer contract, `SPEC-6` took over row-group tuning — or
`self` for a purely internal revision. Once a spec is `🟣 Planned` or later, any substantive edit to
`spec.md` or `tech-design.md` must bump `**Version:**` and add a row to `spec.md`'s changelog, and
`check-spec-version.sh` enforces it. Ticking a checkbox, advancing the status, and writing
`audit-trail.md` are all explicitly *not* substantive, so the normal implement → verify →
close-out pass needs no bumps.

**Open questions are a ledger, not a queue.** Both `Q-1` blocks here are *answered* and they stayed in
the file — that is the point. While `**Answer:**` was empty, `check-open-questions.sh` held the spec
at `🔵 In Planning` (a `spec.md` question) or `🟣 Planned` (a `tech-design.md` one), so nothing was
built on an unconfirmed guess; once answered, the block is the record of why the codec is `snappy` and
why row-group tuning left this spec. Editing the section never demands a version bump — but what the
answer *changed* did, which is why the `v2` row cites `Q-1`. This is also where a command running
unattended (`interaction.mode: "file"`) parks everything it had to decide for you, with its
`**Assumed:**` answer visible; see the README's *Running unattended*.

**Dependencies are declared, not implied.** `Requires: SPEC-1` is what makes the build order in
`specs/INDEX.md` meaningful, and it's what tells you which other specs to re-check when a contract
moves.

**Superseded specs are never rewritten.** Had this feature been dropped instead of shipped, `spec.md`
would carry `⚫ Deprecated`, a final changelog row citing the obsoleting spec, and a short
`## Deprecation` note — and the folder would stay as a tombstone so the history remains traceable.

The blank template `spec.md` comes from lives at `.spec-workflow/templates/spec.template.md` in your
project after install.
