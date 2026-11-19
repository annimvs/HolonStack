# RECORDS

> **AGENTS: maintain this file with Haiku or a similar-class model, in grok'd prose.** Style rules: [QUIET](QUIET.md), [PROSE](PROSE.md).

Each record is one closure file, and only `.agents/harness/bin/write` writes it. Agents read the `.closure` files. The `.md` files are views for people. [NOTATION](NOTATION.md) covers the notation, the templates and the draft form.

Everything lives under `.agents/records/`: the stores, their views, `drafts/`, the `.ids` ledger and the lock. Paths below are relative to that folder. `templates/` and `reasons.closure` stay at the top of `.agents/`. Template `// store:` paths are read relative to `records/`.

| Kind | Stored at | Use for |
|---|---|---|
| `plan` | `PLAN.closure` (one per project) | the title, synopsis and abstract, and the ordered list of its phases |
| `phase` | `PHASES/phase-<nn>-<slug>.closure` | a stage of the plan: `depends` on other phases and its `tasks` (nested, each with its own id, `est` and `done`) |
| `task` | `TASKS/task-<slug>.closure`, indexed by `TODO.closure` | ad-hoc work not worth a phase |
| `memory` | `MEMORIES/memory-<slug>.closure` | a fact or preference to carry between sessions: `user`, `feedback`, `project` or `reference` |
| `question` | `QUESTIONS/question-<slug>.closure` | something blocked on the user; `status` is `open`, `answered` or `dropped` |
| `proposal` | `PROPOSALS/proposal-<slug>.closure`, listed in `PROPOSALS.md` | work proposed to the user: a summary, numbered `steps` with `points`, what is `yours` to do, and an `ask`; `status` is `open`, `accepted`, `rejected` or `done`. Needs `templates/proposal.closure` |
| `issue` | `ISSUES/issue-<slug>.closure`, listed in `BUGS.md` | a confirmed bug: `area`, `repro`, `status` (`open`, `fixed`, `wontfix`) and, once closed, `fix`. Needs `templates/issue.closure` |
| `semantics` | `SEMANTICS/semantics-<name>.closure` | one area's card for `route-semantics`: `scope` (`always` or `routed`), the `paths` and `cues` that select it, and what `holds`, its `terms` and the files `next`. Written as statements, not orders. Needs `templates/semantics.closure` |
| `result` | `RESULTS/result-<slug>.closure` | what a delegated worker reports when it stops: `status` (`done`, `failed` or `blocked`), a prose `report` and the files it `touched`. `write status` prints the ones not yet reported ([DELEGATION](DELEGATION.md)). Needs `templates/result.closure` |
| `interface` | `INTERFACES/interface-<slug>.closure` | the contract of one command: its `command_api` line, `inputs`, `output` and `error_exit`. No tool reads it yet, and nothing has filed one. Needs `templates/interface.closure` |

```sh
.agents/harness/bin/write phase check-draft draft.closure   # first-write check, writes nothing
.agents/harness/bin/write plan new draft.closure            # also: phase, task, memory, question ("-" reads stdin)
.agents/harness/bin/write check [path…]                     # every record, or the paths; exit 1 on any problem
.agents/harness/bin/write lint [--fix] file…                # syntax and canonical form of any .closure file
.agents/harness/bin/write list [kind]    get <id>    next   # read: one line each, the file, the next phase
.agents/harness/bin/write done <id>      reopen <id>        # tick or untick a task; done runs its criteria first (nothing is committed)
.agents/harness/bin/write answer <id> "text"                # answer a question
.agents/harness/bin/write fix <id> "where"                  # close an issue, saying where it was fixed
.agents/harness/bin/write set <id|plan> <field> <value>     # update a scalar, grok, text or enum field on a record or nested task
.agents/harness/bin/write link|unlink <id> <field> <ref>    # add or remove a ref in a list field (such as depends)
.agents/harness/bin/write move <id> before|after <id>       # reorder a phase in PLAN.closure, a task in TODO.closure, or a nested task
.agents/harness/bin/write del <task-id>                     # remove a nested task inside an open phase
.agents/harness/bin/write show <draft | proposal>            # a proposal in reply style, without ids
.agents/harness/bin/write accept <proposal>  reject <proposal>   # record the user's decision (id or a name word)
.agents/harness/bin/write render                            # regenerate MEMORY.md and OPEN.md
```

Every writing command prints one JSON envelope and takes the lock `.write.lock`.

