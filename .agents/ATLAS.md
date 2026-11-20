# ATLAS — HolonStack

> **AGENTS: maintain this file with Haiku or a similar-class model, in grok'd prose.** Style rules: [QUIET](harness/rules/QUIET.md), [PROSE](harness/rules/PROSE.md).

Add, remove or rename a file under `.agents/` → update its row here in the same change. Detail files are linked, not imported. Open only the row you need. The project is the HolonStack repository above `.agents/`, and every path in these docs is relative to that folder.

## Before any work

1. **Replies are prose; records are closures.** Anything a script or another agent reads (a plan, a task, a memory, a question) is a closure filed through `harness/bin/write`. What you say to the user is plain prose drawn from it ([NOTATION](harness/rules/NOTATION.md)).
2. **Read memory and open work first:** [MEMORY.md](records/MEMORY.md), then `harness/bin/write list task` and `write next`. Something blocked on the user is a `question` ([OPEN.md](records/OPEN.md)).
3. **Never commit.** `write done` ticks a task after its criteria pass and commits nothing; commits in this project are the user's.
4. **Behavior is verified, not argued:** verify harness changes with `./scripts/smoke-test.sh` plus `write check`, `check-docs`, `lint`, and `sync-settings --check`, never by reading the source alone.

## State

| Path | Open when | Detail |
|---|---|---|
| `records/MEMORIES/`, [records/MEMORY.md](records/MEMORY.md) | Starting a task; saving a fact for later. `MEMORY.md` is the generated index, one line per memory | [RECORDS](harness/rules/RECORDS.md) |
| `records/PLAN.closure`, `records/PHASES/`, `records/PLAN.md` | Phased work and what comes next (`write next`). `PLAN.md`, the generated checklist, appears once a plan is filed | [RECORDS](harness/rules/RECORDS.md) |
| `records/TODO.closure`, `records/TASKS/`, [records/TODO.md](records/TODO.md) | Ad-hoc open work, each task with the `criteria` its `check:` commands prove; `TODO.md` is the generated list, open tasks first | [RECORDS](harness/rules/RECORDS.md) |
| `records/QUESTIONS/`, [records/OPEN.md](records/OPEN.md) | Something is blocked on the user; `OPEN.md` lists the open ones | [RECORDS](harness/rules/RECORDS.md) |
| `records/ISSUES/`, [records/BUGS.md](records/BUGS.md) | A confirmed bug: file an `issue` with its repro; `BUGS.md` lists open and fixed ones | [RECORDS](harness/rules/RECORDS.md) |
| `records/AUDITS/`, [records/AUDIT.md](records/AUDIT.md) | Architectural, doc, modularity, pattern or language-rule findings from `/holon-audit`; `AUDIT.md` lists them by status, impact and effort | [holon-audit](harness/skills/holon-audit/SKILL.md) |
| `records/PROPOSALS/`, [records/PROPOSALS.md](records/PROPOSALS.md) | Proposing multi-step work to the user (`write show` renders it as the reply) | [QUIET](harness/rules/QUIET.md) |
| `records/FINDINGS/`, `records/CATALOG/`, `records/DESIGN/` | A cost finding with a check; the catalog of what Swift ships for a structure or algorithm; design notes | [PERF](harness/rules/PERF.md), [DESIGN](harness/rules/DESIGN.md) |
| `records/SEMANTICS/`, [records/SEMANTICS.md](records/SEMANTICS.md) | Changing what an area's card says, or adding an area: `route-semantics` adds the matching card to the context by prompt words or file path, and the `always` card with it as the transcript grows; `semantics-report` writes the `SEMANTICS.md` scoreboard. `write list semantics` lists them | [harness/README.md](harness/README.md) |
| `records/RESULTS/`, `records/INTERFACES/` | A delegated worker's `result` (status, report, files touched; `write status` lists the unread ones), and a command's `interface` contract. Both stores appear when the first record is filed | [RECORDS](harness/rules/RECORDS.md), [DELEGATION](harness/rules/DELEGATION.md) |
| `records/drafts/` | Writing a draft before filing it; every save is checked, and a failing draft can't be left behind | [ESCALATION](harness/rules/ESCALATION.md) |
| `records/.ids`, `records/.write.lock` | The id ledger and the writer's lock; never edit | [RECORDS](harness/rules/RECORDS.md) |

## The code

| Path | Open when | Detail |
|---|---|---|
| `codebase/CODEBASE.md` | Orienting in HolonStack's components, layers, glossary, or deciding where a change belongs | [CODEBASE.md](codebase/CODEBASE.md) |
| `codebase/LIFECYCLE.md` | Following hook dispatch, `bootstrap.sh` / `sync-settings`, or record writes end to end | [LIFECYCLE.md](codebase/LIFECYCLE.md) |

