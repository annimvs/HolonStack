---
name: adopt-holon
description: Adopt the Holon .agents harness in the current project. Copies the bundled .agents/ and AGENTS.md from this skill's directory into the project root, bootstraps and compiles the Swift tooling into bin/, inspects the project's manifests and source tree to fill the AGENTS.md, ATLAS.md, CODEBASE.md, LIFECYCLE.md and map stubs, downloads authoritative domain RFCs and specifications (DDD) into reference/, and configures semantics cards.
---

> **AGENTS: maintain this file with Haiku or a similar-class model, in grok'd prose.** Style rules: `.agents/harness/rules/QUIET.md`, `.agents/harness/rules/PROSE.md`.

# adopt-holon

Use this skill when running `/adopt-holon` in a repository to install the bundled `.agents/` harness and fill every stubbed document and record from the adopting project's codebase and domain.

## 1. Copy the bundled harness and bootstrap `bin/`

`.agents/` and `AGENTS.md` are bundled directly beside this `SKILL.md` file.

1. **Locate `<SKILL_DIR>`:** use the directory that holds this `SKILL.md` (if your runtime didn't pass the path, check `~/.claude/skills/adopt-holon`, `~/.gemini/antigravity/skills/adopt-holon`, or wherever this skill is installed).
2. **Copy `.agents/` and preserve existing root docs:**
   - Copy `.agents/` into the project root:
     ```sh
     cp -R "$SKILL_DIR/.agents" .
     ```
   - If `AGENTS.md` does **not** exist yet, copy `$SKILL_DIR/AGENTS.md` and create relative `CLAUDE.md` and `GEMINI.md` symlinks pointing to `AGENTS.md`:
     ```sh
     cp "$SKILL_DIR/AGENTS.md" .
     [ -e CLAUDE.md ] || ln -s AGENTS.md CLAUDE.md
     [ -e GEMINI.md ] || ln -s AGENTS.md GEMINI.md
     ```
   - If the project **already has** `AGENTS.md`, `CLAUDE.md`, or `GEMINI.md`, do not overwrite it: merge the `.agents/ATLAS.md` pointer, record rules, `bin/edit` rule, and Compact instructions into the existing file, and include the required `> **AGENTS: maintain this file with Haiku or a similar-class model, in grok'd prose.**` banner in lines 1–8 of `AGENTS.md` so `bin/check-docs` passes.
3. **Add harness caches to `.gitignore`:**
   - Append `.agents/harness/.cache/` and `.agents/records/.write.lock` to `.gitignore` (if not already ignored) so compiled binaries, run logs, and transcripts stay untracked.
4. **Compile the Swift tooling into `bin/` and generate hook wiring.** Run the bootstrap stub in `.agents/harness/bin/bootstrap.sh`:
   ```sh
   .agents/harness/bin/bootstrap.sh
   ```
   This checks for `swift`/`swiftc`, runs `swift .agents/harness/hooks/sync-settings.swift` (generating `.agents/harness/bin/<name>` shims, `.agents/harness/bin/build.sh`, `.claude/skills/`, `.agents/hooks.json`, and merging hooks into `.claude/settings.json` while preserving existing settings), and then executes `.agents/harness/bin/build.sh` to compile all `hooks/*.swift` and `tools/*.swift` binaries into `.agents/harness/.cache/bin/`.

## 2. Survey the build system, project structure, and domain (DDD)

1. **Detect the build system and language(s), and tailor the harness scripts:**
   - **Graph isolation (`.agents/harness/tools/isolate.swift`):**
     - **Single-target / simple repo** (one executable or library with no sub-targets): skip rewriting `isolate.swift`—parallel target isolation isn't needed.
     - **SwiftPM, Cargo, Node/pnpm, Go, and CMake** (`Package.swift`, `Cargo.toml`, `package.json`/`pnpm-workspace.yaml`, `go.mod`, `CMakeLists.txt`): `isolate.swift` works out of the box.
     - **Meson / Ninja / Bazel / Gradle / Make** (`meson.build`, `build.ninja`, `BUILD.bazel`, `build.gradle`, `Makefile`): add a graph loader to `loadGraph` in `isolate.swift` (e.g., `meson introspect --targets`, `ninja -t graph`, `bazel query`, or manifest parsing), keeping `Graph`, `Claim`, and the CLI unchanged. Follow `.agents/harness/rules/SWIFT.md` (`// MARK: - <Type>` + `///` doc comments, Swift 6 concurrency) so `bin/lint` passes on the first save.
   - **Build output filtering (`.agents/harness/hooks/rewrite-bash.swift` and `tools/filter-run.swift`):**
     - Extend `rewrite-bash.swift`'s `pattern` for the project's build and test commands (e.g. `cmake --build`, `ctest`, `meson compile`, `ninja`, `npm test`, `pnpm build`, `cargo build`, `cargo test`, `pytest`, `go test`).
     - Verify `filter-run.swift`'s `keep` / `drop` regexes match the project's compiler and test-runner diagnostics.
   - **Linting & code rules (`.agents/harness/hooks/check-edit.swift` and `rules/`):**
     - Keep `.agents/harness/tools/lint.swift` and `.agents/harness/lint.closure` for the Swift harness scripts under `.agents/harness/`.
     - Detect the adopting project's language(s) and linters/formatters (e.g. `clang-format`/`clang-tidy`, `eslint`/`biome`/`prettier`, `clippy`/`rustfmt`, `golangci-lint`, `ruff`, `swift-format`), wire them into `check-edit.swift` if the project wants post-edit checks on source files, and add or adapt a language coding-standards rule under `.agents/harness/rules/` (linked in `ATLAS.md`).
   - **Language-specific guards and tooling for non-Swift repos:**
     - **Python projects:** remove `.agents/harness/guards.d/python-scripts.json` (which blocks inline Python) and update `ATLAS.md` / `harness/README.md` accordingly.
     - **Multi-language search (`tools/seek.swift`):** `seek.swift` parses declaration units out of the box for Swift, C/C++/ObjC, Rust, Go, JS/TS, Java, Kotlin, C#, Zig, Python, Markdown, and `.closure`. If your project uses another language or needs custom unit rules, extend `seek.swift` or set `HOLON_GREP_GUARD=off`.
     - **Performance catalog (`records/CATALOG/`, `tools/perf-scan.swift`):** `records/CATALOG/` starts empty so non-Swift repos aren't stuck with Swift entries. For Swift projects, seed it by copying `.agents/harness/catalog-seeds/swift/*.closure` into `.agents/records/CATALOG/` (or filing them with `write entry new`). For non-Swift projects, file language-appropriate `entry` records using `ships: stdlib`, `ships: package`, or `ships: none` (and update `perf-scan.swift`'s file extension filter if you use `perf-scan`).
   - After editing any `.swift` file under `.agents/harness/`, run `.agents/harness/bin/lint` on it and re-run `.agents/harness/bin/build.sh` so the cached binary in `.cache/bin/` is rebuilt.
