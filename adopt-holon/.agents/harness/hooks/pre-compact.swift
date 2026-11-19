// Claude Code PreCompact and Antigravity Stop: copies the session transcript to
// `.agents/harness/.cache/compactions/<claude|gemini>/`, so conversations stay on disk and `session-compact` /
// `semantics-report` can read them. Keeps the newest 100 transcripts per provider. Never blocks: every path exits 0.
// On Claude Code it also prints `summaryInstructions`: a PreCompact hook that exits 0 has its stdout used as
// instructions for the compaction summary (hooks reference, "PreCompact output", checked 2026-11-18), so stdout must
// carry nothing else. Exit 2 would block the compaction, which this hook never does.
import Foundation

// MARK: - Summary instructions

/// What the compaction summary must keep, given to Claude Code on stdout for every compaction, manual or automatic.
/// It matches AGENTS.md's "Compact instructions" and rules/COMPACT.md. Stays far under the 10,000-character cap.
let summaryInstructions = """
    Keep what the records under .agents/records/ don't hold: the current goal, files mid-edit with their exact \
    paths, the last failing command and its error, and rejected approaches with the reason. Point at records by \
    their id instead of restating them. Keep the user's own instructions for this session word for word.
    """

// MARK: - Archive

/// The maximum number of archived transcripts kept per provider folder.
let keepTranscripts = 100

/// The folder that holds archived transcripts for `provider` (`claude` or `gemini`), under the harness cache.
func archiveDirectory(project: String, provider: String) -> URL {
    URL(fileURLWithPath: project).appendingPathComponent(
        ".agents/harness/.cache/compactions/\(provider)", isDirectory: true)
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

/// Deletes the oldest files in `directory` whose names end in `suffix` (and not in `excluding`), keeping the newest
/// `keep` by modification time.
func prune(_ directory: URL, suffix: String, excluding: String? = nil, keep: Int) {
    let manager = FileManager.default
    // no folder means nothing to prune
    guard let names = try? manager.contentsOfDirectory(atPath: directory.path) else { return }
    var dated: [(name: String, date: Date)] = []
    for name in names where name.hasSuffix(suffix) && !(excluding.map { name.hasSuffix($0) } ?? false) {
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
    FileHandle.standardError.write(Data("pre-compact: \(message)\n".utf8))
}

// MARK: - Main

/// Archives the transcript, then answers the caller: Claude Code gets the summary instructions on stdout, Antigravity
/// an empty JSON object. Returns 0 on every path, so a compaction is never blocked.
func main() -> Int32 {
    let input = readInput()
    let isGemini = input["conversationId"] != nil || input["transcriptPath"] != nil
    archive(input, isGemini: isGemini)
    print(isGemini ? "{}" : summaryInstructions)
    return 0
}

/// Copies the transcript named in the hook input into `compactions/claude/` or `compactions/gemini/`, writes its
/// Markdown sibling, and prunes old archives. Failures are reported on stderr and never stop the compaction.
func archive(_ input: [String: Any], isGemini: Bool) {
    let environment = ProcessInfo.processInfo.environment
    let project = environment["CLAUDE_PROJECT_DIR"] ?? FileManager.default.currentDirectoryPath
    let transcript = (input["transcript_path"] as? String) ?? (input["transcriptPath"] as? String) ?? ""
    guard !transcript.isEmpty else {
        report("no transcript_path or transcriptPath in the input; nothing archived")
        return
    }
    let provider = isGemini ? "gemini" : "claude"
    let session = (input["session_id"] as? String) ?? (input["conversationId"] as? String) ?? "session"
    let directory = archiveDirectory(project: project, provider: provider)
    let filename = isGemini ? "\(String(session.prefix(8))).jsonl" : "\(stamp(session: session, date: Date())).jsonl"
    let target = directory.appendingPathComponent(filename)
    do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.removeItem(at: target)
        }
        try FileManager.default.copyItem(atPath: transcript, toPath: target.path)
    } catch {
        report("could not archive \(transcript): \(error)")
        return
    }
    prune(directory, suffix: ".jsonl", keep: keepTranscripts)
    let converter = URL(fileURLWithPath: project).appendingPathComponent(".agents/harness/bin/transcript-md")
    if FileManager.default.isExecutableFile(atPath: converter.path) {
        let p = Process()
        p.executableURL = converter
        p.arguments = [target.path]
        var env = environment
        env["CLAUDE_PROJECT_DIR"] = project
        p.environment = env
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        // a failed markdown conversion still leaves the archived .jsonl intact
        try? p.run()
        p.waitUntilExit()
    }
    // the transcripts' Markdown siblings only (post-compact keeps its own 100 `.summary.md` files), pruned after the
    // new sibling exists so the count settles at keepTranscripts
    prune(directory, suffix: ".md", excluding: ".summary.md", keep: keepTranscripts)
}

exit(main())
