# ATLAS — TaskFlow

> **AGENTS: maintain this file with Haiku or a similar-class model, in grok'd prose.** Style rules: [QUIET](harness/rules/QUIET.md), [PROSE](harness/rules/PROSE.md).

Add, remove or rename a file under `.agents/` → update its row here in the same change. Detail files are linked, not imported. Open only the row you need.

## State

| Path | Open when | Detail |
|---|---|---|
| `records/MEMORIES/`, [records/MEMORY.md](records/MEMORY.md) | Starting a task; saving a fact for later | [RECORDS](harness/rules/RECORDS.md) |
| `records/PLAN.closure`, `records/PHASES/`, [records/PLAN.md](records/PLAN.md) | Phased work and what comes next (`write next`) | [RECORDS](harness/rules/RECORDS.md) |
| `records/TODO.closure`, `records/TASKS/`, [records/TODO.md](records/TODO.md) | Ad-hoc open work with `check:` criteria | [RECORDS](harness/rules/RECORDS.md) |
| `records/QUESTIONS/`, [records/OPEN.md](records/OPEN.md) | Something blocked on the user | [RECORDS](harness/rules/RECORDS.md) |
| `records/ISSUES/`, [records/BUGS.md](records/BUGS.md) | Confirmed bugs | [RECORDS](harness/rules/RECORDS.md) |
| `records/AUDITS/`, [records/AUDIT.md](records/AUDIT.md) | Findings from `/holon-audit` | [holon-audit](harness/skills/holon-audit/SKILL.md) |
| `records/PROPOSALS/`, [records/PROPOSALS.md](records/PROPOSALS.md) | Multi-step proposals | [QUIET](harness/rules/QUIET.md) |
| `records/FINDINGS/`, `records/CATALOG/`, `records/DESIGN/` | Cost findings, catalog, and design records | [PERF](harness/rules/PERF.md), [DESIGN](harness/rules/DESIGN.md) |
| `records/SEMANTICS/`, [records/SEMANTICS.md](records/SEMANTICS.md) | Routed semantics cards and `semantics-report` scoreboard | [harness/README.md](harness/README.md) |
| `records/RESULTS/`, `records/INTERFACES/` | Worker results and command contracts | [DELEGATION](harness/rules/DELEGATION.md) |
| `records/drafts/`, `records/.ids`, `records/.write.lock` | Drafts, id ledger, writer lock | [RECORDS](harness/rules/RECORDS.md) |

## The code

| Path | Open when | Detail |
|---|---|---|
| `codebase/CODEBASE.md` | Module graph, task-to-code table, layering rules | [CODEBASE.md](codebase/CODEBASE.md) |
| `codebase/LIFECYCLE.md` | Following an API request or CLI command end to end | [LIFECYCLE.md](codebase/LIFECYCLE.md) |
| `codebase/maps/packages.md` | Which file owns which symbol across `packages/*` | [packages](codebase/maps/packages.md) |

## Harness

| Path | Open when | Detail |
|---|---|---|
| `harness/` | Shared HolonStack harness (staged from `adopt-holon/.agents/harness/` on adoption) | [harness/README.md](harness/README.md) |
| `harness/HARNESS.md` | Architecture diagrams for hooks, guards, and record writes | [HARNESS.md](harness/HARNESS.md) |
| `harness/templates/*.closure`, `harness/reasons.closure`, `harness/lint.closure`, `harness/tools/lint.swift` | Templates, escalation codes, and Swift lint rules | [NOTATION](harness/rules/NOTATION.md) |
| `harness/hooks/`, `harness/hooks.json`, `harness/guards.d/`, `hooks.json` | Hook wiring and Bash guard rules | [harness/README.md](harness/README.md) |
| `harness/.cache/`, `harness/.swift-format` | Compiled `bin/` cache, semantics state, compaction archive | [harness/README.md](harness/README.md) |
| `harness/tools/edit.swift`, `harness/tools/seek.swift`, `harness/hooks/guard-search.swift` | Exact-match editing and unit-level search | [EDITING](harness/rules/EDITING.md) |
| `harness/tools/isolate.swift`, `harness/hooks/guard-agent.swift` | Disjoint worker planning and claim enforcement | [DELEGATION](harness/rules/DELEGATION.md) |
| `harness/hooks/route-semantics.swift` | Semantics card routing | [harness/README.md](harness/README.md) |
| `harness/bin/bootstrap.sh`, `harness/bin/` | Bootstrapping and calling tools/hooks by name | [SCRIPTS](harness/rules/SCRIPTS.md) |
| `harness/skills/closure-system/` | Walkthrough of drafting, checking and filing a record | [SKILL.md](harness/skills/closure-system/SKILL.md) |
| `harness/skills/seek/`, `edit/` | Searching and editing files | [seek](harness/skills/seek/SKILL.md), [edit](harness/skills/edit/SKILL.md) |
| `harness/skills/log-bug/`, `remember/`, `plan-and-enact/`, `work-queue/`, `inject-context/`, `holon-audit/` | Operational skills for bugs, memory, plans, queued work, handoff, and audits | [log-bug](harness/skills/log-bug/SKILL.md), [remember](harness/skills/remember/SKILL.md), [plan-and-enact](harness/skills/plan-and-enact/SKILL.md), [work-queue](harness/skills/work-queue/SKILL.md), [inject-context](harness/skills/inject-context/SKILL.md), [holon-audit](harness/skills/holon-audit/SKILL.md) |

## Rules

| Rule | Open when |
|---|---|
| [ACCESS](harness/rules/ACCESS.md) | What an agent may do without asking |
| [QUIET](harness/rules/QUIET.md) | Reply style and length |
| [READ](harness/rules/READ.md) | Read before claiming; honest fallback |
| [COMPACT](harness/rules/COMPACT.md) | Compaction workflow and `Context reinjected` block |
| [PROSE](harness/rules/PROSE.md) | Plain prose rules |
| [GROK](harness/rules/GROK.md) | Grok'd prose style |
| [NOTATION](harness/rules/NOTATION.md) | Closure syntax |
| [RECORDS](harness/rules/RECORDS.md) | Record kinds and `bin/write` |
| [ESCALATION](harness/rules/ESCALATION.md) | Escalating a stuck draft |
| [VERIFICATION](harness/rules/VERIFICATION.md) | Before `write done` |
| [PRACTICES](harness/rules/PRACTICES.md) | Harness and doc structure |
| [SCRIPTS](harness/rules/SCRIPTS.md) | Single-file Swift scripts |
| [SWIFT](harness/rules/SWIFT.md) | Swift conventions |
| [DESIGN](harness/rules/DESIGN.md) | New types, modules, or cross-boundary APIs |
| [PERF](harness/rules/PERF.md) | Cost findings |
| [TESTS](harness/rules/TESTS.md) | Ordering failure fixes |
| [ROLLBACK](harness/rules/ROLLBACK.md) | Bulk changes |
| [PROJECT](harness/rules/PROJECT.md) | Project facts only |
| [DELEGATION](harness/rules/DELEGATION.md) | Subagent workers and `isolate` |
| [CLEANUP](harness/rules/CLEANUP.md) | Workspace hygiene |
| [EDITING](harness/rules/EDITING.md) | Using `bin/edit` |
