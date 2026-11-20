# reference — authoritative RFCs, standards and domain literature (DDD)

> **AGENTS: maintain this file with Haiku or a similar-class model, in grok'd prose.** Style rules: [QUIET](../harness/rules/QUIET.md), [PROSE](../harness/rules/PROSE.md).

<!-- STUB: Run /adopt-holon to identify the adopting project's bounded contexts, protocols, file formats and algorithms, download the authoritative RFCs, standards, vendor manuals or papers into `reference/<DOMAIN>/`, and index them below. -->
These are the upstream authoritative texts as published for the project's domain, not notes about our code. Add a file → add its row here with its source, edition and the bounded context or target it informs. Never edit an upstream file in place: fetch a newer edition and update the row.

## How `/adopt-holon` populates this folder

1. **Identify the domain standards (DDD):** inspect `Package.swift`, imports, protocol names, parsers, wire formats, cryptography, storage engines, and domain types to list the exact external specifications the codebase implements or depends on.
2. **Create one subfolder per domain topic:** e.g. `reference/RFC/`, `reference/PROTOCOL/`, `reference/STORAGE/`, `reference/ALGORITHMS/`.
3. **Download authoritative texts locally:** fetch plain text, HTML, Markdown or PDF directly from the standard body (IETF RFCs, W3C, ECMA, POSIX, Unicode, vendor documentation, or foundational papers) so agents can read and verify against the exact specification offline without guessing from training memory.
4. **Index every file below** and add a row per topic folder under "Domain references" in [ATLAS](../ATLAS.md).

## `<DOMAIN_TOPIC>` (Stub)

| File | What | Informs | Source, edition |
|---|---|---|---|
| `<DOMAIN_TOPIC>/<spec-file.txt>` | Replace with the section or scope of the specification | Replace with the target or type in [CODEBASE](../codebase/CODEBASE.md) that implements it | Replace with the standard title, RFC number or edition, and canonical URL |
