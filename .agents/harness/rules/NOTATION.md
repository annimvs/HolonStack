# NOTATION

> **AGENTS: maintain this file with Haiku or a similar-class model, in grok'd prose.** Style rules: [QUIET](QUIET.md), [PROSE](PROSE.md).

An agent writes anything a script must read as nested closures: `()` `[]` `{}`, in a loose C/Swift style. A parser that counts brackets and matches a template can then check the output. A failed check names the line and the rule.

## The grammar

```
form  := ident "(" [value ("," value)*] ")" [block]
block := "{" (ident ":" value)* "}"
value := "string" | """multi-line""" | atom | [list, …] | { block } | form(…)
// comments run to end of line
```

- `()` names a thing and its identity: `task(3fa91c2e)`. `{}` holds its fields, `[]` holds ordered items.
- Commas and newlines both separate. Strings are double-quoted; `"""` opens a multi-line string whose common indent is stripped. Everything else is a bare atom (`open`, `3fa91c2e`, `2h`).
- Nest as deep as the content is. Never flatten a list into a sentence.
- A record file is exactly one form. Nothing may follow its closing `}`.

## Templates

Each kind has a template in [`templates/`](../templates/). A template is a record whose value slots hold placeholders. Its first line names where records are stored: `// store: PHASES/phase-{n}-{name}.closure`. The checker walks the template and the record side by side.

| Placeholder | The value must be | Filled by |
|---|---|---|
| `grok("<= 8 words, no dashes")` | one quoted line of plain prose; the text inside is guidance on size and style, not a limit the checker enforces. Only the file name slug is capped (8 words) | the model |
| `text("…")` | a non-empty string, may be multi-line | the model |
| `enum(a, b, c)` | one of the listed atoms | the model |
| `duration()` | `30m`, `2h` or `1.5d` | the model |
| `ref(kind)` | the id of an existing record of that kind | the model |
| `id()` | 8 lowercase hex characters | the tool |
| `index()` | a positive integer, never reused | the tool |
| `bool(false)` | `true` or `false`; the argument is the default | the tool |
| `opt(x)` | `x`, or the field may be left out | the model |
| `many [ item ]` | a list of zero or more `item` | the model |
| `use(kind)` | in a draft, a whole `kind` record nested; stored, its id | the tool |
| `score("min..max")` | a numeric score within the specified range (e.g. `0.0..1.0` or `1..5`) | the model |
| `detect()` | `true` or `false` boolean detection indicator | the model |
| `derived(…)` | never written; computed when read | nobody |

A placeholder marks what goes in a slot. Never write one in a draft. In a template, `depends: many [ ref(phase) ]` means a draft writes `depends: []` or the ids of phases that already exist. A `grok` slot is always one line, with no line break inside the quotes, even when its limit is sentences or words. Its limits apply to the prose only: each `` `code span` `` counts as one word and its contents are not checked, so technical detail stays exactly as written.

Fields must appear in the template's order. An unknown field, a missing field, a wrong value or a wrong item form is an error with a line number.

## Drafts and stored records

The agent writes a **draft**: the template's shape with `_` where the tool fills an id, and with `index()`, `bool(…)` and `many` fields allowed to be left out. Inside a `plan` draft, an inline `phase` may carry a draft label (`phase(parse) { … }`) so another phase in the same draft can cite `depends: [parse]`; the writer replaces each label with its minted hex id.

```
phase(_) {
  name: "Build the template parser"
  tasks: [
    task(_) { name: "Write the template parser", est: 3h },
  ]
}
```

`write phase check-draft <file>` checks a draft. `write phase new <file>` checks it, assigns ids, numbers and defaults, validates the result again, and writes it in canonical form. The agent never types an id and never types a file name.

## Canonical form and lint

The writer emits one layout: two-space indent, one field per line, lists of scalars inline, lists of records one per line with a trailing comma. `write lint <file>` fails on a syntax error or on a record that is not byte-for-byte what the writer would emit; `write lint --fix <file>` rewrites it. Templates are linted for syntax only.

## Pseudocode for plans and procedures

When a record, plan or procedure that a script or another agent reads describes steps, write them as C/Swift-shaped pseudocode with a fixed verb set, not paragraphs. Replies to the user are prose; never answer in closures or pseudocode:

```
func route(task) {
  guard !touches(task, ["parser", "executor"]) else { return .deep }
  if readOnly(task) { return .direct }
  return .standard
}
```

- One statement per line. `guard … else { … }` for preconditions, `for … in … where …` for loops, `if/else` for branches.
- Calls name real tools or scripts, such as `write check`. A call to a name that does not exist is a bug in the plan.
- Every `{` closes on its own line at the indent it opened.

## What is enforced

The checker enforces these today: balanced brackets, one form per file, the template for every record, the placeholder types and limits, field order, ids that resolve, filenames, `depends` without cycles, and canonical form. It does not yet check the pseudocode blocks above (a bracket-balance check on fenced blocks is the first one planned), and it does not check free prose.
