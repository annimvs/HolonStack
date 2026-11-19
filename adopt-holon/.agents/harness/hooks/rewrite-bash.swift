// Claude Code PreToolUse(Bash): routes build commands through `filter-run`, so only errors, failed tests and totals
// reach the model; the full output stays in a log whose path `filter-run` prints. A command matches when it runs a
// `build.sh`, `swift build` or `swift test` (during `/adopt-holon`, extend `pattern` for the project's build system:
// cmake, meson, ninja, npm/pnpm, cargo, etc.). Start a command with `RAW=1` to run it as written. Claude Code runs it
// in parallel with `guard-bash`, not after it; a refused command still never runs, because a deny outranks everything
// else (hooks reference, "PreToolUse"). Never refuses anything itself: it exits 0, with an `updatedInput` on stdout
// when it rewrote the command.
import Foundation

// MARK: - Rewrite

/// Returns the command wrapped in `filter-run`, or nil when it is not a build command, opts out with `RAW=1`, or is
/// already filtered.
func rewrite(_ command: String, project: String) -> String? {
    let pattern = #"(^|[;&|[:space:]/])build\.sh([[:space:]]|$)|swift[[:space:]]+(test|build)([[:space:]]|$)"#
    guard !command.hasPrefix("RAW=1"), !command.contains("filter-run"),
        let re = try? NSRegularExpression(pattern: pattern),
        re.firstMatch(in: command, range: NSRange(command.startIndex..., in: command)) != nil
    else { return nil }
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
