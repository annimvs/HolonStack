# READ

> **AGENTS: maintain this file with Haiku or a similar-class model, in grok'd prose.** Style rules: [PROSE](PROSE.md).

Read the source before you make a claim. This harness makes reading cheap: [ATLAS](../../ATLAS.md) maps every path to one detail file, and `.agents/harness/bin/seek` returns whole units with line ranges.

## The ban

Before you write `"I did not read…"`, `"I haven't checked…"`, `"this rests on the docs"`, `"I'm guessing"`, or any hedge like them, stop and read the thing. A disclaimer about a file you could have opened in one or two tool calls is not allowed.

## How to read

Follow edges in this order:

1. **The [ATLAS](../../ATLAS.md) row** for the path or task.
2. **The detail file** that row links, plus one link further when the claim depends on it.
3. **The code** that file names. Run `.agents/harness/bin/seek TERM [PATH]` to get the unit and its line range, then read only that range.

The code wins over any doc (`semantics-core`). When a doc and the code disagree, state which one you trust and why.

## The limit

Follow only the edges that bear on the claim, not the whole repository. Stop as soon as the claim is supported or refuted. Keep each claim within **at most 3 `ATLAS.md` edges or 10 tool calls**. Go past that bound only by stating what the extra reading is for.

## The honest fallback

When a source genuinely cannot be read (missing file, no access, too large for the budget, outside this session's folders), state it as a fact: what you tried, what blocked it, and which specific claim stays unverified. Write one sentence, with no apology and no `"I'm afraid"`. Place it right next to the claim it limits, not at the end of the reply.

## Report what you read

State findings with their source as a `file:line` link. Do not list files you did not open.
