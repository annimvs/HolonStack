// transcript-md.swift — renders a Claude Code or Gemini/Antigravity .jsonl transcript into a compact,
// human- and agent-readable .md sibling, and prints the latest rendered transcript for cross-agent context handoff.
//
// Usage:
//   transcript-md <file.jsonl…>                  write <file.md> next to each <file.jsonl>
//   transcript-md --all                          render every .jsonl in .cache/compactions/{claude,gemini}/
//   transcript-md --latest [claude|gemini|any] [--turns N]
//                                                render the newest transcript and print its header + last N turns
import Foundation

// MARK: - Model

// MARK: - ToolEvent
/// One normalized tool call and any failure line that followed it.
struct ToolEvent {
    let summary: String
    var failure: String?
}

// MARK: - Turn
/// One user prompt and the assistant's tool calls and prose replies in that turn.
struct Turn {
    let number: Int
    let user: String
    var tools: [ToolEvent] = []
    var replies: [String] = []
}

// MARK: - ParsedTranscript
/// The normalized contents of one `.jsonl` transcript file.
struct ParsedTranscript {
    let sourcePath: String
    let provider: String
    var filesEdited: [String] = []
    var filesRead: [String] = []
    var lastFailure: String?
    var turns: [Turn] = []
}

// MARK: - Helpers

/// Strips surrounding quotes from a JSON-encoded string argument when present.
func cleanArg(_ s: String?) -> String {
    guard var text = s?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return "" }
    if text.hasPrefix("\""), text.hasSuffix("\""), text.count >= 2 {
        text = String(text.dropFirst().dropLast())
    }
    return text.replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\n", with: " ")
}

/// Converts an absolute path inside `project` to a project-relative path.
func relativePath(_ path: String, project: String) -> String {
    let clean = cleanArg(path)
    guard !clean.isEmpty else { return "" }
    if clean.hasPrefix(project + "/") { return String(clean.dropFirst(project.count + 1)) }
    return clean
}

