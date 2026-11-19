// semantics-report.swift — writes records/SEMANTICS.md: the semantics card scoreboard, from records/SEMANTICS/,
// .agents/harness/.cache/semantics/events.jsonl, .agents/harness/.cache/compactions/*.jsonl, and any .jsonl files
// passed on the command line (harness/README.md).
// Usage: semantics-report [transcript.jsonl…]   Prints the path it wrote. Exit 0.
import Foundation

// MARK: - Card
/// One semantics card from records/SEMANTICS/: its name, file, scope, paths, cues and listed `next` file paths.
struct Card {
    let name: String
    let file: String
    let always: Bool
    let paths: [String]
    let cues: [String]
    let nextFiles: [String]
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

/// Reads the top-level fields of one canonical record into a key-to-value map.
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

/// Extracts the leading path from each `path: description` line in a card's `next` block.
func parseNextFiles(_ next: String) -> [String] {
    var out: [String] = []
    for line in next.components(separatedBy: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let colon = trimmed.range(of: ":") else { continue }
        let head = String(trimmed[..<colon.lowerBound]).trimmingCharacters(in: .whitespaces)
        if !head.isEmpty { out.append(head) }
    }
    return out
}

/// Loads every card under records/SEMANTICS/ in file order.
func loadCards(project: String) -> [Card] {
    let dir = project + "/.agents/records/SEMANTICS"
    // a missing folder means no cards yet
    let names = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).filter { $0.hasSuffix(".closure") }
    var cards: [Card] = []
    for file in names.sorted() {
        // an unreadable file is skipped; write check reports it
        guard let text = try? String(contentsOfFile: dir + "/" + file, encoding: .utf8) else { continue }
        let f = fields(of: text)
        guard let name = f["name"] else { continue }
        cards.append(
            Card(
                name: name, file: file, always: f["scope"] == "always",
                paths: quotedItems(f["paths"] ?? ""), cues: quotedItems(f["cues"] ?? "").map { $0.lowercased() },
                nextFiles: parseNextFiles(f["next"] ?? "")))
    }
    return cards
}

/// True when `cue` appears in `text` as a whole word or phrase.
func mentions(_ text: String, _ cue: String) -> Bool {
    let pattern = "(^|[^a-z0-9_])" + NSRegularExpression.escapedPattern(for: cue) + "($|[^a-z0-9_])"
    return text.range(of: pattern, options: .regularExpression) != nil
}

/// Matches a prompt against all routed cards: returns the winning card, the cues it matched, and any tied card names.
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

/// Returns the routed card whose path prefix matches `path` most closely, or nil.
func matchPath(_ path: String, in cards: [Card], project: String) -> Card? {
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

// MARK: - Telemetry

// MARK: - BandStats
/// Tool call and hook rejection counts inside one byte-distance band since the last semantics card injection.
struct BandStats {
    var calls = 0
    var guardBash = 0
    var guardEdit = 0
    var checkEdit = 0
    var checkDrafts = 0
    var totalFails: Int { guardBash + guardEdit + checkEdit + checkDrafts }
}

// MARK: - CardStats
/// Per-card injection, navigation, cue and failure counters collected across events and transcripts.
struct CardStats {
    var byPath = 0
    var byPrompt = 0
    var byRegrow = 0
    var nextHits: [String: Int] = [:]
    var nextMisses = 0
    var wanderings = 0
    var failures = 0
    var cueHits: [String: Int] = [:]
    var ties: [String] = []
    var totalInjections: Int { byPath + byPrompt + byRegrow }
}

// MARK: - ReportData
/// All aggregated metrics used to render records/SEMANTICS.md.
struct ReportData {
    var transcripts = 0
    var totalBytes = 0
    var totalCalls = 0
    var bands = [BandStats(), BandStats(), BandStats(), BandStats()]
    var perCard: [String: CardStats] = [:]
}

/// Returns the band index (0: 0–100 KB, 1: 100–200 KB, 2: 200–300 KB, 3: 300 KB+) for a byte distance.
func bandIndex(_ distance: Int) -> Int {
    if distance < 100_000 { return 0 }
    if distance < 200_000 { return 1 }
    if distance < 300_000 { return 2 }
    return 3
}

/// True when `readPath` matches one of the card's `next` entries by suffix or filename.
func hitsNext(_ readPath: String, nextFiles: [String]) -> String? {
    let clean = readPath.trimmingCharacters(in: .whitespaces)
    for n in nextFiles {
        let pat = n.trimmingCharacters(in: CharacterSet(charactersIn: "` "))
        if pat.isEmpty { continue }
        if clean.hasSuffix(pat) || URL(fileURLWithPath: clean).lastPathComponent == pat {
            return pat
        }
    }
    return nil
}

/// Reads live injection events from `.agents/harness/.cache/semantics/events.jsonl` into `data`.
func loadEvents(project: String, into data: inout ReportData) {
    let path = project + "/.agents/harness/.cache/semantics/events.jsonl"
    // a missing event log just means no live injections have been recorded yet
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return }
    for line in text.split(separator: "\n") {
        // a malformed line is skipped
        guard let obj = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
            let name = obj["card"] as? String
        else { continue }
        var st = data.perCard[name, default: CardStats()]
        switch obj["reason"] as? String ?? "path" {
        case "prompt": st.byPrompt += 1
        case "regrow": st.byRegrow += 1
        default: st.byPath += 1
        }
        for cue in (obj["cues"] as? [String]) ?? [] { st.cueHits[cue, default: 0] += 1 }
        for tie in (obj["ties"] as? [String]) ?? [] where !st.ties.contains(tie) { st.ties.append(tie) }
        data.perCard[name] = st
    }
}

