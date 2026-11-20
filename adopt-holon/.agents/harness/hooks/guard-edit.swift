// Claude Code PreToolUse(Edit|Write|MultiEdit): refuse a direct edit of a file the writer owns.
// The indexes (PLAN.closure, TODO.closure), the generated views (MEMORY.md, OPEN.md) and the id ledger change only through
// `.agents/harness/bin/write`; the templates, `.ids` and `.write.lock` change only when the user edits them (rules/RECORDS.md).
// Records in PHASES/, TASKS/, MEMORIES/ and QUESTIONS/ may be edited: `check-edit` lints and checks them right after.
// Exit 2 (reason on stderr) blocks the call. Escape hatch: the user edits the file themselves.
// Edits to enforcement code (hooks/, guards.d/, tools/) are not blocked: that would stop the harness from being developed.
// The same paths are guarded against shell redirects, `sed -i` and the like by guards.d/records-bash.json.
import Foundation

let environment = ProcessInfo.processInfo.environment
let proj = URL(fileURLWithPath: environment["CLAUDE_PROJECT_DIR"] ?? FileManager.default.currentDirectoryPath)
    .resolvingSymlinksInPath().path

// lint-ignore: no-unsafe-sendable: a hook reads its one input at start-up and only this single thread ever uses it
nonisolated(unsafe) let rawInput =
    (try? JSONSerialization.jsonObject(with: FileHandle.standardInput.readDataToEndOfFile()) as? [String: Any]) ?? [:]
let isGemini = rawInput["hookEventName"] != nil

/// Blocks the edit: prints JSON `deny` for Antigravity, or writes to stderr and exits 2 for Claude Code.
func blockEdit(_ reason: String) -> Never {
    if isGemini {
        let reply: [String: Any] = ["decision": "deny", "reason": reason]
        if let data = try? JSONSerialization.data(withJSONObject: reply, options: [.sortedKeys]) {
            FileHandle.standardOutput.write(data)
            print()
        }
        exit(0)
    }
    FileHandle.standardError.write(Data((reason + "\n").utf8))
    exit(2)
}

let toolInput =
    (rawInput["tool_input"] as? [String: Any])
    ?? ((rawInput["toolCall"] as? [String: Any])?["args"] as? [String: Any]) ?? [:]
guard
    let file = (toolInput["file_path"] as? String) ?? (toolInput["TargetFile"] as? String)
        ?? (toolInput["AbsolutePath"] as? String) ?? (toolInput["Path"] as? String),
    !file.isEmpty
else {
    if isGemini { print("{\"decision\":\"allow\"}") }
    exit(0)
}

/// Takes a file path that may not exist yet; returns it with symlinks resolved on its nearest existing ancestor.
/// Foundation drops a leading `/private` from a path that does not exist, so resolving the whole path would not match `proj`.
func resolvedPath(_ file: String) -> String {
    var url = URL(fileURLWithPath: file)
    var tail: [String] = []
    while !FileManager.default.fileExists(atPath: url.path), url.pathComponents.count > 1 {
        tail.insert(url.lastPathComponent, at: 0)
        url = url.deletingLastPathComponent()
    }
    return ([url.resolvingSymlinksInPath().path] + tail).joined(separator: "/")
}

let path = resolvedPath(file)

// MARK: - Worker claims

let claimsDir = proj + "/.agents/harness/.cache/claims"
let claimTTL: Double = 6 * 3600

/// Reads every unexpired claim file written by `isolate claim`; returns name to its JSON fields.
func liveClaims() -> [String: [String: Any]] {
    // a missing folder just means no claims yet
    let files = ((try? FileManager.default.contentsOfDirectory(atPath: claimsDir)) ?? []).filter {
        $0.hasSuffix(".json")
    }
    var found: [String: [String: Any]] = [:]
    for file in files {
        guard let data = FileManager.default.contents(atPath: claimsDir + "/" + file),
            let fields = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let made = fields["created"] as? Double, Date().timeIntervalSince1970 - made < claimTTL
        else { continue }
        found[String(file.dropLast(5))] = fields
    }
    return found
}

/// Takes a subagent's id and a claim name; ties the claim to that agent. Returns an error message, or nil when bound.
func bindClaim(agent: String, name: String, claims: [String: [String: Any]]) -> String? {
    guard var claim = claims[name] else {
        return "guard-edit: no claim named \(name); the orchestrator files it with `isolate claim`"
    }
    if let bound = claim["agent"] as? String, !bound.isEmpty, bound != agent {
        return "guard-edit: claim \(name) already belongs to another agent"
    }
    claim["agent"] = agent
    guard let data = try? JSONSerialization.data(withJSONObject: claim, options: [.sortedKeys]),
        (try? data.write(to: URL(fileURLWithPath: claimsDir + "/" + name + ".json"), options: .atomic)) != nil
    else { return "guard-edit: could not bind claim \(name)" }
    return nil
}

