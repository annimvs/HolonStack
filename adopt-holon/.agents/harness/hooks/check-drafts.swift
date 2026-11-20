// Claude Code Stop / SubagentStop: refuse to finish while a draft this agent wrote under .agents/records/drafts/ fails `write check-draft`.
// The drafts are found in the agent's own transcript (agent_transcript_path for a subagent, else transcript_path), so parallel
// agents don't block each other. Exit 2 (reason on stderr) keeps the agent working.
// A draft the agent can't fix escalates. Its first line names a reason from reasons.closure, `// cannot fix: <code>: <note>`;
// the hook writes `<draft>.escalate`, a closure record with the reason, its route (model, user or harness) and the checker
// output, and lets the agent stop. A code that is not in the list is refused once. On a second stop (stop_hook_active) every
// failing draft escalates, with reason `none` if the agent gave none. An orchestrator reads the route and passes the draft on.
import Foundation

let environment = ProcessInfo.processInfo.environment
let proj = URL(fileURLWithPath: environment["CLAUDE_PROJECT_DIR"] ?? FileManager.default.currentDirectoryPath)
    .resolvingSymlinksInPath().path

guard
    let input = try? JSONSerialization.jsonObject(with: FileHandle.standardInput.readDataToEndOfFile())
        as? [String: Any]
else { exit(0) }
let isGemini = input["hookEventName"] != nil
let secondStop = (input["stop_hook_active"] as? Bool) == true || (input["continuationActive"] as? Bool) == true
// A background subagent may end even when SubagentStop blocks it, so a failing draft is escalated at once as well as blocked;
// if the agent does keep working and fixes it, the next check removes the escalation.
let subagent = (input["hook_event_name"] as? String) == "SubagentStop"
let transcript =
    (input["agent_transcript_path"] as? String) ?? (input["transcript_path"] as? String)
    ?? (input["transcriptPath"] as? String) ?? ""
guard !transcript.isEmpty, let text = try? String(contentsOfFile: transcript, encoding: .utf8) else {
    if isGemini { print("{}") }
    exit(0)
}

// drafts this agent saved itself (the file_path of its own Write or Edit calls), not ones it only read or mentioned
let writeTools: Set<String> = [
    "Write", "Edit", "MultiEdit", "write_file", "edit_file", "write_to_file", "replace_file_content",
    "multi_replace_file_content",
]
let shellTools: Set<String> = ["Bash", "run_command"]
var drafts: [String] = []
let fileRe = try? NSRegularExpression(
    pattern:
        #""(?:file_path|TargetFile|AbsolutePath|Path)"\s*:\s*"[^"]*?(\.agents/records/drafts/[A-Za-z0-9._-]+\.closure)""#
)
let shellRe = try? NSRegularExpression(
    pattern:
        #"(?:>>?\s*|tee\s+(?:-a\s+)?|bin/edit\s+(?:--[a-z-]+\s+\S+\s+)*|(?:cp|mv|install)\s+(?:-[a-zA-Z]+\s+)*[^\s"';&|]+\s+)[^\s"';&|]*?(\.agents/records/drafts/[A-Za-z0-9._-]+\.closure)"#
)
for line in text.split(separator: "\n") {
    let s = String(line)
    if let re = fileRe, writeTools.contains(where: { s.contains("\"\($0)\"") }) {
        for m in re.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
            guard let r = Range(m.range(at: 1), in: s) else { continue }
            let p = proj + "/" + s[r]
            if !drafts.contains(p), FileManager.default.fileExists(atPath: p) { drafts.append(p) }
        }
    }
    if let re = shellRe, shellTools.contains(where: { s.contains("\"\($0)\"") }), !s.contains("--read") {
        for m in re.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
            guard let r = Range(m.range(at: 1), in: s) else { continue }
            let p = proj + "/" + s[r]
            if !drafts.contains(p), FileManager.default.fileExists(atPath: p) { drafts.append(p) }
        }
    }
}
guard !drafts.isEmpty else {
    if isGemini { print("{}") }
    exit(0)
}

