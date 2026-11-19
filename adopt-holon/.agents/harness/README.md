# README — agent system

> **AGENTS: maintain this file with Haiku or a similar-class model, in grok'd prose.** Style rules: [QUIET](rules/QUIET.md), [PROSE](rules/PROSE.md).

[ATLAS](../ATLAS.md) is the entry point; this file explains the machinery behind it, and [HARNESS.md](HARNESS.md) draws it. `.agents/` splits in two: `harness/` (this folder: templates, rules, hooks, tools, which only the user changes in substance) and `records/` (the state the agents write, only through `bin/write`). Records are closures; replies to the user are prose drawn from them. The `.md` files under `records/` are views for people.

## The bet

A model told to write `()` `[]` `{}` nesting, and C/Swift-shaped pseudocode with a fixed verb set, keeps its output inside that grammar. So the deterministic side stays small: a bracket-counting parser and a template walk, not a heuristic that guesses at prose. The checker's errors are positional, so an agent can fix its own output from the message. Whether the bet holds is measured: `write measure` reports how often a draft passes on the first write and how many distinct skeletons the passing ones have.

## The four layers

| Layer | What | Where | Kept true by |
|---|---|---|---|
| Knowledge | The map and detail docs an agent reads | `.agents/ATLAS.md`, anything it links | The keep-the-map-current rule |
| Rules | How to behave | `harness/rules/` | Reading them; the hooks back the ones a script can decide |
| Records | State: plan, phases, tasks, memories, questions | `.agents/records/`: `PLAN.closure`, `PHASES/`, `TODO.closure` + `TASKS/`, `MEMORIES/`, `QUESTIONS/`, `ISSUES/`, `PROPOSALS/`, `SEMANTICS/`, `drafts/` | `bin/write` and `write check`, against `harness/templates/` |
| Guards | Scripts that run on tool calls | `harness/hooks/`, listed in `harness/hooks.json` | The harness runs them every time |

## The closure system

A *closure* is a record written as nested `()` `[]` `{}`: a name and identity in `()`, fields in `{}`, ordered items in `[]`. Every record in `.agents/` is one, in a `.closure` file. The full grammar and placeholder table are in [rules/NOTATION.md](rules/NOTATION.md); this is the whole idea.

**Three forms of one record.** The agent writes a *draft*, the writer turns it into the *stored* record, and a *view* for people is generated from the stored ones.

```
phase(_) {                                    ← draft: what the agent writes
  name: "Build the template parser"           (ids are `_`; the tool fills them)
  tasks: [
    task(_) { name: "Write the template parser", est: 3h },
  ]
}
```

```
phase(cd88f0cb) {                             ← stored: records/PHASES/cd88f0cb-phase-1-build-the-template-parser.closure
  n: 1
  name: "Build the template parser"
  depends: []
  tasks: [
    task(e8ff9144) {
      name: "Write the template parser"
      est: 3h
      done: false
    },
  ]
}
```

**A template per kind.** [`templates/<kind>.closure`](templates/) is the same shape with placeholders in the value slots: `grok("<= 8 words, no dashes")` for a line the model writes, `duration()`, `enum(a, b)`, `ref(kind)`, `score("1..5")`, `detect()`, `many [ … ]`, and `id()`, `index()`, `bool(false)` for what the tool fills. The first line, `// store: PHASES/phase-{n}-{name}.closure`, says where records go. One file is both the form an agent follows and the schema the checker enforces.

**The lifecycle.**

```
func file(kind, draft) {
  guard check-draft(draft, template(kind)) else { return errors(line, rule) }   // nothing is written
  record = fill(draft)              // ids, phase numbers, defaults come from the tool
  guard check(record, template(kind)) else { return internalError }
  write(canonical(record))          // one layout, so lint can compare bytes
  refresh(indexes, PLAN.md, TODO.md, MEMORY.md, OPEN.md)
}
```

**What makes it deterministic.** The checker rejects, with a line number: unbalanced brackets, anything after the closing `}`, an unknown or missing or out-of-order field, a value outside its enum, a duration like `about two hours`, an id that doesn't exist, a filename that doesn't match its pattern, a `depends` cycle. The model never supplies an id, a number or a filename, and the writer emits one canonical layout. What stays free is the wording inside `grok` and `text` slots, with no word, character or dash limits (the spec in a `grok` slot is guidance; only the file name slug is capped), so `write measure` compares the skeletons (the structure with strings blanked) of repeated runs.

**Where things are.** Kinds, commands and ids are in [rules/RECORDS.md](rules/RECORDS.md). To add a kind, add `templates/<kind>.closure` with a `// store:` line; the checker needs no change, but an index for the new kind does. `PLAN.md`, `TODO.md`, `MEMORY.md`, `OPEN.md`, `BUGS.md` and `PROPOSALS.md` are generated views, refreshed after each write; agents work from the `.closure` files, which are denser and already validated.

## Guards

