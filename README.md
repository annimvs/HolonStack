# HolonStack

HolonStack is a portable, deterministic agent harness and structured record system (`.agents/`) packaged as an installable `/adopt-holon` skill for **Claude Code** and **Antigravity / Gemini**.

Instead of relying on ad-hoc prose prompts or fragile scripts, HolonStack separates **enforcement** (compiled Swift hooks and tools), **guidance** (progressive-disclosure Markdown maps and rules), and **state** (validated `.closure` records with generated Markdown views).

## Requirements

- **Swift 6+ toolchain** (`swift` and `swiftc` on `PATH` — macOS Xcode Command Line Tools or Swift 6+ on Linux).
- `.agents/harness/bin/bootstrap.sh` compiles all Swift hooks and tools locally into `.agents/harness/.cache/bin/` and wires `.claude/settings.json`, `.claude/skills/`, and `.agents/hooks.json`.

## Installing `/adopt-holon`

Copy or symlink `adopt-holon/` into your agent's skills directory:

- **Claude Code:**
  ```sh
  ln -s /path/to/HolonStack/adopt-holon ~/.claude/skills/adopt-holon
  ```
- **Antigravity / Gemini:**
  ```sh
  ln -s /path/to/HolonStack/adopt-holon ~/.gemini/antigravity/skills/adopt-holon
  ```

Then open any repository and invoke `/adopt-holon`. The skill:
1. Copies the bundled `.agents/` and `AGENTS.md` into the repository root and creates relative `CLAUDE.md` and `GEMINI.md` symlinks to `AGENTS.md` without clobbering existing settings.
2. Runs `.agents/harness/bin/bootstrap.sh` to compile all Swift tools and hooks and generate client wiring.
3. Detects the project's build system and language(s), tailoring `isolate.swift`, `rewrite-bash.swift`, `check-edit.swift`, and `guards.d/` as needed.
4. Inspects manifests and source files to populate `AGENTS.md`, `ATLAS.md`, `codebase/CODEBASE.md`, `codebase/LIFECYCLE.md`, and per-target `codebase/maps/*.md`.
5. Identifies the project's bounded contexts and domain standards (DDD), downloads authoritative RFCs, specifications, and papers into `.agents/reference/`, and indexes them.
6. Tailors `.agents/records/SEMANTICS/` cards and verifies the setup with `write check`, `check-docs`, `lint`, and `sync-settings --check`.

## Repository layout