/// Classification of one line in a `.jsonl` transcript: any prompt text, tool calls (`name`, `file_path`), and hook error text.
func inspectLine(_ line: Substring) -> (prompt: String?, tools: [(String, String?)], errors: [String]) {
    let raw = String(line)
    // non-JSON lines are ignored
    guard let obj = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any] else {
        return (nil, [], [])
    }
    var prompt: String?
    var tools: [(String, String?)] = []
    var errors: [String] = []
    if let p = obj["prompt"] as? String { prompt = p }
    let stepType = obj["type"] as? String ?? ""
    if stepType == "USER_INPUT", let c = obj["content"] as? String { prompt = c }
    if stepType == "user" || (obj["role"] as? String) == "user" {
        if let c = obj["content"] as? String { prompt = c }
        if let msg = obj["message"] as? [String: Any], let c = msg["content"] as? String { prompt = c }
    }
    if let calls = obj["tool_calls"] as? [[String: Any]] {
        let agyMap = [
            "read_file": "Read", "view_file": "Read", "write_file": "Write", "write_to_file": "Write",
            "edit_file": "Edit", "replace_file_content": "Edit", "multi_replace_file_content": "MultiEdit",
            "run_command": "Bash", "grep_search": "Grep", "find_by_name": "Glob",
        ]
        for call in calls {
            guard let rawName = call["name"] as? String else { continue }
            let args = call["args"] as? [String: Any]
            let fp =
                (args?["Path"] as? String) ?? (args?["TargetFile"] as? String)
                ?? (args?["AbsolutePath"] as? String) ?? (args?["file_path"] as? String)
            tools.append((agyMap[rawName] ?? rawName, fp))
        }
    }
    /// Collects tool calls and error strings from a content array or message dictionary.
    func walkContent(_ any: Any) {
        if let dict = any as? [String: Any] {
            let t = dict["type"] as? String ?? ""
            if t == "tool_use", let name = dict["name"] as? String {
                let fp = (dict["input"] as? [String: Any])?["file_path"] as? String
                tools.append((name, fp))
            } else if let name = dict["tool_name"] as? String {
                let fp = (dict["tool_input"] as? [String: Any])?["file_path"] as? String
                tools.append((name, fp))
            }
            if t == "tool_result", let c = dict["content"] as? String { errors.append(c) }
            for v in dict.values { walkContent(v) }
        } else if let arr = any as? [Any] {
            for item in arr { walkContent(item) }
        }
    }
    walkContent(obj)
    if raw.contains("BLOCKED by .agents/harness/hooks/guard-bash.swift")
        || raw.contains("guard-edit:")
        || raw.contains("check-edit (")
        || raw.contains("check-drafts:")
    {
        errors.append(raw)
    }
    return (prompt, tools, errors)
}

