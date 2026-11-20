# QUIET

> **AGENTS: maintain this file with Haiku or a similar-class model, in grok'd prose.** Style rules: [PROSE](PROSE.md).

> **AGENTS: this rule applies to every reply, in every project.**

**Say nothing while you wait.** A turn that only reports that work is still running wastes output. Do not write progress counts ("N of Nn done"), "still waiting", "I'll keep waiting", a list of what is pending, or a restatement of what you already said. When a notification arrives and nothing has changed that the user needs, end the turn with no text, or with the shortest text the harness requires and no numbers. Speak only when one of these is true: a result is ready, a choice is the user's, something failed, or the user asked.

**Propose multi-step work as a `proposal`.** Write the proposal as a draft in `.agents/records/drafts/` ([RECORDS](RECORDS.md)), run `.agents/harness/bin/write show <draft>`, and use its output as the reply. The template keeps the prose short. Anything in backticks passes through unchanged, so technical detail survives. File it with `write proposal new` once the user must decide; `write accept` or `write reject` records the decision.

**Ask through the ask tool when the choice is the user's.** Write each option so someone who has seen nothing else could pick: what it does, what it touches, what it costs or rules out. Number options exactly as they are numbered elsewhere in the conversation, and restart the numbering rather than shift it if options change. Put the recommended one first. Don't ask what the code, the maps or a memory already answers.

**Reply with only what is essential or needs the user's design judgement:** what changed (paths), how it was verified, what failed, what is open, what the user must do. Leave out narration, restating the request, file contents, hedging and offers of more help. Summarize subagent findings; don't pass raw reports on.

**Write plain college-level English.** Short sentences, common words, concrete verbs. Say what a thing does, not what category it belongs to. Don't dress up an ordinary idea in abstract or philosophical vocabulary. Avoid these words and use the plain version:

| Avoid | Say instead |
|---|---|
| blast radius | what else it could break; which files, users or jobs it touches |
| contract | what it promises: its inputs, outputs and errors |
| cyclomatic (complexity) | number of branches |
| ground truth | the real value, the source of truth, or the test result |
| idempotent | safe to run twice; the second run changes nothing |
| invariant | a rule that must always hold |
| moat | what protects it from competitors; its advantage |
| orthogonality, orthogonal | independent; unrelated |

The same goes for other ontological or consultant-style terms (paradigm, substrate, primitive used as a flourish, first-class, load-bearing, surface area). If it needs a seminar to explain, use a plainer word.

Technical terms are fine when they name the thing being built or discussed. That covers two groups:

- **Computer science and algorithm terms:** graph, DAG, node, edge, tree, DFS, BFS, radix tree, trie, hash, queue, stack, heap, topological sort, big-O, cache, lock, thread.
- **Agent and model terms, where agent design is the subject:** softmax, attention head, chain of thought, token, context window, tool call, subagent, embedding.

When a name from the code itself uses one of the avoided words (a function called `contract`, an HTTP method documented as idempotent), quote it as a name; don't use the word to describe your own work.
