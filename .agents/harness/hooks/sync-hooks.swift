// Generate .claude/settings.json and .agents/hooks.json from .agents/harness/hooks.json (single source of hook wiring).
// Usage: sync-hooks.swift [--check]   --check writes nothing and exits 1 if either file is out of date.
import Foundation

// MARK: - Wiring

let environment = ProcessInfo.processInfo.environment
let proj = URL(fileURLWithPath: environment["CLAUDE_PROJECT_DIR"] ?? FileManager.default.currentDirectoryPath)
let check = CommandLine.arguments.contains("--check")
let fm = FileManager.default

/// Returns `bin/<name>` for `hooks/<name>.swift` or `tools/<name>.swift`, else the script path as written.
func entryPoint(_ script: String) -> String {
    guard script.hasSuffix(".swift"), script.hasPrefix("hooks/") || script.hasPrefix("tools/") else { return script }
    return "bin/" + String((script as NSString).lastPathComponent.dropLast(".swift".count))
}

/// True when a Claude hook handler dictionary invokes a script under `.agents/harness/`.
func isHarnessHandler(_ handler: Any) -> Bool {
    guard let dict = handler as? [String: Any], let cmd = dict["command"] as? String else { return false }
    return cmd.contains("/.agents/harness/")
}

/// Keeps non-harness entries from an existing `.claude/settings.json` `"hooks"` map and merges `wanted` harness entries.
func mergeClaudeHooks(existing: [String: Any], wanted: [String: Any]) -> [String: Any] {
    var merged: [String: [Any]] = [:]
    for (event, rawEntries) in existing {
        guard let entries = rawEntries as? [Any] else { continue }
        var kept: [Any] = []
        for entry in entries {
            guard var dict = entry as? [String: Any], let handlers = dict["hooks"] as? [Any] else {
                kept.append(entry)
                continue
            }
            let userHandlers = handlers.filter { !isHarnessHandler($0) }
            if !userHandlers.isEmpty {
                dict["hooks"] = userHandlers
                kept.append(dict)
            }
        }
        if !kept.isEmpty { merged[event] = kept }
    }
    for (event, rawEntries) in wanted {
        guard let entries = rawEntries as? [Any] else { continue }
        merged[event] = entries + (merged[event] ?? [])
    }
    return merged
}

/// Checks whether a JSON dictionary on disk matches `wanted`, or writes `wanted` when not in `--check` mode.
/// When `mergeTopLevel` is true, existing top-level keys outside `wanted` are preserved; when `mergeHooks` is true,
/// non-harness entries inside `"hooks"` are preserved alongside the generated harness hooks.
func syncJSON(
    file: URL, wanted: NSDictionary, label: String, stale: inout Bool,
    mergeTopLevel: Bool = false, mergeHooks: Bool = false
) throws {
    var target: [String: Any] = (wanted as? [String: Any]) ?? [:]
    if mergeTopLevel,
        let existingData = try? Data(contentsOf: file),
        var existing = (try? JSONSerialization.jsonObject(with: existingData)) as? [String: Any]
    {
        for (k, v) in target {
            if mergeHooks, k == "hooks", let exHooks = existing[k] as? [String: Any], let newHooks = v as? [String: Any]
            {
                existing[k] = mergeClaudeHooks(existing: exHooks, wanted: newHooks)
            } else {
                existing[k] = v
            }
        }
        target = existing
    }
    let finalWanted = target as NSDictionary
    if check {
        let have =
            (try? Data(contentsOf: file)).flatMap { try? JSONSerialization.jsonObject(with: $0) } as? NSDictionary
        if have != finalWanted {
            FileHandle.standardError.write(Data("\(label) is out of date\n".utf8))
            stale = true
        }
    } else {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: finalWanted, options: [.prettyPrinted, .sortedKeys]).write(to: file)
    }
}