- **The writer generates ids.** An id is 8 lowercase hex characters, recorded in the `.ids` ledger and never reused. Don't type one into a draft; write `_`. An id lives inside its record and in refs. It never goes in a file name, because tools find a record by id and file names are for people.
- **The writer generates file names.** A name is `<kind>[-<nn>]-<slug>`. `nn` is the zero-padded phase number, so a listing sorts in work order. The slug is the first 8 ASCII words of `name`, fixed at creation. `check` verifies the pattern, not that the slug still matches the name. A name that collides with an existing file is refused: edit that record or pick another name.
- **Phase numbers never change.** `n` is set once and never reused. Gaps are allowed. Work order comes from `depends`, not from position: `write next` names the first phase that is not done and whose `depends` are done. A phase is done when it has tasks and all of them are `done`. That is derived, never stored.
- **Search before you add.** Run `write list` on the kind, and edit the existing record rather than filing a duplicate.
- **To change a record, use `write set`, `link`, `unlink`, `move`, `del`, `done`, `reopen`, `answer`, or `fix`, or edit its file.** `check-edit` then lints it and checks it against its template. `PLAN.closure` is updated through `write set plan <field> <value>` and `write move`.
- **Finished records stay.** Tick `done` instead of deleting. `write del <task-id>` removes only a nested task inside an open phase, never a stored top-level record. The shell can't delete or move one either: `guards.d/records-delete.json` refuses `rm`, `mv`, `unlink` and `trash` of a stored record. Drafts are yours to remove.
- **Memory entries hold what the code and git history don't say, plus the reason.** Link related entries with `[[id]]` in the `body`.
- **Ask instead of guessing.** File a `question` for anything open, and state in `context` the default you will use. [OPEN.md](../../records/OPEN.md) lists the open ones for the user.

## Views for people

`write render` generates these views and refreshes them after every write, including `write done`:

- `PLAN.md`: the plan as a checklist. Each phase and its tasks appear, ticked as they are done, with estimates before names and no ids.
- `TODO.md`: the ad-hoc tasks in `TASKS/`, open ones first, then a Done list, each with its estimate and a link to its record.
- `MEMORY.md`: one line per memory.
- `OPEN.md`: unresolved questions.
- `BUGS.md` and `PROPOSALS.md`.

`PLAN.md` appears once a plan is filed. Never edit these by hand. Agents don't need them, except that tools auto-load `MEMORY.md`. `check` warns when one is stale.

## Drafts and escalation

Write drafts in `.agents/records/drafts/`. Fields in a draft can come in any order. A line break inside a one-line field becomes a space. The writer stores the fields in the template's order, with that joined line.

- **Every save is checked.** Saving a draft there makes `check-edit` run `write check-draft` and show you the errors.
- **A failing draft blocks the end of your turn.** The `Stop` and `SubagentStop` hook `check-drafts` refuses to end your turn while a draft you wrote fails, and shows the errors again.
- **If you can't fix a draft, give a reason code.** Make the draft's first line `// cannot fix: <code>: <one-line note>`, using a code from [`reasons.closure`](../reasons.closure), then finish. The hook writes `<draft>.escalate`, a closure record holding the code, its route and the checker output. A code not in the list is refused. Stopping twice with a failing draft escalates it with reason `none`.
- **Routes:** `model` sends the draft to a stronger model, `user` needs your decision, and `harness` means the tool or a template is wrong. Only the user edits `reasons.closure`.

## What the hooks refuse

The hook [`hooks/guard-edit.swift`](../hooks/guard-edit.swift) blocks an Edit or Write to `PLAN.closure`, `PLAN.md`, `TODO.closure`, `TODO.md`, `MEMORY.md`, `OPEN.md`, `BUGS.md`, `PROPOSALS.md`, `.ids`, `.write.lock` and anything under `templates/`. Only the writer changes the indexes and views, and only the user changes the rest. [`hooks/check-edit.swift`](../hooks/check-edit.swift) lints any edited `.closure` file and checks each record against its template. [`hooks/guard-bash.swift`](../hooks/guard-bash.swift) refuses a shell command that redirects, `tee`s, `sed -i`s, `rm`s, `mv`s or `cp`s onto a protected path. It checks what each command writes to, so a command that only mentions a record path in text passes. It cannot see a target built in a variable.

## Changing the writer

[`tools/write.swift`](../tools/write.swift) is JIT Swift ([SCRIPTS](SCRIPTS.md)). After a change, run `write check` over the store and `write check-draft` on a draft that exercises the change.

## Measuring first-write determinism

Run `write measure <dir>` on a folder of drafts, one per sampled run of the same prompt. It reports the share that pass `check-draft` on the first write, and how many distinct skeletons the passing ones have. A skeleton is the draft with strings blanked and ids, durations and numbers replaced by their type. `loose` also collapses repeated list items. A low pass rate, or many skeletons for one prompt, means the template or the instructions need work.

## Criteria and the done gate

A task can carry `criteria`: conditions that must be true when it is done, each with a `check`. The check is a shell command that exits 0 when the condition holds, or the word `manual`. Write criteria when the task is filed, from the goal and not from the steps, for example `text: "The like survives a reload"`.

`write done <task-id>` runs every check from the project folder and prints one line each: `pass`, `confirmed` or `FAIL`. A failing check shows its command, its exit status and the last lines of its output, and the task stays open. A `manual` criterion passes only when you give a confirmation: `write done <task-id> --confirmed "who checked what"`. When all pass, the task is ticked and the evidence lines are printed with the result. Nothing is committed: commits are the user's. A task with no criteria is ticked as it is.

Criteria are fixed once filed. `guard-edit` refuses an agent edit that changes them, so a builder cannot loosen its own check; only the user changes them. The Bash guard also refuses a shell write into a phase or task record when the command mentions criteria or checks, but it matches the command text, so a script that builds the change from variables could slip past. A check is only as good as its command, so read what each one runs before you accept the plan.
