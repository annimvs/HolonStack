# DELEGATION

> **AGENTS: maintain this file with Haiku or a similar-class model, in grok'd prose.** Style rules: [QUIET](QUIET.md), [PROSE](PROSE.md).

This file explains how to start subagents in `.agents` and how they report back.

## Directives

1. **Pass Concise Context:**
   Pass only the target files, the relevant record closure and the expected output. Never dump full conversation logs or raw transcripts into a subagent prompt.
2. **Workspace Isolation:**
   Use `'inherit'` for read-heavy investigations and quick edits. Use `'branch'` for experimental changes, high-risk migrations or parallel branches.
3. **Structured Returns:**
   Tell subagents to return structured summaries or typed `.closure` records, not raw stream-of-consciousness narratives.
4. **Summary Obligation:**
   When a subagent finishes, summarize its findings in plain English. Do not paste its raw output back to the user ([QUIET](QUIET.md)).

## The swarm: Haiku workers, a delegating model, Opus last

The main session is the delegator. It defaults to `sonnet`, unless the user names another model. It splits a job into task items and gives each item to a `haiku` subagent. Each agent gets one item, and 1 to 5 agents run at once. The delegator never gives an item to a stronger model before a cheaper one has tried it.

```
func swarm(items: [Item], delegator: Model = .sonnet) -> [Result] {
  let workers = items.prefix(5).map { spawn(agent(model: .haiku, task: brief($0))) }
  var results = []
  for (item, w) in zip(items, workers) {
    switch w.status {
    case .done:   results.append(w.result)              // read through `write status`, never paraphrased
    case .failed, .blocked: results.append(delegator.attempt(item))   // the delegator redoes it itself
                  if !results.last.done { results.last = spawn(agent(model: .opus, task: brief(item, tried: [.haiku, delegator]))) }
    }
  }
  return results
}
```

- **The brief** names the item, the target files, any record closure it needs and the result shape. It carries no transcript ([directive 1](#directives)).
- **A worker files a `result` record** with `write result new`. Its status is `done`, `failed` or `blocked`. It sets `failed` when it cannot finish and `blocked` when it needs a decision. It never guesses. Its report is plain prose: what finished, where it stopped and what it would do next. A blocked worker puts its question in the report. It does not ask the delegator mid-run.
- **The delegator reads `write status`, not the workers.** The command prints only results not yet reported, as markdown: blocked first, then failed, then done. The delegator echoes that text and adds no summary of its own ([QUIET](QUIET.md)). When `write status` prints nothing, there is nothing to report. `--peek` shows the text without marking it as reported.
- **Results are files.** They survive the delegator's death and keep its context small. A worker that dies before filing leaves no result, so the delegator treats it as failed.
- **A failed item climbs one step at a time:** haiku, then the delegator, then `opus`. Each stronger model gets the notes from the earlier attempts. If `opus` fails too, file a question with `write question new` and give a default.
- **Items are independent.** One failed worker does not stop the others, and a retry never reruns items that passed.
- **Isolation:** use `'inherit'` for read-only or small items. Use `'branch'` when two workers could touch the same files.

## Parallel workers on one project

The orchestrator and its workers form a star: each worker talks only to the orchestrator, never to another worker. Checking pairs of workers against each other is where the cost grows fastest, so the orchestrator does it once at dispatch and the workers never reconcile.

- **Plan with `bin/isolate plan [--max N] <task…>`.** A task is a target name, several joined by commas, or a path. The plan keeps workers whose write sets and read closures (the target plus everything it depends on, from every package's `Package.swift` under the project folder) are disjoint. A path task is relative to the project folder, such as `Sources/Core`. The cap is 2 by default; the user sets another with `--max N` or `HOLON_WORKERS`. A task past the cap or overlapping a placed worker is deferred, not dropped.
- **The orchestrator owns the choke points:** the targets nearly everything depends on, every package outside this folder, and every `Package.swift`. `isolate graph` lists them; `--choke a,b` replaces the derived list. It makes any change there before it spawns workers, so a worker's inputs never move under it.
- **Shared singletons are the orchestrator's too:** the live install, shared daemons or caches, and the final build.
- **Claim before you spawn (enforced by `guard-agent`).** Run `bin/isolate claim <name> <task…>` for each worker; it refuses a choke point, an overlap with a live claim, or a claim past the cap. Put the claim name in the brief and tell the worker to start by writing an empty file at `.agents/harness/.cache/claims/<name>.bind`. `guard-agent` blocks spawning any non-read-only subagent unless a live unbound claim exists and the prompt names it (read-only types like `Explore`/`Plan`/`research` stay exempt, or mark a prompt `[unrestricted]` / `[read-only]`, or set `HOLON_ALLOW_UNCLAIMED_AGENT=1`). When the work is done, run `bin/isolate release --all`. A claim expires after six hours.
- **A worker stays inside its write set (enforced by `guard-edit`).** `guard-edit` blocks any subagent edit (`agent_id` present) to project source when no claim exists, before the worker has bound its claim, or outside the claim's paths (both built-in edit tools and `bin/edit` via `guard-bash`). The orchestrator has no `agent_id` and stays unrestricted. A worker that needs something outside its claim files a `blocked` result with the request in its report and stops; the orchestrator makes the change and resumes it.
- **The check is conservative.** It treats any edit to a target as able to affect every target that depends on it; it does not tell a body edit from an interface edit.

Failed record drafts follow their own ladder, in [ESCALATION](ESCALATION.md).
