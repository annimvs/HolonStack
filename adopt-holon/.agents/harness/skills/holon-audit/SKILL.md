---
name: holon-audit
description: Audit a repo or module against codebase maps/diagrams, PRACTICES, PERF, logic/state-machines, enforcement guards, language rules, and linting. Files findings in records/AUDITS/ (rendered to AUDIT.md) and records/FINDINGS/ (PERF.md), then proposes prioritized fixes.
---

> **AGENTS: maintain this file with Haiku or a similar-class model, in grok'd prose.** Style rules: `.agents/harness/rules/QUIET.md`, `.agents/harness/rules/PROSE.md`.

# holon-audit

Run a structured audit on the whole repo or a scoped path (`/holon-audit [path]`). Deterministic tools run first; agent judgment covers only what scripts cannot prove. Findings live in `.agents/records/AUDITS/` (rendered to `records/AUDIT.md`) and `.agents/records/FINDINGS/` (`records/PERF.md`), then feed a proposal into `/plan-and-enact`.

## 1. Mechanical gate

Run the compiled checks first and capture failures as facts (do not re-check them by hand):

```sh
.agents/harness/bin/lint
.agents/harness/bin/check-docs
.agents/harness/bin/write check
.agents/harness/bin/sync-settings --check
.agents/harness/bin/perf-scan <scope>
```

Before filing anything, read `.agents/records/AUDIT.md` and `.agents/records/PERF.md`. Skip items already recorded as `open`, `proposed`, or `wontfix`.

## 2. Five judgment passes

Inspect the scoped code with `.agents/harness/bin/seek` (not `grep`):

1. **Maps and diagrams (`area: docs`).** Compare actual files, imports, and entry points against `.agents/ATLAS.md`, `.agents/codebase/CODEBASE.md`, `.agents/codebase/LIFECYCLE.md`, and `.agents/codebase/maps/*.md`. Flag missing or stale files, inaccurate Mermaid edges, and duplicated detail violating progressive disclosure.
2. **Modularity and practices (`area: modularity`).** Check `.agents/harness/rules/PRACTICES.md`: monolithic files or types doing two jobs, duplicated logic across modules (DRY), and boundary leaks (e.g., core importing UI or hooks reaching into tool internals).
3. **Data structures and cost (`area: patterns` or `finding`).** Judge every `perf-scan` hit and look for what the scanner misses (slow calls inside loops, loop-invariant work, wrong container types). File measurable cost gaps as `finding` records (`write finding new` + `perf-confirm`, per `.agents/harness/rules/PERF.md`), referencing `.agents/records/CATALOG/` or escalating novel structures via `.agents/harness/rules/DESIGN.md`. File structural pattern improvements as `audit` records (`area: patterns`).
4. **Language rules and lint (`area: language`, `area: lint`).** Check rules static lint cannot prove (e.g., `.agents/harness/rules/SWIFT.md` concurrency isolation, typed error propagation, hot-path allocations, API surface). Record unresolved lint failures under `area: lint`.
5. **Logic, state machines, and enforcement (`area: logic`, `area: enforcement`).** Trace state transitions, lock scopes, error/exit paths, parser edge cases, and guard bypasses. Prefer reproducing each finding with a concrete command or hook payload (`evidence: reproduced`, `repro: "..."`); mark code-reading-only findings `evidence: inferred`.

## 3. File records

For each new non-perf finding, write a draft in `.agents/records/drafts/` matching `.agents/harness/templates/audit.closure`:

```
audit(_) {
  name:     "Stale diagram in CODEBASE"
  area:     docs
  unit:     ".agents/codebase/CODEBASE.md:42"
  rule:     "PRACTICES.md progressive disclosure"
  severity: medium
  impact:   medium
  effort:   low
  evidence: reproduced
  repro:    "bin/check-docs"
  fix:      "Update module graph to show TerminalSession between Emulator and UI."
  status:   open
}
```

Check and file each draft:

```sh
.agents/harness/bin/write audit check-draft .agents/records/drafts/<file>.closure
.agents/harness/bin/write audit new .agents/records/drafts/<file>.closure
```

Run `.agents/harness/bin/write render` and `.agents/harness/bin/write check` to refresh `.agents/records/AUDIT.md` and verify all records.

## 4. Propose and hand off

1. Synthesize open `AUDIT.md` and confirmed `PERF.md` findings into one `proposal` draft (`.agents/harness/templates/proposal.closure`), grouped into **Quick Wins** (high/medium impact, low effort), **Doc & Map Drift**, and **Strategic Refactors** (medium/high effort). Reference each item by `[[id]]`.
2. Show the proposal with `.agents/harness/bin/write show <draft>` and ask the user which items to accept, defer, or mark `wontfix`.
3. On approval, file the proposal, update rejected `audit` records to `wontfix`, and hand accepted items to `/plan-and-enact` (each completed task closes its linked `audit` or `finding` record as `fixed`).
