// Claude Code SessionStart with the `compact` matcher: after a compaction, adds the memory index, the open questions,
// the open tasks and the location of the archived transcripts to the model's context, read fresh from
// `.agents/records/`.
// The summary can drop a constraint; the records cannot, because `write` checks them and they live on disk. The message
// stays under 9,000 characters, because Claude Code saves hook context over 10,000 characters to a file and shows a
// 2,000-character preview instead. It does nothing for other start sources and never refuses.
import Foundation

// MARK: - Context

/// The most one record view may add, in characters, so the whole message stays under Claude Code's 10,000 limit.
let sectionLimit = 2_500

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

/// Returns the path of the newest file in `directory` whose name ends in `suffix`, or nil when there is none.
func newest(in directory: URL, suffix: String) -> String? {
    let manager = FileManager.default
    // the folder is created by the first compaction
    guard let names = try? manager.contentsOfDirectory(atPath: directory.path) else { return nil }
    // names start with a UTC stamp, so the largest name is the newest
    let latest = names.filter { $0.hasSuffix(suffix) }.max()
    return latest.map { directory.appendingPathComponent($0).path }
}

/// Builds the message: what happened, where the archives are, then each record view that has content.
func message(project: String) -> String {
    var parts = [
        "The conversation was just compacted. The summary can omit constraints, decisions and rejected approaches. "
            + "The records under .agents/records/ and the archives below keep them."
    ]
    let archive = URL(fileURLWithPath: project).appendingPathComponent(".agents/harness/.cache/compactions/claude")
    let fallback = URL(fileURLWithPath: project).appendingPathComponent(".agents/harness/.cache/compactions")
    var archiveLine =
        "Archive folder: \(archive.path). A .jsonl file is the transcript from before a compaction, "
        + "a .md file beside it is the same transcript in readable Markdown (transcript-md), "
        + "and a .summary.md file is the summary Claude Code wrote for it."
    if let transcript = newest(in: archive, suffix: ".jsonl") ?? newest(in: fallback, suffix: ".jsonl") {
        archiveLine += " The newest transcript is \(transcript)."
    }
    parts.append(archiveLine)
    let views = [
        ("Memory index", ".agents/records/MEMORY.md"),
        ("Open questions", ".agents/records/OPEN.md"),
        ("Open tasks", ".agents/records/TODO.md"),
    ]
    for (label, relative) in views {
        guard let text = excerpt(project + "/" + relative, limit: sectionLimit) else { continue }
        parts.append("## \(label) (\(relative))\n\(text)")
    }
    return parts.joined(separator: "\n\n")
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

/// Prints Claude Code's `additionalContext` reply when the session started after a compaction. Returns 0 either way.
func main() -> Int32 {
    let environment = ProcessInfo.processInfo.environment
    let project = environment["CLAUDE_PROJECT_DIR"] ?? FileManager.default.currentDirectoryPath
    let input = readInput()
    guard input["source"] as? String == "compact" else { return 0 }
    markSemanticsCompacted(project: project, session: input["session_id"] as? String ?? "none")
    let reply: [String: Any] = [
        "hookSpecificOutput": ["hookEventName": "SessionStart", "additionalContext": message(project: project)]
    ]
    // an unencodable reply adds nothing, which is the safe default
    guard let data = try? JSONSerialization.data(withJSONObject: reply, options: [.sortedKeys]) else { return 0 }
    FileHandle.standardOutput.write(data)
    print()
    return 0
}

exit(main())