2. **Inspect the target dependency graph:**
   - Run `.agents/harness/bin/isolate graph` to get every package/target, source path, dependency closure, and choke point.
3. **Identify bounded contexts and ubiquitous language:**
   - Use `.agents/harness/bin/seek --outline` on key entry points and core domain files to map the layers, public types, protocols, and state machines.
   - Note the exact domain vocabulary (DDD ubiquitous language) used in type and module names.

## 3. Fill the Markdown stubs using `bin/edit`

Use `.agents/harness/bin/edit` (never raw shell redirects on existing project files) to replace every `<!-- STUB: ... -->` comment and placeholder table with concrete facts from the codebase, following `.agents/harness/rules/PROSE.md`, `.agents/harness/rules/QUIET.md`, and `.agents/harness/rules/PROJECT.md`:

1. **`AGENTS.md`**:
   - Replace `<Project Name>` and the opening stub paragraph with the project's packages, targets, products, and path conventions.
2. **`.agents/codebase/CODEBASE.md`**:
   - Draw the Mermaid `flowchart TB` dependency diagram from `Package.swift` / `bin/isolate graph` (direct dependencies only, grouped by architectural subgraph).
   - Write **Layers**, **Start here by task** (mapping common changes to flow docs and exact source files), **Glossary** (the domain's ubiquitous language), **Layering rules**, **Maps**, and **Flows**.
3. **`.agents/codebase/LIFECYCLE.md`**:
   - Trace the primary end-to-end operation(s) in the project (request, command, compilation pass, transaction, or event loop).
   - Replace the stub Mermaid `sequenceDiagram` and `flowchart TB` blocks with the real types, method calls, and branching decisions.
   - Fill **Entry points** (exact file paths and function names) and **Invariants and gotchas**.
4. **`.agents/codebase/maps/<area>.md`**:
   - Create one map file per target or bounded context (following `codebase/maps/module-template.md`), listing every source file in that target and what it owns.
   - Delete `codebase/maps/module-template.md` once the real map files are written.
5. **`.agents/ATLAS.md`**:
   - Replace `<Project Name>` and the opening description.
   - Update **Before any work** item 4 with the project's verification command or test suite.
   - Update **The code** and **Maps: which file owns what** so every doc in `codebase/` and `codebase/maps/` has a row and link.

## 4. Download authoritative domain references (DDD)

Populate `.agents/reference/` with authoritative specifications for the project's domain:

1. **Determine the authoritative specs:** from the project's bounded contexts, protocols, wire formats, standards, or algorithms, list the upstream documents that define correctness (IETF RFCs, W3C/WHATWG specs, POSIX/IEEE chapters, ECMA standards, Unicode annexes, format specs, or foundational papers).
2. **Download them into `.agents/reference/<TOPIC>/`:**
   - Create one uppercase topic folder per domain area (e.g., `.agents/reference/RFC/`, `.agents/reference/HTTP/`, `.agents/reference/CRYPTO/`).
   - Fetch the published text, HTML, Markdown, or PDF files into those folders (e.g. `curl -fsSL https://www.rfc-editor.org/rfc/rfc9110.txt -o .agents/reference/HTTP/rfc9110-http-semantics.txt`).
   - Never write summaries in place of upstream specs; store the upstream text as published.
   - **Offline or paywalled fallback:** if a spec cannot be downloaded (network restricted, paywalled ISO/IEEE doc, or JS-only portal), list it under a `## Not here yet` section in `.agents/reference/README.md` with its canonical URL and edition, and file a `question` if the user needs to supply a local copy.
3. **Index them in `.agents/reference/README.md` and `.agents/ATLAS.md`:**
   - In `.agents/reference/README.md`, replace the stub section with one table per `<TOPIC>` folder: `File`, `What`, `Informs` (which target/file in `CODEBASE.md` uses it), and `Source, edition`.
   - In `.agents/ATLAS.md` under **Domain references**, add one row per `<TOPIC>` folder saying when an agent should open it.

## 5. Tailor semantics cards and guards

1. **Update `.agents/records/SEMANTICS/semantics-core.closure`:**
   - Replace the stub line in `holds` with the project's packages, targets, verification rule, and core invariants.
   - Add key domain terms to `terms`.
2. **Tailor `semantics-security.closure` and add domain cards:**
   - Append the project's own security-sensitive paths (process launch, auth, secrets, parsers, plugins) and language sinks to `.agents/records/SEMANTICS/semantics-security.closure` through `bin/write`.
   - For each major bounded context or subsystem, draft a `semantics` record in `.agents/records/drafts/<area>.closure` (`scope: routed`, with `paths`, `cues`, `holds`, `terms`, `next`) and file it with `.agents/harness/bin/write semantics new .agents/records/drafts/<area>.closure`.
3. **Add project-specific Bash guards (if needed):**
   - If the project has protected deployment paths, signing rules, or forbidden commands, add a `.json` rule file under `.agents/harness/guards.d/`.

## 6. Verify the adoption

Run all five checks from the project root and fix any reported issue before finishing:

```sh
.agents/harness/bin/write check
.agents/harness/bin/write render
.agents/harness/bin/check-docs
.agents/harness/bin/lint .agents/harness/hooks/*.swift .agents/harness/tools/*.swift
.agents/harness/bin/sync-settings --check
```
