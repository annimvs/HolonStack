// Claude Code SessionStart with the `compact` matcher: after a compaction, adds the memory index, the open questions,
// the open tasks and the location of the archived transcripts to the model's context, read fresh from
// `.agents/records/`.
// The summary can drop a constraint; the records cannot, because `write` checks them and they live on disk. The message
// stays under 9,000 characters, because Claude Code saves hook context over 10,000 characters to a file and shows a
// 2,000-character preview instead. It does nothing for other start sources and never refuses.
import Foundation

// MARK: - Context

/// The most one record view may add, in characters, so the whole message stays under the 9,000-character budget.
let sectionLimit = 2_500

/// Total injected context budget, in characters; keeps hook output under the 10,000-character truncation threshold.
let budgetLimit = 9_000

/// Returns the trimmed text of the file at `path`, cut to `limit` characters with a note when cut. Returns nil when
/// the file is missing or empty.
func excerpt(_ path: String, limit: Int) -> String? {
    // a missing view adds nothing
    guard let raw = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return nil }
    guard text.count > limit else { return text }
    return String(text.prefix(limit)) + "\n[cut at \(limit) characters; open the file for the rest]"
}

/// Returns the byte size of the file at `path`, or nil when it cannot be read.
func fileSize(_ path: String) -> Int? {
    // a missing or unreadable archive file reports no size
    (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int
}

/// Returns the path of the newest file in `directory` whose name ends in `suffix`, or nil when there is none.
func newest(in directory: URL, suffix: String) -> String? {
    let manager = FileManager.default
    // the folder is created by the first compaction
    guard let names = try? manager.contentsOfDirectory(atPath: directory.path) else { return nil }
    // names start with a UTC stamp, so the largest name is the newest
    let latest = names.filter { $0.hasSuffix(suffix) }.max()
    return latest.map { directory.appendingPathComponent($0).path }
}

/// Formats `date` as a UTC ISO-8601 string for the append-only reinjection log.
func isoStamp(_ date: Date) -> String {
    ISO8601DateFormatter().string(from: date)
}

// MARK: - ArchiveInfo
/// The newest archived transcript name and byte sizes for the compaction status line.
struct ArchiveInfo {
    let transcriptPath: String?
    let newestName: String
    let transcriptBytes: Int
    let summaryBytes: Int
}

/// Finds the newest archived transcript and reads its Markdown (or JSONL) and summary sizes.
func archiveInfo(project: String) -> ArchiveInfo {
    let archive = URL(fileURLWithPath: project).appendingPathComponent(".agents/harness/.cache/compactions/claude")
    let fallback = URL(fileURLWithPath: project).appendingPathComponent(".agents/harness/.cache/compactions")
    guard let jsonl = newest(in: archive, suffix: ".jsonl") ?? newest(in: fallback, suffix: ".jsonl") else {
        return ArchiveInfo(transcriptPath: nil, newestName: "none", transcriptBytes: 0, summaryBytes: 0)
    }
    let stem = String(jsonl.dropLast(".jsonl".count))
    let mdPath = stem + ".md"
    let hasMd = FileManager.default.fileExists(atPath: mdPath)
    let preferred = hasMd ? mdPath : jsonl
    let summaryBytes = fileSize(stem + ".summary.md") ?? 0
    return ArchiveInfo(
        transcriptPath: preferred,
        newestName: URL(fileURLWithPath: preferred).lastPathComponent,
        transcriptBytes: fileSize(preferred) ?? 0,
        summaryBytes: summaryBytes)
}

/// Builds the injected message and its matching log entry, keeping total length within `budgetLimit`.
func buildContext(project: String, session: String, now: Date = Date()) -> (text: String, log: [String: Any]) {
    let info = archiveInfo(project: project)
    var parts = [
        "The conversation was just compacted. The summary can omit constraints, decisions and rejected approaches. "
            + "The records under .agents/records/ and the archives below keep them."
    ]
    let archiveDir = URL(fileURLWithPath: project).appendingPathComponent(".agents/harness/.cache/compactions/claude")
    var archiveLine =
        "Archive folder: \(archiveDir.path). A .jsonl file is the transcript from before a compaction, "
        + "a .md file beside it is the same transcript in readable Markdown (transcript-md), "
        + "and a .summary.md file is the summary written for it."
    if let transcript = info.transcriptPath { archiveLine += " The newest transcript is \(transcript)." }
    parts.append(archiveLine)
    let views: [(key: String, label: String, path: String)] = [
        ("memory", "Memory index", ".agents/records/MEMORY.md"),
        ("open", "Open questions", ".agents/records/OPEN.md"),
        ("todo", "Open tasks", ".agents/records/TODO.md"),
    ]
    var sizes: [String: Int] = ["memory": 0, "open": 0, "todo": 0]
    for view in views {
        guard let text = excerpt(project + "/" + view.path, limit: sectionLimit) else { continue }
        sizes[view.key] = text.count
        parts.append("## \(view.label) (\(view.path))\n\(text)")
    }
    let body = parts.joined(separator: "\n\n")
    let prefix =
        "[context-reinjected kind=compact transcript=\(info.transcriptBytes) "
        + "summary=\(info.summaryBytes) memory=\(sizes["memory"] ?? 0) open=\(sizes["open"] ?? 0) "
        + "todo=\(sizes["todo"] ?? 0) newest=\(info.newestName) budget=\(budgetLimit) reinjected="
    let approx = min(budgetLimit, body.count + 2 + prefix.count + 5)
    let statsLine = prefix + "\(approx)]"
    let maxBody = max(0, budgetLimit - statsLine.count - 2)
    let trimmedBody = body.count > maxBody ? String(body.prefix(maxBody)) : body
    let base = trimmedBody.count + 2 + prefix.count + 1
    let digits = "\(base + "\(base)".count)".count
    let exactStats = prefix + "\(min(budgetLimit, base + digits))]"
    let full = trimmedBody + "\n\n" + exactStats
    let log: [String: Any] = [
        "at": isoStamp(now), "budget_chars": budgetLimit, "kind": "compact",
        "memory_chars": sizes["memory"] ?? 0, "newest": info.newestName, "open_chars": sizes["open"] ?? 0,
        "reinjected_chars": full.count, "session": session, "summary_chars": info.summaryBytes,
        "todo_chars": sizes["todo"] ?? 0, "transcript_chars": info.transcriptBytes,
    ]
    return (full, log)
}

// MARK: - Logging

/// Appends one JSON line to `.agents/harness/.cache/reinjections.jsonl`. Failures are ignored so the hook exits 0.
func appendLog(project: String, entry: [String: Any]) {
    let url = URL(fileURLWithPath: project + "/.agents/harness/.cache/reinjections.jsonl")
    // an unencodable entry is skipped so the hook still exits 0
    guard let data = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]) else { return }
    var line = data
    line.append(0x0A)
    // the cache folder may exist already; a write failure below is ignored
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    if let handle = try? FileHandle(forWritingTo: url) {
        handle.seekToEndOfFile()
        handle.write(line)
        // closing an already-flushed descriptor cannot fail meaningfully
        try? handle.close()
    } else {
        // a failed first write only means this reinjection is not logged
        try? line.write(to: url, options: .atomic)
    }
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