| Event | Script | Does |
|---|---|---|
| `PreToolUse` on `Bash` | `hooks/guard-bash.swift` | Blocks (exit 2 with a reason): destructive git (`reset --hard`, `checkout .`, `restore .`, `clean`, `stash drop/clear`, force push, `push --delete`, `branch -D`); recursive `rm`, `find -delete` and script deletes outside `.build/` and scratch; redirects, `tee`, `sed -i`, `perl -i`, `dd of=` and `truncate` outside the project; `kill -1` broadcasts, `killall`, `pkill`; any `security` Keychain call; semantic hazards (base64 piped to a shell, `curl … \| bash`, reverse-shell sockets, `nc -e`, `chmod 777 /`, a fork bomb); then every rule in `guards.d/*.json` |
| `PreToolUse` on `Bash`, in parallel with `guard-bash` (a deny from `guard-bash` still wins) | `hooks/rewrite-bash.swift` | Never refuses. A command that runs a `build.sh`, `swift build` or `swift test` is rewritten (`updatedInput`) to run through `bin/filter-run`, so only errors, failed tests and totals reach the model and the full output goes to a log. Start a command with `RAW=1` to run it as written |
| `PreToolUse` on `Edit\|Write\|MultiEdit` | `hooks/guard-edit.swift` | Blocks (exit 2) an edit of an index, a generated view, the id ledger or a template. While `isolate` claims exist under `.cache/claims/`, it also blocks a subagent's edit to project source outside that subagent's claim, and one from a subagent that has not bound a claim; the main agent is never limited. Paths under `.agents/` and outside the project are not claim business. On project files outside `records/` it also steers the built-in tools toward `bin/edit` ([rules/EDITING.md](rules/EDITING.md)): `HOLON_EDIT_GUARD=deny` (the default) refuses the call, `advise` allows it with a reminder, `off` is silent; `HOLON_ALLOW_BUILTIN_EDIT=1` skips it for one run |
| `PostToolUse` on `Edit\|Write\|MultiEdit` | `hooks/check-edit.swift` | After a save to `records/drafts/`, runs `write check-draft`; after an edit to another `.closure` file, runs `write lint`, and for a record `write check <file>`, then `write render` so the views follow the edit; after a saved `.swift` under `harness/`, `lint`; after a `hooks/`, `tools/` or `hooks.json` edit, `sync-settings --check`; reports (exit 2) problems |
| `PostToolUse` on `Bash` | `hooks/check-shell-edit.swift` | After a command that runs `bin/edit FILE`, feeds `check-edit` and `route-semantics` an Edit payload for FILE (a Read payload for `--read`), so a change made with `edit` gets the checks and the semantics card an Edit would. Exit 2 with the findings, and any card routed in the same call; never refuses otherwise. Antigravity gets an empty reply |
| `Stop`, `SubagentStop` | `hooks/check-drafts.swift` | Refuses (exit 2) to end a turn while a draft that agent wrote fails its check. A draft the agent can't fix escalates: a `// cannot fix: <code>` first line, with a code from `reasons.closure`, or a second stop writes `<draft>.escalate` with the route for the orchestrator |
| `PreCompact` | `hooks/pre-compact.swift` | Never refuses. Copies the session transcript to `.cache/compactions/claude/<stamp>.jsonl` before each compaction (and on Antigravity `Stop` to `.cache/compactions/gemini/<conv8>.jsonl`) and keeps the newest 100 per folder |
| `PostCompact` | `hooks/post-compact.swift` | Never refuses. Saves Claude Code's `compact_summary` to `.cache/compactions/claude/<stamp>.summary.md` and keeps the newest 100 |
| `SessionStart` with matcher `compact` | `hooks/session-compact.swift` | Never refuses. After a compaction, adds `records/MEMORY.md`, `OPEN.md` and `TODO.md` and the archive path to the context, and marks this session's semantics state so the next event adds the cards again; does nothing for other start sources. See [rules/COMPACT.md](rules/COMPACT.md) |
| `UserPromptSubmit`; `PostToolUse` on `Read` and on `Edit\|Write\|MultiEdit` | `hooks/route-semantics.swift` | Never refuses. Picks the `records/SEMANTICS/` card whose `cues` the prompt names most, or whose `paths` prefix the file falls under most closely, and adds it as `additionalContext` when the area changes, unless that card was added within the last 300,000 bytes of transcript. When the transcript has grown 300,000 bytes since the `always` cards were last added, or after a compaction, it adds them and the active card again. A lock file per state keeps parallel tool calls from adding the same card twice. State is one JSON file per session and agent in `.cache/semantics/`, pruned after 7 days. Each reply stays under 6,000 characters |

`hooks.json` lists the scripts by event; `sync-hooks` also understands `post-shell`, which `check-shell-edit` uses (`pre-shell`, `pre-edit`, `post-shell`, `post-edit`, `post-read`, `prompt-submit`, `stop`, `subagent-stop`, `pre-compact`, `post-compact`, `session-compact`); [`hooks/sync-hooks.swift`](hooks/sync-hooks.swift) generates `.claude/settings.json` and `.agents/hooks.json` from it, and [`hooks/sync-settings.swift`](hooks/sync-settings.swift) generates `.claude/skills/` and `bin/<name>` for every script in `hooks/` and `tools/` (and runs `sync-hooks`). Don't hand-edit those: after adding or changing a script or `hooks.json`, run `.agents/harness/bin/sync-settings`; `--check` exits 1 if anything is stale. It also refuses a script that is missing or not executable.

