# MAPS · HolonStack · Harness Hooks (`harness/hooks/` and `harness/guards.d/`)

> **AGENTS: maintain this file with Haiku or a similar-class model, in grok'd prose.** Style rules: [QUIET](../../harness/rules/QUIET.md), [PROSE](../../harness/rules/PROSE.md).

Which file owns what in `.agents/harness/hooks/` and `adopt-holon/.agents/harness/hooks/`. Index: [ATLAS](../../ATLAS.md). Layers: [CODEBASE](../CODEBASE.md); hook dispatch flow: [LIFECYCLE](../LIFECYCLE.md).

## `harness/hooks/` — compiled Swift lifecycle hooks

| File | Owns |
|---|---|
| `sync-settings.swift` | Generates `bin/` wrapper shims, `bin/build.sh`, `.claude/skills/` symlinks, and invokes `sync-hooks` (`--check` reports drift) |
| `sync-hooks.swift` | Reads `harness/hooks.json` and emits `.claude/settings.json` (preserving unrelated top-level keys) and `.agents/hooks.json` |
| `guard-edit.swift` | `PreToolUse(Edit\|Write\|MultiEdit)`: protects indexes, templates, and task criteria; enforces worker claims; steers project edits to `bin/edit` |
| `guard-bash.swift` | `PreToolUse(Bash\|run_command)`: blocks destructive git, unsafe `rm`, writes outside the repo, shell-based file edits, and regex rules from `guards.d/*.json` |
| `guard-search.swift` | `PreToolUse(Grep\|Bash)`: steers project searches from `grep`/`rg` to `bin/seek` (`HOLON_GREP_GUARD`) |
| `guard-agent.swift` | `PreToolUse(Agent\|invoke_subagent)`: refuses spawning project-editing subagents without an unbound `isolate` claim named in the prompt |
| `rewrite-bash.swift` | `PreToolUse(Bash)`: wraps build and test commands in `bin/filter-run` |
| `check-edit.swift` | `PostToolUse`: runs `bin/lint` on harness Swift, checks saved drafts and records, and verifies hook wiring |
| `check-shell-edit.swift` | `PostToolUse(Bash\|run_command)`: detects `bin/edit` invocations and runs `check-edit` and `route-semantics` |
| `check-drafts.swift` | `Stop` / `SubagentStop`: blocks turn completion while any draft in `records/drafts/` fails its template |
| `route-semantics.swift` | `PreInvocation` / `UserPromptSubmit` / `PostToolUse`: injects the `always` card and matching `routed` cards from `records/SEMANTICS/` |
| `pre-compact.swift` | `PreCompact` / `Stop`: archives JSONL and rendered Markdown transcripts into `.cache/` |
| `post-compact.swift` | `PostCompact`: archives compaction summaries |
| `session-compact.swift` | `SessionStart(compact)`: re-injects `MEMORY.md`, `OPEN.md`, and `TODO.md` after compaction |

## `harness/guards.d/` — data-driven Bash regex guards

| File | Owns |
|---|---|
| `criteria-bash.json` | Refuses shell rewrites of filed task criteria |
| `python-scripts.json` | Steers inline Python commands toward single-file Swift scripts |
| `records-delete.json` | Refuses `rm`/`mv`/`unlink`/`trash` on stored records |
| `adopt-template-records.json` | Root-only guard: refuses writing HolonStack's own records into `adopt-holon/.agents/records/` |