// MARK: - Semantics state

/// Marks every route-semantics state file of this session as compacted (`bytes` -1), so its next event adds the
/// `always` cards and the active card again. The file name rule matches `stateURL` in route-semantics.swift.
func markSemanticsCompacted(project: String, session: String) {
    let safe = String(session.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "_" })
    let dir = URL(fileURLWithPath: project + "/.agents/harness/.cache/semantics")
    // no folder means route-semantics has not run in this project yet
    let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
    for name in names where name.hasPrefix(safe + "--") {
        let file = dir.appendingPathComponent(name)
        // a damaged state file is skipped; route-semantics treats it as a fresh start anyway
        guard let data = try? Data(contentsOf: file),
            var state = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { continue }
        state["bytes"] = -1
        state["shown"] = [String: Int]()
        // a failed write only delays the cards until the transcript grows
        try? JSONSerialization.data(withJSONObject: state).write(to: file, options: .atomic)
    }
}

// MARK: - Main

/// Prints the `additionalContext` reply when the session started after a compaction. Returns 0 either way.
func main() -> Int32 {
    let environment = ProcessInfo.processInfo.environment
    let project = environment["CLAUDE_PROJECT_DIR"] ?? FileManager.default.currentDirectoryPath
    let input = readInput()
    guard input["source"] as? String == "compact" else { return 0 }
    let session = input["session_id"] as? String ?? "none"
    markSemanticsCompacted(project: project, session: session)
    let built = buildContext(project: project, session: session)
    appendLog(project: project, entry: built.log)
    let reply: [String: Any] = [
        "hookSpecificOutput": ["hookEventName": "SessionStart", "additionalContext": built.text]
    ]
    // an unencodable reply adds nothing, which is the safe default
    guard let data = try? JSONSerialization.data(withJSONObject: reply, options: [.sortedKeys]) else { return 0 }
    FileHandle.standardOutput.write(data)
    print()
    return 0
}

exit(main())
