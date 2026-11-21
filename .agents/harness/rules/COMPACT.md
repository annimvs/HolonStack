# COMPACT

> **AGENTS: maintain this file with Haiku or a similar-class model, in grok'd prose.** Style rules: [QUIET](QUIET.md), [PROSE](PROSE.md).

File what must survive as records before the context compacts, and let the summary point at them. Claude Code writes the compaction summary from the transcript. `pre-compact` tells it what to keep, but the summary is still a model's recap. A record is checked by `write` and read back from disk after the compaction, so it can't be dropped the way a line in a summary can.

## What goes where

| It is | File it as | Template |
|---|---|---|
| A decision, a constraint or a working rule, with the reason | `memory` (`project` or `feedback`) | [remember](../skills/remember/SKILL.md) |
| A rejected approach and why it failed | `memory` (`project`), one per approach | [remember](../skills/remember/SKILL.md) |
| Something blocked on the user | `question` | [RECORDS](RECORDS.md) |
| Work still to do | `task` with `check:` criteria | [RECORDS](RECORDS.md) |
| A confirmed bug | `issue` with its repro | [RECORDS](RECORDS.md) |
| A choice of data structure or algorithm | `design` | [DESIGN](DESIGN.md) |

Leave out what the code, the docs under `.agents/` or git already record ([remember](../skills/remember/SKILL.md) step 2). The summary keeps only what has no home in a record: the current goal, the files being edited with their exact paths, and the command that last failed with its error.

## What the hooks do

`hooks.json` binds three scripts, and all three run without being asked. This was checked against the Claude Code hooks reference ("PreCompact" and "PostCompact") on 2026-11-18:
- **A PreCompact hook's stdout,** when it exits 0, is used as instructions for the summary, up to 10,000 characters.
- **Exit 2 from a PreCompact hook,** or `"decision": "block"`, blocks the compaction.
- **A PostCompact hook** has no decision control.

- **`pre-compact`** prints its summary instructions (`summaryInstructions` in the hook, the same text as AGENTS.md's "Compact instructions") on stdout, for every compaction, manual or automatic. It never blocks one. It also archives the transcript: before each Claude Code compaction it copies it to `.agents/harness/.cache/compactions/claude/<stamp>.jsonl` (on Antigravity `Stop`, to `.agents/harness/.cache/compactions/gemini/<conv8>.jsonl`). It writes the readable `<stamp>.md` beside it with `transcript-md`, and keeps the newest 100 of each.
- **`post-compact`** saves the summary Claude Code wrote as `<stamp>.summary.md`, named after the transcript `pre-compact` just archived, keeping the newest 100. A summary can then be compared with the records and the transcript.
- **`session-compact`** runs when a session restarts after a compaction (SessionStart, source `compact`). It adds `records/MEMORY.md`, `OPEN.md` and `TODO.md` to the context, each cut at 2,500 characters, with the archive folder and the newest transcript path. It also marks this session's `route-semantics` state, so the next prompt or file read adds the `always` semantics card and the active area's card again. Claude Code saves hook context over 10,000 characters to a file and shows a preview, so the message stays under 9,000.

## After a compaction

1. Read the injected records before acting on the summary. Where they disagree, the record is right, because the summary is a model's recap.
2. When the summary lacks a detail you need, search the newest transcript in `.agents/harness/.cache/compactions/` with `grep` instead of guessing.
3. File what the summary shows that has no record yet, using the table above.

## Context reinjected block

Hook context reaches the model only; the client does not show it to the user. Print one `### Context reinjected` block at the end of your reply on **exactly two triggers**, and on no other reply:

1. **First reply after a compaction restart** (`[context-reinjected kind=compact ...]` is in context).
2. **A reply after `route-semantics` loads or refreshes a card** (`[context-reinjected kind=card ...]` is in context, including on a 300 KB regrow).

This block is an explicit exception to [QUIET](QUIET.md) ("reply with only what is essential"): print it only on those two triggers, never when nothing was injected. Read the numbers from the `[context-reinjected ...]` line the hook added (hooks also append the same numbers to `.agents/harness/.cache/reinjections.jsonl`). Sizes are characters shown as `k` (`1k` = 1,000 chars; tokens are roughly `chars / 4`). Omit rows whose size is `0`, and use short names (`core`, `harness`, `pre-compact` instead of file extensions).

**Compaction restart form** (include any cards loaded in the same turn):

```markdown
### Context reinjected
Transcript **412k** → summary **3.1k** · reinjected **6.8k / 9k**

| Source | Size | Why |
|---|---|---|
| `core` | 0.9k | always present |
| `harness` | 0.7k | matched `pre-compact` |
| `MEMORY.md` | 1.1k | records win over summary |
| `OPEN.md` | 0.3k | 1 open question |
| `TODO.md` | 0.2k | open work |
| `<stamp>.md` | 412k | newest transcript; search, don't guess |

- **In summary (agent's read, unverified):** goal, files mid-edit, last failure, rejected approaches
- **In records:** record ids or counts referenced
```

The two footer bullets are the agent's own reading of the summary and are the least reliable part of the block; drop either bullet if you cannot name concrete items, and never invent counts.

**Card-only form** (trigger 2, when no compaction just happened):

```markdown
### Context reinjected

| Source | Size | Why |
|---|---|---|
| `harness` | 0.7k | matched `pre-compact` |
```

## Compacting by hand

`pre-compact` already gives these instructions on every compaction, so a bare `/compact` is enough. Add a focus only when this compaction needs something extra kept, for example (Claude Code also hands the focus to the hook as `custom_instructions`):

```
/compact also keep the failure totals from the last verification run
```

AGENTS.md carries a short "Compact instructions" section that says the same thing, for any agent that reads it. The hook is what makes it reliable on Claude Code: one public measurement found the AGENTS.md section alone ignored on a bare `/compact`.

## Limits

The summary stays a model's recap. The instructions make a good one likelier, and the records and archives make a bad one cheap to recover from, but none of it makes the summary correct. If a hook doesn't run, `sync-settings --check` and `bin/lint` are the first two checks.
