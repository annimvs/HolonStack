// Claude Code PreToolUse(Grep|Bash) and Antigravity grep_search/run_command: steers project searches to `.agents/harness/bin/seek`.
// `seek` returns the whole function or section around each hit with its line range and file hash, so `edit --range` can act on it.
// Mode comes from HOLON_GREP_GUARD: `off`, `advise` (default: allow the call and add a reminder) or `deny` (exit 2, or a JSON deny).
// HOLON_ALLOW_GREP=1 skips it for one run. Allowed anyway: grep reading a pipe, searches outside the project, and searches
// aimed at conformance/ or reference/ (data seek skips by default). Exit 0 always except in deny mode.
import Foundation

let environment = ProcessInfo.processInfo.environment
let proj = URL(fileURLWithPath: environment["CLAUDE_PROJECT_DIR"] ?? FileManager.default.currentDirectoryPath)
    .resolvingSymlinksInPath().path
let mode = environment["HOLON_GREP_GUARD"] ?? "advise"

// lint-ignore: no-unsafe-sendable: a hook reads its one input at start-up and only this single thread ever uses it
nonisolated(unsafe) let rawInput =
    (try? JSONSerialization.jsonObject(with: FileHandle.standardInput.readDataToEndOfFile()) as? [String: Any]) ?? [:]
let isGemini = rawInput["hookEventName"] != nil
let toolInput =
    (rawInput["tool_input"] as? [String: Any])
    ?? ((rawInput["toolCall"] as? [String: Any])?["args"] as? [String: Any]) ?? [:]

/// Lets the call through; Antigravity expects an explicit decision.
func allow(_ note: String? = nil) -> Never {
    if isGemini {
        var reply: [String: Any] = ["decision": "allow"]
        if let note { reply["reason"] = note }
        if let data = try? JSONSerialization.data(withJSONObject: reply) { FileHandle.standardOutput.write(data) }
    } else if let note {
        let reply: [String: Any] = ["hookSpecificOutput": ["hookEventName": "PreToolUse", "additionalContext": note]]
        if let data = try? JSONSerialization.data(withJSONObject: reply) { FileHandle.standardOutput.write(data) }
    }
    exit(0)
}

/// Refuses the call with the reason: exit 2 for Claude Code, a JSON deny for Antigravity.
func deny(_ reason: String) -> Never {
    if isGemini {
        let reply: [String: Any] = ["decision": "deny", "reason": reason]
        if let data = try? JSONSerialization.data(withJSONObject: reply) { FileHandle.standardOutput.write(data) }
        exit(0)
    }
    FileHandle.standardError.write(Data((reason + "\n").utf8))
    exit(2)
}

let message =
    "Prefer `.agents/harness/bin/seek TERM [PATH]` to grep: hits come grouped by function or section with `A-B` ranges for `edit --range` (seek skill)."

/// True the first time this session and agent reaches the reminder, so later searches add nothing to the context.
func firstAdvice() -> Bool {
    let id = (rawInput["session_id"] as? String) ?? (rawInput["sessionId"] as? String) ?? "unknown"
    let agent = (rawInput["agent_id"] as? String) ?? "main"
    let directory = proj + "/.agents/harness/.cache/search-advised"
    let marker = directory + "/" + id + "--" + agent
    let fm = FileManager.default
    if fm.fileExists(atPath: marker) { return false }
    // a failed marker only means the reminder shows again
    try? fm.createDirectory(atPath: directory, withIntermediateDirectories: true)
    fm.createFile(atPath: marker, contents: nil)
    // markers older than a week belong to finished sessions
    for name in (try? fm.contentsOfDirectory(atPath: directory)) ?? [] {
        let path = directory + "/" + name
        if let date = (try? fm.attributesOfItem(atPath: path))?[.modificationDate] as? Date,
            Date().timeIntervalSince(date) > 7 * 24 * 3600
        {
            // an old marker that stays does no harm
            try? fm.removeItem(atPath: path)
        }
    }
    return true
}

/// True when a search aimed at `target` is not seek's business: outside the project, or in data folders it skips.
func exempt(_ target: String) -> Bool {
    let absolute = target.hasPrefix("/") ? target : proj + "/" + target
    let path = URL(fileURLWithPath: absolute).standardized.path
    return !(path == proj || path.hasPrefix(proj + "/")) || path.contains("/conformance") || path.contains("/reference")
}

/// The words of the first pipeline stage of each shell segment that runs grep or rg on a file or folder operand.
func searchesFiles(_ command: String) -> [String]? {
    let segments = command.components(separatedBy: CharacterSet(charactersIn: ";\n&"))
    for segment in segments {
        let stage = segment.components(separatedBy: "|")[0]
        var words = stage.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        // leading VAR=value assignments are not the program
        while let first = words.first, first.contains("="), !first.hasPrefix("-"), !first.hasPrefix("/") {
            words.removeFirst()
        }
        while words.first == "command" || words.first == "exec" { words.removeFirst() }
        guard let program = words.first,
            ["grep", "egrep", "fgrep", "rg", "ag"].contains((program as NSString).lastPathComponent)
        else { continue }
        let operands = words.dropFirst().filter { !$0.hasPrefix("-") }
        let recursive = words.contains {
            $0 == "-r" || $0 == "-R"
                || ($0.hasPrefix("-") && !$0.hasPrefix("--") && ($0.contains("r") || $0.contains("R")))
                || $0 == "--recursive"
        }
        // a pattern plus a path, or a recursive search with no path (the current folder)
        if operands.count >= 2 { return Array(operands.dropFirst()) }
        if operands.count == 1 && (recursive || program.hasSuffix("rg") || program.hasSuffix("ag")) { return ["."] }
    }
    return nil
}

guard mode != "off", environment["HOLON_ALLOW_GREP"] != "1" else { allow() }

if let command = (toolInput["command"] as? String) ?? (toolInput["CommandLine"] as? String) {
    guard let targets = searchesFiles(command), !targets.allSatisfy(exempt) else { allow() }
} else if toolInput["pattern"] != nil || toolInput["Query"] != nil {
    // the Grep tool: path is optional and means the current folder
    let target = (toolInput["path"] as? String) ?? (toolInput["SearchPath"] as? String) ?? "."
    guard !exempt(target) else { allow() }
} else {
    allow()
}
if mode == "deny" { deny("guard-search: " + message) }
allow(firstAdvice() ? message : nil)
