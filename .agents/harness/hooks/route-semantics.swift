// Claude Code UserPromptSubmit and PostToolUse(Read|Edit|Write|MultiEdit): picks the semantics card
// (records/SEMANTICS/) for the prompt's words or the file's path and adds it to the model's context as
// `additionalContext`, so the area's invariants and vocabulary sit near the end of the context as it grows.
// A card is added when the area changes, and the active card plus the `always` cards come back each time the
// transcript grows by `regrowBytes`, and on the first event after a compaction (session-compact marks the state).
// State lives per session and agent in .agents/harness/.cache/semantics/. It never refuses: every path exits 0.
// The cards are read in the writer's canonical layout, the way perf-scan reads the catalog (rules/PRACTICES.md).
import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

// MARK: - Limits

/// Transcript growth, in bytes, after which the active card and the `always` cards are added again.
let regrowBytes = 300_000
/// The most the reply may add, in characters; Claude Code saves hook context over 10,000 characters to a file.
let messageLimit = 6_000
/// State files older than this many seconds are removed when a new one is written.
let stateLifetime: TimeInterval = 7 * 24 * 3600

// MARK: - Card
/// One semantics record: its name, scope, the path prefixes and prompt cues that select it, and its three prose fields.
struct Card {
    let name: String
    let file: String
    let always: Bool
    let paths: [String]
    let cues: [String]
    let holds: String
    let terms: String
    let next: String
}

// MARK: - Reading cards

/// Undoes the writer's string escapes: backslash, quote, newline and tab.
func unescape(_ s: String) -> String {
    var out = ""
    var escaped = false
    for c in s {
        if escaped {
            out.append(c == "n" ? "\n" : c == "t" ? "\t" : c)
            escaped = false
        } else if c == "\\" {
            escaped = true
        } else {
            out.append(c)
        }
    }
    return out
}

/// Splits a one-line list such as `["a", "b"]` into its strings.
func quotedItems(_ list: String) -> [String] {
    var items: [String] = []
    var current: String?
    var escaped = false
    for c in list {
        guard var text = current else {
            if c == "\"" { current = "" }
            continue
        }
        if escaped {
            text.append("\\")
            text.append(c)
            escaped = false
        } else if c == "\\" {
            escaped = true
        } else if c == "\"" {
            items.append(unescape(text))
            current = nil
            continue
        } else {
            text.append(c)
        }
        current = text
    }
    return items
}

/// Reads the top-level fields of one canonical record: a quoted string, a `"""` block or a one-line list each become
/// text, lists keep their brackets. Returns key to raw value.
func fields(of text: String) -> [String: String] {
    var out: [String: String] = [:]
    var lines = text.components(separatedBy: "\n")[...]
    while let line = lines.popFirst() {
        guard line.hasPrefix("  "), !line.hasPrefix("   "), let colon = line.range(of: ": ") else { continue }
        let key = String(line[line.index(line.startIndex, offsetBy: 2)..<colon.lowerBound])
        let value = String(line[colon.upperBound...])
        if value == "\"\"\"" {
            var block: [String] = []
            while let inner = lines.popFirst(), inner.trimmingCharacters(in: .whitespaces) != "\"\"\"" {
                block.append(inner.hasPrefix("    ") ? String(inner.dropFirst(4)) : inner)
            }
            out[key] = block.joined(separator: "\n")
        } else if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
            out[key] = unescape(String(value.dropFirst().dropLast()))
        } else {
            out[key] = value
        }
    }
    return out
}

/// Loads every card under records/SEMANTICS/ in file order. A file that lacks a name is skipped.
func loadCards(project: String) -> [Card] {
    let dir = project + "/.agents/records/SEMANTICS"
    // a missing folder means no cards yet, so there is nothing to add
    let names = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).filter { $0.hasSuffix(".closure") }
    var cards: [Card] = []
    for file in names.sorted() {
        // an unreadable card is skipped; write check reports it
        guard let text = try? String(contentsOfFile: dir + "/" + file, encoding: .utf8) else { continue }
        let f = fields(of: text)
        guard let name = f["name"] else { continue }
        cards.append(
            Card(
                name: name, file: ".agents/records/SEMANTICS/" + file, always: f["scope"] == "always",
                paths: quotedItems(f["paths"] ?? ""), cues: quotedItems(f["cues"] ?? "").map { $0.lowercased() },
                holds: f["holds"] ?? "", terms: f["terms"] ?? "", next: f["next"] ?? ""))
    }
    return cards
}