/// Scans one `.jsonl` transcript file, replaying `route-semantics` rules and tallying tool calls, `next` hits and hook failures.
// lint-ignore: func-length: single-pass state machine over transcript lines keeps byte offset and active card in sync
func scanTranscript(_ path: String, cards: [Card], project: String, into data: inout ReportData) {
    // an unreadable transcript is skipped
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return }
    data.transcripts += 1
    var offset = 0
    var active: Card?
    var lastShown: [String: Int] = [:]
    var lastAlways = -1
    var lastInjectBytes = 0
    var awaitingFirstNav = false
    for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
        let bytes = line.utf8.count + 1
        offset += bytes
        let (prompt, tools, errors) = inspectLine(line)
        let due = lastAlways < 0 || offset - lastAlways >= 300_000
        if let p = prompt, !p.isEmpty {
            let m = matchPrompt(p, in: cards)
            if let c = m.card {
                let fresh = (lastShown[c.name] == nil) || (offset - (lastShown[c.name] ?? 0) >= 300_000)
                if due || fresh {
                    var st = data.perCard[c.name, default: CardStats()]
                    st.byPrompt += 1
                    for cue in m.cues { st.cueHits[cue, default: 0] += 1 }
                    for tie in m.ties where !st.ties.contains(tie) { st.ties.append(tie) }
                    data.perCard[c.name] = st
                    lastShown[c.name] = offset
                    lastInjectBytes = offset
                    awaitingFirstNav = true
                }
                active = c
            }
        }
        for (tool, fp) in tools {
            data.totalCalls += 1
            let b = bandIndex(max(0, offset - lastInjectBytes))
            data.bands[b].calls += 1
            if awaitingFirstNav, let cur = active {
                if tool == "Read", let fp = fp {
                    var st = data.perCard[cur.name, default: CardStats()]
                    if let hit = hitsNext(fp, nextFiles: cur.nextFiles) {
                        st.nextHits[hit, default: 0] += 1
                    } else {
                        st.nextMisses += 1
                    }
                    data.perCard[cur.name] = st
                    awaitingFirstNav = false
                } else if tool == "Glob" || tool == "Grep" {
                    var st = data.perCard[cur.name, default: CardStats()]
                    st.wanderings += 1
                    data.perCard[cur.name] = st
                    awaitingFirstNav = false
                }
            }
            if let fp = fp, ["Read", "Edit", "Write", "MultiEdit"].contains(tool),
                let c = matchPath(fp, in: cards, project: project)
            {
                let fresh = (lastShown[c.name] == nil) || (offset - (lastShown[c.name] ?? 0) >= 300_000)
                if due || fresh {
                    var st = data.perCard[c.name, default: CardStats()]
                    if due && c.name == active?.name { st.byRegrow += 1 } else { st.byPath += 1 }
                    data.perCard[c.name] = st
                    lastShown[c.name] = offset
                    lastInjectBytes = offset
                    awaitingFirstNav = true
                }
                active = c
            }
        }
        if due { lastAlways = offset }
        let b = bandIndex(max(0, offset - lastInjectBytes))
        for err in errors {
            var failed = false
            if err.contains("BLOCKED by .agents/harness/hooks/guard-bash.swift") {
                data.bands[b].guardBash += 1
                failed = true
            }
            if err.contains("guard-edit:") {
                data.bands[b].guardEdit += 1
                failed = true
            }
            if err.contains("check-edit (") {
                data.bands[b].checkEdit += 1
                failed = true
            }
            if err.contains("check-drafts:") {
                data.bands[b].checkDrafts += 1
                failed = true
            }
            if failed, let cur = active {
                var st = data.perCard[cur.name, default: CardStats()]
                st.failures += 1
                data.perCard[cur.name] = st
            }
        }
    }
    data.totalBytes += offset
}

// MARK: - Rendering

/// Formats a percentage `num / den` as `N.N%`, or `0.0%` when `den` is zero.
func pct(_ num: Int, _ den: Int) -> String {
    guard den > 0 else { return "0.0%" }
    return String(format: "%.1f%%", Double(num) * 100.0 / Double(den))
}

/// Renders one card's markdown subsection for `SEMANTICS.md`.
func renderCardSection(_ c: Card, stats st: CardStats) -> [String] {
    let hitsTotal = st.nextHits.values.reduce(0, +)
    let navTotal = hitsTotal + st.nextMisses + st.wanderings
    let hitDetail = st.nextHits.sorted { $0.value > $1.value }.map { "`\($0.key)`: \($0.value)" }.joined(
        separator: ", ")
    let fired = st.cueHits.sorted { $0.value > $1.value }.map { "`\($0.key)` (\($0.value))" }.joined(
        separator: ", ")
    let dead = c.cues.filter { (st.cueHits[$0] ?? 0) == 0 }.map { "`\($0)`" }.joined(separator: ", ")
    let ties = st.ties.isEmpty ? "none" : st.ties.map { "`\($0)`" }.joined(separator: ", ")
    return [
        "### `\(c.name)` ([`\(c.file)`](SEMANTICS/\(c.file)), `\(c.always ? "always" : "routed")`)", "",
        "| Measure | Value |",
        "|---|---|",
        "| Injections | \(st.totalInjections) (\(st.byPath) by path, \(st.byPrompt) by prompt cue, \(st.byRegrow) by regrow) |",
        "| First-read hit on `next` | \(hitsTotal) of \(navTotal)\(hitDetail.isEmpty ? "" : " (\(hitDetail))") |",
        "| Wandering after injection (`Glob`/`Grep` first) | \(st.wanderings) of \(navTotal) |",
        "| Failures while active | \(st.failures) |",
        "| Cues fired | \(fired.isEmpty ? "none" : fired) |",
        "| Dead cues (0 hits) | \(dead.isEmpty ? "none" : dead) |",
        "| Cue ties | \(ties) |", "",
    ]
}