### Maps: which file owns what

| Area | Open when | Map |
|---|---|---|
| `adopt-holon/` | Changing the `/adopt-holon` skill entrypoint, stubs, or shipped template bundle | [adopt-holon](codebase/maps/adopt-holon.md) |
| `harness/hooks/`, `harness/guards.d/` | Changing a lifecycle hook, client wiring sync, or Bash regex guard | [harness-hooks](codebase/maps/harness-hooks.md) |
| `harness/tools/`, `harness/bin/` | Changing `write`, `edit`, `seek`, `isolate`, `lint`, `check-docs`, or `bootstrap.sh` | [harness-tools](codebase/maps/harness-tools.md) |
| `scripts/`, `.github/` | Changing end-to-end smoke verification or CI workflows | [scripts-and-ci](codebase/maps/scripts-and-ci.md) |

## Domain references

| Path | Open when | Detail |
|---|---|---|
| `reference/` | Index of all downloaded upstream agent-platform and standard specs | [reference/README.md](reference/README.md) |
| `reference/CLAUDE_CODE/` | Verifying Claude Code hooks, tool-use schemas, skills, settings, `CLAUDE.md`, or subagent contracts | [reference/README.md](reference/README.md) |
| `reference/ANTIGRAVITY/` | Verifying Antigravity or Gemini CLI hooks, skills, rules, or plugin specs | [reference/README.md](reference/README.md) |
| `reference/OPENAI/` | Verifying OpenAI Codex CLI hooks, skills, rules, subagents, `AGENTS.md`, or function-calling specs | [reference/README.md](reference/README.md) |
| `reference/STANDARDS/` | Checking cross-client Agent Skills (`agentskills.io`) or `AGENTS.md` specifications | [reference/README.md](reference/README.md) |

## Harness

| Path | Open when | Detail |
|---|---|---|
| `harness/` | Understanding the machinery: closures, the writer, the guards, what is not built yet | [harness/README.md](harness/README.md) |
| `harness/HARNESS.md` | Seeing the harness as diagrams: what enforces and what advises, what runs on each hook event, one record write | [HARNESS.md](harness/HARNESS.md) |
| `harness/templates/*.closure` | The fields, limits and store path of a record kind; edited only by the user | [NOTATION](harness/rules/NOTATION.md) |
| `harness/reasons.closure` | The reason codes a stuck draft may cite, and where each goes; edited only by the user | [ESCALATION](harness/rules/ESCALATION.md) |
| `harness/lint.closure`, `harness/tools/lint.swift` | The Swift lint rules and their checker, run on every saved `.swift` under `harness/` | [SWIFT](harness/rules/SWIFT.md) |
| `harness/hooks/`, `harness/hooks.json`, `harness/guards.d/`, `hooks.json` | What runs on each tool call (including `rewrite-bash`, which sends build commands through `bin/filter-run` and keeps the full log), and the project's own Bash rules (`guards.d/`: `adopt-template-records`, `criteria-bash`, `python-scripts`, `records-delete`). `sync-settings` generates the wiring, including the top-level `.agents/hooks.json`: never edit it | [harness/README.md](harness/README.md) |
| `harness/.cache/`, `harness/.swift-format` | Built `bin/` binaries, per-session semantics state, and the compaction archive; all regenerated or machine-written. The formatter config for the lint | [harness/README.md](harness/README.md) |
| `harness/tools/edit.swift` | Changing a project file: the exact-match editor (`bin/edit`) agents use in place of the built-in Edit and Write tools. `check-shell-edit` runs the Edit checks after each call, and `guard-bash` and `guard-edit` hold it to the same protected files and worker claims. `--range A-B` replaces, deletes or reads whole lines | [EDITING](harness/rules/EDITING.md) |
| `harness/tools/seek.swift`, `harness/hooks/guard-search.swift` | Finding code, docs or records: `bin/seek TERM [PATH…]` returns the whole unit around each hit with its line range and file hash, the input to `edit --range`. `guard-search` steers grep and rg on project paths to it (`HOLON_GREP_GUARD`: `off`, `advise` default, `deny`) | [seek skill](harness/skills/seek/SKILL.md) |
| `harness/tools/isolate.swift`, `harness/hooks/guard-agent.swift` | Choosing parallel workers that cannot touch each other's compile inputs: `isolate` reads the project's build manifests and files claims; `guard-agent` refuses spawning a project-editing subagent without an unbound claim named in its prompt (exempt: read-only types or `[unrestricted]` / `[read-only]`) | [DELEGATION](harness/rules/DELEGATION.md) |
| `harness/hooks/route-semantics.swift` | A semantics card appeared in the context, or did not when it should have: how a card is picked, when it comes back, and where its state lives | [harness/README.md](harness/README.md) |
| `harness/bin/bootstrap.sh`, `harness/bin/` | Bootstrapping and calling a tool or hook by name: `bootstrap.sh` runs `sync-settings` to generate the `bin/` entry points and compiles `hooks/*.swift` and `tools/*.swift` with `swiftc` into `.cache/bin/` | [SCRIPTS](harness/rules/SCRIPTS.md) |
| `harness/skills/closure-system/` | A walkthrough of drafting, checking and filing a record | [SKILL.md](harness/skills/closure-system/SKILL.md) |
| `harness/skills/seek/`, `edit/` | Searching the project and changing a file: the commands, the seek-then-edit loop, exit codes | [seek](harness/skills/seek/SKILL.md), [edit](harness/skills/edit/SKILL.md) |
| `harness/skills/log-bug/`, `remember/`, `plan-and-enact/`, `work-queue/`, `inject-context/`, `holon-audit/` | Filing a confirmed bug, saving a memory, planning and carrying out multi-step work, draining queued tasks via `isolate` claims, loading the latest Claude/Gemini Markdown transcript, or running a structured codebase audit | [log-bug](harness/skills/log-bug/SKILL.md), [remember](harness/skills/remember/SKILL.md), [plan-and-enact](harness/skills/plan-and-enact/SKILL.md), [work-queue](harness/skills/work-queue/SKILL.md), [inject-context](harness/skills/inject-context/SKILL.md), [holon-audit](harness/skills/holon-audit/SKILL.md) |
| `harness/guards.d/records-delete.json` | A command was refused for deleting or moving a stored record from the shell | [RECORDS](harness/rules/RECORDS.md) |

