# ROLLBACK

> **AGENTS: maintain this file with Haiku or a similar-class model, in grok'd prose.** Style rules: [QUIET](QUIET.md), [PROSE](PROSE.md).

Before a large or destructive change, make sure there is a state to return to.

Before you delete, overwrite or rewrite many files, run `git status --porcelain` in the repository checkout. If it lists changes you did not make, stop and tell the user before you start. Say which of their files the change would touch, and ask whether to go on; commits are the user's, so never make one to protect them.

**Why:**
- The user keeps work in progress uncommitted in `Sources/`; a rewrite on top of it can't be undone.
- `.agents/`, `AGENTS.md` and `.claude/` may not be tracked in git.
- The hooks block only the worst commands.

**How to apply:**
- **When:** before any change that touches more than a few files, and before any delete or overwrite outside `.build/` and scratch.
- **Untracked files:** copy them outside the tree first, to the session's scratch folder. This covers `.agents/` stores, for example before rewriting many records.
- **Deleting:** move whole folders to the Trash instead of deleting them.
- **Afterwards:** say where the copy or the Trash folder is.
