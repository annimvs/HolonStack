---
name: remember
description: Save a fact, preference or correction about the project as a memory record. Use when the user states how they want to work here, corrects an approach, or gives a project fact that the code and git history don't record.
---

> **AGENTS: maintain this file with Haiku or a similar-class model, in grok'd prose.** Style rules: `.agents/harness/rules/QUIET.md`, `.agents/harness/rules/PROSE.md`.

# remember

Memories are `memory` records in `.agents/records/MEMORIES/`, filed only through `.agents/harness/bin/write`. The form is `.agents/harness/templates/memory.closure`. `records/MEMORY.md` is the generated index, one line per memory, and the first thing to read before a task.

1. **Check first.** Run `.agents/harness/bin/write list memory`. If one already covers it, edit that record's file instead of adding a second; `check-edit` checks the edit.
2. **Save only what nothing else says.** Leave out what the code, the docs under `.agents/` or git history already record, and anything that only matters to this conversation.
3. **Write a draft** in `.agents/records/drafts/<short-name>.closure`:

   ```
   memory(_) {
     name: "Keep domain models free of transport types"
     description: "domain targets never import HTTP or database frameworks; map at the boundary"
     type: feedback
     body: """
       The rule in one sentence.
       Why: what happened, or the reason the user gave.
       How to apply: when it applies and what to do then. Link related memories with [[id]].
       """
   }
   ```

   Types:
   - `user` is who the user is.
   - `feedback` is how to work, with the reason.
   - `project` is a goal or constraint.
   - `reference` is where something lives outside the repository.
4. **File it** with `.agents/harness/bin/write memory new .agents/records/drafts/<short-name>.closure`, then delete the draft.

`description` is the line a later session sees in `MEMORY.md`, so write it to say when to open the entry.
