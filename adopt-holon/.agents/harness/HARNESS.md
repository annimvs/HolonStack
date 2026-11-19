# HARNESS — the `.agents/` system as diagrams

> **AGENTS: maintain this file with Haiku or a similar-class model, in grok'd prose.** Style rules: [QUIET](rules/QUIET.md), [PROSE](rules/PROSE.md).

Three diagrams:
1. what enforces and what only advises;
2. what runs on each hook event;
3. what one record write does.

The prose for each part is in [README.md](README.md), and the rules agents follow are in [rules/](rules/). **Update this file when** `hooks.json`, a hook's branches, or `write`'s `new` or `done` path changes.

## 1. Enforcement, guidance and artifacts

A part is enforcement only if it still holds against an agent that ignores the guidance. That means code that runs outside the model and decides whether an action happens. A markdown rule is guidance. A record, once written, is an artifact.

- **Gating:**
  - `guard-bash` and `guards.d/*.json` refuse a command before it runs.
  - `guard-edit` refuses an edit of an index, the ledger, a template, `reasons.closure`, `lint.closure` or an escalation. It also refuses a change to a filed task's criteria.
  - `write` refuses a draft that fails its template, and a `done` whose criteria fail.
- **Verification:**
  - `check-edit` checks each save: a draft against its template, a record against its template and canonical form (then it renders the views), Swift under `harness/` against the lint rules, and the hook wiring.
  - `check-drafts` keeps a turn open while a draft fails.
- **Transport:** the generated `bin/` entry points, and `write`'s file writes under its lock.
- **Guidance:** `ATLAS.md`, the rules, the README and this file, the skills, and the docs under `codebase/` and `reference/`.
- **Artifacts:** the record stores, their generated views and the `.ids` ledger.

```mermaid
%%{init: {
  "theme": "base",
  "themeVariables": {
    "darkMode": true,
    "background": "#363B40",
    "primaryColor": "#41474E",
    "primaryTextColor": "#DCDFE4",
    "primaryBorderColor": "#5C646D",
    "lineColor": "#8FA2B5",
    "textColor": "#B8BFC6",
    "clusterBkg": "#2F3338",
    "clusterBorder": "#4A5057"
  },
  "flowchart": { "curve": "basis", "nodeSpacing": 40, "rankSpacing": 50 }
}}%%
flowchart LR
    agent["Agent<br/><b>proposes</b>"]

    subgraph Enforcement["Enforcement: code that decides"]
        direction TB
        subgraph Gating["Gating"]
            direction TB
            gb["guard-bash · guards.d/*.json<br/>refuse a command before it runs"]
            ge["guard-edit<br/>refuse an edit of an index, the ledger,<br/>a template, reasons, lint rules, task criteria"]
            wg["write<br/>a draft must pass its template<br/>done needs its criteria to pass"]
        end
        subgraph Verification["Verification"]
            direction TB
            ce["check-edit<br/>draft · record · Swift lint · wiring"]
            cd["check-drafts<br/>a failing draft keeps the turn open"]
        end
        subgraph Transport["Transport"]
            direction TB
            bin["bin/&lt;name&gt;<br/>one per hooks/*.swift and tools/*.swift"]
            ww["write: lock · ids · canonical file · indexes · views"]
        end
        inputs["Data the code reads, edited only by the user<br/>hooks.json · guards.d · templates/ · reasons.closure · lint.closure"]
    end

    subgraph Guidance["Guidance: markdown agents read"]
        direction TB
        know["ATLAS.md · harness/README.md · HARNESS.md<br/>codebase/ · reference/"]
        rules["harness/rules/*.md"]
        skill["harness/skills/closure-system"]
    end

    subgraph Artifacts["Artifacts: written data"]
        direction TB
        records["records/: PLAN · PHASES · TODO · TASKS · MEMORIES<br/>QUESTIONS · ISSUES · PROPOSALS · FINDINGS · CATALOG · SEMANTICS"]
        views["generated views: MEMORY.md · OPEN.md · PLAN.md · TODO.md<br/>BUGS.md · PROPOSALS.md · PERF.md · SEMANTICS.md"]
        ledger[".ids ledger"]
    end

    agent -- "reads" --> Guidance
    agent -- "tool calls and edits pass through" --> Enforcement
    ww --> records
    ww --> views
    ww --> ledger
    agent -. "direct edit of an index, view or ledger:<br/>refused by guard-edit and guard-bash" .-> records
```

