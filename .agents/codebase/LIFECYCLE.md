# LIFECYCLE — one operation, end to end

> **AGENTS: maintain this file with Haiku or a similar-class model, in grok'd prose.** Style rules: [QUIET](../harness/rules/QUIET.md), [PROSE](../harness/rules/PROSE.md).

<!-- STUB: Run /adopt-holon to trace the primary end-to-end lifecycle of the adopting project (e.g. a request, a command, a compilation pass, an event pipeline, or a transaction). -->
What happens from the moment an input enters the system until the output or state change completes.

The module map is in [CODEBASE.md](CODEBASE.md). **Update this file when** a step is added or reordered in the primary execution path, a dispatch or resolution rule changes, or a boundary hand-off changes.

## Primary turn or request flow

<!-- STUB: Replace the participants and messages below with the actual types and calls traced from the codebase. -->

```mermaid
%%{init: {"theme":"base","themeVariables":{"darkMode":true,"background":"#363B40","primaryColor":"#41474E","primaryTextColor":"#DCDFE4","primaryBorderColor":"#5C646D","lineColor":"#8FA2B5","textColor":"#B8BFC6","actorBkg":"#41474E","actorBorder":"#5C646D","actorTextColor":"#DCDFE4","signalColor":"#8FA2B5","signalTextColor":"#B8BFC6","noteBkgColor":"#2B3F52","noteTextColor":"#DCDFE4","noteBorderColor":"#5B8DB8"}}}%%
sequenceDiagram
    participant In as EntryPoint
    participant Dom as DomainService
    participant Out as Store / Output

    In->>Dom: parse and validate input
    Dom->>Out: apply domain transition
    Out-->>In: result
```

## Decision and dispatch flow

<!-- STUB: Add flowcharts for key branching decisions (e.g. fast path vs fallback, caching, routing, error recovery). -->

```mermaid
%%{init: {"theme":"base","themeVariables":{"darkMode":true,"background":"#363B40","primaryColor":"#41474E","primaryTextColor":"#DCDFE4","primaryBorderColor":"#5C646D","lineColor":"#8FA2B5","textColor":"#B8BFC6"},"flowchart":{"curve":"basis"}}}%%
flowchart TB
    input["Input"] --> check{"Fast path eligible?"}
    check -- "yes" --> fast["Run fast path"]
    check -- "no" --> full["Run full path"]
```

## Entry points

<!-- STUB: Map each stage of the lifecycle to the exact file and function that defines it. -->

| What | Defined in |
|---|---|
| Startup / main entry point | `Sources/<Target>/<File>.swift` |
| Primary dispatch / execution | `Sources/<Target>/<File>.swift` |

## Invariants and gotchas

<!-- STUB: List the rules that must always hold across this lifecycle and non-obvious traps in the code. -->
- State the rules that must always hold across the lifecycle after tracing the source in `/adopt-holon`.
