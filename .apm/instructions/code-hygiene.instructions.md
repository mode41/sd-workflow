---
description: Post-change hygiene — remove dead code and keep architecture, docs, and specs consistent with reality.
---

# Code Hygiene

After finishing and testing a change, leave the codebase clean:

- **No zombie code.** Remove dead branches, unused helpers, commented-out blocks, and workarounds the
  change has superseded. A change is not done while its predecessor is still lying around.
- **Keep the architecture source of truth true.** If the change makes the project's architecture
  documentation inconsistent with the codebase, fix it: update it in place when the context map
  (`.spec-workflow/context-map.md`, `kind=architecture`; default `ARCHITECTURE.md`) resolves it to a
  repo file; when it resolves to an external tool or provider you cannot edit, flag the drift for a
  human. Honor the map's `context-schema:` front-matter — this core supports `1`; on an unsupported
  value note `context schema N unsupported` and fall back to the default.
- **Keep documentation true.** Update user documentation and specs whenever a change makes them
  outdated — including specs other than the one you are implementing.
