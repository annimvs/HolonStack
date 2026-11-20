---
name: work-queue
description: Run unblocked tasks from PLAN.md and TODO.md through isolate claims, parallel workers, result collection, and check-verified completion. Use to execute a queued phase or batch of independent tasks.
---

> **AGENTS: maintain this file with Haiku or a similar-class model, in grok'd prose.** Style rules: `.agents/harness/rules/QUIET.md`, `.agents/harness/rules/PROSE.md`.

# work-queue

Chain the existing planning, isolation, and verification tools to drain unblocked tasks without overlapping edits. Every step follows `.agents/harness/rules/DELEGATION.md`.

## Loop

1. **Inspect open work:**
   ```sh
   .agents/harness/bin/write next
   .agents/harness/bin/write list task
   ```
   - If `write next` prints a `design` line for a task that adds a new public type, module, or cross-boundary API, handle `.agents/harness/rules/DESIGN.md` first before dispatching workers.
   - If open `question` records (`records/OPEN.md`) block all remaining tasks, stop and ask the user.

2. **Handle choke points first:**
   Run `.agents/harness/bin/isolate graph`. Any task touching a choke point, a manifest (`Package.swift`, `package.json`, `Cargo.toml`, `CMakeLists.txt`), or a shared singleton runs in the orchestrator before spawning workers.

3. **Partition and claim disjoint tasks:**
   ```sh
   .agents/harness/bin/isolate plan <task…>
   .agents/harness/bin/isolate claim <worker-name> <task…>
   ```
   Keep the default cap of 2 parallel workers unless the user sets `--max N` or `HOLON_WORKERS`.

4. **Dispatch workers:**
   Give each worker a concise brief naming its claim (`<worker-name>`), its target files, its task record id, and its `check:` criteria. Tell it to bind `.agents/harness/.cache/claims/<worker-name>.bind` first and file a `result` record (`write result new`) when done, failed, or blocked. Follow the escalation ladder in `DELEGATION.md`: Haiku first, then the delegator, then Opus.

5. **Collect results and verify:**
   ```sh
   .agents/harness/bin/write status
   ```
   - For each `done` result, run `.agents/harness/bin/write done <task-id>` to verify every `check:` criterion and tick the task.
   - Release claims with `.agents/harness/bin/isolate release --all`.
   - On any `blocked` result or exhausted retry, file a `question` record with a default and stop on that branch.

6. **Repeat** until no unblocked tasks remain. Never commit or push unless the user asks.
