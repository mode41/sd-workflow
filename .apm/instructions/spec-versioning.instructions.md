---
description: Spec versioning and inline changelog rules — when to bump a spec's Version, what counts as substantive, and how to deprecate.
---

# Spec Versioning & Changelog

Every spec carries a `**Version:**` (`v1`, `v2`, …) and an inline `## Changelog` table
(`| Version | Date | Change | Driver |`). This keeps each spec reflecting what is actually built,
and makes its evolution traceable inline. The rules:

- A spec is a folder: `spec.md` (the contract, which carries `**Version:**` and `## Changelog`),
  `tech-design.md` (the HOW), `implementation.md` (close-out evidence), plus any attachments.
- A spec starts at `v1`. While it is still `🔵 In Planning`, edits are free drafting — no bump.
- Once a spec is `🟣 Planned` or later, **any substantive change** to its `spec.md` or
  `tech-design.md` must bump `**Version:**` and add a `## Changelog` row — both live in `spec.md`, so
  a change to `tech-design.md` is still recorded by bumping `spec.md`. Substantive = changes to
  overview, user stories, acceptance-criteria *text*, edge cases, or tech-design contracts. **Not**
  version-gated (no bump): advancing status, editing the changelog, ticking ACs, `implementation.md`
  (close-out evidence), and attachments (`mockups/`, `source/`, …) — so the normal implement → verify
  → close-out flow needs no bumps.
- The **Driver** column names *why*: the `SPEC-N` whose work drove the change (especially when
  another spec's design/implementation forced this one to change), or `self` for an in-spec
  revision, or `—` for the initial row.
- **Deprecation (drop, don't rewrite):** when a change makes a spec's feature no longer exist,
  deprecate it — set `⚫ Deprecated` in both the spec header and its INDEX row, bump its version +
  add a changelog row citing the obsoleting `SPEC-N`, append a short `## Deprecation` note to
  `spec.md`, and **keep the spec folder as a tombstone** (never delete it). Deprecated specs are
  frozen: the AC-closeout and status-floor checks no longer apply to them.
- `specs/INDEX.md` mirrors each spec's version in a `Version` column for at-a-glance visibility
  (kept updated by the workflow steps; not itself hook-enforced — the spec header + changelog are
  the source of truth).

The shared `.spec-workflow/hooks/check-spec-version.sh` (run as a per-harness finish-boundary hook and
a git pre-commit check) blocks finishing/committing when a Planned-or-later spec changed
substantively — or was deprecated — without a version bump + a new changelog row.

**Git still holds implementation history:** the inline changelog records *spec-level* evolution; code
-level detail lives in git commits (`git log --grep="SPEC-1"`). There is no separate changelog file —
the changelog is inline, per spec.
