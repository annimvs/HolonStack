// lint.swift — the Swift lint rules from .agents/harness/lint.closure (rules/SWIFT.md). Line based, not a parser: it reads
// code with strings and trailing comments blanked, so it can miss unusual layouts but does not flag text inside a string.
// Usage: lint <file.swift…>   One `file:line: rule-id: reason` line per finding. Every finding fails: exit 1 when there is any, else 0.
import Foundation

// MARK: - Rules

// MARK: - Rule
/// One rule from lint.closure, holding the reason that is printed with each finding.
struct Rule { let reason: String }

/// Reads `id: rule("reason")` lines from lint.closure; a rule that is not listed is off. A leftover `error,` or `warn,` label is ignored.
func loadRules(_ path: String) -> [String: Rule] {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8),
        let re = try? NSRegularExpression(
            pattern: #"^\s*([a-z-]+):\s*rule\((?:(?:error|warn),\s*)?"(.*)"\)"#, options: .anchorsMatchLines)
    else { return [:] }
    var rules: [String: Rule] = [:]
    for m in re.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
        guard let id = Range(m.range(at: 1), in: text), let why = Range(m.range(at: 2), in: text) else { continue }
        rules[String(text[id])] = Rule(reason: String(text[why]))
    }
    return rules
}

// MARK: - Reading code

