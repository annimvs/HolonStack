// perf-scan.swift — lists code lines that match a catalog `detect` span while inside a loop body (rules/PERF.md).
// It reads text, not types, so every hit is a question for the agent to judge, not a finding.
// Usage: perf-scan [--hot=name,name] <file-or-folder…>   One `path:line: nest=N: <entry name>: <code>` line per hit, then a summary. Exit 2 on bad usage.
// A `--hot` function is one a loop elsewhere calls on every pass, such as a VM's run or opcode handler; its whole body counts as inside a loop.
import Foundation

// MARK: - Catalog

// MARK: - Detector
/// One catalog entry that has a `detect` field: its name and the literal code spans to look for.
struct Detector {
    let name: String
    let spans: [String]
}

/// Takes a field name and a record's text; returns the quoted value of the first `  name: "…"` line, or nil.
func fieldValue(_ key: String, in text: String) -> String? {
    for line in text.components(separatedBy: "\n") {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix(key + ": \""), t.hasSuffix("\""), t.count > key.count + 3 else { continue }
        return String(t.dropFirst(key.count + 3).dropLast())
    }
    return nil
}

/// Takes text; returns the strings between pairs of backticks, in order.
func codeSpans(_ s: String) -> [String] {
    var spans: [String] = []
    var current: String?
    for ch in s {
        if ch == "`" {
            if let c = current {
                if !c.isEmpty { spans.append(c) }
                current = nil
            } else {
                current = ""
            }
        } else if current != nil {
            current?.append(ch)
        }
    }
    return spans
}

/// Reads `name` and `detect` from every catalog entry; an entry without `detect` is skipped.
/// Takes the project path; returns the detectors in file order.
func loadDetectors(_ proj: String) -> [Detector] {
    let dir = proj + "/.agents/records/CATALOG"
    // a missing catalog folder just means no detectors; the caller reports that
    let files = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).filter { $0.hasSuffix(".closure") }
    var found: [Detector] = []
    for file in files.sorted() {
        guard let text = try? String(contentsOfFile: dir + "/" + file, encoding: .utf8),
            let name = fieldValue("name", in: text), let detect = fieldValue("detect", in: text)
        else { continue }
        let spans = codeSpans(detect)
        if !spans.isEmpty { found.append(Detector(name: name, spans: spans)) }
    }
    return found
}

// MARK: - Reading code

/// Blanks the contents of string literals and drops a trailing `//` comment, so spans match code only.
/// Takes one line; returns it with strings emptied and the comment removed.
func codeOnly(_ line: String) -> String {
    var out = ""
    var inString = false
    var escaped = false
    var prev: Character = " "
    for c in line {
        if inString {
            if escaped {
                escaped = false
                prev = " "
                continue
            }
            if c == "\\" {
                escaped = true
                prev = c
                continue
            }
            if c == "\"" {
                inString = false
                out.append(c)
            }
            prev = c
            continue
        }
        if c == "\"" {
            inString = true
            out.append(c)
            prev = " "
            continue
        }
        if c == "/" && prev == "/" {
            out.removeLast()
            break
        }
        out.append(c)
        prev = c
    }
    return out
}

/// Tests whether a regular expression matches anywhere in a string. Takes the pattern and the text.
func matches(_ pattern: String, _ s: String) -> Bool { s.range(of: pattern, options: .regularExpression) != nil }

let funcDecl = #"^\s*(\w+\s+)*func\s+\w"#
// an iterating closure opens right after the method name; `if x.contains(y) {` is an if body, not a closure
let loopHeader =
    #"^\s*(\w+:\s*)?(for|while)\b|^\s*repeat\b|\.(forEach|map|compactMap|flatMap|filter|allSatisfy|sorted|min|max|contains|first|firstIndex)\s*\{|\.reduce\([^)]*\)\s*\{"#