/// Takes the calling subagent's id; refuses (exit 2) an edit to project source unless the subagent has bound a live
/// claim covering that path (or `HOLON_ALLOW_UNCLAIMED_AGENT=1`).
/// An empty file written to `claims/<name>.bind` binds the claim `<name>` to the agent. Paths under `.agents/` and
/// outside the project are not claim business; the main orchestrator has no `agent_id` and is never restricted.
func enforceClaim(agent: String) {
    if environment["HOLON_ALLOW_UNCLAIMED_AGENT"] == "1" { return }
    let claims = liveClaims()
    if path.hasPrefix(claimsDir + "/"), path.hasSuffix(".bind") {
        let name = String(path.dropFirst(claimsDir.count + 1).dropLast(5))
        if let problem = bindClaim(agent: agent, name: name, claims: claims) { blockEdit(problem) }
        if isGemini { print("{\"decision\":\"allow\"}") }
        exit(0)
    }
    guard path.hasPrefix(proj + "/"), !path.hasPrefix(proj + "/.agents/") else { return }
    let rel = String(path.dropFirst(proj.count + 1))
    if claims.isEmpty {
        blockEdit(
            "guard-edit: subagent cannot edit \(rel) without an isolate claim; the orchestrator must file one with "
                + "`.agents/harness/bin/isolate claim <name> <task>` before spawning (rules/DELEGATION.md)")
    }
    guard let mine = claims.first(where: { $0.value["agent"] as? String == agent }) else {
        let names = claims.keys.sorted().joined(separator: " ")
        blockEdit(
            "guard-edit: workers are claimed (\(names)); bind yours first by writing an empty file at .agents/harness/.cache/claims/<name>.bind"
        )
    }
    let paths = mine.value["paths"] as? [String] ?? []
    if !paths.contains(where: { rel == $0 || rel.hasPrefix($0 + "/") }) {
        blockEdit(
            "guard-edit: \(rel) is outside claim \(mine.key) (\(paths.joined(separator: " "))); file a blocked result with the request and stop"
        )
    }
}

// MARK: - Edit Tool Steering

/// How the built-in Edit, Write and MultiEdit tools are treated on project files: `off` leaves them alone, `advise`
/// allows the call and reminds the model to use `.agents/harness/bin/edit`, `deny` refuses it. Set `HOLON_EDIT_GUARD`
/// to change it; the default is `deny`. `HOLON_ALLOW_BUILTIN_EDIT=1` skips the steering for one run.
let editGuardMode = environment["HOLON_EDIT_GUARD"] ?? "deny"
/// File types the `edit` tool refuses or cannot handle (binary or structured), so the built-in tools stay allowed for them.
let steeringSkipped: Set<String> = [
    "ipynb", "png", "jpg", "jpeg", "gif", "icns", "pdf", "xlsx", "docx", "pptx", "zip", "dylib", "a", "o",
]

/// Steers a built-in edit of a project file toward `.agents/harness/bin/edit`: a reminder in `advise` mode, a refusal
/// in `deny` mode. Skips calls that already came from `edit` (guard-bash marks them), records (the built-in tools keep
/// their record checks), binary types, files outside the project, and a missing `edit` tool.
func steerToEditTool() {
    let tool = proj + "/.agents/harness/bin/edit"
    guard editGuardMode != "off", environment["HOLON_ALLOW_BUILTIN_EDIT"] != "1",
        rawInput["via_edit_tool"] as? Bool != true, path.hasPrefix(proj + "/"),
        !path.hasPrefix(proj + "/.agents/records/"),
        !(path.hasPrefix(claimsDir + "/") && path.hasSuffix(".bind")),
        !steeringSkipped.contains(URL(fileURLWithPath: path).pathExtension),
        FileManager.default.isExecutableFile(atPath: tool)
    else { return }
    let rel = String(path.dropFirst(proj.count + 1))
    let creating = !FileManager.default.fileExists(atPath: path)
    let how =
        creating
        ? "`.agents/harness/bin/edit \(rel) --create --content-file -` (the text on stdin)"
        : "`.agents/harness/bin/edit \(rel) --read`, then `.agents/harness/bin/edit \(rel) --hash H --old TEXT --new TEXT`"
    let message =
        "Use the project's edit tool for \(rel): \(how). It matches exact text, checks the file has not changed, "
        + "prints a diff, and takes several --old/--new pairs or --batch-file JSON; see `edit --help`. "
        + "The lint and record checks run after it as they do here."
    if editGuardMode == "deny" { blockEdit("guard-edit: " + message) }
    if isGemini {
        let reply: [String: Any] = ["decision": "allow", "reason": message]
        if let data = try? JSONSerialization.data(withJSONObject: reply, options: [.sortedKeys]) {
            FileHandle.standardOutput.write(data)
            print()
        }
        exit(0)
    }
    let reply: [String: Any] = ["hookSpecificOutput": ["hookEventName": "PreToolUse", "additionalContext": message]]
    if let data = try? JSONSerialization.data(withJSONObject: reply) {
        FileHandle.standardOutput.write(data)
    }
}

