---
name: edit
description: Change a project file with the exact-match edit tool: read, replace text or whole line ranges, create files. Use for every change to a project file, since the built-in Edit and Write tools are steered here.
---

> **AGENTS: maintain this file with Haiku or a similar-class model, in grok'd prose.** Style rules: `.agents/harness/rules/QUIET.md`, `.agents/harness/rules/PROSE.md`.

# edit

`.agents/harness/bin/edit` changes one file at a time, checks that it has not changed under you, and prints a diff and the new hash. The full rules are in `.agents/harness/rules/EDITING.md`; `edit --help` lists every flag.

1. **Find the place with `seek`,** which prints the file hash and the line range of the unit: `seek TERM PATH` → `== FILE hash H`, `A-B label`.
2. **Replace text:** `edit FILE --hash H --old TEXT --new TEXT`. The old text must match once; add `--at LINE`, `--after TEXT` or `--before TEXT` to narrow it, `--all` for every match. Several pairs, or text with awkward quoting, go in `--batch-file F|-` as JSON `[{"old","new"}]`.
3. **Replace whole lines:** `edit FILE --hash H --range A-B --new TEXT` (or `--new-file F`, `-` for stdin) swaps lines A to B; `--range A-B --delete` removes them. `--range` with `--old` searches only those lines. `edit FILE --read --range A-B` prints just them.
4. **Create:** `edit FILE --create --content-file -` with the text on stdin; it never overwrites.
5. **Preview:** `--check` prints the diff and writes nothing.

The hash comes from `seek`, `--read` or the last edit. Exit codes: 1 no match, 2 ambiguous (candidates listed), 3 stale hash (read again), 4 file exists, 5 binary or over 8 MB, 64 usage. After the edit the lint and record checks run on their own. Records the writer owns still go through `bin/write`.
