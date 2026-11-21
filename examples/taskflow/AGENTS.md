# AGENTS — TaskFlow (HolonStack sample)

> **AGENTS: maintain this file with Haiku or a similar-class model, in grok'd prose.** Style rules: [QUIET](.agents/harness/rules/QUIET.md), [PROSE](.agents/harness/rules/PROSE.md).

This folder holds **TaskFlow**, a synthetic three-package TypeScript monorepo (`@taskflow/core`, `@taskflow/api`, `@taskflow/cli`) demonstrating an adopted HolonStack `.agents/` workspace with zero PII. All paths in docs, records, and hooks resolve relative to this folder.

Start at [.agents/ATLAS.md](.agents/ATLAS.md): it maps every path under `.agents/` to a detail file. Open only the one you need. `CLAUDE.md` and `GEMINI.md` link to this file.

- **Replies are prose; records are closures.** File plans, tasks, memories and questions through `.agents/harness/bin/write`; tell the user in plain prose.
- **Never commit or push** unless the user asks.
- **Change project files with `.agents/harness/bin/edit`:** `edit FILE --read`, then `edit FILE --hash H --old … --new …` ([EDITING](.agents/harness/rules/EDITING.md)).
- **Keep the map current:** add, remove or rename a file under `.agents/` → update its ATLAS row in the same change.

## Compact instructions

Write compaction summaries in grok'd prose ([GROK](.agents/harness/rules/GROK.md): plain words, short sentences, lead with the point, no filler). Keep only what the records under `.agents/records/` don't hold: the current goal, files mid-edit with exact paths, the last failing command and its error, and rejected approaches with the reason. Point at records by id instead of restating them, and keep the user's instructions for this session word for word. Before a compaction, file decisions, open questions and unfinished work as records. Details: [COMPACT](.agents/harness/rules/COMPACT.md).
