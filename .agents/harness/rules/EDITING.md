# EDITING

> **AGENTS: maintain this file with Haiku or a similar-class model, in grok'd prose.** Style rules: [QUIET](QUIET.md), [PROSE](PROSE.md).

Change project files with `.agents/harness/bin/edit` ([tools/edit.swift](../tools/edit.swift)), not with a shell redirect or `sed -i`. `edit --help` lists every flag.

- **Read first:** `edit FILE --read` prints the lines with numbers, then `hash: H`.
- **Find first:** `seek TERM [PATH…]` ([seek skill](../skills/seek/SKILL.md)) prints the unit around each hit as `A-B` with the file hash, so you can edit without a separate read.
- **Change:** `edit FILE --hash H --old TEXT --new TEXT`. The text must match exactly once. Narrow it with `--at LINE`, `--after TEXT` or `--before TEXT`, or replace every match with `--all`. `--hash` refuses the change if the file moved since you read it.
- **Whole lines:** `edit FILE --hash H --range A-B --new TEXT` (or `--new-file F`) replaces lines A to B, `--range A-B --delete` removes them, `--read --range A-B` prints only them, and `--range` with `--old` searches only those lines.
- **Several changes at once:** repeat the `--old`/`--new` pair, or pass `--batch-file F` (`-` for stdin) with a JSON array of `{"old","new"}`. They apply together or not at all.
- **Multi-line text:** use `--old-file` and `--new-file` (`-` is stdin) or the JSON batch, so the shell never quotes it.
- **New file:** `edit FILE --create --content-file -`. It never overwrites, and it makes the folders.
- **Preview:** `--check` prints the diff and writes nothing.
- **Exit codes:** 1 no match or I/O error, 2 ambiguous (the matches are listed), 3 stale hash (read again), 4 file exists, 5 binary or over 8 MiB, 64 usage.
- **Checks:** after each call the `check-shell-edit` hook runs the same lint, record and wiring checks as after the Edit tool, and routes the semantics card for the file.
- **Records:** `guard-bash` refuses `edit` on `.agents/records/` except `drafts/`. Use `write` or the Edit tool, which check criteria and templates. Worker claims apply to `edit` as they do to Edit.
- **Shell edits:** in `deny` mode `guard-bash` also refuses a shell command that changes an existing project file: `sed -i`, `perl -i`, `awk -i inplace`, `ed`, `ex`, and a redirect, `tee`, `cp` or `install` onto it. New files, build output, `.cache`, logs, `.agents/records/` and anything outside the project are left alone, as are moves, deletes and links. The message names `edit`.
- **Searching:** `guard-search` steers grep and rg on project paths, and the Grep tool, to `seek`. `HOLON_GREP_GUARD` is `advise` (default, a reminder), `deny` or `off`; `HOLON_ALLOW_GREP=1` skips it once. Piped grep, paths outside the project and `conformance/`, `reference/` are never steered.
- **The built-in tools:** `guard-edit` steers Edit, Write and MultiEdit on project files toward `edit`. The mode is `HOLON_EDIT_GUARD`: `deny` (default) refuses the call, `advise` allows it with a reminder, `off` is silent. `HOLON_ALLOW_BUILTIN_EDIT=1` skips it for one run. Binary types and files outside the project are never steered.
