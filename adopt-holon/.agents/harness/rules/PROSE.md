# PROSE

> **AGENTS: maintain this file with Haiku or a similar-class model, in grok'd prose.** Style rules: [QUIET](QUIET.md).

> **AGENTS: this rule applies to everything written here:** docs, rules, records' prose, code comments, commit and task text, and replies.

Write plain, direct technical English. Describe concrete mechanisms, facts and behaviours. [QUIET](QUIET.md) has the table of abstract and consultant words to replace (ground truth, invariant, contract, orthogonal, …); this rule adds the filler that marks text as machine-written, and how to keep it out.

## Filler to cut

| Avoid | Do instead |
|---|---|
| delve, testament, beacon, crucial, leverage, robust, seamless | State the exact behaviour, or drop the word |
| comprehensive, meticulous, holistic, multifaceted | Say what was checked or done |
| fosters, ensures that, empowers | Say what the code does: "refuses", "writes", "checks" |
| in conclusion, it is worth noting, it's important to note | Write the point without the preamble |

When a name in the code uses one of these words, quote it as a name; don't use the word to describe your own work.

## Guidelines

1. **Be factual and concrete.** State what a function takes, returns or changes. Never praise a design or call it clean or robust.
2. **No narration.** Say what changed, the exact paths, and the command that checked it, not the story of how you got there.
3. **Point at the code.** Instead of retelling what code does in prose, name the file and the function, or link to them.
