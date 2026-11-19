# DESIGN

> **AGENTS: maintain this file with Haiku or a similar-class model, in grok'd prose.** Style rules: [QUIET](QUIET.md), [PROSE](PROSE.md).

When a task builds something new, ask Opus at low effort which data structure or algorithm fits before anyone writes code. The answer is filed as a `design` record, and the builder follows it. This rule is advice today; the gate is described at the end.

## When to ask

Ask when the task creates a new type, collection, algorithm or data pipeline. Do not ask for a bug fix, a rename, an edit to existing code, a doc change, or a task whose design the user already named.

```
func needsDesign(name) -> Bool {
  guard name.startsWith(creatingVerb) else { return false }   // make, create, build, implement, add, write, develop, introduce, design
  return !name.mentions(docs, tests, fix, rename, removal)    // those are not new things
}
```

The tools make the first call from the task's own name, which says what the task intends to do. A name that starts with a creating verb (make, create, build, implement, add, write, develop, introduce, design) is flagged, unless it is about docs, tests, a fix, a rename or a removal. `write task new` and `write phase new` list the flagged names in their output as `design`, `write next` shows `design <name>` under a phase that has open flagged tasks, and `.agents/harness/bin/route-intent "<task>"` sets `needs_design` for free text. It is a keyword check, so treat a miss as a prompt to think, not an answer. When unsure, ask: the call is cheap, and "a plain array is fine" is an accepted answer.

## What to send Opus

Send a short brief, never code, since none exists yet. Spawn the agent with `model: "opus"` at low effort. The brief holds:

1. What the thing must do, in two sentences.
2. The operations it needs and how often each runs (insert, lookup, remove, iterate, sort).
3. How much data: typical and worst case.
4. Whether order, uniqueness or concurrent access matters.
5. The catalog entries that match the task, from [`records/CATALOG/`](../../records/CATALOG/). Pass only the matching ones, chosen by kind and by the smell they replace, so the brief stays small.

Ask for one reply: use a catalog entry, a plain standard-library type is fine, or a custom design is needed, with a reason in a few sentences.

## What comes back

A `design` record, filed with `write design new`. It names the choice (a catalog entry or none), the verdict, and the reason. The delegator echoes `write show`-style output to the user and puts the record in each builder's brief, so no Haiku worker picks its own structure.

## Where the code comes from

Follow the entry's `ships` field, in this order:

1. **`stdlib`:** use it. Add nothing.
2. **A package** (`ships: package`, or a Swift package like `swift-collections`, `swift-algorithms`, `swift-async-algorithms`): add that dependency in the project's package manager (SwiftPM, Cargo, npm, vcpkg/Conan, PyPI, Go modules) and import the named product.
3. **`none`:** implement it, and say so in the record.

The scripts in `.agents/harness/hooks` and `.agents/harness/tools` have no `Package.swift`. They stay dependency-free: where a package would help, implement the small piece they need.

## The catalog

Entries live in [`records/CATALOG/`](../../records/CATALOG/), one per structure, algorithm or pattern. Each says when it wins, the hand-rolled code it replaces, and where it ships. Add an entry only after checking the package's current documentation; never from memory, since what a package ships changes between versions.

## The gate

Today nothing stops a builder from skipping this. To enforce it, the `task` template needs a `design` field and `write done` must refuse a flagged task without one. Templates are changed only by the user.
