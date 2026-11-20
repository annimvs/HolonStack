# reference — upstream agent platform and standard specifications

> **AGENTS: maintain this file with Haiku or a similar-class model, in grok'd prose.** Style rules: [QUIET](../harness/rules/QUIET.md), [PROSE](../harness/rules/PROSE.md).

Authoritative upstream documentation as published by Anthropic (Claude Code), Google (Antigravity and Gemini CLI), OpenAI (Codex CLI and Function Calling), and cross-client open standards (`agentskills.io`, `AGENTS.md`). Add a file → add its row here with its source, fetch date, and the HolonStack file it informs. Never edit an upstream file in place: fetch a newer edition and update the row.

## `CLAUDE_CODE/`

| File | What | Informs | Source, fetched |
|---|---|---|---|
| `CLAUDE_CODE/hooks.md` | Hook lifecycle events (`PreToolUse`, `PostToolUse`, `Stop`, `SubagentStop`, `PreCompact`, `PostCompact`, `SessionStart`, `UserPromptSubmit`), JSON stdin/stdout schemas, matchers, exit codes | `sync-hooks.swift`, `hooks/*.swift`, `hooks.json` | Claude Code Docs, `https://code.claude.com/docs/en/hooks.md`, 2026-11-20 |
| `CLAUDE_CODE/tools-reference.md` | Built-in tool names (`Bash`, `Edit`, `Write`, `Grep`, `Agent`) and input schemas | `guard-edit.swift`, `guard-bash.swift`, `guard-search.swift`, `guard-agent.swift`, `rewrite-bash.swift` | Claude Code Docs, `https://code.claude.com/docs/en/tools-reference.md`, 2026-11-20 |
| `CLAUDE_CODE/skills.md` | Skill directory layout, `SKILL.md` YAML frontmatter, discovery paths, invocation rules | `adopt-holon/SKILL.md`, `sync-settings.swift`, `harness/skills/` | Claude Code Docs, `https://code.claude.com/docs/en/skills.md`, 2026-11-20 |
| `CLAUDE_CODE/settings.md` | `.claude/settings.json` hierarchy, hook keys, permission rules | `sync-hooks.swift`, `sync-settings.swift` | Claude Code Docs, `https://code.claude.com/docs/en/settings.md`, 2026-11-20 |
| `CLAUDE_CODE/memory.md` | `CLAUDE.md` discovery, loading priority, and compaction interaction | `AGENTS.md`, `CLAUDE.md`, `session-compact.swift`, `pre-compact.swift` | Claude Code Docs, `https://code.claude.com/docs/en/memory.md`, 2026-11-20 |
| `CLAUDE_CODE/sub-agents.md` | Subagent invocation, `agent_id` hook payloads, `SubagentStop`, isolation rules | `guard-agent.swift`, `guard-edit.swift`, `check-drafts.swift`, `DELEGATION.md` | Claude Code Docs, `https://code.claude.com/docs/en/sub-agents.md`, 2026-11-20 |
| `CLAUDE_CODE/tool-use-overview.md` | Anthropic Messages API tool definitions, `tool_use` / `tool_result` blocks, loop contract | `transcript-md.swift`, `hooks/*.swift` | Claude Platform Docs, `https://platform.claude.com/docs/en/agents-and-tools/tool-use/overview.md`, 2026-11-20 |

## `ANTIGRAVITY/`

