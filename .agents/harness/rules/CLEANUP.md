# CLEANUP

> **AGENTS: maintain this file with Haiku or a similar-class model, in grok'd prose.** Style rules: [QUIET](QUIET.md), [PROSE](PROSE.md).

This file sets the rules for workspace hygiene, temporary files and obsolete artifacts.

## Hygiene Directives

1. **Scratch and Temporary Files:**
   Put one-off debug scripts, test data and temporary scratch files in `.build/` or a project temporary directory. Never leave loose test scripts at the repository root.
2. **Drafts Lifecycle:**
   Drafts in `.agents/records/drafts/` are staging files. After `.agents/harness/bin/write <kind> new` files a draft into permanent storage, delete the draft file or let the writer move it.
3. **Never Hand-Edit Protected Stores:**
   Do not edit `.ids`, `.write.lock` or generated `.md` indexes by hand. Run `.agents/harness/bin/write render` to refresh the human-readable views.
