// Claude Code PostToolUse(Edit|Write|MultiEdit): after an edit under .agents/, lint any .closure file (syntax and canonical
// form), check a record against its template (write check <file>), or check the generated wiring (sync-settings --check).
// Exit 2 puts the findings in front of the model; silent on success.
import Foundation

let environment = ProcessInfo.processInfo.environment
let proj = URL(fileURLWithPath: environment["CLAUDE_PROJECT_DIR"] ?? FileManager.default.currentDirectoryPath)
    .resolvingSymlinksInPath().path

let rawInput =
    (try? JSONSerialization.jsonObject(with: FileHandle.standardInput.readDataToEndOfFile()) as? [String: Any]) ?? [:]
let isGemini = rawInput["hookEventName"] != nil
let toolInput =
    (rawInput["tool_input"] as? [String: Any])
    ?? ((rawInput["toolCall"] as? [String: Any])?["args"] as? [String: Any]) ?? [:]
guard
    let file = (toolInput["file_path"] as? String) ?? (toolInput["TargetFile"] as? String)
        ?? (toolInput["AbsolutePath"] as? String) ?? (toolInput["Path"] as? String),
    !file.isEmpty
else {
    if isGemini { print("{}") }
    exit(0)
}
let path = URL(fileURLWithPath: file).resolvingSymlinksInPath().path
// Swift under .agents/harness/ is linted on save; every finding is sent back. conformance/ and Sources/ keep their own style.
if path.hasSuffix(".swift"), path.hasPrefix(proj + "/.agents/harness/"),
    FileManager.default.fileExists(atPath: proj + "/.agents/harness/bin/lint")
{
    let p = Process()
    p.executableURL = URL(fileURLWithPath: proj + "/.agents/harness/bin/lint")
    p.arguments = [path]
    var e = environment
    e["CLAUDE_PROJECT_DIR"] = proj
    p.environment = e
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    if (try? p.run()) != nil {
        let d = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        if p.terminationStatus != 0 {
            let errors = String(decoding: d, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            let message =
                "lint (\(path.dropFirst(proj.count + 1))):\n\(errors)\nfix each finding above, or add `// lint-ignore: <rule-id>: <why>`\n"
            if isGemini {
                if let data = try? JSONSerialization.data(
                    withJSONObject: ["systemMessage": message], options: [.sortedKeys])
                {
                    FileHandle.standardOutput.write(data)
                    print()
                } else {
                    print("{}")
                }
                exit(0)
            }
            FileHandle.standardError.write(Data(message.utf8))
            exit(2)
        }
    }
}
guard path.hasPrefix(proj + "/.agents/") else {
    if isGemini { print("{}") }
    exit(0)
}
let rel = String(path.dropFirst(proj.count + "/.agents/".count))

// record folders; keep in step with the templates' `// store:` lines and guard-edit.swift
let folders = [
    "PHASES/", "TASKS/", "MEMORIES/", "QUESTIONS/", "ISSUES/", "AUDITS/", "PROPOSALS/", "FINDINGS/", "CATALOG/",
    "DESIGN/", "SEMANTICS/", "RESULTS/", "INTERFACES/",
].map { "records/" + $0 }

/// Runs a command through `/usr/bin/env` in the project folder and returns its exit status and trimmed output.
/// Takes the command and its arguments; throws when the command cannot start.
func run(_ args: [String]) throws -> (Int32, String) {
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
    try p.run()
    let d = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(decoding: d, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
}

var findings = ""
let writer = proj + "/.agents/harness/bin/write"
if rel.hasPrefix("records/drafts/"), rel.hasSuffix(".closure"), FileManager.default.fileExists(atPath: writer),
    FileManager.default.fileExists(atPath: path)
{
    // a draft is checked against its template on every save, so the agent sees the errors without remembering to check
    let (rc, out) = try run([writer, "check-draft", path])
    if rc != 0 { findings += "\(out)\nfix every problem above and save the draft again" }
} else if rel.hasSuffix(".closure"), FileManager.default.fileExists(atPath: writer),
    FileManager.default.fileExists(atPath: path)
{
    let (lrc, lout) = try run([writer, "lint", path])
    if lrc != 0 {
        findings += lout
    } else if folders.contains(where: { rel.hasPrefix($0) }) {
        let (rc, out) = try run([writer, "check", path])
        if rc != 0 {
            findings += out
        } else {
            // a record edited in place: refresh MEMORY.md, OPEN.md and the other views, as a write through `write` does
            let (vrc, vout) = try run([writer, "render"])
            if vrc != 0 { findings += "write render failed:\n\(vout)" }
        }
    }
} else if rel == "harness/hooks.json" || rel.hasPrefix("harness/hooks/") || rel.hasPrefix("harness/tools/") {
    let sync = proj + "/.agents/harness/bin/sync-settings"
    if FileManager.default.fileExists(atPath: sync) {
        let (rc, out) = try run([sync, "--check"])
        if rc != 0 { findings += "\(out)\nrun .agents/harness/bin/sync-settings" }
    }
}
if !findings.isEmpty {
    let message = "check-edit (\(rel)):\n\(findings)\n"
    if isGemini {
        if let data = try? JSONSerialization.data(withJSONObject: ["systemMessage": message], options: [.sortedKeys]) {
            FileHandle.standardOutput.write(data)
            print()
        } else {
            print("{}")
        }
        exit(0)
    }
    FileHandle.standardError.write(Data(message.utf8))
    exit(2)
}
if isGemini { print("{}") }
