# MAPS · HolonStack · Verification & CI (`scripts/`, `.github/`)

> **AGENTS: maintain this file with Haiku or a similar-class model, in grok'd prose.** Style rules: [QUIET](../../harness/rules/QUIET.md), [PROSE](../../harness/rules/PROSE.md).

Which file owns what in `scripts/` and `.github/`. Index: [ATLAS](../../ATLAS.md). Layers: [CODEBASE](../CODEBASE.md); verification lifecycle: [LIFECYCLE](../LIFECYCLE.md).

## `scripts/` and `.github/workflows/`

| File | Owns |
|---|---|
| `scripts/smoke-test.sh` | Stages a synthetic multi-language temp workspace, copies `adopt-holon/.agents/` and `AGENTS.md`, runs `bootstrap.sh`, `sync-settings --check`, `lint`, `check-docs`, `write check`, `seek`, `edit`, `isolate`, `guard-agent`, `guard-edit`, and task + audit record lifecycles |
| `.github/workflows/ci.yml` | Runs `./scripts/smoke-test.sh` on `macos-15` and `ubuntu-24.04` (Swift 6.0) on push and pull requests to `main` |
