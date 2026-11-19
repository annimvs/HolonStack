// perf-confirm.swift — runs the `check` of each open finding; a pass sets its status to confirmed (rules/PERF.md).
// Only this tool confirms a finding: it swaps the status line, asks `write lint` to accept the file, and restores the old text if lint refuses.
// Usage: perf-confirm [all | <part of a finding file name>]   One line per finding. Exit 1 when any check fails, else 0.
import Foundation

// MARK: - Reading records

/// Takes a field name and a record's text; returns the quoted value of the first `  name: "…"` line, or nil.
func fieldValue(_ key: String, in text: String) -> String? {
    for line in text.components(separatedBy: "\n") {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix(key + ": \""), t.hasSuffix("\""), t.count > key.count + 3 else { continue }
        return String(t.dropFirst(key.count + 3).dropLast())
    }
    return nil
}

// MARK: - Running checks

/// Runs a shell command in a folder. Takes the command and the folder; returns its exit status and the last lines of its output.
func runShell(_ command: String, in dir: String) -> (status: Int32, tail: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/sh")
    p.arguments = ["-c", command]
    p.currentDirectoryURL = URL(fileURLWithPath: dir)
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    do {
        try p.run()
    } catch {
        return (127, "could not start: \(error)")
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    let lines = String(decoding: data, as: UTF8.self).split(separator: "\n").suffix(4)
    return (p.terminationStatus, lines.joined(separator: "\n"))
}

/// Swaps one finding's status line to confirmed, then has the writer lint the file; restores the old text when lint refuses.
/// Takes the file path, its current text and the project path; returns true when the file says confirmed and lints clean.
func markConfirmed(_ path: String, _ original: String, proj: String) -> Bool {
    let updated = original.replacingOccurrences(of: "\n  status: open\n", with: "\n  status: confirmed\n")
    guard updated != original else { return false }
    do {
        try updated.write(toFile: path, atomically: true, encoding: .utf8)
    } catch {
        return false
    }
    if runShell("\"\(proj)/.agents/harness/bin/write\" lint \"\(path)\"", in: proj).status == 0 { return true }
    // lint refused the edit, so put the record back as it was
    try? original.write(toFile: path, atomically: true, encoding: .utf8)
    return false
}

// MARK: - Driver

let argv = Array(CommandLine.arguments.dropFirst())
let proj = ProcessInfo.processInfo.environment["CLAUDE_PROJECT_DIR"] ?? FileManager.default.currentDirectoryPath
let dir = proj + "/.agents/records/FINDINGS"
// a missing folder just means no findings have been filed
let names = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [])
    .filter { $0.hasPrefix("finding-") && $0.hasSuffix(".closure") }.sorted()
let wanted = argv.first?.lowercased()
var failed = false
var seen = 0
for file in names {
    let path = dir + "/" + file
    guard let text = try? String(contentsOfFile: path, encoding: .utf8), text.contains("\n  status: open\n") else {
        continue
    }
    if let w = wanted, w != "all", !file.lowercased().contains(w) { continue }
    seen += 1
    let name = fieldValue("name", in: text) ?? file
    let check = fieldValue("check", in: text) ?? "manual"
    if check == "manual" {
        print("manual: \(name): a person confirms it, then edits the status")
        continue
    }
    let run = runShell(check, in: proj)
    if run.status == 0 {
        print(markConfirmed(path, text, proj: proj) ? "confirmed: \(name)" : "pass but not recorded: \(name)")
    } else {
        print("FAIL: \(name) (check exited \(run.status))\n\(run.tail)")
        failed = true
    }
}
print(seen == 0 ? "perf-confirm: no open finding" : "perf-confirm: \(seen) open finding(s) checked")
exit(failed ? 1 : 0)
