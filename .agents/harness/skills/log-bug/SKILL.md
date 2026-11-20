---
name: log-bug
description: Log, check or close a confirmed bug as an issue record. Use the moment a defect is confirmed (before or after fixing it), and before fixing anything, to check whether it is already known.
---

> **AGENTS: maintain this file with Haiku or a similar-class model, in grok'd prose.** Style rules: `.agents/harness/rules/QUIET.md`, `.agents/harness/rules/PROSE.md`.

# log-bug

Bugs are `issue` records in `.agents/records/ISSUES/`, filed only through `.agents/harness/bin/write`. The form is `.agents/harness/templates/issue.closure`, and `.agents/harness/rules/RECORDS.md` covers drafts. `records/BUGS.md` lists them for people.

1. **Check first.** Run `.agents/harness/bin/write list issue`, then `write get <id>` for any that looks like yours. Don't log a duplicate, and don't fix a logged bug without saying which one.
2. **Log only what is confirmed.** It has to reproduce against the current build or test suite. A suspicion is not a bug.
3. **Write a draft** in `.agents/records/drafts/<short-name>.closure`:

   ```
   issue(_) {
     name: "Parser drops trailing empty line in block"
     area: "parser"
     status: open
     repro: """
       swift test --filter BlockParserTests.testTrailingEmptyLine
       Actual: count is 1; expected: count is 2.
       """
   }
   ```

   Put the exact repro command or input in `repro`, then what the code does, then what it should do.
4. **File it** with `.agents/harness/bin/write issue new .agents/records/drafts/<short-name>.closure`, and delete the draft once it is filed.
5. **When it is fixed,** run `write fix <id> "<file or function that fixed it>"`. If it comes back, set `status: open` in its record file; `check-edit` checks the edit.
