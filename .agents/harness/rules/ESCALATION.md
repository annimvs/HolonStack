# ESCALATION

> **AGENTS: maintain this file with Haiku or a similar-class model, in grok'd prose.** Style rules: [QUIET](QUIET.md), [PROSE](PROSE.md).

A draft that an agent could not make pass gets an escalation file at `records/drafts/<name>.closure.escalate`. That file is a closure record. It holds the reason code, its route, the agent's note and the checker output. The `check-drafts` hook writes it ([RECORDS](RECORDS.md)). Only the hook and `write escalation` change it. The reason codes and their routes are in [`reasons.closure`](../reasons.closure), which only the user edits.

Only failed record drafts use this ladder. Task items given to `haiku` workers follow the swarm rule in [DELEGATION](DELEGATION.md): haiku, then the delegating model, then `opus`.

## Commands

```sh
.agents/harness/bin/write escalations                          # one JSON line per open escalation: draft, reason, route, tried, next
.agents/harness/bin/write escalation <draft> resolve           # the draft passes now: remove the escalation (refused while it fails)
.agents/harness/bin/write escalation <draft> bump <tier>       # <tier> tried and failed; after the last tier the route becomes user
.agents/harness/bin/write escalation <draft> ask               # file a question with the draft, reason and errors; OPEN.md lists it
```

## The orchestrator

The main session runs the orchestrator. It is the only agent that can start agents on another model. The fix tiers are `sonnet` then `opus`, in that order, after the model that wrote the draft.

```
func orchestrate() {
  for e in write.escalations() {
    guard e.question == nil else { continue }                  // already waiting on the user
    switch e.route {
    case .user, .harness:
      write.escalation(e.draft, .ask)                          // a question in OPEN.md; the user decides
    case .model:
      guard let tier = e.next else { write.escalation(e.draft, .ask); continue }
      spawn(agent(model: tier, task: fix(e.draft, errors: e.checker, note: e.note)))
      if !write.escalation(e.draft, .resolve) {
        write.escalation(e.draft, .bump(tier))                 // past opus the route becomes user
      }
    }
  }
}
```

- **The fixer's task** names the draft, gives it the checker output and the note, and says to fix the draft in place. If the draft starts with a `// cannot fix:` line, the fixer removes that line once the draft passes. The fixer may run `check-draft`. It does not file the draft.
- **One tier at a time.** Run `resolve` after each fixer. Call `bump` only when `resolve` is refused, so a fixed draft never climbs further.
- **Report** each escalation's end state to the user in one line: which tier resolved it, or which question it was asked as.
- **Harness routes are bugs.** `checker-wrong` and `missing-record` mean the fix belongs in the tool or a template, and agents don't edit those. `ask` reports them as an `issue` (listed in `BUGS.md`) when the issue template exists. Otherwise it files a question.
