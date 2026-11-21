# Changelog

## 0.3

- Add `Context reinjected` status block rule (`COMPACT.md`), machine-readable stats lines in `session-compact.swift` and `route-semantics.swift` (prepended so 6k truncation never drops them), and append-only `.cache/reinjections.jsonl`
- Require grok'd prose in compaction instructions (`AGENTS.md`, `pre-compact.swift`)
- Add `READ.md` rule banning unverified disclaimers and wire into `ATLAS.md`
- Add security-sink semantics card (`semantics-security.closure`), Pass 6 (`area: security`) in `/holon-audit` + `audit.closure`, design gate step in `/plan-and-enact`, and `/work-queue` skill
- Add zero-PII `examples/taskflow/` adopted sample repository verified by Step 8 in `scripts/smoke-test.sh`
- Remove tracked `CLAUDE.md`/`GEMINI.md` symlinks and generate them during `/adopt-holon`

## 0.2

- Dogfood the harness at the repository root with project-specific maps, semantics cards, and upstream platform references
- Extend `/holon-audit` schema with `logic` and `enforcement` areas plus `severity`, `evidence`, and `repro` fields
- Harden `guard-bash`, `guard-edit`, `check-drafts`, `sync-hooks`, `sync-settings`, and `write` across initial audit findings (H1–H4, M1–M8):
  - Fail closed on guard compile/runtime errors, lock task criteria/`done` transitions, and validate phase filing before minting IDs
  - Unwrap command wrappers (`sudo`, `env`, `nice`, `timeout`, `xargs`, `eval`, `sh -c`), track `cd`/`pushd`, and expand `$TMPDIR`
  - Preserve adopting projects' existing hooks in `.claude/settings.json` and `.agents/hooks.json`
  - Protect `hooks.json` from direct edits, normalize CRLF drafts, and gate shell-copied drafts
- Add root-vs-shipped harness drift check to `scripts/smoke-test.sh` CI suite

## 0.1

- Initial Release