`guards.d/*.json` holds the project's own Bash rules: each file is `{"pattern": <regex>, "message": <reason>}` (or a list of them), searched in the whole command. Add a file instead of editing `guard-bash`. Patterns are ICU regexes (`NSRegularExpression`). `python-scripts.json` refuses inline Python; `criteria-bash.json` refuses a shell rewrite of task criteria; `records-delete.json` refuses `rm`, `mv`, `unlink` or `trash` of a stored record (drafts excepted). The protected record files are checked in `guard-bash.swift` itself, by what each command writes to: redirect targets, `tee`, `rm`, `mv`, `truncate`, `dd of=`, the destination of `cp`, `install` and `ln`, and the file operands of `sed -i` and `perl -i`. A script or a string that only *mentions* a record path passes. The guards are still a safety net, not a sandbox: a target built in a variable (`sed -i … $F`) is not resolved, and the regex rules in `guards.d/` match the whole command text, so one that names a blocked pattern in a string is refused too.

## Tools

| Tool | Does |
|---|---|
| [`bin/write`](tools/write.swift) | parse, check, lint, write and render the records (see [rules/RECORDS.md](rules/RECORDS.md)) |
| [`bin/lint <file.swift…>`](tools/lint.swift) | the Swift rules in `lint.closure`; `check-edit` runs it on every saved `.swift` file under `harness/` and sends back errors ([rules/SWIFT.md](rules/SWIFT.md)) |
| [`bin/check-docs`](tools/check-docs.swift) | the `> AGENTS:` banner on hand-maintained docs, links that resolve, no orphan docs ([rules/PRACTICES.md](rules/PRACTICES.md)) |
| [`bin/filter-run '<command>'`](tools/filter-run.swift) | runs a command with zsh (`posix_spawn`), writes the full output to `.agents/harness/.cache/run-logs/<time>-<pid>.log`, prints errors with three lines of context, failed tests, totals and step headers (150 lines at most), then `[exit N] full log: <path>`; exits with the command's status |
| `bin/perf-scan`, `bin/perf-confirm`, `bin/perf-report` | scan for hot-loop smells, confirm a filed finding by its check, write the `PERF.md` scoreboard ([rules/PERF.md](rules/PERF.md)) |
| [`bin/semantics-report`](tools/semantics-report.swift) | measure `route-semantics` injections, `next` navigation hits, dead cues, and guard or draft failure rates across `.cache/semantics/events.jsonl` and `.cache/compactions/*.jsonl`; writes `records/SEMANTICS.md` |
| [`bin/edit`](tools/edit.swift) | the exact-match editor agents use for project files: `--read`, `--old`/`--new` with `--hash`, `--batch-file`, `--create`, `--check`; its exit codes and rules are in [rules/EDITING.md](rules/EDITING.md). `guard-bash` refuses it on records other than drafts and asks `guard-edit` about every other file, so protected files and worker claims hold. In `deny` mode it also refuses `sed -i`, `perl -i`, `awk -i inplace`, `ed`, `ex`, and a redirect, `tee`, `cp` or `install` onto an existing project file |
| [`bin/isolate`](tools/isolate.swift) | read every package's `Package.swift` under the project folder and plan which tasks can run as parallel workers: `graph` prints each target's read closure and the choke points, `plan [--max N] <task…>` picks workers whose write sets and read closures are disjoint, `owner <path…>` names a path's target, `claim <name> <task…>` files a worker's claim (refused on a choke point, an overlap or the cap), `release <name…\|--all>` and `claims` end and list them ([rules/DELEGATION.md](rules/DELEGATION.md)) |
| [`bin/transcript-md`](tools/transcript-md.swift) | render Claude Code and Gemini `.jsonl` transcripts into compact `<name>.md` siblings in `.cache/compactions/{claude,gemini}/`, and print the latest N turns (`--latest`) for cross-agent handoff |
| [`bin/sync-settings`](hooks/sync-settings.swift) | generates the wiring and the entry points |

There are no test tools for the harness itself: a change to a tool is checked by running it on the real store.

## Not built yet

- **Per-record views:** `write render` writes the indexes (`MEMORY.md`, `OPEN.md`, `TODO.md`, `PLAN.md` once a plan exists, `BUGS.md`, `PROPOSALS.md`). The `.md` view beside each record (`x.closure` → `x.md`, tables and prose) is planned.
- **A checker for the pseudocode blocks.**
- **An automatic orchestrator:** `write escalations` and `write escalation` do the bookkeeping ([rules/ESCALATION.md](rules/ESCALATION.md)), but starting the Sonnet and Opus fixers is a step the main session runs, because only it can start agents on another model.