| File | What | Informs | Source, fetched |
|---|---|---|---|
| `ANTIGRAVITY/hooks.md` | Antigravity `.agents/hooks.json` schema, hook events (`PreInvocation`, `PreToolUse`, `PostToolUse`, `Stop`), tool matchers (`run_command`, `edit_file`, `write_file`, `invoke_subagent`) | `sync-hooks.swift`, `hooks.json`, `hooks/*.swift` | Antigravity Docs, `https://antigravity.google/docs/hooks.md`, 2026-11-20 |
| `ANTIGRAVITY/skills.md` | Antigravity skill discovery (`.agents/skills/`, `~/.gemini/antigravity/skills/`), `SKILL.md` frontmatter | `adopt-holon/SKILL.md`, `harness/skills/` | Antigravity Docs, `https://antigravity.google/docs/skills.md`, 2026-11-20 |
| `ANTIGRAVITY/rules.md` | Antigravity rule discovery (`GEMINI.md`, `AGENTS.md`, `.agents/rules/`), activation modes | `AGENTS.md`, `GEMINI.md`, `route-semantics.swift` | Antigravity Docs, `https://antigravity.google/docs/rules.md`, 2026-11-20 |
| `ANTIGRAVITY/plugins.md` | Antigravity plugin bundle structure for packaging skills, rules, and hooks | `adopt-holon/`, `README.md` | Antigravity Docs, `https://antigravity.google/docs/plugins.md`, 2026-11-20 |
| `ANTIGRAVITY/gemini-cli-hooks-reference.md` | Gemini CLI hook events, JSON stdin/stdout contract, and exit codes | `sync-hooks.swift`, `hooks/*.swift` | Gemini CLI Docs, `https://geminicli.com/docs/hooks/reference.md`, 2026-11-20 |
| `ANTIGRAVITY/gemini-cli-skills.md` | Gemini CLI skill layout and activation | `adopt-holon/SKILL.md`, `harness/skills/` | Gemini CLI Docs, `https://geminicli.com/docs/cli/skills.md`, 2026-11-20 |

## `OPENAI/`

| File | What | Informs | Source, fetched |
|---|---|---|---|
| `OPENAI/codex-hooks.md` | Codex CLI `.codex/hooks.json` lifecycle events, matchers, JSON payloads, exit code 2 blocking | `sync-hooks.swift`, future Codex hook adapter | OpenAI Codex Docs, `https://developers.openai.com/codex/hooks.md`, 2026-11-20 |
| `OPENAI/codex-skills.md` | Codex skill structure (`SKILL.md`, `openai.yaml`, progressive disclosure) | `adopt-holon/SKILL.md`, `harness/skills/` | OpenAI Codex Docs, `https://developers.openai.com/codex/skills.md`, 2026-11-20 |
| `OPENAI/codex-rules.md` | Codex execution rules and command approval policies | `guard-bash.swift`, `guards.d/` | OpenAI Codex Docs, `https://developers.openai.com/codex/rules.md`, 2026-11-20 |
| `OPENAI/codex-subagents.md` | Codex subagent spawning, sandboxing, and delegation contracts | `guard-agent.swift`, `DELEGATION.md` | OpenAI Codex Docs, `https://developers.openai.com/codex/subagents.md`, 2026-11-20 |
| `OPENAI/codex-agents-md.md` | Codex `AGENTS.md` discovery hierarchy and size limits | `AGENTS.md`, `adopt-holon/AGENTS.md` | OpenAI Codex Docs, `https://developers.openai.com/codex/guides/agents-md.md`, 2026-11-20 |
| `OPENAI/function-calling.md` | OpenAI Responses / Chat Completions tool definitions and tool-call loop | `transcript-md.swift`, cross-client tool schemas | OpenAI API Docs, `https://developers.openai.com/api/docs/guides/function-calling.md`, 2026-11-20 |

## `STANDARDS/`

| File | What | Informs | Source, fetched |
|---|---|---|---|
| `STANDARDS/agentskills-specification.md` | Cross-client Agent Skills specification (`SKILL.md` frontmatter, directory layout, naming rules) | `adopt-holon/SKILL.md`, `harness/skills/*/SKILL.md` | Agent Skills Spec, `https://agentskills.io/specification.md`, 2026-11-20 |
| `STANDARDS/agents-md.md` | Cross-client `AGENTS.md` convention | `AGENTS.md`, `adopt-holon/AGENTS.md` | agents.md, `https://raw.githubusercontent.com/agentsmd/agents.md/main/README.md`, 2026-11-20 |
