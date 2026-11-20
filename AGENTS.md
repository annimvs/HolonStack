# AGENTS — HolonStack

> **AGENTS: maintain this file with Haiku or a similar-class model, in grok'd prose.** Style rules: [QUIET](.agents/harness/rules/QUIET.md), [PROSE](.agents/harness/rules/PROSE.md).

This folder holds **HolonStack**: the portable `.agents/` harness, Swift 6 CLI tools and hooks, and structured `.closure` record system shipped as the installable `/adopt-holon` skill bundle (`adopt-holon/`). Root `.agents/` dogfoods the harness for HolonStack itself (with project-specific maps, upstream agent-platform specs in `.agents/reference/`, and live records in `.agents/records/`); `adopt-holon/.agents/` is the clean template bundle copied into adopting repositories, verified end-to-end by `scripts/smoke-test.sh`. All paths in docs, records, and hooks resolve relative to this repository root.

Start at [.agents/ATLAS.md](.agents/ATLAS.md): it maps every path under `.agents/` to a detail file. Open only the one you need. `CLAUDE.md` and `GEMINI.md` link to this file.

- **Replies are prose; records are closures.** File plans, tasks, memories and questions through `.agents/harness/bin/write`; tell the user in plain prose.
- **Never commit or push** unless the user asks.
- **Change project files with `.agents/harness/bin/edit`:** `edit FILE --read`, then `edit FILE --hash H --old … --new …` ([EDITING](.agents/harness/rules/EDITING.md)). The built-in Edit and Write tools are refused on project files.
- **Keep the map current:** add, remove or rename a file under `.agents/` → update its ATLAS row in the same change.

## Compact instructions

When compacting, keep what the records don't hold: the current goal, files mid-edit with exact paths, the last failing command and its error, and rejected approaches with the reason. Point at records by id instead of restating them. Before a compaction, file decisions, open questions and unfinished work as records. Details: [COMPACT](.agents/harness/rules/COMPACT.md).
