# PERF

> **AGENTS: maintain this file with Haiku or a similar-class model, in grok'd prose.** Style rules: [QUIET](QUIET.md), [PROSE](PROSE.md).

Judge the cost of code that already exists. A script finds candidates, you judge them, and a script confirms what you claim. You never mark a finding true yourself.

```
func audit(paths) {
  let hits = perfScan(paths)                          // .agents/harness/bin/perf-scan <paths>
  for hit in hits {
    guard let finding = judge(hit) else { continue }  // read the code; drop the hit if the cost is fine
    write.finding.checkDraft(finding)                 // fix every problem it prints
    write.finding.new(finding)
  }
  perfConfirm()                                       // .agents/harness/bin/perf-confirm runs each check
  perfReport()                                        // .agents/harness/bin/perf-report writes records/PERF.md
}
```

## Judging a hit

- **A hit is a question.** `perf-scan` reads text, not types. `contains` on a `Set` is cheap and on an `Array` is not. Open the code and decide.
- **A finding is a claim plus a check.** The `check` is a shell command that exits 0 when the gap is measured, such as a benchmark at a realistic size with a threshold. Use `manual` only when no command can measure it. Keep double quotes out of `check`; use single quotes, or call a script.
- **Only `perf-confirm` sets `confirmed`.** On exit 0 it swaps `status: open` for `status: confirmed`, has `write lint` accept the file, and puts the old text back if lint refuses. You set `fixed` or `wontfix` by editing the file once the work is done.
- **Name the sizes.** `declared` and `necessary` are worst case, with the size named: `O(L) per pass over L local slots`, not `O(n)`.
- **Pick the fix from the catalog.** Set `fix` to the id of the matching [entry](../templates/entry.closure) record. If none fits, ask for a design ([DESIGN](DESIGN.md)); don't invent a structure.
- **Fix a confirmed finding as a task** whose criterion is the same check, run after the change ([RECORDS](RECORDS.md)).

## What the scanner cannot see

It matches a catalog entry's `detect` spans on lines inside a loop. It does not follow calls, so a loop that calls a slow function is missed, and it does not see work that gives the same answer on every pass. Read for both. The catalog entry `Resolve once outside the loop` names the second.

## When you cannot finish a draft

If the cost depends on code outside this project, put `// cannot fix: cost-unknowable: <note>` first in the draft. If the finding looks real and no command can measure it, use `no-check`. Both go to the user ([ESCALATION](ESCALATION.md)).