## Rules

| Rule | Open when |
|---|---|
| [ACCESS](harness/rules/ACCESS.md) | Before anything else: what an agent may do here |
| [QUIET](harness/rules/QUIET.md) | Every reply: how much to say, asking the user to choose, saying nothing while you wait |
| [READ](harness/rules/READ.md) | Before you say you did not read or check something: how to follow ATLAS and `seek`, the reading bound, and the honest fallback |
| [COMPACT](harness/rules/COMPACT.md) | Before a compaction and right after one: what to file as records first, what the compaction hooks archive and re-inject |
| [PROSE](harness/rules/PROSE.md) | Writing anything here (docs, rules, records, comments, replies): the filler words to cut, facts over narration, point at the code |
| [GROK](harness/rules/GROK.md) | Writing any reply, doc or free-prose slot |
| [NOTATION](harness/rules/NOTATION.md) | Writing a record, a plan or a procedure a script will read |
| [RECORDS](harness/rules/RECORDS.md) | Saving a plan, phase, task, memory, question or issue |
| [ESCALATION](harness/rules/ESCALATION.md) | A draft could not be fixed |
| [VERIFICATION](harness/rules/VERIFICATION.md) | Before marking a task done |
| [PRACTICES](harness/rules/PRACTICES.md) | Designing or restructuring docs, tools, hooks or records |
| [SCRIPTS](harness/rules/SCRIPTS.md) | You need a script or a hook: one `.swift` file (run with `swift`, `holon`, or its `bin/` entry point), never Python |
| [SWIFT](harness/rules/SWIFT.md) | Writing any Swift here: the MARK conventions apply to all project code; the concurrency, comment and lint rules to `harness/` |
| [DESIGN](harness/rules/DESIGN.md) | Building a new type, collection, algorithm or pipeline |
| [PERF](harness/rules/PERF.md) | Judging the cost of existing code |
| [TESTS](harness/rules/TESTS.md) | Ordering fixes for a list of test or suite failures: cluster by cause, most cleared per fix first |
| [ROLLBACK](harness/rules/ROLLBACK.md) | Before a change that deletes, overwrites or rewrites many files |
| [PROJECT](harness/rules/PROJECT.md) | Writing any doc here: project facts only, the code wins |
| [DELEGATION](harness/rules/DELEGATION.md) | Handing work to a subagent |
| [CLEANUP](harness/rules/CLEANUP.md) | Temporary files and workspace hygiene |
| [EDITING](harness/rules/EDITING.md) | Changing a project file: the `edit` tool, its flags and exit codes, and what the guards do about the built-in Edit tool |
