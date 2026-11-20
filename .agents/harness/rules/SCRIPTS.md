# SCRIPTS

> **AGENTS: maintain this file with Haiku or a similar-class model, in grok'd prose.** Style rules: [QUIET](QUIET.md), [PROSE](PROSE.md).

Write tooling as one Swift file and call it through its `bin/` entry point. The entry point builds the file with `swiftc` the first time, keeps the binary in `.agents/harness/.cache/bin`, and rebuilds it when the source is newer. Only the Swift toolchain is needed. Don't write Python. A saved `.swift` file can be read, audited and re-run, and an inline interpreter heredoc leaves nothing behind.

## How

1. Write a script as plain Swift source with no shebang. Start with `import Foundation`. Read input from `CommandLine.arguments` or stdin. It must compile on its own with `swiftc`, so it can use nothing but Foundation and the standard library.
2. Keep a one-off script in the session's scratch directory and run it with `swift <file>`. Put a reusable tool in `.agents/harness/tools/`, or a harness hook in `.agents/harness/hooks/`. Add its ATLAS row, then run `.agents/harness/bin/sync-settings`. That generates `.agents/harness/bin/<name>`, a `/bin/sh` entry point, and keeps `.agents/harness/bin/build.sh` current. Call the tool by that name.
3. The first call of a tool pays for its build, about a second for a hook. Run `.agents/harness/bin/build.sh` once to build every tool ahead of time, four at a time; it skips a binary that is newer than its source. A warm call takes about 30 ms, against about 400 ms for running the source with `swift`.
4. A hook reports through its exit status and its output. Exit 2 blocks. If the build fails, the entry point runs the source under `swift`. If a hook's binary exits with any status other than 0 or 2 (a crash), the entry point drops the cached binary and reruns the source under `swift`. A broken binary therefore cannot turn a guard into a no-op.
5. Exit non-zero on failure, and print only what the caller needs.

Examples to copy: [hooks/guard-bash.swift](../hooks/guard-bash.swift) (JSON on stdin, exit code as the result), [tools/write.swift](../tools/write.swift) (parser, subcommands, file output).

## Running a script through holon

A one-off script can also run through `holon` instead of `swift`. It compiles once and caches the binary: about 0.4 s the first run, about 0.02 s after. A file is one of two kinds, never both:

- **`.swift`:** plain source with no shebang. Run it as `holon path/to/script.swift args…`.
- **A holon script:** an executable file whose first line is `#!/usr/bin/env holon`. Run it directly. Use this for a script a person runs from a shell where `holon` is on `PATH`.

**Gotcha:** holon's script preamble already defines a top-level `env` (`SwiftScriptPreamble.swift`). A script run through holon that declares its own `let env = …` doesn't compile. Name it `environment`. A harness tool built by its `bin/` entry point has no preamble, but use `environment` there too, so the file runs either way.

## What stays allowed

Short single-purpose `sed`, `grep`, `awk` and `jq` pipelines are fine. The rule is about generating scripts: anything longer than a pipeline, or anything kept for later, is a Swift file.

## Enforcement

[`guards.d/python-scripts.json`](../guards.d/python-scripts.json) makes `guard-bash` block inline Python and Python files run from a temp directory. The user can still run any command themselves.