/// Takes a line holding a func declaration; returns the function's name, or an empty string.
func funcName(_ code: String) -> String {
    guard let r = code.range(of: #"func\s+\w+"#, options: .regularExpression) else { return "" }
    return String(code[r].dropFirst(4)).trimmingCharacters(in: .whitespaces)
}

// MARK: - LoopTracker
/// Follows brace depth through a file and records which braces open a loop body or a hot function body.
struct LoopTracker {
    var depth = 0
    var bodies: [Int] = []
    var hotBodies: [Int] = []
    var waiting = 0
    var hotWaiting = 0

    /// How many loop bodies and hot function bodies enclose the current line.
    var nesting: Int { bodies.count + hotBodies.count }

    /// Feeds one line of code and reports which kind of body opened on it.
    /// Takes the line, whether it starts a loop header, and `hotDecl`: nil when the line declares no func, else whether that func is hot.
    mutating func feed(_ code: String, isLoopStart: Bool, hotDecl: Bool?) -> (loop: Bool, hot: Bool) {
        if isLoopStart { waiting = 3 }
        if let h = hotDecl { hotWaiting = h ? 12 : 0 }
        var opened = (loop: false, hot: false)
        for ch in code {
            if ch == "{" {
                depth += 1
                if hotWaiting > 0 {
                    hotBodies.append(depth)
                    hotWaiting = 0
                    opened.hot = true
                } else if waiting > 0 {
                    bodies.append(depth)
                    waiting = 0
                    opened.loop = true
                }
            } else if ch == "}" {
                if bodies.last == depth { bodies.removeLast() }
                if hotBodies.last == depth { hotBodies.removeLast() }
                depth -= 1
            }
        }
        if waiting > 0 { waiting -= 1 }
        if hotWaiting > 0 { hotWaiting -= 1 }
        return opened
    }
}

// MARK: - Scanning

/// Scans one Swift file. Takes the path, the detectors and the hot function names; returns its hit lines and how many funcs it saw.
func scan(_ path: String, _ detectors: [Detector], hot: Set<String>) -> (hits: [String], funcs: Int) {
    guard let source = try? String(contentsOfFile: path, encoding: .utf8) else { return ([], 0) }
    var tracker = LoopTracker()
    var hits: [String] = []
    var funcs = 0
    for (i, line) in source.components(separatedBy: "\n").enumerated() {
        let code = codeOnly(line)
        var hotDecl: Bool?
        if matches(funcDecl, code) {
            funcs += 1
            hotDecl = hot.contains(funcName(code))
        }
        let start = matches(loopHeader, code)
        let before = tracker.nesting
        let opened = tracker.feed(code, isLoopStart: start, hotDecl: hotDecl)
        var scanText = code
        if opened.loop, let brace = code.firstIndex(of: "{") {
            scanText = String(code[code.index(after: brace)...])
        } else if start {
            scanText = ""
        }
        let nest = before + (opened.loop ? 1 : 0)
        guard nest > 0, !opened.hot else { continue }
        for d in detectors where d.spans.contains(where: { scanText.contains($0) }) {
            hits.append("\(path):\(i + 1): nest=\(nest): \(d.name): \(line.trimmingCharacters(in: .whitespaces))")
        }
    }
    return (hits, funcs)
}

/// Takes the arguments (files or folders); returns every .swift file under them, sorted, without `.build`, `.git` or test files.
func swiftFiles(_ args: [String]) -> [String] {
    let fm = FileManager.default
    var out: [String] = []
    for a in args {
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: a, isDirectory: &isDir) else { continue }
        if !isDir.boolValue {
            out.append(a)
            continue
        }
        let walker = fm.enumerator(atPath: a)
        while let rel = walker?.nextObject() as? String {
            guard rel.hasSuffix(".swift"), !rel.contains(".build/"), !rel.contains(".git/") else { continue }
            let name = (rel as NSString).lastPathComponent
            if rel.contains("tests/") || name.hasPrefix("test_") || name.hasSuffix("-test.swift") { continue }
            out.append(a + "/" + rel)
        }
    }
    return out.sorted()
}

// MARK: - Driver

let args = Array(CommandLine.arguments.dropFirst())
let proj = ProcessInfo.processInfo.environment["CLAUDE_PROJECT_DIR"] ?? FileManager.default.currentDirectoryPath
let targets = args.filter { !$0.hasPrefix("--") }
let hotArg = args.first { $0.hasPrefix("--hot=") } ?? ""
let hot = Set(hotArg.dropFirst(6).split(separator: ",").map(String.init))
guard !targets.isEmpty else {
    print("usage: perf-scan [--hot=name,name] <file-or-folder…>")
    exit(2)
}
let detectors = loadDetectors(proj)
guard !detectors.isEmpty else {
    print("perf-scan: no catalog entry has a detect field")
    exit(2)
}
let paths = swiftFiles(targets)
var total = 0
var units = 0
for p in paths {
    let result = scan(p, detectors, hot: hot)
    result.hits.forEach { print($0) }
    total += result.hits.count
    units += result.funcs
}
print("perf-scan: \(total) hit(s) in \(paths.count) file(s), \(units) func(s) seen")
// the summary only feeds perf-report; a failed write loses nothing else
try? "units=\(units) hits=\(total) files=\(paths.count)\n".write(
    toFile: proj + "/.agents/harness/.cache/perf-scan.summary", atomically: true, encoding: .utf8)
exit(0)
