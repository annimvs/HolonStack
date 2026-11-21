# AGENTS — <Project Name>

> **AGENTS: maintain this file with Haiku or a similar-class model, in grok'd prose.** Style rules: [QUIET](.agents/harness/rules/QUIET.md), [PROSE](.agents/harness/rules/PROSE.md).

<!-- STUB: Run /adopt-holon to replace <Project Name> and this summary with a one-paragraph overview of the project's packages, targets, products, and relative path conventions, and create relative symlinks `CLAUDE.md -> AGENTS.md` and `GEMINI.md -> AGENTS.md` (`ln -s AGENTS.md CLAUDE.md && ln -s AGENTS.md GEMINI.md`). -->
This folder holds `<Project Name>`: replace this stub during `/adopt-holon` with the packages or modules in this workspace, what each product builds, and how paths in docs, records and hooks resolve relative to this root.

Start at [.agents/ATLAS.md](.agents/ATLAS.md): it maps every path under `.agents/` to a detail file. Open only the one you need. `CLAUDE.md` and `GEMINI.md` link to this file.

- **Replies are prose; records are closures.** File plans, tasks, memories and questions through `.agents/harness/bin/write`; tell the user in plain prose.
- **Never commit or push** unless the user asks.
- **Change project files with `.agents/harness/bin/edit`:** `edit FILE --read`, then `edit FILE --hash H --old … --new …` ([EDITING](.agents/harness/rules/EDITING.md)). The built-in Edit and Write tools are refused on project files.
- **Keep the map current:** add, remove or rename a file under `.agents/` → update its ATLAS row in the same change.

## Compact instructions

Write compaction summaries in grok'd prose ([GROK](.agents/harness/rules/GROK.md): plain words, short sentences, lead with the point, no filler). Keep only what the records under `.agents/records/` don't hold: the current goal, files mid-edit with exact paths, the last failing command and its error, and rejected approaches with the reason. Point at records by id instead of restating them, and keep the user's instructions for this session word for word. Before a compaction, file decisions, open questions and unfinished work as records. Details: [COMPACT](.agents/harness/rules/COMPACT.md).
