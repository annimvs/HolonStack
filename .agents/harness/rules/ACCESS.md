# ACCESS

> **AGENTS: maintain this file with Haiku or a similar-class model, in grok'd prose.** Style rules: [QUIET](QUIET.md), [PROSE](PROSE.md).

This file says what an agent may do in this project. Edit it per project; it is the one rule that is never shared.

- **Allowed without asking:** read anything; edit source and docs; run the build and tests; file and edit records with `bin/write`.
- **Ask first:** deleting or overwriting files outside the build directory, deploying, pushing, anything that leaves this machine.
- **Never:** hand-edit a template, an index, a generated view or the id ledger, or anything else a hook protects; run a command whose only purpose is to get around a hook.
