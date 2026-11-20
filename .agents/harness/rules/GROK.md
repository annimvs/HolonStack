# GROK

> **AGENTS: maintain this file with Haiku or a similar-class model, in grok'd prose.** Style rules: [QUIET](QUIET.md), [PROSE](PROSE.md).

What "grok'd prose" means: writing that a reader understands fully on the first pass. This is a style, not a check. Nothing in `.agents/` enforces it, and it works because agents choose to follow it. [QUIET](QUIET.md) covers how much to say and which words to avoid; this file covers how to say it.

## The rules

1. **Lead with the point.** The first sentence is the answer, the decision or the rule. Background comes after, and only if the reader needs it.
2. **Say what a thing does.** Name the action and what it changes: "the hook blocks the command", not "the hook provides a guarding capability". A category is not an explanation.
3. **Use plain words and short sentences.** One idea per sentence. Pick the common word, and keep technical terms when they name the thing being discussed.
4. **Give the reason once.** A rule says what to do and why, in the same place. Don't repeat it elsewhere; link to it.
5. **Match the shape of the question.** Three numbered questions get three numbered answers, in the same order. A yes or no question starts with yes or no.
6. **Say how you know.** Mark a claim as checked, read, or guessed, once, where it matters. Say plainly what was not verified.
7. **Put code in code.** File names, commands, fields and values go in backticks. A command the reader will run gets its own fenced block.
8. **Recommend one thing.** When there is a choice, name the option you would take and give the reason in a sentence. Lay out the others only if the reader could realistically pick them.
9. **Cut what doesn't help.** Drop restating the request, hedging, praise and offers of more help. There is no length limit; every sentence just has to earn its place.

## Before and after

Before: "The system leverages a validation layer to facilitate draft correctness."

After: "The checker rejects a draft that doesn't match its template, and its error names the line to fix."

## Where it applies

Every reply, every hand-maintained doc in `.agents/`, and the free-prose slots (`grok` and `text`) in records. Generated views follow their template, not this file.