// the reasons an agent may cite, and who each one goes to (reasons.closure, edited only by the user)
// MARK: - Reason
/// One reason code from `reasons.closure`, with the route it goes to and what it means.
struct Reason {
    let code: String
    let route: String
    let meaning: String
}
var reasons: [Reason] = []
if let r = try? String(contentsOfFile: proj + "/.agents/harness/reasons.closure", encoding: .utf8),
    let re = try? NSRegularExpression(
        pattern: #"^\s*([a-z][a-z0-9-]*):\s*reason\(\s*([a-z]+)\s*,\s*"([^"]*)"\s*\)"#, options: [.anchorsMatchLines])
{
    for m in re.matches(in: r, range: NSRange(r.startIndex..., in: r)) {
        /// Returns capture group `i` of the current match, or an empty string when the group did not match.
        func g(_ i: Int) -> String { Range(m.range(at: i), in: r).map { String(r[$0]) } ?? "" }
        reasons.append(Reason(code: g(1), route: g(2), meaning: g(3)))
    }
}
let reasonList = reasons.map { "  \($0.code): \($0.meaning)" }.joined(separator: "\n")

/// Runs a command through `/usr/bin/env` in the project folder and returns its exit status and trimmed output.
/// Takes the command and its arguments; returns status 2 with a message when the command cannot start.
func run(_ args: [String]) -> (Int32, String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    p.arguments = args
    var e = environment
    e["CLAUDE_PROJECT_DIR"] = proj
    p.environment = e
    p.currentDirectoryURL = URL(fileURLWithPath: proj)
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    guard (try? p.run()) != nil else { return (2, "could not run \(args[0])") }
    let d = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(decoding: d, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
}
/// Wraps a string in double quotes, escaping backslashes and quotes inside it.
/// Takes the raw string and returns the quoted, escaped text.
func quote(_ s: String) -> String {
    "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
}

/// Writes a `<draft>.escalate` closure record that hands a failing draft to its route.
/// Takes the draft path, the reason code, the route, a note and the checker output; does nothing if an escalation already exists.
func escalate(_ draft: String, code: String, route: String, note: String, checker: String) {
    // keep an open escalation with history or a real reason, but let an explicit reason replace a placeholder `none`
    let escPath = draft + ".escalate"
    if let existing = try? String(contentsOfFile: escPath, encoding: .utf8) {
        let isPlaceholder = existing.contains("  reason: none\n") && !existing.contains("  tried:")
        if !(isPlaceholder && code != "none") { return }
    }
    let name = URL(fileURLWithPath: draft).deletingPathExtension().lastPathComponent
    let stem = String(name.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "-" })
    let rel = draft.hasPrefix(proj + "/") ? String(draft.dropFirst(proj.count + 1)) : draft
    let body = checker.components(separatedBy: "\n").map { "    " + $0 }.joined(separator: "\n")
    let record =
        "escalation(\(stem)) {\n  draft: \(quote(rel))\n  reason: \(code)\n  route: \(route)\n  note: \(quote(note))\n  checker: \"\"\"\n\(body)\n    \"\"\"\n}\n"
    // a failed write only means no escalation file appears; the draft still blocks the stop, so nothing is lost
    try? record.write(toFile: draft + ".escalate", atomically: true, encoding: .utf8)
}

let writer = proj + "/.agents/harness/bin/write"
var blocking = ""
for d in drafts {
    let (rc, out) = run([writer, "check-draft", d])
    if rc == 0 {
        // a draft that passes has no escalation file, so a missing one is the normal case
        try? FileManager.default.removeItem(atPath: d + ".escalate")
        continue
    }
    let first = ((try? String(contentsOfFile: d, encoding: .utf8)) ?? "").components(separatedBy: "\n").first ?? ""
    if first.hasPrefix("// cannot fix:") {
        let rest = first.dropFirst("// cannot fix:".count)
        let parts = rest.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        let code = parts.first ?? ""
        let note = parts.count > 1 ? parts[1] : ""
        if let r = reasons.first(where: { $0.code == code }) {
            escalate(d, code: r.code, route: r.route, note: note, checker: out)
        } else if secondStop {
            escalate(
                d, code: "unknown", route: "model", note: "gave '\(code)', which is not a listed reason. \(note)",
                checker: out)
        } else {
            blocking += "\(d):\n'\(code)' is not a listed reason; use one of the codes below\n"
        }
    } else if secondStop {
        escalate(
            d, code: "none", route: "model", note: "stopped twice with the draft failing and gave no reason",
            checker: out)
    } else {
        if subagent {
            escalate(
                d, code: "none", route: "model", note: "the agent stopped with the draft failing and gave no reason",
                checker: out)
        }
        blocking += "\(d):\n\(out)\n"
    }
}
if !blocking.isEmpty {
    let message = """
        check-drafts: you are not finished; these drafts fail their check:
        \(blocking)
        Fix every problem and save the draft again. If you cannot, make the draft's first line `// cannot fix: <code>: <one-line note>` with one of these codes, then finish; the draft is passed on by its code:
        \(reasonList)
        """
    if isGemini {
        let reply: [String: Any] = ["decision": "continue", "reason": message]
        if let data = try? JSONSerialization.data(withJSONObject: reply, options: [.sortedKeys]) {
            FileHandle.standardOutput.write(data)
            print()
        }
        exit(0)
    }
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}
if isGemini { print("{}") }
exit(0)
