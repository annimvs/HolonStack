# Changelog

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