// MARK: - Routing

/// Returns the routed card whose path prefix matches `path` most closely, or nil. Prefixes resolve against the project.
func card(forPath path: String, in cards: [Card], project: String) -> Card? {
    let target = URL(fileURLWithPath: path).standardized.path
    var best: (card: Card, length: Int)?
    for c in cards where !c.always {
        for p in c.paths {
            var prefix = URL(fileURLWithPath: project).appendingPathComponent(p).standardized.path
            if p.hasSuffix("/") { prefix += "/" }
            guard target == prefix || target.hasPrefix(prefix.hasSuffix("/") ? prefix : prefix + "/") else { continue }
            if prefix.count > (best?.length ?? -1) { best = (c, prefix.count) }
        }
    }
    return best?.card
}

/// True when `cue` appears in `text` as a whole word or phrase.
func mentions(_ text: String, _ cue: String) -> Bool {
    let pattern = "(^|[^a-z0-9_])" + NSRegularExpression.escapedPattern(for: cue) + "($|[^a-z0-9_])"
    return text.range(of: pattern, options: .regularExpression) != nil
}

/// Returns the routed card with the most cues in `prompt`, the cues it matched, and any cards that tied its hit count.
func matchPrompt(_ prompt: String, in cards: [Card]) -> (card: Card?, cues: [String], ties: [String]) {
    let text = prompt.lowercased()
    var best: (card: Card, cues: [String])?
    var ties: [String] = []
    for c in cards where !c.always {
        let matched = c.cues.filter { mentions(text, $0) }
        guard !matched.isEmpty else { continue }
        if matched.count > (best?.cues.count ?? 0) {
            best = (c, matched)
            ties = []
        } else if matched.count == (best?.cues.count ?? 0) {
            ties.append(c.name)
        }
    }
    return (best?.card, best?.cues ?? [], ties)
}

/// Appends one JSON line to `.agents/harness/.cache/semantics/events.jsonl` when a card is injected.
func appendEvent(project: String, entry: [String: Any]) {
    let url = URL(fileURLWithPath: project + "/.agents/harness/.cache/semantics/events.jsonl")
    // an unencodable event is skipped so the hook still exits 0
    guard let data = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]) else { return }
    var line = data
    line.append(0x0A)
    if let handle = try? FileHandle(forWritingTo: url) {
        handle.seekToEndOfFile()
        handle.write(line)
        // closing an already-flushed descriptor cannot fail meaningfully
        try? handle.close()
    } else {
        // a failed first write only means this injection is not logged
        try? line.write(to: url, options: .atomic)
    }
}

/// Appends one JSON line to `.agents/harness/.cache/reinjections.jsonl` for card injections.
func appendReinjectionLog(
    project: String, session: String, agent: String, cards: [(name: String, chars: Int, reason: String)], total: Int
) {
    let url = URL(fileURLWithPath: project + "/.agents/harness/.cache/reinjections.jsonl")
    let entry: [String: Any] = [
        "agent": agent, "at": ISO8601DateFormatter().string(from: Date()),
        "cards": cards.map { ["chars": $0.chars, "name": $0.name, "reason": $0.reason] },
        "kind": "card", "session": session, "total_chars": total,
    ]
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
        // a failed first write only means this injection is not logged
        try? line.write(to: url, options: .atomic)
    }
}
// MARK: - State
/// What this session and agent last saw: the active card, the transcript size when the `always` cards were last
/// added (below zero after a compaction), and the size at which each card was last added.
struct State: Codable {
    var card: String?
    var bytes: Int
    var shown: [String: Int]?
}

/// True when `size` is `regrowBytes` past `mark`, or the transcript shrank or was compacted since `mark`.
func stale(_ mark: Int, at size: Int) -> Bool { mark < 0 || size < mark || size - mark >= regrowBytes }

