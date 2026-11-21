# LIFECYCLE — TaskFlow

> **AGENTS: maintain this file with Haiku or a similar-class model, in grok'd prose.** Style rules: [QUIET](../harness/rules/QUIET.md), [PROSE](../harness/rules/PROSE.md).

## API create path

1. `handleCreate(store, rawBody)` in `packages/api/src/server.ts` calls `parsePayload(rawBody)`.
2. `parsePayload` parses JSON and checks that `id` and `title` are strings.
3. `store.add(id, title)` in `packages/core/src/task.ts` trims `title`, rejects empty titles, and inserts into the `Map`.
4. `handleCreate` serializes the created `Task` back to JSON.

## CLI path

1. `runCommand(store, args)` in `packages/cli/src/main.ts` dispatches `add`, `done`, or default listing.
2. Mutations call `store.add` or `store.complete` in `packages/core/src/task.ts`.
3. Output is plain one-line text for stdout.