```text
HolonStack/
├── README.md                          # This file
├── LICENSE.md                         # MIT License
├── .gitignore                         # Ignores .DS_Store, .cache/, and .write.lock
└── adopt-holon/                       # The installable /adopt-holon skill bundle
    ├── SKILL.md                       # Skill entrypoint (YAML frontmatter + adoption workflow)
    ├── AGENTS.md                      # Root agent instructions stub (/adopt-holon links CLAUDE.md and GEMINI.md to it)
    └── .agents/                       # Portable harness, docs, references, and records
        ├── ATLAS.md                   # Entry map: links every file under .agents/ (open only the row you need)
        ├── codebase/                  # Architecture & execution flow docs (populated during /adopt-holon)
        │   ├── CODEBASE.md            # Target dependency graph (Mermaid), layers, task-to-code table, DDD glossary
        │   ├── LIFECYCLE.md           # End-to-end request/command/pipeline flows, entry points, invariants
        │   └── maps/                  # File-by-file ownership tables per target or bounded context
        │       └── module-template.md # Stub template replaced with real maps during /adopt-holon
        ├── reference/                 # Authoritative upstream RFCs, standards, and domain papers (DDD)
        │   └── README.md              # Index of downloaded specs, editions, and which targets they inform
        ├── records/                   # Structured closure state (written only through bin/write)
        │   ├── .ids                   # Immutable 8-char hex ID ledger (never hand-edited)
        │   ├── CATALOG/               # Language/ecosystem algorithm & data-structure catalog (starts empty)
        │   ├── DESIGN/                # Architecture & algorithm selection records
        │   ├── FINDINGS/              # Performance audit findings with runnable checks
        │   ├── ISSUES/                # Confirmed bugs with minimal repros (view: BUGS.md)
        │   ├── MEMORIES/              # Cross-session facts & preferences (view: MEMORY.md)
        │   ├── PHASES/                # Phased plan stages and nested tasks (view: PLAN.md)
        │   ├── PROPOSALS/             # Multi-step work proposals (view: PROPOSALS.md)
        │   ├── QUESTIONS/             # Open items blocked on the user (view: OPEN.md)
        │   ├── RESULTS/               # Subagent worker result records
        │   ├── SEMANTICS/             # Context-routed area cards (core always-on + routed areas; view: SEMANTICS.md)
        │   ├── TASKS/                 # Ad-hoc tasks with verifiable check: criteria (view: TODO.md)
        │   ├── drafts/                # Staging folder for record drafts before filing via bin/write
        │   └── *.md                   # Generated read-only Markdown views (MEMORY.md, TODO.md, OPEN.md, BUGS.md, PROPOSALS.md, SEMANTICS.md)
        └── harness/                   # Enforcement code, rules, templates, and skills
            ├── README.md              # How the closure system, guards, and tools work
            ├── HARNESS.md             # Mermaid diagrams of enforcement, hook events, and record writes
            ├── hooks.json             # Single source of truth for hook event wiring
            ├── lint.closure           # Swift lint rule definitions for harness/*.swift
            ├── reasons.closure        # Escalation reason codes and routing (model / user / harness)
            ├── .swift-format          # swift-format configuration for harness Swift files
            ├── bin/
            │   └── bootstrap.sh       # Preflight Swift 6+ check, runs sync-settings.swift, compiles bin/build.sh
            ├── catalog-seeds/
            │   └── swift/             # Optional 19 Swift stdlib / swift-collections / swift-algorithms catalog entries
            ├── guards.d/              # Data-driven regex Bash guards (*.json)
            │   ├── criteria-bash.json # Blocks shell rewrites of filed task criteria
            │   ├── python-scripts.json# Steers inline Python to Swift tools (removed during /adopt-holon in Python repos)
            │   └── records-delete.json# Blocks rm/mv/unlink/trash of stored records
            ├── hooks/                 # Thin Swift hook scripts compiled into .cache/bin/
            │   ├── check-drafts.swift # Stop / SubagentStop: blocks turn end while a draft fails its template
            │   ├── check-edit.swift   # PostToolUse: lints harness Swift, checks drafts/records, verifies wiring
            │   ├── check-shell-edit.swift # PostToolUse(Bash/run_command): runs check-edit & route-semantics after bin/edit
            │   ├── guard-agent.swift  # PreToolUse(Agent/invoke_subagent): refuses spawning editing subagents without an unbound isolate claim
            │   ├── guard-bash.swift   # PreToolUse(Bash/run_command): blocks destructive git, unsafe rm, outside writes, shell edits
            │   ├── guard-edit.swift   # PreToolUse(Edit/Write): protects indexes/templates/criteria, enforces worker claims, steers to bin/edit
            │   ├── guard-search.swift # PreToolUse(Grep/Bash): steers project searches to bin/seek
            │   ├── post-compact.swift # PostCompact: archives compaction summaries
            │   ├── pre-compact.swift  # PreCompact / Stop: archives JSONL + Markdown transcripts
            │   ├── rewrite-bash.swift # PreToolUse(Bash): wraps build/test commands in bin/filter-run
            │   ├── route-semantics.swift # Injects matching SEMANTICS/ cards by prompt cues or file path
            │   ├── session-compact.swift # SessionStart(compact): re-injects MEMORY.md, OPEN.md, TODO.md
            │   ├── sync-hooks.swift   # Generates .claude/settings.json (merging top-level keys) and .agents/hooks.json
            │   └── sync-settings.swift# Generates bin/ shims, bin/build.sh, .claude/skills/, and runs sync-hooks
            ├── tools/                 # Standalone Swift CLI tools compiled into .cache/bin/
            │   ├── check-docs.swift   # Verifies AGENTS banners, relative links, skill docs, and zero orphans
            │   ├── edit.swift         # Hash-checked, exact-match/line-range atomic file editor with unified diff
            │   ├── filter-run.swift   # Runs build/test commands, keeps full log, prints concise errors/totals
            │   ├── isolate.swift      # Target dependency graph & parallel worker claim planner (SwiftPM, Cargo, Node/pnpm, Go, CMake)
            │   ├── lint.swift         # Swift 6 typecheck, swift-format, and lint.closure checker for harness scripts
            │   ├── perf-confirm.swift # Runs checks on open performance findings to confirm them
            │   ├── perf-report.swift  # Generates records/PERF.md scoreboard
            │   ├── perf-scan.swift    # Scans loops for catalog smell spans
            │   ├── seek.swift         # Scope-aware search & --outline (Swift, C/C++, Rust, Go, JS/TS, Java, Kotlin, C#, Zig, Python, Markdown, closures)
            │   ├── semantics-report.swift # Measures semantics card routing efficacy and writes records/SEMANTICS.md
            │   ├── transcript-md.swift# Normalizes Claude Code & Gemini JSONL transcripts to compact Markdown
            │   └── write.swift        # Deterministic closure parser, validator, ID minter, canonicalizer, and view renderer
            ├── templates/             # Closure schemas (both agent form and validator spec; user-edited only)
            ├── rules/                 # Agent operating rules (ACCESS, QUIET, PROSE, GROK, NOTATION, RECORDS, EDITING, DELEGATION, SWIFT, DESIGN, PERF, TESTS, etc.)
            └── skills/                # Operational skills synced to .claude/skills/ (closure-system, edit, seek, plan-and-enact, log-bug, remember, inject-context)
```

## Supported Languages & Clients

| Area | Out-of-the-box support |
|---|---|
| **Agent clients** | Claude Code (`.claude/settings.json`, `.claude/skills/`) and Antigravity / Gemini (`.agents/hooks.json`) with full `bin/edit` and `bin/seek` enforcement parity |
| **OS platforms** | macOS (`Darwin`) and Linux (`Glibc`) via Swift 6+ |
| **Graph isolation (`isolate`)** | SwiftPM (`Package.swift`), Cargo (`Cargo.toml`), npm/yarn/bun (`package.json`), pnpm (`pnpm-workspace.yaml`), Go (`go.mod`), CMake (`CMakeLists.txt`); extensible for Meson, Ninja, Bazel, Gradle, Make during `/adopt-holon` |
| **Scope-aware search (`seek`)** | Swift, C/C++/ObjC, Rust, Go, JS/TS, Java, Kotlin, C#, Zig, Python, Markdown, `.closure` |

## License

MIT — see [LICENSE.md](LICENSE.md).