## 2. What runs on a hook event

`hooks.json` binds ten events, two hooks on Bash and two after an edit, and `sync-settings` writes them into `.claude/settings.json`. Each hook reads the event's JSON on stdin and exits 2 to refuse, or to show the model what it found. Nothing here commits. The three compaction hooks never refuse: `pre-compact` gives Claude Code instructions for the summary on stdout, and they archive the transcript and the summary and put the record views back into the context after a compaction ([rules/COMPACT.md](rules/COMPACT.md)). `route-semantics` never refuses either: it adds an area's semantics card to the context.

```mermaid
%%{init: {
  "theme": "base",
  "themeVariables": {
    "darkMode": true,
    "background": "#363B40",
    "primaryColor": "#41474E",
    "primaryTextColor": "#DCDFE4",
    "primaryBorderColor": "#5C646D",
    "lineColor": "#8FA2B5",
    "textColor": "#B8BFC6",
    "clusterBkg": "#2F3338",
    "clusterBorder": "#4A5057"
  },
  "flowchart": { "curve": "basis", "nodeSpacing": 40, "rankSpacing": 50 }
}}%%
flowchart LR
    shell(["PreToolUse: Bash"]) --> gb{"guard-bash"}
    gb -- "destructive git · recursive rm outside .build and scratch<br/>writes outside the project · killall/pkill · Keychain<br/>remote-shell tricks · a write onto a protected record path<br/>a guards.d match (inline Python, task criteria)" --> refused["exit 2: refused, reason on stderr"]
    shell --> rb{"rewrite-bash"}
    gb -- "no match" --> ok["not refused"]
    rb -- "build.sh · swift build · swift test<br/>not started with RAW=1" --> fr["runs as bin/filter-run<br/>errors and totals shown, full log kept"]
    rb -- "anything else" --> runs["command runs as written"]
    refused -. "a deny outranks the rewrite: the command never runs" .- rb

    preedit(["PreToolUse: Edit · Write · MultiEdit"]) --> ge{"guard-edit"}
    ge -- "records/ index or view · .ids · .write.lock<br/>harness/templates/ · reasons.closure · lint.closure<br/>a drafts/*.escalate · changed task criteria" --> refusededit["exit 2: refused"]
    ge -- "any other path" --> editok["edit proceeds"]

    postedit(["PostToolUse: Edit · Write · MultiEdit"]) --> ce{"check-edit"}
    ce -- "a .swift under harness/" --> lint["bin/lint"]
    ce -- "records/drafts/*.closure" --> cdraft["write check-draft"]
    ce -- "another .closure" --> wl["write lint; for a record, write check then write render"]
    ce -- "harness/hooks/ · tools/ · hooks.json" --> ss["sync-settings --check"]
    ce -- "any other path" --> quiet["nothing"]
    lint --> found["findings: exit 2, shown to the model"]
    cdraft --> found
    wl --> found
    ss --> found

    precompact(["PreCompact"]) --> pc["pre-compact<br/>copy the transcript to .cache/compactions, write its .md<br/>stdout: instructions for the summary"]
    postcompact(["PostCompact"]) --> poc["post-compact<br/>save compact_summary beside the transcript<br/>as the same name .summary.md"]
    sstart(["SessionStart: compact"]) --> sc["session-compact<br/>add MEMORY.md · OPEN.md · TODO.md<br/>and the archive path to the context<br/>mark the semantics state compacted"]
    route(["UserPromptSubmit · PostToolUse: Read · Edit · Write"]) --> rs{"route-semantics"}
    rs -- "a new area, by prompt cues or file path" --> card["add that card"]
    rs -- "transcript grew 300 KB, or compacted" --> again["add the always cards and the active card"]
    rs -- "same area, nothing due" --> silent["nothing"]

    stop(["Stop · SubagentStop"]) --> cd{"check-drafts"}
    cd -- "a draft this agent saved fails" --> first{"first stop, no reason given?"}
    first -- "yes" --> block["exit 2: keep working"]
    first -- "a // cannot fix: code line,<br/>or a second stop" --> esc["write draft.escalate<br/>with the code's route: model · user · harness"]
    cd -- "all drafts pass" --> done(["turn ends"])
```

