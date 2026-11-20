---
name: seek
description: Search the project for code, docs or records and get whole units with line ranges to act on. Use instead of grep, rg or a full-file Read whenever you look for a name, phrase or the place to change; follow it with `edit --range`.
---

> **AGENTS: maintain this file with Haiku or a similar-class model, in grok'd prose.** Style rules: `.agents/harness/rules/QUIET.md`, `.agents/harness/rules/PROSE.md`.

# seek

`.agents/harness/bin/seek TERM [PATH…]` finds a term and prints the whole unit around each hit: a Swift function or type, a markdown section, or a closure record. Other files get a few lines of context. Each file prints once as `== path #H` (H starts the hash `edit --hash` accepts). Output is compact, about the size of grep -n: per unit, an `A-B  label` line then the hit lines, or `A-B<TAB>text` when the hit is the declaration line itself. `-b` prints whole units instead. Read a unit you want with `edit FILE --read --range A-B`.

1. **Find:** `seek parseRange .agents/harness` (literal; `-i` ignores case, `-w` whole word, `-E` regular expression, `-e TERM` when the term starts with `-`).
2. **Map a big file first:** `seek --outline FILE` lists declarations or headings with ranges and no bodies; add `-e TERM` to keep the matching ones.
3. **Count before reading:** `seek --files TERM PATH` lists the files that hit.
4. **Act on a range:** `edit FILE --hash H --range A-B --new-file F` replaces those lines, `--delete` removes them, `edit FILE --read --range A-B` prints only them. Use the hash `seek` printed; exit 3 means the file changed, so seek again.
5. **Budget:** compact output stops at 200 hit lines and whole-unit output at `--max-lines N` (default 150); later units list as ranges only. Narrow the term or the PATH instead of raising it.

PATH defaults to the current folder. `conformance/` and `reference/` are skipped unless a PATH names them; so are `.git`, `.build` and `.cache`. Swift ranges come from brace depth, so a range inside odd syntax can be off by a line: read it before replacing it. Grep is still right for piped output and for the probes in `conformance/`.
