---
description: How the commands ask you things — terminal interview (ask) vs. questions recorded in the spec for unattended runs (file), the Open Questions block format, and the status ceiling that gates the next phase.
---

# Interaction Mode

Several commands are written to interview a human: `/requirements` clarifies scope and edge cases,
`/technical-design` asks before it guesses, the plan-review pipeline escalates unresolved critical
findings. None of that works when nobody is at the terminal.

**Interaction mode** decides where those questions go. Read it before the first question you would
ask, from `.spec-workflow/config.json`:

```json
{ "interaction": { "mode": "ask" } }
```

- **`ask`** (the default, and what applies when the file or key is absent) — interview the user in the
  terminal, using your harness's single/multiple-choice questions where it supports them.
- **`file`** — do not ask. Record the question in the artifact you own, record the answer you
  **assumed**, and carry on.

## The Open Questions block

One format, three homes — `docs/PRD.md` (project-level questions, `/requirements` Init Mode),
`specs/SPEC-N-*/spec.md` (contract questions, `/requirements` Spec Mode), and
`specs/SPEC-N-*/tech-design.md` (design questions, `/technical-design` and the plan-review pipeline).
Always a `## Open Questions` section — `##`, never `###`, even in `tech-design.md` where the
surrounding headings are `###`; the version check strips sections by `##` boundary and cannot exempt
a `###` one.

```markdown
## Open Questions

### Q-1: Which compression codec is the default?
- (a) snappy — faster writes, ~30% larger files
- (b) zstd — ~2× slower, ~50% smaller
**Assumed:** (b) zstd — AC-2 prioritises storage cost over write latency.
**Answer:**
```

- IDs are `Q-1`, `Q-2`, … numbered per file, like `US-N` / `AC-N` / `EC-N`. Never renumber; a Q-ID
  gets cited in commits and changelog rows.
- Give **concrete options** with their trade-offs, exactly as you would in the terminal. A question
  with no options is a question a human cannot answer quickly.
- **`**Assumed:**`** is mandatory in `file` mode and states what you actually built on, plus the
  one-line reason. Never leave it blank and never invent an assumption you did not use.
- **`**Answer:**`** is the human's line. Leave it **empty**. They write their choice, or `confirmed`
  to accept your assumption.
- **Answered questions stay in the file.** This section is a ledger, not a queue — it is the only
  place the workflow records *why* a decision went the way it did.

## Working in `file` mode

1. **Never block.** Choose the most defensible option, record it as `**Assumed:**`, and finish your
   own artifact on that basis. A command that stops half-done is worse than one that documents a
   guess.
2. **Never silently guess.** Every decision you would have asked about becomes a `Q-N`. If you find
   yourself writing "I'll assume…" anywhere, that is a question.
3. **Skip the approval step.** Where a command says "present for approval" / "wait for Approved",
   write the artifact and hand off instead. Say plainly in your summary how many questions you left
   open and where.
4. **Do not answer your own questions later.** Only a human fills in `**Answer:**`. Reading your own
   `**Assumed:**` back as if it were settled is the one failure mode this whole mechanism exists to
   prevent.

## The gate: an open question stops the next phase

This holds in **both** modes — a question is unanswered no matter how it got there, and a human may
add one by hand to park a spec.

| Unanswered question in | The spec may not advance past |
|---|---|
| `docs/PRD.md` | `🔵 In Planning` — for **every** spec |
| `specs/SPEC-N-*/spec.md` | `🔵 In Planning` |
| `specs/SPEC-N-*/tech-design.md` | `🟣 Planned` |

So `/technical-design` must **refuse to run** on a spec whose `spec.md` still has an unanswered
question, and implementation must not start while `tech-design.md` has one. Check before you start,
and say which `Q-N` is blocking.

`.spec-workflow/hooks/check-open-questions.sh` enforces this as a git pre-commit check, so an agent
that skips the courtesy check is still stopped at commit time. Resolve a block by answering the
question, or by rolling the status back — never by deleting a question you raised.

An open question is a *ceiling*, and nothing imposes a conflicting floor: you may sit on the spec's
branch at `🔵 In Planning` for as long as the question is open, and discuss it freely. No hook fires
while you are talking it through — they run only when you commit.

Writing or answering a question is **not** a substantive change: `check-spec-version.sh` exempts the
whole `## Open Questions` section, so a spec at `🟣 Planned` or later needs no version bump for it.
Whatever the answer then changes in the contract or design *is* substantive and follows the normal
spec-versioning rules — cite the `Q-N` in the changelog row.

## Scope

`/write-tests` asks nothing and is unaffected. `/frontend-architecture` produces a conversational plan
rather than a file it owns, so it has nowhere to park a question — it stays interactive in both modes;
if it needs a decision under `file` mode and the work belongs to a spec, record it in that spec's
`tech-design.md`.