/// Blanks the contents of string literals and drops a trailing `//` comment, so patterns match code only.
/// A raw string (`#"…"#`) ends only at `"#`, so a quote inside it, common in regexes, does not end it early.
func codeOnly(_ line: String) -> String {
    var out = ""
    var inString = false
    var raw = false
    var prev: Character = " "
    var chars = line.makeIterator()
    while let c = chars.next() {
        if inString {
            let closes = raw ? (c == "#" && prev == "\"") : (c == "\"" && prev != "\\")
            if closes {
                inString = false
                out.append(c)
            }
            prev = c
            continue
        }
        if c == "\"" {
            inString = true
            raw = prev == "#"
            out.append(c)
            // the quote that opens a raw string must not count as the one that closes it
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

/// Tests whether a regular expression matches anywhere in a string.
/// Takes the pattern and the text; returns true when it matches.
func matches(_ pattern: String, _ s: String) -> Bool { s.range(of: pattern, options: .regularExpression) != nil }

// MARK: - Checks

/// Takes a file path; returns true for a test (under a tests folder, or named test_*.swift or *-test.swift), where a failed force is the failure.
func isTestFile(_ path: String) -> Bool {
    let name = (path as NSString).lastPathComponent
    return path.contains("/tests/") || name.hasPrefix("test_") || name.hasSuffix("-test.swift")
}

/// Lints one file and returns its findings as (line, rule id, reason).
// lint-ignore: func-length: kept whole so its steps read in order; split it when it grows
func lint(_ path: String, _ rules: [String: Rule]) -> [(Int, String, String)] {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
    let lines = text.components(separatedBy: "\n")
    let code = lines.map(codeOnly)
    var found: [(Int, String, String)] = []
    // an executable script has statements at file scope; its top level `var`s are main actor isolated, so no-mutable-global skips it
    let isScript = code.contains {
        matches(#"^(for|if|guard|while|switch|do|defer)\b|^(exit|print)\(|^[A-Za-z_.]+\(|^[a-z]\w*\s*=\s"#, $0)
    }

    // `// lint-ignore: <id>: <why>` on the line or the one above skips that rule there; no reason is its own error
    func ignored(_ i: Int, _ id: String) -> Bool {
        for j in [i, i - 1] where j >= 0 {
            guard let r = lines[j].range(of: "lint-ignore:\\s*" + id + "\\b", options: .regularExpression) else {
                continue
            }
            let rest = lines[j][r.upperBound...].trimmingCharacters(in: CharacterSet(charactersIn: ": "))
            if !rest.isEmpty { return true }
        }
        return false
    }
    /// Records a finding for line `i` (zero based) when the rule is listed and not ignored on that line.
    func add(_ i: Int, _ id: String) {
        guard let rule = rules[id], !ignored(i, id) else { return }
        found.append((i + 1, id, rule.reason))
    }

    for (i, line) in lines.enumerated() {
        let c = code[i]
        if line.contains("lint-ignore:"), matches("lint-ignore:\\s*[a-z-]+\\s*:?\\s*$", line) {
            add(i, "ignore-needs-reason")
        }
        if matches(#"^\s*(\w+\s+)*func\s+\w"#, c) {
            // the comment may sit above attribute lines, so skip those when looking up
            var j = i - 1
            while j >= 0, lines[j].trimmingCharacters(in: .whitespaces).hasPrefix("@") { j -= 1 }
            if j < 0 || !lines[j].trimmingCharacters(in: .whitespaces).hasPrefix("//") { add(i, "doc-comment") }
            // length: count lines until the braces opened on or after the func line close again
            var depth = 0
            var opened = false
            var end = i
            for k in i..<lines.count {
                for ch in code[k] {
                    if ch == "{" {
                        depth += 1
                        opened = true
                    } else if ch == "}" {
                        depth -= 1
                    }
                }
                end = k
                if opened && depth <= 0 { break }
            }
            if opened && end - i + 1 > 60 { add(i, "func-length") }
        }
        if matches(
            #"^\s*(@\w+(\([^)]*\))?\s+)*((public|internal|private|fileprivate|open|final|indirect)\s+)*(struct|enum|class|actor|protocol)\s+(?!func\b|var\b|let\b|subscript\b|init\b)\w"#,
            c)
        {
            // the comment block directly above the type (attribute lines skipped) needs a MARK banner and a line saying what the type does
            var j = i - 1
            while j >= 0, lines[j].trimmingCharacters(in: .whitespaces).hasPrefix("@") { j -= 1 }
            var block: [String] = []
            while j >= 0, lines[j].trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                block.append(lines[j].trimmingCharacters(in: .whitespaces))
                j -= 1
            }
            if !block.contains(where: { $0.hasPrefix("// MARK:") }) { add(i, "type-mark") }
            if !block.contains(where: {
                !$0.hasPrefix("// MARK:")
                    && $0.drop(while: { $0 == "/" }).trimmingCharacters(in: .whitespaces).count > 0
            }) {
                add(i, "type-doc")
            }
        }
        if !isScript, matches(#"^(private |fileprivate |public |internal )?(nonisolated\(unsafe\) )?var\s"#, c) {
            add(i, "no-mutable-global")
        }
        if c.contains("@unchecked Sendable") || c.contains("nonisolated(unsafe)") { add(i, "no-unsafe-sendable") }
        if !isTestFile(path), matches(#"\btry!|\bas!|\bfatalError\("#, c) { add(i, "no-force") }
        // the reason may trail the line or sit in a comment on the line above
        if matches(#"^\s*try\?|_\s*=\s*try\?"#, c), !line.contains("//"),
            i == 0 || !lines[i - 1].trimmingCharacters(in: .whitespaces).hasPrefix("//")
        {
            add(i, "no-silent-try")
        }
    }
    if lines.count > 150, !text.contains("// MARK: -") { add(0, "mark-sections") }
    return found
}

// MARK: - Style

/// Takes a file path; returns true when a `.swift-format` file sits in the file's folder or any folder above it.
func hasStyleConfig(_ path: String) -> Bool {
    var dir = URL(fileURLWithPath: path).deletingLastPathComponent().standardizedFileURL
    while dir.path != "/" {
        if FileManager.default.fileExists(atPath: dir.appendingPathComponent(".swift-format").path) { return true }
        dir.deleteLastPathComponent()
    }
    return false
}

/// Runs `swift format lint` on one file and returns its findings as `file:line: format-Rule: message` lines.
/// Returns nil when `swift format` cannot run, so the caller can say the style was not checked.
func styleFindings(_ path: String) -> [String]? {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
    p.arguments = ["format", "lint", path]
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    guard (try? p.run()) != nil else { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    let out = String(decoding: data, as: UTF8.self)
    // a finding reads `path:line:col: warning: [Rule] message`; anything else means the tool itself failed
    guard let re = try? NSRegularExpression(pattern: #"^(.+?):(\d+):\d+: (?:warning|error): \[(\w+)\] (.*)$"#) else {
        return nil
    }
    var found: [String] = []
    for line in out.split(separator: "\n").map(String.init) {
        let range = NSRange(line.startIndex..., in: line)
        guard let m = re.firstMatch(in: line, range: range),
            let ln = Range(m.range(at: 2), in: line), let rule = Range(m.range(at: 3), in: line),
            let msg = Range(m.range(at: 4), in: line)
        else { continue }
        found.append("\(path):\(line[ln]): format-\(line[rule]): \(line[msg])")
    }
    if found.isEmpty && p.terminationStatus != 0 && !out.contains("[") { return nil }
    return found
}

// MARK: - Compiler

/// True for a single-file harness script, which the compiler can check on its own; package sources need their module.
func isHarnessScript(_ path: String) -> Bool {
    let absolute = URL(fileURLWithPath: path).standardized.path
    return absolute.contains("/.agents/harness/tools/") || absolute.contains("/.agents/harness/hooks/")
}

/// Type-checks one script the way Swift 6 strict concurrency and `-warnings-as-errors` would, and returns each
/// diagnostic as `file:line: compiler-warnings: message`. Returns nil when `swiftc` cannot run.
func compilerFindings(_ path: String) -> [String]? {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/swiftc")
    p.arguments = ["-typecheck", "-swift-version", "6", "-warnings-as-errors", path]
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    guard (try? p.run()) != nil else { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    let out = String(decoding: data, as: UTF8.self)
    // a diagnostic starts a line as `path:line:col: error|warning: message`; the lines under it are source excerpts
    guard let re = try? NSRegularExpression(pattern: #"^(.+?):(\d+):\d+: (?:warning|error): (.*)$"#) else { return nil }
    var found: [String] = []
    for line in out.split(separator: "\n").map(String.init) {
        guard let m = re.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
            let ln = Range(m.range(at: 2), in: line), let msg = Range(m.range(at: 3), in: line)
        else { continue }
        found.append("\(path):\(line[ln]): compiler-warnings: \(line[msg])")
    }
    if found.isEmpty && p.terminationStatus != 0 { return nil }
    return Array(NSOrderedSet(array: found)) as? [String] ?? found
}

let argv = Array(CommandLine.arguments.dropFirst())
let files = argv.filter { !$0.hasPrefix("--") }
let proj = ProcessInfo.processInfo.environment["CLAUDE_PROJECT_DIR"] ?? FileManager.default.currentDirectoryPath
let rules = loadRules(proj + "/.agents/harness/lint.closure")
guard !rules.isEmpty else {
    print("lint: no rules in .agents/harness/lint.closure")
    exit(1)
}
guard !files.isEmpty else {
    print("usage: lint <file.swift…>")
    exit(1)
}

var failed = false
var styleSkipped = false
var compilerSkipped = false
for f in files {
    // style is checked only where the project has chosen one, with a `.swift-format` file
    if hasStyleConfig(f) {
        if let found = styleFindings(f) {
            for s in found {
                print(s)
                failed = true
            }
        } else {
            styleSkipped = true
        }
    }
    // compiler warnings fail like any other finding, but only where lint.closure turns the rule on
    if rules["compiler-warnings"] != nil, isHarnessScript(f) {
        if let found = compilerFindings(f) {
            for s in found {
                print(s)
                failed = true
            }
        } else {
            compilerSkipped = true
        }
    }
    for (line, id, why) in lint(f, rules).sorted(by: { $0.0 < $1.0 }) {
        print("\(f):\(line): \(id): \(why)")
        failed = true
    }
}
if styleSkipped { print("lint: swift format is not available, so style was not checked") }
if compilerSkipped { print("lint: swiftc did not run, so compiler warnings were not checked") }
exit(failed ? 1 : 0)