## 3. One record write

`bin/write` runs [tools/write.swift](tools/write.swift) as a cached binary and falls back to `swift`. Commands that only read take no lock: `list`, `get`, `check`, `check-draft`, `next`, `show` and `measure`. The diagram follows `new`; `done` is described below it.

```mermaid
%%{init: {
  "theme": "base",
  "themeVariables": {
    "darkMode": true,
    "background": "#363B40",
    "primaryColor": "#41474E",
    "primaryTextColor": "#DCDFE4",
    "primaryBorderColor": "#5C646D",
    "lineColor": "#8FA2B5",
    "textColor": "#B8BFC6",
    "clusterBkg": "#2F3338",
    "clusterBorder": "#4A5057"
  },
  "flowchart": { "curve": "basis", "nodeSpacing": 40, "rankSpacing": 50 }
}}%%
flowchart TB
    cmd["write kind new draft"] --> root["find .agents/: $CLAUDE_PROJECT_DIR, else the nearest above the cwd<br/>load harness/templates/"]
    root --> cd{"check-draft against the template"}
    cd -- "problems" --> refuse["print each with its line; nothing written"]
    cd -- "passes" --> lock["flock records/.write.lock<br/>(about 10 s, then give up)"]
    lock --> fill["fill: mint ids for each _, numbers, defaults"]
    fill --> recheck{"check the filled record as stored"}
    recheck -- "problems" --> refuse2["internal error; nothing written"]
    recheck -- "passes" --> exists{"file name already taken?"}
    exists -- "yes" --> refuse3["refused: edit that record or rename"]
    exists -- "no" --> files

    subgraph files["writes, in this order"]
        direction TB
        rec["the record file, canonical form<br/>records/KIND/kind-slug.closure"]
        ids[".ids: the new ids appended"]
        idx["the index: PLAN.closure for a phase, TODO.closure for a task"]
        views["write render: MEMORY.md · OPEN.md · PLAN.md · TODO.md · BUGS.md · PROPOSALS.md"]
        rec --> ids --> idx --> views
    end

    files --> envelope["one JSON envelope: ids, files, and any task names that want a design first"]
```

**`done <task>`** runs each criterion's `check:` from the project folder and prints `pass`, `confirmed` or `FAIL` for each.
- **If any fails,** the task stays open.
- **If all pass,** it takes the lock, sets `done: true`, checks the record, writes it, renders the views, and prints the evidence.
- **It commits nothing,** and there is no lint gate on the project's `Sources/`.

`reopen` sets `done: false` without running anything.

## Where each part is described

| Part | File |
|---|---|
| Layers, guards, tools, what is not built | [README.md](README.md) |
| Record kinds, ids, drafts, criteria, the done gate | [rules/RECORDS.md](rules/RECORDS.md) |
| The notation and the placeholders | [rules/NOTATION.md](rules/NOTATION.md) |
| Escalation routes | [rules/ESCALATION.md](rules/ESCALATION.md) |
| Hook events and their scripts | [hooks.json](hooks.json), [hooks/](hooks/) |
