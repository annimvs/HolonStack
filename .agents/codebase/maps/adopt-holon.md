# MAPS · HolonStack · Skill Bundle (`adopt-holon/`)

> **AGENTS: maintain this file with Haiku or a similar-class model, in grok'd prose.** Style rules: [QUIET](../../harness/rules/QUIET.md), [PROSE](../../harness/rules/PROSE.md).

Which file owns what in `adopt-holon/`. Index: [ATLAS](../../ATLAS.md). Layers: [CODEBASE](../CODEBASE.md); end-to-end flow: [LIFECYCLE](../LIFECYCLE.md). Add, remove or rename a file in these folders → update its row here.

## `adopt-holon/` — distributable `/adopt-holon` skill

| File | Owns |
|---|---|
| `SKILL.md` | `/adopt-holon` skill entrypoint (YAML frontmatter and 6-step adoption workflow) |
| `AGENTS.md` | Root agent-instructions stub copied into adopting repositories (`/adopt-holon` creates relative `CLAUDE.md` and `GEMINI.md` symlinks to it) |
| `.agents/ATLAS.md` | Template map stub populated per adopting repository |
| `.agents/codebase/` | Stub templates for `CODEBASE.md`, `LIFECYCLE.md`, and `maps/module-template.md` |
| `.agents/reference/README.md` | Stub index for the adopting project's domain RFCs and specifications |
| `.agents/records/` | Clean empty template record stores (`.ids`, `SEMANTICS/` core + harness cards, empty views); protected from HolonStack record writes by root `guards.d/adopt-template-records.json` |
| `.agents/harness/` | Portable Swift hooks, CLI tools, closure templates, rules, skills, `hooks.json`, `lint.closure`, `reasons.closure`, and `catalog-seeds/swift/` |
