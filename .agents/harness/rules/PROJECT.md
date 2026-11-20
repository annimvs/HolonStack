# PROJECT

> **AGENTS: maintain this file with Haiku or a similar-class model, in grok'd prose.** Style rules: [QUIET](QUIET.md), [PROSE](PROSE.md).

This project's `.md` files hold only knowledge from within the project, nothing a-priori.

Every `.md` here (`AGENTS.md` and `.agents/**`) states only what belongs to this project:
- its paths, targets and packages;
- its contracts, build steps and verification results;
- its known bugs and how a request or command runs.

Do not restate general programming, platform, tool, model or vendor knowledge, and do not guess what the project doesn't say. If a fact isn't in the tree, leave a gap rather than fill it from memory.

The exception is `reference/`, which holds upstream texts as published, each with its source and edition.

**Why:** a doc that mixes outside knowledge with project facts can't be trusted as a map of the project, and outside facts go stale without anyone noticing.

**How to apply:**
- **Before adding a line,** name the file, type or behavior in the project that it describes.
- **Don't restate what the source already holds,** such as a count, a function list or a signature. Link to the source instead.
- **When a doc and the code disagree, the code wins.** Fix the doc in the same change.