if let agent = (rawInput["agent_id"] as? String) ?? (rawInput["agentId"] as? String), !agent.isEmpty {
    enforceClaim(agent: agent)
}
guard path.hasPrefix(proj + "/.agents/") else {
    steerToEditTool()
    if isGemini { print("{\"decision\":\"allow\"}") }
    exit(0)
}
let rel = String(path.dropFirst(proj.count + "/.agents/".count))

// Keep in step with check-edit.swift and guards.d/records-bash.json.
let writerOwned: Set<String> = [
    "records/PLAN.closure", "records/TODO.closure", "records/MEMORY.md", "records/OPEN.md", "records/PLAN.md",
    "records/TODO.md", "records/BUGS.md", "records/AUDIT.md", "records/PROPOSALS.md", "records/SEMANTICS.md",
]
let userOnly: Set<String> = [
    "records/.ids", "records/.write.lock", "harness/reasons.closure", "harness/lint.closure", "harness/hooks.json",
    "hooks.json",
]

if writerOwned.contains(rel) {
    blockEdit("guard-edit: .agents/\(rel) is written only by .agents/harness/bin/write (rules/RECORDS.md)")
}
if rel.hasPrefix("records/drafts/"), rel.hasSuffix(".escalate") {
    blockEdit(
        "guard-edit: .agents/\(rel) is written only by the check-drafts hook and `write escalation` (rules/ESCALATION.md)"
    )
}
if userOnly.contains(rel) || rel.hasPrefix("harness/templates/") {
    blockEdit("guard-edit: .agents/\(rel) is edited only by the user")
}

// MARK: - Criteria lock

/// Takes the text of a record; returns the trimmed lines that hold its criteria, in order.
func criteriaLines(_ text: String) -> [String] {
    text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { line in
        ["criteria:", "criterion(", "check:", "text:", "done:"].contains { line.hasPrefix($0) }
    }
}

// A task's criteria are fixed when it is filed: an agent that could rewrite them could pass its own check. An edit that
// changes them is refused; the user can change them by hand. This does not stop a shell redirect into the record.
if rel.hasPrefix("records/PHASES/") || rel.hasPrefix("records/TASKS/") {
    let before = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    var after = before
    if let content = (toolInput["content"] as? String) ?? (toolInput["Content"] as? String)
        ?? (toolInput["CodeContent"] as? String)
    {
        after = content
    } else if let old = (toolInput["old_string"] as? String) ?? (toolInput["Target"] as? String)
        ?? (toolInput["TargetContent"] as? String),
        let new = (toolInput["new_string"] as? String) ?? (toolInput["Replacement"] as? String)
            ?? (toolInput["ReplacementContent"] as? String)
    {
        after = before.replacingOccurrences(of: old, with: new)
    } else if let edits = (toolInput["edits"] as? [[String: Any]])
        ?? (toolInput["ReplacementChunks"] as? [[String: Any]])
    {
        for edit in edits {
            let old = (edit["old_string"] as? String) ?? (edit["TargetContent"] as? String) ?? ""
            let new = (edit["new_string"] as? String) ?? (edit["ReplacementContent"] as? String) ?? ""
            after = after.replacingOccurrences(of: old, with: new)
        }
    }
    if criteriaLines(after) != criteriaLines(before) {
        blockEdit(
            "guard-edit: criteria and done status in .agents/\(rel) cannot be edited directly; use `write done` or ask the user (rules/RECORDS.md)"
        )
    }
}
steerToEditTool()
if isGemini { print("{\"decision\":\"allow\"}") }
exit(0)