/// Builds the full markdown text for `.agents/records/SEMANTICS.md`.
func renderReport(cards: [Card], data: ReportData) -> String {
    let alwaysCount = cards.filter(\.always).count
    let routedCount = cards.count - alwaysCount
    let allStats = cards.map { data.perCard[$0.name] ?? CardStats() }
    let byPath = allStats.reduce(0) { $0 + $1.byPath }
    let byPrompt = allStats.reduce(0) { $0 + $1.byPrompt }
    let byRegrow = allStats.reduce(0) { $0 + $1.byRegrow }
    let totalInj = byPath + byPrompt + byRegrow
    let totalNextHits = allStats.reduce(0) { $0 + $1.nextHits.values.reduce(0, +) }
    let totalNavs = allStats.reduce(0) { $0 + $1.nextHits.values.reduce(0, +) + $1.nextMisses + $1.wanderings }
    let totalFails = data.bands.reduce(0) { $0 + $1.totalFails }
    let kb = String(format: "%.1f KB", Double(data.totalBytes) / 1000.0)
    var out = [
        "# Semantics", "",
        "Generated by `semantics-report`; do not edit. Refresh with `.agents/harness/bin/semantics-report`.", "",
        "## Scoreboard", "",
        "| Measure | Value |",
        "|---|---|",
        "| Cards in `records/SEMANTICS/` | \(cards.count) (\(alwaysCount) `always`, \(routedCount) `routed`) |",
        "| Transcripts scanned | \(data.transcripts) (\(kb), \(data.totalCalls) tool calls) |",
        "| Card injections | \(totalInj) (\(byPath) by path, \(byPrompt) by prompt cue, \(byRegrow) by 300 KB regrow) |",
        "| First-read hit on card `next` files | \(pct(totalNextHits, totalNavs)) (\(totalNextHits) of \(totalNavs) post-injection navigations) |",
        "| Overall hook or draft failure rate | \(pct(totalFails, data.totalCalls)) (\(totalFails) of \(data.totalCalls) tool calls) |",
        "",
        "## Failure rate by bytes since last card injection", "",
        "| Bytes since injection | Tool calls | `guard-bash` | `guard-edit` | `check-edit` / draft | `check-drafts` | Total fail rate |",
        "|---|---|---|---|---|---|---|",
    ]
    let labels = ["0 – 100 KB", "100 – 200 KB", "200 – 300 KB", "300 KB+"]
    for (i, label) in labels.enumerated() {
        let b = data.bands[i]
        out.append(
            "| \(label) | \(b.calls) | \(b.guardBash) | \(b.guardEdit) | \(b.checkEdit) | \(b.checkDrafts) | \(pct(b.totalFails, b.calls)) |"
        )
    }
    out += ["", "## Cards", ""]
    for c in cards { out += renderCardSection(c, stats: data.perCard[c.name] ?? CardStats()) }
    return out.joined(separator: "\n")
}

// MARK: - Driver

/// Collects events and transcripts, writes `.agents/records/SEMANTICS.md`, and returns 0 (or 1 on write failure).
func main() -> Int32 {
    let proj = ProcessInfo.processInfo.environment["CLAUDE_PROJECT_DIR"] ?? FileManager.default.currentDirectoryPath
    let cards = loadCards(project: proj)
    var data = ReportData()
    for c in cards { data.perCard[c.name] = CardStats() }
    loadEvents(project: proj, into: &data)
    let compDirs = [
        proj + "/.agents/harness/.cache/compactions",
        proj + "/.agents/harness/.cache/compactions/claude",
        proj + "/.agents/harness/.cache/compactions/gemini",
    ]
    // missing compaction directories just mean no compactions have been archived yet
    let archived = compDirs.flatMap { dir in
        ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [])
            .filter { $0.hasSuffix(".jsonl") }.sorted().map { dir + "/" + $0 }
    }
    let cliFiles = Array(CommandLine.arguments.dropFirst()).filter { $0.hasSuffix(".jsonl") }
    var seen = Set<String>()
    for file in archived + cliFiles {
        let std = URL(fileURLWithPath: file).standardized.path
        guard seen.insert(std).inserted else { continue }
        scanTranscript(std, cards: cards, project: proj, into: &data)
    }
    let text = renderReport(cards: cards, data: data)
    let target = proj + "/.agents/records/SEMANTICS.md"
    do {
        try text.write(toFile: target, atomically: true, encoding: .utf8)
        print("semantics-report: wrote \(target)")
        return 0
    } catch {
        print("semantics-report: could not write \(target): \(error)")
        return 1
    }
}

exit(main())
