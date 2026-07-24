---
description: Post-change hygiene — remove dead code and keep architecture, docs, and specs consistent with reality.
---

# Code Hygiene

After finishing and testing a change, leave the codebase clean:

- **No zombie code.** Remove dead branches, unused helpers, commented-out blocks, and workarounds the
  change has superseded. A change is not done while its predecessor is still lying around.
- **Keep `ARCHITECTURE.md` true.** If the change makes it inconsistent with the codebase, update it.
- **Keep documentation true.** Update user documentation and specs whenever a change makes them
  outdated — including specs other than the one you are implementing.
