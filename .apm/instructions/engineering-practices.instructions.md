---
description: General engineering practices — discovery before assumption, design principles, and what not to introduce.
---

# Engineering Practices

These rules are stack-agnostic and apply to every change, inside or outside the spec workflow.

## Discovery First

Read the codebase before proposing anything. Match the patterns already established — component
structure, layering, naming, error handling, and folder conventions come from what the project
actually does, not from what is idiomatic elsewhere.

Never assume a framework, library, test runner, or convention the project has not established. If you
cannot find the pattern, discover it or ask — do not invent it.

If a deviation from an existing pattern is warranted, say why, and apply it consistently: either
migrate the existing code too, or flag the remainder explicitly as tech debt. A half-migrated pattern
is worse than either end state.

## Design Principles

KISS, DRY, YAGNI. Solve the problem in front of you at the simplest level that will hold.

- **No premature abstractions.** Three similar lines beat a generic wrapper nobody asked for.
- **No unnecessary dependencies.** Justify every addition — the stack stays lean by default.
- **No catch-all files.** No `utils`, `helpers`, or `types` dumping grounds; colocate code with its
  consumers and export when it is genuinely reused.

## Push Back

If a requested change would introduce a pattern that conflicts with existing code, say so and propose
the better alternative. Do not silently accept an approach you can see is wrong.