/// Takes an exclusive lock on `url` plus `.lock`, so parallel tool calls decide one at a time. Returns the descriptor,
/// which the process holds until it exits, or -1 when the lock file cannot be opened (the hook then runs unlocked).
func lock(_ url: URL) -> Int32 {
    // the folder may exist already; a real failure shows up as open returning -1
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let fd = open(url.path + ".lock", O_CREAT | O_RDWR, 0o644)
    if fd >= 0 { flock(fd, LOCK_EX) }
    return fd
}

/// Returns the state file for one session and agent, with anything outside letters, digits and dashes replaced.
func stateURL(project: String, session: String, agent: String) -> URL {
    let safe = { (s: String) in String(s.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "_" }) }
    return URL(fileURLWithPath: project + "/.agents/harness/.cache/semantics")
        .appendingPathComponent(safe(session) + "--" + safe(agent) + ".json")
}

/// Reads the state, or nil when this session and agent have none yet.
func readState(_ url: URL) -> State? {
    // no file or a damaged one both mean a fresh start
    guard let data = try? Data(contentsOf: url) else { return nil }
    // a damaged file is treated as no state
    return try? JSONDecoder().decode(State.self, from: data)
}

/// Writes the state and removes state files past their lifetime.
func writeState(_ state: State, to url: URL) {
    let fm = FileManager.default
    let dir = url.deletingLastPathComponent()
    // the folder may exist already; a real failure shows up in the write below
    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    // losing the state only means the next event adds the cards again
    try? JSONEncoder().encode(state).write(to: url, options: .atomic)
    // an unreadable folder has nothing to prune
    for name in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] where name != "events.jsonl" {
        let file = dir.appendingPathComponent(name)
        // a file whose date cannot be read is left alone
        guard let date = (try? fm.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date else { continue }
        // a file that vanished meanwhile needs no removal
        if Date().timeIntervalSince(date) > stateLifetime { try? fm.removeItem(at: file) }
    }
}

/// Returns the size of the transcript in bytes, or 0 when it cannot be read.
func transcriptBytes(_ path: String?) -> Int {
    // a missing transcript counts as empty, so only area changes add cards
    guard let path, let size = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int else {
        return 0
    }
    return size
}

// MARK: - Message

/// Renders one card as statements under its name and file.
func render(_ c: Card, reason: String) -> String {
    var parts = ["Semantics: \(c.name) (\(c.file); \(reason))."]
    if !c.holds.isEmpty { parts.append("Holds here:\n" + c.holds) }
    if !c.terms.isEmpty { parts.append("Terms:\n" + c.terms) }
    if !c.next.isEmpty { parts.append("Files that go deeper:\n" + c.next) }
    return parts.joined(separator: "\n")
}

/// Formats the machine-readable status line for the cards injected in this event.
func reinjectedLine(cards: [(name: String, chars: Int, reason: String)], total: Int) -> String {
    let summary = cards.map { "\($0.name):\($0.chars)(\($0.reason))" }.joined(separator: "; ")
    return "[context-reinjected kind=card total=\(total) cards=\(summary)]"
}

/// Joins the parts and cuts the result at `messageLimit` characters with a note naming the folder.
func bounded(_ parts: [String]) -> String {
    let text = parts.joined(separator: "\n\n")
    guard text.count > messageLimit else { return text }
    let note = "\n[cut at \(messageLimit) characters; the cards are in .agents/records/SEMANTICS/]"
    return String(text.prefix(messageLimit)) + note
}

// MARK: - Input and output

/// Reads the hook's JSON from stdin. Empty or malformed input gives an empty dictionary.
func readInput() -> [String: Any] {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    // malformed input routes nothing, which is the safe default
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
}

/// Prints the context injection reply: `injectSteps` for Antigravity (`PreInvocation`), `{}` for Antigravity
/// `PostToolUse`, or `hookSpecificOutput` for Claude Code.
func reply(_ text: String, event: String, isGemini: Bool) {
    let body: [String: Any]
    if isGemini {
        if event == "PreInvocation" {
            body = ["injectSteps": [["systemMessage": ["systemMessage": text]]]]
        } else {
            body = [:]
        }
    } else {
        body = ["hookSpecificOutput": ["hookEventName": event, "additionalContext": text]]
    }
    // an unencodable reply adds nothing, which is the safe default
    guard let data = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]) else { return }
    FileHandle.standardOutput.write(data)
    print()
}

