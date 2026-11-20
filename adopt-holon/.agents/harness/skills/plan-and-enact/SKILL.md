---
name: plan-and-enact
description: Write multi-step work as a plan with phases and tasks, then work through it task by task. Use for work with several steps across files, or when asked to plan, propose or carry out a larger change.
---

> **AGENTS: maintain this file with Haiku or a similar-class model, in grok'd prose.** Style rules: `.agents/harness/rules/QUIET.md`, `.agents/harness/rules/PROSE.md`.

# plan-and-enact

A plan is one `plan` record (`records/PLAN.closure`) and a `phase` record per stage, each holding its tasks. All of them are filed through `.agents/harness/bin/write`. The forms are `.agents/harness/templates/plan.closure` and `.agents/harness/templates/phase.closure`. Small ad-hoc work is a single `task` instead.

## Plan

1. **Propose before you file** when the user hasn't agreed to the work yet. Write a `proposal` draft and run `write show <draft>`; its output is the reply (`.agents/harness/rules/QUIET.md`).
2. **File the plan,** once: a `plan` draft with a title, a synopsis, an abstract and `phases: []`, then `write plan new <draft>`.
3. **File one draft per phase** with its tasks, using `write phase new <draft>`:

   ```
   phase(_) {
     name: "Add batch validation"
     depends: []
     tasks: [
       task(_) {
         name: "Reject duplicate record identifiers"
         est: 2h
         criteria: [
           criterion(_) {
             text: "duplicate identifier test passes"
             check: "swift test --filter BatchValidatorTests"
           },
         ]
       },
     ]
   }
   ```

   Write each task's criteria from the goal, not from the steps, and give each one a `check:` command that exits 0 when it holds. Criteria are fixed once filed; only the user changes them.
4. **Run `write check`** before you show the plan. `records/PLAN.md` is the checklist people read.

## Enact

1. **Take the next task.** `write next` names the first phase that isn't done and whose `depends` are done; take its first open task.
2. **Check for a design flag.** If `write next` prints a `design` line for a task that adds a new public type, module, or cross-boundary API, follow `.agents/harness/rules/DESIGN.md` and file a `design` record before editing code.
3. **Do the work.** If a test or verification list fails, order the fixes by `.agents/harness/rules/TESTS.md`.
4. **Close it with `write done <task-id>`.** That runs every `check:` and ticks the task only when all pass. A `manual` criterion needs `--confirmed "who checked what"`. Nothing is committed.
5. **If a task can't be done as written,** file a `question` stating the default you would take, and move to a task that doesn't depend on it.
