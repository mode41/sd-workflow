# A worked example: what a spec actually looks like

This is one complete spec at the end of its life — `🟢 Validated`, version `v3`, close-out written.
It is the same CSV→Parquet CLI the README's *Start here* section uses.

A spec is a **folder**, not a single file. Reading a finished one is the fastest way to understand
the workflow, because every convention the hooks enforce is visible at once: the status header, the
inline changelog, the ticked acceptance criteria, the one deliberately descoped criterion, and the
verification evidence that justifies calling it done.

You don't write this by hand. `/requirements` creates the folder and `spec.md`, `/technical-design
SPEC-2` writes `tech-design.md`, and `/write-tests SPEC-2` plus close-out produce `implementation.md`.

```
specs/SPEC-2-parquet-writer/
  spec.md              # the contract — WHAT (written by /requirements)
  tech-design.md       # the HOW (written by /technical-design)
  implementation.md    # close-out evidence (written at verification/close-out)
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
| v2 | 2026-03-09 | Writer contract takes a compression codec; added AC-3 | SPEC-4 |
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
````

---

## `specs/SPEC-2-parquet-writer/tech-design.md`

The HOW, its own file beside `spec.md`. Adding it the first time flips the spec `🔵 In Planning →
🟣 Planned` with no version bump; editing it *after* Planned is a substantive change that bumps
`spec.md`'s version.

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

### Open Questions
None remaining — the row-group sizing question was resolved by descoping AC-5 into SPEC-6.
````

---

## `specs/SPEC-2-parquet-writer/implementation.md`

The close-out evidence. Its existence tells the status hook verification has happened; it is **not**
version-gated, so writing it never demands a bump.

````markdown
# SPEC-2: Parquet Writer — Implementation & Verification

Implemented on branch `SPEC-2` (commits `a1c9f02..7d3e118`).

- Unit tests cover AC-1, AC-3 and AC-4, including the invalid-codec and unwritable-path branches.
- An integration test round-trips a 50k-row fixture through write → read and asserts every column
  type survives (AC-2). The same fixture family covers EC-1 and EC-3.
- EC-2 is verified by a test asserting exit 1 with the original file byte-identical, then exit 0
  with `--force`.
- Full suite green: 41 tests, 0 failures, run on the branch head.

AC-5 is intentionally unticked and marked DESCOPED in `spec.md`; SPEC-6 carries it.
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
`implementation.md` can't still claim `In Progress`.

**Acceptance criteria are the definition of done.** Once `implementation.md` exists,
`check-ac-closeout.sh` blocks the commit while any `- [ ] AC-N` remains unticked in `spec.md` —
unless that line says `DESCOPED`. That's the only escape hatch, and it costs you a written reason,
which is why AC-5 explains itself and names the spec that inherited it.

**The changelog records why, not just what.** The `Driver` column names the `SPEC-N` whose work
forced the change — `SPEC-4` widened the writer contract, `SPEC-6` took over row-group tuning — or
`self` for a purely internal revision. Once a spec is `🟣 Planned` or later, any substantive edit to
`spec.md` or `tech-design.md` must bump `**Version:**` and add a row to `spec.md`'s changelog, and
`check-spec-version.sh` enforces it. Ticking a checkbox, advancing the status, and writing
`implementation.md` are all explicitly *not* substantive, so the normal implement → verify →
close-out pass needs no bumps.

**Dependencies are declared, not implied.** `Requires: SPEC-1` is what makes the build order in
`specs/INDEX.md` meaningful, and it's what tells you which other specs to re-check when a contract
moves.

**Superseded specs are never rewritten.** Had this feature been dropped instead of shipped, `spec.md`
would carry `⚫ Deprecated`, a final changelog row citing the obsoleting spec, and a short
`## Deprecation` note — and the folder would stay as a tombstone so the history remains traceable.

The blank template `spec.md` comes from lives at `.spec-workflow/templates/spec.template.md` in your
project after install.
