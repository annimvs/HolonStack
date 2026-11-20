# SWIFT — Coding and Concurrency Standards

> **AGENTS: maintain this file with Haiku or a similar-class model, in grok'd prose.** Style rules: [QUIET](QUIET.md), [PROSE](PROSE.md).

<!-- STUB (/adopt-holon): Keep section 6 for `.agents/harness/*.swift`. If the adopting project is not Swift, narrow sections 1-2 to `.agents/harness/` and add a rule file under `harness/rules/` for the project's own language and linter. -->
Section 2, the MARK conventions, applies to all Swift in the project: the package sources (`Sources/`) as well as `.agents/`. The rest applies to every Swift script, hook and tool in `.agents/harness/`. Section 1 covers concurrency. Sections 3 to 5 cover comments, types and complex code, and section 6 covers the linter that checks the harness.

## 1. Swift 6 Strict Concurrency

All Swift code builds in Swift 6 language mode with complete concurrency checking. Keep package manifests at `swift-tools-version: 6.0` with no language-mode override. Harness scripts and hooks are single files that `bin/lint` type-checks with `swiftc -typecheck -swift-version 6 -warnings-as-errors` (section 6).

Make mutable state ownership explicit so the concurrency checker stays useful where code really is concurrent (`Task`, `async`, `DispatchQueue`).
- **One owner per piece of mutable state.** Keep it inside a type, not in a file scope `var`. New code adds no mutable global.
- **Across threads, use `Synchronization`.** A `Mutex` or an `Atomic` replaces `NSLock` with `@unchecked Sendable` in new code.
- **`nonisolated(unsafe)` and `@unchecked Sendable` need a reason.** Put a one-line comment above each saying which single thread owns the value, or which lock guards it. They are an exception, not the way to silence an error.
- **Signal handlers only set a flag.** Store into an `Atomic` or `sig_atomic_t`; the main loop reads it and does the work. Nothing else is safe in a handler.
- **Prefer value types.** `struct` and `enum` cross task boundaries as `Sendable` for free; a `class` that crosses one conforms to `Sendable` or lives behind an actor or lock.
- **A hook or tool reads its input once.** Declare it `nonisolated(unsafe) let` with a `lint-ignore` that says so (see `rawInput` in `hooks/guard-edit.swift`).
- **Warnings are errors.** Fix a compiler warning; do not leave it. A new `nonisolated(unsafe)` that only hides an error is a bug in waiting.

## 2. MARK Conventions (all project Swift)

The code is read in Xcode, so `// MARK:` comments keep the jump bar (Control-6) structured and scannable.

**Syntax:**
- **Major section:** `// MARK: - <Name>`, with a space, a dash and a space, then the name in Title Case. It draws a rule in the jump bar.
- **Sub-group or algorithm:** `// MARK: <Name>`, a plain label with no rule.
- **Never:** `//MARK:`, `// MARK -`, `//mark:`, or a trailing colon (`// MARK: Foo:`).

**Where to put them:**
1. **Sections of a file:** split each file into major sections, and put a label above each major function.
2. **Conformances:** one extension per protocol conformance, each under `// MARK: - <ProtocolName>`.
3. **Lifecycle:** initializers and teardown under `// MARK: - Lifecycle` or `// MARK: - Init`.
4. **Algorithms and data structures:** name each non-trivial one, for example `// MARK: Ring Buffer Slicing` or `// MARK: Breadth-First Traversal`.
5. **Long explanations:** a multi-line comment that explains a design or an implementation gets its own mark above it.
6. **Gotchas:** a subtle trap inside an implementation gets `// MARK: Gotcha: <what>`, as in `// MARK: Gotcha: A Failed Definition Is Rolled Back`.

```swift
// MARK: - Validation

// MARK: Validate draft schema against template
func checkDraft(_ draft: Form, template: Template) -> [String] {
    ...
}
```

In the harness, `lint` checks part of this: the `type-mark` and `mark-sections` rules (section 6). Elsewhere it is guidance, not checked.

## 3. Grok Comments

Every function needs a grok comment that says in plain English what it does.
- State what the function does, what inputs it expects, and what it returns.
- Keep the summary to one or two short sentences.
- Name the exact behavior. "Handles data" is too vague. "Parses bracket-counted closure tokens into a Form tree" says what happens.

## 4. Types

Every `struct`, `enum`, `class`, `actor` and `protocol` gets a `// MARK: - <Name>` banner and a comment saying what the type is for, directly above it. This holds whether the type is `Codable`, `Observable`, `Sendable` or plain, and whether it is nested or at file scope. Write the comment in grok'd prose ([GROK](GROK.md)): what the type holds or does and who uses it, not which protocols it adopts.

```swift
// MARK: - Escalation
/// A draft the writer could not fix, with the reason code and the route it takes next.
struct Escalation: Codable, Sendable {
    ...
}
```

Attributes such as `@frozen` or `@Observable` go between the comment and the type. The lint rules `type-mark` and `type-doc` check this.

## 5. Complex Code and Algorithmic Notes

Add inline comments directly above logic that isn't obvious: tricky state transitions and algorithm branches.
- Explain why a branch or workaround exists, not what the syntax does.
- Document regex expressions, bracket-counting edge cases, and file descriptor operations.

## 6. Lint

`bin/lint <file.swift…>` checks Swift files against the rules in [`lint.closure`](../lint.closure), which only the user edits. Each rule there is one line that names what is enforced; this file explains how to meet it. A rule left out of `lint.closure` is off.

- **Every finding fails:** `bin/lint` exits 1. The edit hook runs it on every saved `.swift` file under `.agents/harness/` and sends the findings back. The packages' own `Sources/` keep their own style and are not linted by these rules.
- **To skip a rule on one line,** write `// lint-ignore: <rule-id>: <why>` on it or on the line above. An ignore with no reason is itself a finding.
- **The checks read lines, not a syntax tree,** so unusual layouts can be missed.
- **Compiler warnings fail too.** With the `compiler-warnings` rule on in `lint.closure`, `bin/lint` type-checks each script under `harness/tools/` and `harness/hooks/` with `swiftc -typecheck -swift-version 6 -warnings-as-errors` and reports every diagnostic as `file:line: compiler-warnings: message`. This is the Swift 6 check of section 1: it costs about 0.2 seconds a file. The build shims compile quietly in the older mode so a hook never fails to start; the lint is where these show.
- **Formatting:** `bin/lint` also runs `swift format lint` on any file with a `.swift-format` file in its folder or above it (`.agents/harness/.swift-format` covers the harness). It reports each finding as `format-<Rule>`. Where `swift format` is missing, it says the style was not checked.
- **`write done` does not lint.** It runs only the task's criteria.

After changing a harness script, run `bin/lint` over `harness/tools/*.swift` and `harness/hooks/*.swift`; it should print nothing. There is no test suite for the linter.