// MARK: - Main

/// Picks the card for this event, decides whether anything is due, prints the reply and saves the state. Returns 0.
// lint-ignore: func-length: single-pass hook handler reads input, locks state, injects card, and writes state
func main() -> Int32 {
    let input = readInput()
    let project = ProcessInfo.processInfo.environment["CLAUDE_PROJECT_DIR"] ?? FileManager.default.currentDirectoryPath
    let isGemini = input["hookEventName"] != nil
    let event = (input["hook_event_name"] as? String) ?? (input["hookEventName"] as? String) ?? ""
    let cards = loadCards(project: project)
    guard !cards.isEmpty, !event.isEmpty else {
        if isGemini { print("{}") }
        return 0
    }
    var chosen: Card?
    var reason = ""
    var kind = "regrow"
    var matchedCues: [String] = []
    var ties: [String] = []
    if let prompt = (input["prompt"] as? String) ?? (input["lastUserInput"] as? String),
        event == "UserPromptSubmit" || event == "PreInvocation"
    {
        let m = matchPrompt(prompt, in: cards)
        chosen = m.card
        matchedCues = m.cues
        ties = m.ties
        reason = matchedCues.isEmpty ? "matched the prompt" : "matched \(matchedCues.prefix(3).joined(separator: ", "))"
        if chosen != nil { kind = "prompt" }
    } else {
        let toolInput =
            (input["tool_input"] as? [String: Any])
            ?? ((input["toolCall"] as? [String: Any])?["args"] as? [String: Any])
        if let path = (toolInput?["file_path"] as? String) ?? (toolInput?["TargetFile"] as? String)
            ?? (toolInput?["AbsolutePath"] as? String) ?? (toolInput?["Path"] as? String)
        {
            chosen = card(forPath: path, in: cards, project: project)
            reason = "matched \(URL(fileURLWithPath: path).lastPathComponent)"
            if chosen != nil { kind = "path" }
        }
    }
    let session = (input["session_id"] as? String) ?? (input["conversationId"] as? String) ?? "none"
    let agent = (input["agent_id"] as? String) ?? (input["agentId"] as? String) ?? "main"
    let url = stateURL(project: project, session: session, agent: agent)
    let held = lock(url)
    defer { if held >= 0 { close(held) } }
    var state = readState(url) ?? State(card: nil, bytes: -1, shown: [:])
    var shown = state.shown ?? [:]
    let size = transcriptBytes((input["transcript_path"] as? String) ?? (input["transcriptPath"] as? String))
    let due = stale(state.bytes, at: size)
    let active = chosen ?? cards.first { $0.name == state.card }
    // a card shown within the last regrowBytes is still near the end of the context, so a switch back to it adds nothing
    let fresh = active.map { stale(shown[$0.name] ?? -1, at: size) } ?? false
    let canDeliver = !isGemini || event == "PreInvocation"
    var parts: [String] = []
    var injected: [(name: String, chars: Int, reason: String)] = []
    if canDeliver {
        if due {
            for card in cards.filter(\.always) {
                let text = render(card, reason: "always present")
                parts.append(text)
                injected.append((card.name, text.count, "always present"))
            }
        }
        if let active, due || fresh {
            let activeReason = chosen == nil ? "the active area" : reason
            let text = render(active, reason: activeReason)
            parts.append(text)
            injected.append((active.name, text.count, activeReason))
            shown[active.name] = size
            appendEvent(
                project: project,
                entry: [
                    "agent": agent, "bytes": size, "card": active.name, "cues": matchedCues,
                    "reason": chosen == nil ? "regrow" : kind, "session": session, "ties": ties,
                ])
        }
    }
    if !parts.isEmpty {
        let total = injected.reduce(0) { $0 + $1.chars }
        parts.insert(reinjectedLine(cards: injected, total: total), at: 0)
        appendReinjectionLog(project: project, session: session, agent: agent, cards: injected, total: total)
        reply(bounded(parts), event: event, isGemini: isGemini)
    } else if isGemini {
        print("{}")
    }
    state.card = active?.name ?? state.card
    state.bytes = (canDeliver && due) ? size : state.bytes
    state.shown = shown
    writeState(state, to: url)
    return 0
}

exit(main())