/// Extracts the inner text of `<USER_REQUEST>...</USER_REQUEST>` when present, else returns trimmed text.
func cleanUserPrompt(_ raw: String) -> String {
    if let start = raw.range(of: "<USER_REQUEST>"), let end = raw.range(of: "</USER_REQUEST>"),
        start.upperBound <= end.lowerBound
    {
        return String(raw[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return raw.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Appends `item` to `list` if it is non-empty and not already present.
func appendUnique(_ item: String, to list: inout [String]) {
    guard !item.isEmpty, !list.contains(item) else { return }
    list.append(item)
}

// MARK: - Parsing

/// Normalizes a tool name and its arguments into `(kind, summary, editedFile, readFile)`.
func normalizeTool(
    name rawName: String, args: [String: Any], project: String
) -> (summary: String, edited: String?, read: String?) {
    let agyMap = [
        "read_file": "Read", "view_file": "Read", "write_file": "Write", "write_to_file": "Write",
        "edit_file": "Edit", "replace_file_content": "Edit", "multi_replace_file_content": "MultiEdit",
        "run_command": "Bash", "grep_search": "Grep", "find_by_name": "Glob",
    ]
    let name = agyMap[rawName] ?? rawName
    let rawPath =
        (args["file_path"] as? String) ?? (args["Path"] as? String) ?? (args["TargetFile"] as? String)
        ?? (args["AbsolutePath"] as? String) ?? ""
    let path = relativePath(rawPath, project: project)
    switch name {
    case "Read":
        return ("`Read` `\(path)`", nil, path)
    case "Write", "Edit", "MultiEdit":
        return ("`\(name)` `\(path)`", path, nil)
    case "Bash":
        let cmd = cleanArg((args["command"] as? String) ?? (args["CommandLine"] as? String))
        let short = cmd.count > 110 ? String(cmd.prefix(110)) + "…" : cmd
        return ("`Bash` `\(short)`", nil, nil)
    case "Grep", "Glob":
        let q = cleanArg((args["pattern"] as? String) ?? (args["Query"] as? String) ?? (args["Pattern"] as? String))
        return ("`\(name)` `\(q)`", nil, nil)
    default:
        return ("`\(name)`" + (path.isEmpty ? "" : " `\(path)`"), nil, nil)
    }
}

/// Extracts failure summary text from a tool output string when it exited non-zero or was blocked by a hook.
func extractFailure(from content: String) -> String? {
    if content.contains("BLOCKED by .agents/harness/hooks/guard-bash.swift")
        || content.contains("guard-edit:")
        || content.contains("check-edit (")
        || content.contains("check-drafts:")
    {
        let lines = content.split(separator: "\n").map(String.init)
        return lines.first {
            $0.contains("BLOCKED") || $0.contains("guard-edit:") || $0.contains("check-edit")
                || $0.contains("check-drafts:")
        } ?? lines.first
    }
    if let r = content.range(of: #"Command exited with code [1-9][0-9]*"#, options: .regularExpression) {
        let codeLine = String(content[r])
        let after = content[r.upperBound...]
        let tail = after.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "Command output:" && $0 != "." }
        let detail = tail.prefix(2).joined(separator: " | ")
        let joined = detail.isEmpty ? codeLine : "\(codeLine): \(detail)"
        return joined.count > 140 ? String(joined.prefix(140)) + "…" : joined
    }
    return nil
}

/// Returns true for text Claude Code puts in a user message that the person did not type: background-task
/// notifications, system reminders, local command output and the command echo.
func isInjectedUserText(_ text: String) -> Bool {
    let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let injected = [
        "<task-notification>", "<system-reminder>", "<local-command-", "<command-name>", "<command-message>",
        "Caveat: The messages below",
    ]
    return injected.contains { t.hasPrefix($0) }
}

/// The text of a Claude Code `tool_result`: a plain string, or the joined `text` blocks of an array.
func toolResultText(_ block: [String: Any]) -> String {
    if let s = block["content"] as? String { return s }
    let blocks = block["content"] as? [[String: Any]] ?? []
    return blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined(separator: "\n")
}

/// What a failed tool result says, cut to 160 characters: its first line, and after a bare `Exit code N` (the way
/// Claude Code opens a failed Bash result) the first line of the output too.
func failureLine(_ text: String) -> String {
    let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    guard var line = lines.first else { return "" }
    if line.range(of: #"^Exit code \d+$"#, options: .regularExpression) != nil, lines.count > 1 {
        line += ": " + lines[1]
    }
    return line.count > 160 ? String(line.prefix(160)) + "…" : line
}

/// Starts a new turn for `text` typed by the person, closing the current one.
func startTurn(_ text: String, current: inout Turn?, parsed: inout ParsedTranscript) {
    let cleaned = cleanUserPrompt(text)
    guard !cleaned.isEmpty, !isInjectedUserText(cleaned) else { return }
    if let prev = current { parsed.turns.append(prev) }
    current = Turn(number: parsed.turns.count + 1, user: cleaned)
}

/// Inspects a Claude Code message dictionary and updates `current` turn and `parsed` metadata.
func parseClaudeEntry(_ obj: [String: Any], project: String, current: inout Turn?, parsed: inout ParsedTranscript) {
    let role = (obj["type"] as? String) ?? (obj["role"] as? String) ?? ""
    let msg = (obj["message"] as? [String: Any]) ?? obj
    // Claude Code's own entries: a meta message the person didn't send, and the summary a compaction wrote
    if (obj["isMeta"] as? Bool) == true { return }
    if (obj["isCompactSummary"] as? Bool) == true {
        if let prev = current { parsed.turns.append(prev) }
        let note = "(the conversation was compacted here; its summary is in the `.summary.md` beside the transcript)"
        current = Turn(number: parsed.turns.count + 1, user: note)
        return
    }
    if role == "user" {
        if let text = (msg["content"] as? String) ?? (obj["prompt"] as? String) {
            startTurn(text, current: &current, parsed: &parsed)
        } else if let blocks = msg["content"] as? [[String: Any]] {
            for b in blocks {
                let bt = b["type"] as? String ?? ""
                if bt == "text", let t = b["text"] as? String {
                    startTurn(t, current: &current, parsed: &parsed)
                } else if bt == "tool_result", (b["is_error"] as? Bool) == true {
                    // only a result Claude Code marked as an error is a failure; a file that merely contains
                    // the words of one (a Read of a hook's source) is not
                    let fail = failureLine(toolResultText(b))
                    guard !fail.isEmpty else { continue }
                    parsed.lastFailure = fail
                    if var turn = current, !turn.tools.isEmpty {
                        turn.tools[turn.tools.count - 1].failure = fail
                        current = turn
                    }
                }
            }
        }
    } else if role == "assistant" {
        if current == nil { current = Turn(number: 1, user: "(session start)") }
        if let text = msg["content"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            current?.replies.append(text.trimmingCharacters(in: .whitespacesAndNewlines))
        } else if let blocks = msg["content"] as? [[String: Any]] {
            for b in blocks {
                let bt = b["type"] as? String ?? ""
                if bt == "text", let t = b["text"] as? String,
                    !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                {
                    current?.replies.append(t.trimmingCharacters(in: .whitespacesAndNewlines))
                } else if bt == "tool_use", let name = b["name"] as? String {
                    let args = (b["input"] as? [String: Any]) ?? [:]
                    let norm = normalizeTool(name: name, args: args, project: project)
                    if let e = norm.edited { appendUnique(e, to: &parsed.filesEdited) }
                    if let r = norm.read { appendUnique(r, to: &parsed.filesRead) }
                    current?.tools.append(ToolEvent(summary: norm.summary, failure: nil))
                }
            }
        }
    }
}

/// Parses a `.jsonl` transcript file (Claude Code or Gemini/Antigravity) into a `ParsedTranscript`.
func parseTranscript(at path: String, project: String) -> ParsedTranscript {
    let provider = path.contains("/gemini/") ? "gemini" : (path.contains("/claude/") ? "claude" : "auto")
    var parsed = ParsedTranscript(sourcePath: relativePath(path, project: project), provider: provider)
    // an unreadable file returns an empty transcript
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return parsed }
    var current: Turn?
    for line in text.split(separator: "\n") {
        // malformed lines are skipped
        guard let obj = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else { continue }
        let stepType = obj["type"] as? String ?? ""
        if stepType == "USER_INPUT" {
            let cleaned = cleanUserPrompt((obj["content"] as? String) ?? "")
            guard !cleaned.isEmpty else { continue }
            if let prev = current { parsed.turns.append(prev) }
            current = Turn(number: parsed.turns.count + 1, user: cleaned)
        } else if stepType == "PLANNER_RESPONSE" {
            if current == nil { current = Turn(number: 1, user: "(session start)") }
            if let calls = obj["tool_calls"] as? [[String: Any]] {
                for call in calls {
                    guard let name = call["name"] as? String else { continue }
                    let args = (call["args"] as? [String: Any]) ?? [:]
                    let norm = normalizeTool(name: name, args: args, project: project)
                    if let e = norm.edited { appendUnique(e, to: &parsed.filesEdited) }
                    if let r = norm.read { appendUnique(r, to: &parsed.filesRead) }
                    current?.tools.append(ToolEvent(summary: norm.summary, failure: nil))
                }
            }
            if let reply = obj["content"] as? String, !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                current?.replies.append(reply.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        } else if stepType == "GENERIC" {
            let content = (obj["content"] as? String) ?? ""
            if let fail = extractFailure(from: content) {
                parsed.lastFailure = fail
                if var turn = current, !turn.tools.isEmpty {
                    turn.tools[turn.tools.count - 1].failure = fail
                    current = turn
                }
            }
        } else {
            parseClaudeEntry(obj, project: project, current: &current, parsed: &parsed)
        }
    }
    if let last = current { parsed.turns.append(last) }
    return parsed
}

// MARK: - Rendering

/// Renders a `ParsedTranscript` as Markdown, optionally keeping only the last `lastTurns` turns.
func renderMarkdown(_ t: ParsedTranscript, lastTurns: Int? = nil) -> String {
    let stem = URL(fileURLWithPath: t.sourcePath).deletingPathExtension().lastPathComponent
    let edited = t.filesEdited.isEmpty ? "none" : t.filesEdited.map { "`\($0)`" }.joined(separator: ", ")
    let read = t.filesRead.isEmpty ? "none" : t.filesRead.prefix(15).map { "`\($0)`" }.joined(separator: ", ")
    let fail = t.lastFailure ?? "none"
    var out = [
        "# Transcript — \(stem) (\(t.provider))", "",
        "Generated by `transcript-md`; do not edit.", "",
        "- **Source:** `\(t.sourcePath)`",
        "- **Turns:** \(t.turns.count)",
        "- **Files edited:** \(edited)",
        "- **Files read:** \(read)",
        "- **Last failure:** \(fail)", "",
    ]
    let slice = lastTurns.map { Array(t.turns.suffix($0)) } ?? t.turns
    for turn in slice {
        out += ["## Turn \(turn.number) — User", "", turn.user, ""]
        if !turn.tools.isEmpty || !turn.replies.isEmpty {
            out.append("### Assistant")
            out.append("")
            for tool in turn.tools {
                if let f = tool.failure {
                    out.append("- \(tool.summary) → **FAILED:** `\(f)`")
                } else {
                    out.append("- \(tool.summary)")
                }
            }
            if !turn.tools.isEmpty, !turn.replies.isEmpty { out.append("") }
            for r in turn.replies {
                out.append(r)
                out.append("")
            }
        }
    }
    return out.joined(separator: "\n")
}

/// Converts a single `.jsonl` file to its sibling `.md` file and returns the `.md` path and parsed transcript.
func convertFile(_ jsonlPath: String, project: String) throws -> (mdPath: String, parsed: ParsedTranscript) {
    let parsed = parseTranscript(at: jsonlPath, project: project)
    let mdPath =
        jsonlPath.hasSuffix(".jsonl")
        ? String(jsonlPath.dropLast(".jsonl".count)) + ".md"
        : jsonlPath + ".md"
    let text = renderMarkdown(parsed)
    try text.write(toFile: mdPath, atomically: true, encoding: .utf8)
    return (mdPath, parsed)
}

/// Lists all `.jsonl` files in the compaction archive folders for `provider` (`claude`, `gemini`, or `any`), newest first.
func archivedTranscripts(project: String, provider: String) -> [String] {
    let base = project + "/.agents/harness/.cache/compactions"
    let dirs: [String]
    switch provider {
    case "claude": dirs = [base + "/claude"]
    case "gemini": dirs = [base + "/gemini"]
    default: dirs = [base + "/claude", base + "/gemini", base]
    }
    let fm = FileManager.default
    var dated: [(path: String, date: Date)] = []
    for d in dirs {
        // a missing directory just adds no files
        for name in (try? fm.contentsOfDirectory(atPath: d)) ?? [] where name.hasSuffix(".jsonl") {
            let full = d + "/" + name
            let date = ((try? fm.attributesOfItem(atPath: full))?[.modificationDate] as? Date) ?? .distantPast
            dated.append((full, date))
        }
    }
    return dated.sorted { $0.date > $1.date }.map(\.path)
}

// MARK: - Main

/// Runs `transcript-md` for `--all`, `--latest`, or explicit `.jsonl` file paths.
func main() -> Int32 {
    let project = ProcessInfo.processInfo.environment["CLAUDE_PROJECT_DIR"] ?? FileManager.default.currentDirectoryPath
    var args = Array(CommandLine.arguments.dropFirst())
    if args.isEmpty || args.first == "--all" {
        let files = archivedTranscripts(project: project, provider: "any")
        for f in files {
            // a single unreadable file is skipped
            if let (md, _) = try? convertFile(f, project: project) {
                print("transcript-md: wrote \(relativePath(md, project: project))")
            }
        }
        return 0
    }
    if args.first == "--latest" {
        args.removeFirst()
        var provider = "any"
        var turns = 10
        while !args.isEmpty {
            let a = args.removeFirst()
            if ["claude", "gemini", "any"].contains(a) {
                provider = a
            } else if a == "--turns", let next = args.first, let n = Int(next) {
                args.removeFirst()
                turns = max(1, n)
            }
        }
        guard let newest = archivedTranscripts(project: project, provider: provider).first else {
            FileHandle.standardError.write(
                Data("transcript-md: no archived transcripts found for '\(provider)'\n".utf8))
            return 1
        }
        do {
            let (_, parsed) = try convertFile(newest, project: project)
            print(renderMarkdown(parsed, lastTurns: turns))
            return 0
        } catch {
            FileHandle.standardError.write(Data("transcript-md: \(error)\n".utf8))
            return 1
        }
    }
    var status: Int32 = 0
    for f in args {
        do {
            let (md, _) = try convertFile(f, project: project)
            print("transcript-md: wrote \(relativePath(md, project: project))")
        } catch {
            FileHandle.standardError.write(Data("transcript-md: could not convert \(f): \(error)\n".utf8))
            status = 1
        }
    }
    return status
}

exit(main())
