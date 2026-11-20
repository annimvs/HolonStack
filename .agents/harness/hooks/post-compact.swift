// Claude Code PostCompact: saves the summary Claude Code wrote (`compact_summary`) to
// `.agents/harness/.cache/compactions/claude/<stem>.summary.md`. `<stem>` is the name of the transcript `pre-compact`
// archived for this session just before, so `<stem>.jsonl`, `<stem>.md` and `<stem>.summary.md` sit together; with no
// such transcript it is a fresh stamp. Keeps the newest 100 summaries. PostCompact has no decision control, so it
// can't change the compaction result; every path exits 0 (hooks reference, "PostCompact", checked 2026-11-18).
import Foundation

// MARK: - Archive

/// The folder that holds archived Claude Code transcripts and summaries, under the harness cache.
func archiveDirectory(project: String) -> URL {
    URL(fileURLWithPath: project).appendingPathComponent(".agents/harness/.cache/compactions/claude", isDirectory: true)
}

/// A file name stamp such as `20261118-163900-ab12cd34`: UTC time, then the first 8 characters of the session id.
/// Stamps sort in time order, so the largest name is the newest.
func stamp(session: String, date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return formatter.string(from: date) + "-" + String(session.prefix(8))
}

/// Deletes the oldest files in `directory` whose names end in `suffix`, keeping the newest `keep` by modification time.
func prune(_ directory: URL, suffix: String, keep: Int) {
    let manager = FileManager.default
    // no folder means nothing to prune
    guard let names = try? manager.contentsOfDirectory(atPath: directory.path) else { return }
    var dated: [(name: String, date: Date)] = []
    for name in names where name.hasSuffix(suffix) {
        let path = directory.appendingPathComponent(name).path
        // a file that vanished while listing has nothing left to prune
        guard let date = (try? manager.attributesOfItem(atPath: path))?[.modificationDate] as? Date else { continue }
        dated.append((name, date))
    }
    for old in dated.sorted(by: { $0.date > $1.date }).dropFirst(keep) {
        do {
            try manager.removeItem(at: directory.appendingPathComponent(old.name))
        } catch {
            report("could not prune \(old.name): \(error)")
        }
    }
}

/// The name, without `.jsonl`, of the newest transcript `pre-compact` archived for `session` that has no summary yet.
/// Stamps sort in time order and end in the session's first 8 characters, so the largest matching name is the one
/// this compaction began with. Returns nil when there is none.
func pairedStem(in directory: URL, session: String) -> String? {
    // no folder means pre-compact has not archived anything yet
    let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    let tag = "-" + String(session.prefix(8)) + ".jsonl"
    let stems = names.filter { $0.hasSuffix(tag) }.map { String($0.dropLast(".jsonl".count)) }
    return stems.filter { !names.contains($0 + ".summary.md") }.max()
}

// MARK: - Input and output

/// Reads the hook's JSON from stdin. Empty or malformed input gives an empty dictionary.
func readInput() -> [String: Any] {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    do {
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    } catch {
        return [:]
    }
}

/// Prints one line to stderr, which Claude Code shows only in its debug log for this event.
func report(_ message: String) {
    FileHandle.standardError.write(Data("post-compact: \(message)\n".utf8))
}

// MARK: - Main

/// Writes the compaction summary from the hook input to the archive folder and returns 0.
func main() -> Int32 {
    let environment = ProcessInfo.processInfo.environment
    let project = environment["CLAUDE_PROJECT_DIR"] ?? FileManager.default.currentDirectoryPath
    let input = readInput()
    guard let summary = input["compact_summary"] as? String, !summary.isEmpty else {
        report("no compact_summary in the input; nothing saved")
        return 0
    }
    let session = input["session_id"] as? String ?? "session"
    let trigger = input["trigger"] as? String ?? "unknown"
    let directory = archiveDirectory(project: project)
    let stem = pairedStem(in: directory, session: session) ?? stamp(session: session, date: Date())
    let target = directory.appendingPathComponent(stem + ".summary.md")
    let text = "# Compaction summary (\(trigger))\n\n\(summary)\n"
    do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try text.write(to: target, atomically: true, encoding: .utf8)
    } catch {
        report("could not save the summary: \(error)")
        return 0
    }
    prune(directory, suffix: ".summary.md", keep: 100)
    return 0
}

exit(main())