/// Builds Claude Code's `.claude/settings.json` hooks dictionary from `events`.
func claudeWanted(events: [String: [String]]) -> NSDictionary {
    let map: [String: (String, String)] = [
        "pre-shell": ("PreToolUse", "Bash"), "pre-edit": ("PreToolUse", "Edit|Write|MultiEdit"),
        "post-shell": ("PostToolUse", "Bash"), "post-edit": ("PostToolUse", "Edit|Write|MultiEdit"),
        "session-start": ("SessionStart", ""), "session-end": ("SessionEnd", ""),
        "stop": ("Stop", ""), "subagent-stop": ("SubagentStop", ""),
        "pre-compact": ("PreCompact", ""), "post-compact": ("PostCompact", ""),
        "session-compact": ("SessionStart", "compact"), "pre-search": ("PreToolUse", "Grep"),
        "pre-agent": ("PreToolUse", "Agent"),
        "prompt-submit": ("UserPromptSubmit", ""), "post-read": ("PostToolUse", "Read"),
    ]
    var hooks: [String: Any] = [:]
    for (event, scripts) in events.sorted(by: { $0.key < $1.key }) {
        guard let (toolEvent, matcher) = map[event] else { continue }
        let commands = scripts.map { "\"$CLAUDE_PROJECT_DIR\"/.agents/harness/\(entryPoint($0))" }
        var entry: [String: Any] = ["hooks": commands.map { ["type": "command", "command": $0] }]
        // an empty matcher fires on every event of that kind; session-compact matches only the `compact` source
        if !matcher.isEmpty { entry["matcher"] = matcher }
        hooks[toolEvent] = (hooks[toolEvent] as? [Any] ?? []) + [entry]
    }
    return ["hooks": hooks] as NSDictionary
}

/// Builds Antigravity's `.agents/hooks.json` dictionary from `events`.
func geminiWanted(events: [String: [String]]) -> NSDictionary {
    let toolMap: [(event: String, hookEvent: String, matcher: String)] = [
        ("pre-shell", "PreToolUse", "run_command"),
        ("post-shell", "PostToolUse", "run_command"),
        (
            "pre-edit", "PreToolUse",
            "write_to_file|replace_file_content|multi_replace_file_content|write_file|edit_file"
        ),
        (
            "post-edit", "PostToolUse",
            "write_to_file|replace_file_content|multi_replace_file_content|write_file|edit_file"
        ),
        ("post-read", "PostToolUse", "view_file|read_file"),
        ("pre-search", "PreToolUse", "grep_search"),
        ("pre-agent", "PreToolUse", "invoke_subagent"),
    ]
    var harnessHook: [String: Any] = [:]
    for (event, hookEvent, matcher) in toolMap {
        guard let scripts = events[event], !scripts.isEmpty else { continue }
        let handlers = scripts.map { ["type": "command", "command": "./harness/\(entryPoint($0))"] }
        let group: [String: Any] = ["matcher": matcher, "hooks": handlers]
        harnessHook[hookEvent] = (harnessHook[hookEvent] as? [Any] ?? []) + [group]
    }
    if let scripts = events["prompt-submit"], !scripts.isEmpty {
        harnessHook["PreInvocation"] = scripts.map { ["type": "command", "command": "./harness/\(entryPoint($0))"] }
    }
    var stopScripts = events["stop"] ?? []
    for s in events["pre-compact"] ?? [] where !stopScripts.contains(s) { stopScripts.append(s) }
    if !stopScripts.isEmpty {
        harnessHook["Stop"] = stopScripts.map { ["type": "command", "command": "./harness/\(entryPoint($0))"] }
    }
    return ["harness": harnessHook] as NSDictionary
}

guard let data = try? Data(contentsOf: proj.appendingPathComponent(".agents/harness/hooks.json")),
    let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
    let events = json["events"] as? [String: [String]]
else {
    FileHandle.standardError.write(Data("cannot read .agents/harness/hooks.json\n".utf8))
    exit(2)
}

if (try? fm.destinationOfSymbolicLink(atPath: proj.appendingPathComponent(".claude").path)) != nil {
    FileHandle.standardError.write(
        Data(".claude is a link; it must be a real directory inside the project (no shared .claude)\n".utf8))
    exit(check ? 1 : 2)
}

var stale = false
try syncJSON(
    file: proj.appendingPathComponent(".claude/settings.json"), wanted: claudeWanted(events: events),
    label: ".claude/settings.json", stale: &stale, mergeTopLevel: true, mergeHooks: true)
try syncJSON(
    file: proj.appendingPathComponent(".agents/hooks.json"), wanted: geminiWanted(events: events),
    label: ".agents/hooks.json", stale: &stale, mergeTopLevel: true)

exit(stale ? 1 : 0)
