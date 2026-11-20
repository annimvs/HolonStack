// Claude Code PreToolUse(Bash): routes build commands through `filter-run`, so only errors, failed tests and totals
// reach the model; the full output stays in a log whose path `filter-run` prints. A command matches when it runs a
// `build.sh` (HolonReleases' or any other), `swift build` or `swift test`. Start a command with `RAW=1` to run it as
// written. Claude Code runs it in parallel with `guard-bash`, not after it; a refused command still never runs,
// because a deny outranks everything else (hooks reference, "PreToolUse"). Never refuses anything itself:
// it exits 0, with an `updatedInput` on stdout when it rewrote the command.
import Foundation

// MARK: - Rewrite

/// Splits a shell command into simple-command word arrays at `;`, `&`, `|`, and newlines outside quotes.
func commandSegments(_ command: String) -> [[String]] {
    var segs: [[String]] = []
    var words: [String] = []
    var cur = ""
    var inWord = false
    var quote: Character?
    var it = command.makeIterator()
    /// Flushes the open word into `words`.
    func flush() {
        if inWord {
            words.append(cur)
            cur = ""
            inWord = false
        }
    }
    /// Flushes `words` into `segs`.
    func cut() {
        flush()
        if !words.isEmpty {
            segs.append(words)
            words = []
        }
    }
    while let c = it.next() {
        if let q = quote {
            if q == "\"", c == "\\" {
                if let n = it.next() { cur.append(n) }
            } else if c == q {
                quote = nil
            } else {
                cur.append(c)
            }
        } else if c == "'" || c == "\"" {
            quote = c
            inWord = true
        } else if c == "\\" {
            if let n = it.next() {
                cur.append(n)
                inWord = true
            }
        } else if c == ";" || c == "&" || c == "|" || c == "\n" || c == "(" || c == ")" {
            cut()
        } else if c == " " || c == "\t" {
            flush()
        } else {
            cur.append(c)
            inWord = true
        }
    }
    cut()
    return segs
}

/// True when `seg` runs `build.sh`, `swift build`, or `swift test` in command position.
func isBuildSegment(_ seg: [String]) -> Bool {
    var i = 0
    while i < seg.count, seg[i].contains("="), !seg[i].hasPrefix("-"), !seg[i].hasPrefix("/") { i += 1 }
    guard i < seg.count else { return false }
    let prog = (seg[i] as NSString).lastPathComponent
    if prog == "build.sh" { return true }
    if prog == "swift", i + 1 < seg.count, seg[i + 1] == "build" || seg[i + 1] == "test" { return true }
    if ["sh", "bash", "zsh"].contains(prog), let script = seg[(i + 1)...].first(where: { !$0.hasPrefix("-") }),
        (script as NSString).lastPathComponent == "build.sh"
    {
        return true
    }
    return false
}

/// Returns the command wrapped in `filter-run`, or nil when it is not a build command, opts out with `RAW=1`, or is
/// already filtered.
func rewrite(_ command: String, project: String) -> String? {
    guard !command.contains("filter-run") else { return nil }
    let segs = commandSegments(command)
    if segs.contains(where: { $0.contains("RAW=1") }) { return nil }
    guard segs.contains(where: isBuildSegment) else { return nil }
    let quoted = "'" + command.replacingOccurrences(of: "'", with: "'\\''") + "'"
    return "\"\(project)/.agents/harness/bin/filter-run\" \(quoted)"
}

// MARK: - Main

/// Reads the hook input, and prints Claude Code's `updatedInput` or Antigravity's `overwrite` reply when rewritten.
func main() -> Int32 {
    let environment = ProcessInfo.processInfo.environment
    let project = environment["CLAUDE_PROJECT_DIR"] ?? FileManager.default.currentDirectoryPath
    let input =
        (try? JSONSerialization.jsonObject(with: FileHandle.standardInput.readDataToEndOfFile()) as? [String: Any])
        ?? [:]
    let isGemini = input["hookEventName"] != nil
    var toolInput =
        (input["tool_input"] as? [String: Any])
        ?? ((input["toolCall"] as? [String: Any])?["args"] as? [String: Any]) ?? [:]
    guard let command = (toolInput["command"] as? String) ?? (toolInput["CommandLine"] as? String), !command.isEmpty
    else {
        if isGemini { print("{\"decision\":\"allow\"}") }
        return 0
    }
    guard let rewritten = rewrite(command, project: project) else {
        if isGemini { print("{\"decision\":\"allow\"}") }
        return 0
    }
    let reply: [String: Any]
    if isGemini {
        reply = ["decision": "allow", "overwrite": ["CommandLine": rewritten]]
    } else {
        toolInput["command"] = rewritten
        reply = ["hookSpecificOutput": ["hookEventName": "PreToolUse", "updatedInput": toolInput]]
    }
    guard let data = try? JSONSerialization.data(withJSONObject: reply, options: [.sortedKeys]) else { return 0 }
    FileHandle.standardOutput.write(data)
    print()
    return 0
}

exit(main())
