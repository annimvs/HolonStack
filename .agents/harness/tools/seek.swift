// seek.swift — scope-aware search: grep that returns the whole unit around each hit, with the line range `edit --range` takes.
//   seek TERM [PATH…]        each hit's enclosing unit: a Swift func or type, a markdown section, a closure record, else a window
//   seek --outline PATH…     the file's units with line ranges and no bodies (add -e TERM to keep only matching ones)
//   seek --files TERM [PATH…]  the files that hit, with a count
// Each file prints once as `== path #H`; H is the start of the hash `edit --hash` checks. Output is compact: a unit's range
// (`A-B<TAB>text` on its declaration line, else an `A-B  label` line) and its hit lines. `--bodies` prints whole units. Exit: 0 hits, 1 none, 64 usage.
// Swift units come from brace depth and declaration keywords, not SwiftSyntax: the range is a good guess `edit` re-checks by hash.
import Foundation

// MARK: - Options
/// What the command line asked for.
struct Options {
    var term: String?
    var paths: [String] = []
    var ignoreCase = false
    var word = false
    var regex = false
    var outline = false
    var filesOnly = false
    var maxLines = 150
    var unitMax = 60
    var context = 3
    var style: Style?
}

// MARK: - Style
/// How matches print: whole units, or each unit's range and hit lines only.
enum Style { case full, compact }

/// The text `seek --help` prints.
let helpText = """
    usage:
      seek TERM [PATH…]            the unit around each hit, with its line range and the file hash
      seek --outline PATH…         units and ranges only; -e TERM keeps the matching ones
      seek --files TERM [PATH…]    files that hit, with counts
    options:
      -i  ignore case     -w  whole word     -E  TERM is a regular expression     -e TERM  the term, when it starts with '-'
      -b, --bodies    print whole units instead of the hit lines (-c, --compact is the default)
      --max-lines N   with whole units, stop after N lines (default 150); compact output stops at 200 hit lines
      --unit-max N    a unit longer than N lines prints only its hit lines (default 60)
      --context N     lines around a hit that has no unit (default 3)
    PATH defaults to the current folder. Skipped unless a PATH names them: .git .build .cache .swiftpm DerivedData node_modules
    conformance reference. Binary and over-2MB files are skipped. Edit what you found: edit FILE --hash H --range A-B --new TEXT
    """

/// Prints a usage error and exits 64.
func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("seek: " + message + "\n").utf8))
    exit(64)
}

/// Reads the command line.
func parseArguments() -> Options {
    var options = Options()
    let args = Array(CommandLine.arguments.dropFirst())
    var positional: [String] = []
    var index = 0
    /// The positive number after `flag`, or a usage failure.
    func number(_ flag: String) -> Int {
        index += 1
        guard index < args.count, let value = Int(args[index]), value > 0 else {
            fail("\(flag) needs a positive number")
        }
        return value
    }
    while index < args.count {
        let arg = args[index]
        switch arg {
        case "-h", "--help":
            print(helpText)
            exit(0)
        case "-i": options.ignoreCase = true
        case "-w": options.word = true
        case "-E", "--regex": options.regex = true
        case "-e":
            index += 1
            guard index < args.count else { fail("-e needs a term") }
            options.term = args[index]
        case "--outline": options.outline = true
        case "--files": options.filesOnly = true
        case "--bodies", "-b": options.style = .full
        case "--compact", "-c": options.style = .compact
        case "--max-lines": options.maxLines = number(arg)
        case "--unit-max": options.unitMax = number(arg)
        case "--context": options.context = number(arg)
        default:
            if arg.hasPrefix("-") && arg.count > 1 { fail("unknown flag '\(arg)' (seek --help)") }
            positional.append(arg)
        }
        index += 1
    }
    if options.term == nil && !options.outline && !positional.isEmpty { options.term = positional.removeFirst() }
    if options.term == nil && !options.outline { fail("missing TERM (seek TERM [PATH…] | seek --outline PATH…)") }
    options.paths = positional.isEmpty ? ["."] : positional
    return options
}

// MARK: - Matching
/// Returns a test for one line: a plain substring when the term is literal, else a regular expression.
func makeMatcher(_ options: Options) -> (String) -> Bool {
    guard let term = options.term else { return { _ in true } }
    if !options.regex && !options.word {
        return options.ignoreCase ? { $0.range(of: term, options: .caseInsensitive) != nil } : { $0.contains(term) }
    }
    var pattern = options.regex ? term : NSRegularExpression.escapedPattern(for: term)
    if options.word { pattern = "\\b(?:" + pattern + ")\\b" }
    guard let re = try? NSRegularExpression(pattern: pattern, options: options.ignoreCase ? [.caseInsensitive] : [])
    else { fail("invalid pattern: \(term)") }
    return { line in re.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil }
}

// MARK: - Files
let skipDirectories: Set<String> = [
    ".git", ".build", ".cache", ".swiftpm", "DerivedData", "node_modules",
    "target", "dist", "build", "builddir", ".next", ".venv", "__pycache__", "vendor",
    "conformance", "reference",
]
let maxFileBytes = 2 * 1024 * 1024

/// Lists the files under `paths`, skipping the usual noise folders unless a path itself sits in one.
func collectFiles(_ paths: [String]) -> [String] {
    let fm = FileManager.default
    var out: [String] = []
    for path in paths {
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDirectory) else {
            FileHandle.standardError.write(Data("seek: \(path): no such file or folder\n".utf8))
            continue
        }
        if !isDirectory.boolValue {
            out.append(path)
            continue
        }
        let named = Set(URL(fileURLWithPath: path).standardized.pathComponents)
        let skip = skipDirectories.subtracting(named)
        guard let walker = fm.enumerator(atPath: path) else { continue }
        while let relative = walker.nextObject() as? String {
            let name = (relative as NSString).lastPathComponent
            let full = path == "." ? relative : path + "/" + relative
            var entryIsDirectory: ObjCBool = false
            guard fm.fileExists(atPath: full, isDirectory: &entryIsDirectory) else { continue }
            // skipDescendants on a symlink to a folder would end the whole parent folder (it is not a descent), and a link may
            // loop or leave the tree, so a linked folder is not followed
            let linkType = walker.fileAttributes?[.type] as? FileAttributeType
            if entryIsDirectory.boolValue, linkType == .typeSymbolicLink { continue }
            if entryIsDirectory.boolValue {
                if skip.contains(name) { walker.skipDescendants() }
            } else if name != ".DS_Store" {
                out.append(full)
            }
        }
    }
    return out.sorted()
}

// MARK: - Source
/// One readable text file: its lines and the hash `edit` would print for it.
struct Source {
    let lines: [String]
    let hash: String
}

/// Reads a file, or nil when it is binary, too large or unreadable. The hash is FNV-1a 64, the same one `edit` prints.
func load(_ path: String) -> Source? {
    guard let data = FileManager.default.contents(atPath: path), data.count <= maxFileBytes,
        !data.prefix(8192).contains(0)
    else { return nil }
    var value: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in data { value = (value ^ UInt64(byte)) &* 0x100_0000_01b3 }
    let digits = String(value, radix: 16)
    var lines = data.split(separator: 0x0A, omittingEmptySubsequences: false).map { slice -> String in
        let trimmed = slice.last == 0x0D ? slice.dropLast() : slice
        return String(decoding: trimmed, as: UTF8.self)
    }
    if lines.last == "" { lines.removeLast() }
    return Source(lines: lines, hash: String(repeating: "0", count: 16 - digits.count) + digits)
}

// MARK: - Units
/// A range of lines (0-based, inclusive) with a label, and the 1-based lines that hit inside it.
struct Unit {
    var start: Int
    var end: Int
    var label: String
    var hits: [Int] = []
    var isWindow = false
}

// MARK: - Blocks
/// A Swift declaration with a body: its first line, the line of its `{`, its last line, and whether it is a type.
struct Block {
    var start: Int
    var open: Int
    var end: Int
    var isType: Bool
    var label: String
    var keyword: String
}

let declarationPattern =
    #"^\s*(?:@[A-Za-z_]+(?:\([^)]*\))?\s+)*(?:(?:public|private|fileprivate|internal|open|package|export|default|pub(?:\([^)]*\))?|extern|inline|constexpr|virtual|static|final|override|mutating|nonmutating|nonisolated|indirect|required|convenience|lazy|weak|unowned|dynamic|async|unsafe|abstract|readonly|declare|prefix|postfix|infix)(?:\([a-z]+\))?\s+)*(func|fn|function|init|deinit|subscript|struct|class|enum|extension|protocol|actor|interface|trait|impl|namespace|mod|type|var|let)\b"#
let declarationRegex = try? NSRegularExpression(pattern: declarationPattern)
let typeKeywords: Set<String> = [
    "struct", "class", "enum", "extension", "protocol", "actor", "interface", "trait", "impl", "namespace", "mod",
]
let braceLanguageExts: Set<String> = [
    "swift", "c", "cc", "cpp", "cxx", "h", "hh", "hpp", "m", "mm", "rs", "go", "ts", "tsx", "js", "jsx", "mjs",
    "cjs", "java", "kt", "cs", "zig",
]
let cFamilyExts: Set<String> = ["c", "cc", "cpp", "cxx", "h", "hh", "hpp", "m", "mm"]
let cFuncRegex = try? NSRegularExpression(
    pattern: #"^[ \t]*(?:[A-Za-z_][A-Za-z0-9_:*&<> \t]+)[ \t]+([A-Za-z_~][A-Za-z0-9_:]*)\s*\("#)
let cControlWords: Set<String> = ["if", "for", "while", "switch", "catch", "return", "else", "sizeof", "alignof"]
let pythonDeclRegex = try? NSRegularExpression(
    pattern: #"^([ \t]*)(?:async\s+)?(def|class)\s+([A-Za-z_][A-Za-z0-9_]*)"#)

/// The keyword of a declaration line, or nil when the line is not one.
func declarationKeyword(_ line: String, cFamily: Bool = false) -> String? {
    let range = NSRange(line.startIndex..., in: line)
    if let regex = declarationRegex, let match = regex.firstMatch(in: line, range: range),
        let keyword = Range(match.range(at: 1), in: line)
    {
        return String(line[keyword])
    }
    if cFamily, let regex = cFuncRegex, let match = regex.firstMatch(in: line, range: range),
        let nameRange = Range(match.range(at: 1), in: line)
    {
        let name = String(line[nameRange])
        if !cControlWords.contains(name) { return "func" }
    }
    return nil
}

// MARK: - Lexing
/// Where the scan stands between lines: the depth of block comments, and the `#` count of an open multi-line string.
struct LexState {
    var comment = 0
    var triple: Int?
}

/// The number of `#` in a row from `start`.
func hashes(_ s: [Unicode.Scalar], from start: Int) -> Int {
    var n = 0
    while start + n < s.count, s[start + n] == "#" { n += 1 }
    return n
}

/// True when `marks` quotes followed by `hashCount` hashes sit at `start`.
func closes(_ s: [Unicode.Scalar], at start: Int, _ marks: Int, _ hashCount: Int) -> Bool {
    guard start + marks + hashCount <= s.count else { return false }
    return (0..<marks).allSatisfy { s[start + $0] == "\"" }
        && (0..<hashCount).allSatisfy { s[start + marks + $0] == "#" }
}

/// True when `u` is an ASCII hexadecimal digit (used to spot C++14 digit separators like `1'000`).
func isAsciiHex(_ u: UnicodeScalar) -> Bool {
    (u >= "0" && u <= "9") || (u >= "a" && u <= "f") || (u >= "A" && u <= "F")
}

/// Advances past a closed single-quoted or backtick literal starting at `start`, returning `start + 1` when unclosed
/// or when `'` is a C++14 digit separator or Rust lifetime so braces on the line are never swallowed.
func skipDelimited(_ s: [UnicodeScalar], from start: Int, delim: UnicodeScalar) -> Int {
    if delim == "'" {
        if start > 0, start + 1 < s.count, isAsciiHex(s[start - 1]), isAsciiHex(s[start + 1]) { return start + 1 }
        if start > 0, s[start - 1] == "<" || s[start - 1] == "&" {
            let isCharLit =
                (start + 2 < s.count && s[start + 2] == "'") || (start + 1 < s.count && s[start + 1] == "\\")
            if !isCharLit { return start + 1 }
        }
    }
    var i = start + 1
    while i < s.count {
        if s[i] == "\\" {
            i += 2
        } else if s[i] == delim {
            return i + 1
        } else {
            i += 1
        }
    }
    return start + 1
}

/// The `{` and `}` on one line that are code, and the state for the next line.
// lint-ignore: func-length: single-pass brace scanner keeps comment and string states in one loop
func braces(onLine line: String, _ state: inout LexState) -> [Character] {
    var found: [Character] = []
    let s = Array(line.unicodeScalars)
    var i = 0
    while i < s.count {
        if state.comment > 0 {
            if s[i] == "*", i + 1 < s.count, s[i + 1] == "/" {
                state.comment -= 1
                i += 2
            } else if s[i] == "/", i + 1 < s.count, s[i + 1] == "*" {
                state.comment += 1
                i += 2
            } else {
                i += 1
            }
            continue
        }
        if let n = state.triple {
            if closes(s, at: i, 3, n) {
                state.triple = nil
                i += 3 + n
            } else {
                i += n == 0 && s[i] == "\\" ? 2 : 1
            }
            continue
        }
        let c = s[i]
        if c == "/", i + 1 < s.count, s[i + 1] == "/" { break }
        if c == "/", i + 1 < s.count, s[i + 1] == "*" {
            state.comment += 1
            i += 2
            continue
        }
        if c == "#" || c == "\"" {
            let n = hashes(s, from: i)
            let q = i + n
            if q < s.count, s[q] == "\"" {
                if closes(s, at: q, 3, 0) {
                    state.triple = n
                    i = q + 3
                    continue
                }
                i = q + 1
                while i < s.count {
                    if n == 0, s[i] == "\\" {
                        i += 2
                    } else if closes(s, at: i, 1, n) {
                        i += 1 + n
                        break
                    } else {
                        i += 1
                    }
                }
                continue
            }
        }
        if c == "'" || c == "`" {
            i = skipDelimited(s, from: i, delim: c)
            continue
        }
        if c == "{" { found.append("{") } else if c == "}" { found.append("}") }
        i += 1
    }
    return found
}

/// The `{` and `}` of each line that are code: not inside a comment, string or raw string.
func braces(in lines: [String]) -> [[Character]] {
    var state = LexState()
    return lines.map { braces(onLine: $0, &state) }
}

/// Finds the declaration that owns the `{` on line `i`: this line, or one a few lines above that has no body of its own yet.
func declarationStart(for i: Int, in lines: [String], cFamily: Bool = false) -> Int? {
    if declarationKeyword(lines[i], cFamily: cFamily) != nil { return i }
    var j = i - 1
    while j >= 0, i - j <= 12 {
        let t = lines[j].trimmingCharacters(in: .whitespaces)
        if t.isEmpty || t.hasSuffix("{") || t.hasSuffix("}") || t.hasPrefix("}") { return nil }
        if declarationKeyword(lines[j], cFamily: cFamily) != nil { return j }
        j -= 1
    }
    return nil
}

/// Every declaration with a body in a brace-delimited file, outermost first.
func swiftBlocks(_ lines: [String], cFamily: Bool = false) -> [Block] {
    var stack: [(start: Int, open: Int, keyword: String)?] = []
    var blocks: [Block] = []
    for (number, found) in braces(in: lines).enumerated() {
        var first = true
        for brace in found {
            if brace == "{" {
                if first, let start = declarationStart(for: number, in: lines, cFamily: cFamily),
                    let word = declarationKeyword(lines[start], cFamily: cFamily)
                {
                    var top = start
                    while top > 0 {
                        let above = lines[top - 1].trimmingCharacters(in: .whitespaces)
                        if above.hasPrefix("///") || above.hasPrefix("@") { top -= 1 } else { break }
                    }
                    stack.append((top, number, word))
                } else {
                    stack.append(nil)
                }
                first = false
            } else if let open = stack.popLast() {
                if let open {
                    let header = lines[declarationStart(for: open.open, in: lines) ?? open.open]
                    let label = String(header.trimmingCharacters(in: .whitespaces).prefix(90))
                    blocks.append(
                        Block(
                            start: open.start, open: open.open, end: number,
                            isType: typeKeywords.contains(open.keyword),
                            label: label, keyword: open.keyword))
                }
            }
        }
    }
    // a local `var` or `let` inside a function is not a unit worth listing or choosing
    let bodies = blocks.filter { !$0.isType }
    blocks.removeAll { block in
        (block.keyword == "var" || block.keyword == "let")
            && bodies.contains {
                $0.start <= block.start && block.end <= $0.end && ($0.start, $0.end) != (block.start, block.end)
            }
    }
    return blocks.sorted { $0.start != $1.start ? $0.start < $1.start : $0.end > $1.end }
}

/// The lines `h ± context`, kept inside the file.
func window(_ h: Int, _ lines: [String], _ context: Int, label: String) -> Unit {
    Unit(start: max(0, h - context), end: min(lines.count - 1, h + context), label: label, isWindow: true)
}

/// The unit for a hit on 0-based line `h` of a Swift file: the outermost member that holds it, else its type header, else a window.
func swiftUnit(_ h: Int, _ blocks: [Block], _ lines: [String], _ options: Options) -> Unit {
    let holding = blocks.filter { $0.start <= h && h <= $0.end }
    if let member = holding.first(where: { !$0.isType }) {
        return Unit(start: member.start, end: member.end, label: member.label)
    }
    if let type = holding.last(where: \.isType) {
        if h <= type.open { return Unit(start: type.start, end: type.end, label: type.label) }
        return window(h, lines, options.context, label: "in " + type.label)
    }
    return window(h, lines, options.context, label: "top level")
}

/// Markdown headings outside code fences: line, level and text.
func headings(_ lines: [String]) -> [(line: Int, level: Int, text: String)] {
    var out: [(line: Int, level: Int, text: String)] = []
    var fenced = false
    for (number, line) in lines.enumerated() {
        if line.hasPrefix("```") || line.hasPrefix("~~~") {
            fenced.toggle()
            continue
        }
        guard !fenced, line.hasPrefix("#") else { continue }
        let level = line.prefix(while: { $0 == "#" }).count
        guard level <= 6, line.dropFirst(level).first == " " else { continue }
        out.append((number, level, String(line.dropFirst(level + 1).prefix(90))))
    }
    return out
}

/// The unit for a hit in a markdown file: the section from its heading to the next heading.
func markdownUnit(_ h: Int, _ heads: [(line: Int, level: Int, text: String)], _ lines: [String]) -> Unit {
    guard let index = heads.lastIndex(where: { $0.line <= h }) else {
        return Unit(start: 0, end: (heads.first?.line ?? lines.count) - 1, label: "preamble")
    }
    let end = index + 1 < heads.count ? heads[index + 1].line - 1 : lines.count - 1
    return Unit(
        start: heads[index].line, end: end,
        label: String(repeating: "#", count: heads[index].level) + " " + heads[index].text)
}

/// Indentation-delimited `def` and `class` blocks in a Python file.
func pythonBlocks(_ lines: [String]) -> [Block] {
    var found: [Block] = []
    for (index, line) in lines.enumerated() {
        let range = NSRange(line.startIndex..., in: line)
        guard let regex = pythonDeclRegex, let match = regex.firstMatch(in: line, range: range),
            let indentRange = Range(match.range(at: 1), in: line),
            let kwRange = Range(match.range(at: 2), in: line)
        else { continue }
        let indent = line[indentRange].count
        let keyword = String(line[kwRange])
        var end = index
        var cursor = index + 1
        while cursor < lines.count {
            let trimmed = lines[cursor].trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                cursor += 1
                continue
            }
            let curIndent = lines[cursor].prefix(while: { $0 == " " || $0 == "\t" }).count
            if curIndent <= indent { break }
            end = cursor
            cursor += 1
        }
        let label = String(line.trimmingCharacters(in: .whitespaces).prefix(90))
        found.append(
            Block(start: index, open: index, end: end, isType: keyword == "class", label: label, keyword: keyword))
    }
    return found
}

/// The unit for a hit in a closure record: the top-level record from its first line to the `}` at column 0.
func closureUnit(_ h: Int, _ lines: [String]) -> Unit {
    var start = h
    while start > 0, lines[start].isEmpty || lines[start].first == " " || lines[start].first == "}" { start -= 1 }
    var end = start
    while end < lines.count - 1, lines[end].first != "}" || end < h { end += 1 }
    if end < h { end = h }
    return Unit(start: start, end: end, label: String(lines[start].prefix(90)))
}

// MARK: - Search
/// Units for the hits in one file, with hits in the same unit merged and overlapping windows joined.
func search(_ file: Source, path: String, matches: (String) -> Bool, options: Options) -> [Unit] {
    let lines = file.lines
    let hitLines = lines.indices.filter { matches(lines[$0]) }
    if hitLines.isEmpty { return [] }
    let ext = (path as NSString).pathExtension
    let blocks =
        braceLanguageExts.contains(ext)
        ? swiftBlocks(lines, cFamily: cFamilyExts.contains(ext)) : (ext == "py" ? pythonBlocks(lines) : [])
    let heads = ext == "md" ? headings(lines) : []
    var units: [Unit] = []
    for h in hitLines {
        var unit: Unit
        if braceLanguageExts.contains(ext) || ext == "py" {
            unit = swiftUnit(h, blocks, lines, options)
        } else if ext == "md" {
            unit = markdownUnit(h, heads, lines)
        } else if ext == "closure" {
            unit = closureUnit(h, lines)
        } else {
            unit = window(h, lines, options.context, label: "lines")
        }
        unit.hits = [h + 1]
        if let last = units.last, last.start == unit.start, last.end == unit.end {
            units[units.count - 1].hits.append(h + 1)
        } else if let last = units.last, last.isWindow, unit.isWindow, unit.start <= last.end + 1 {
            units[units.count - 1].end = max(last.end, unit.end)
            units[units.count - 1].hits.append(h + 1)
        } else {
            units.append(unit)
        }
    }
    return units
}

// MARK: - Output
/// The lines that print for a unit: all of them, or only the hit lines and their context when the unit is long.
func shownLines(_ unit: Unit, context: Int, unitMax: Int) -> [Int?] {
    let all = Array(unit.start...unit.end)
    if all.count <= unitMax { return all }
    var keep = Set<Int>()
    for hit in unit.hits {
        for n in (hit - 1 - context)...(hit - 1 + context) where n >= unit.start && n <= unit.end { keep.insert(n) }
    }
    var out: [Int?] = []
    var previous = unit.start - 1
    for n in keep.sorted() {
        if n != previous + 1 { out.append(nil) }
        out.append(n)
        previous = n
    }
    return out
}

// MARK: - Printing
/// One file's matches: its path, text and hash, and the units the hits fall in.
struct Found {
    let path: String
    let source: Source
    let units: [Unit]
}

/// Hit lines kept for one unit, and in all, in compact output; the rest become counts.
let compactPerUnit = 12
let compactTotal = 200

/// A line cut to a length that fits a result, with an ellipsis when it was cut.
func clip(_ line: String, _ limit: Int = 200) -> String {
    line.count <= limit ? line : String(line.prefix(limit)) + "…"
}

/// Prints one unit compactly: its hit lines only. When the first hit is the unit's own declaration line, the range
/// replaces that line's number (`A-B<TAB>text`); otherwise an `A-B  label` line comes first. A plain window has no
/// range worth printing, so its hit lines print alone. Returns the lines printed.
func printCompact(_ unit: Unit, of file: Found) -> Int {
    var count = 0
    var hits = unit.hits.prefix(compactPerUnit)
    if !unit.isWindow {
        let range = "\(unit.start + 1)-\(unit.end + 1)"
        let declaration = hits.first.map {
            file.source.lines[$0 - 1].trimmingCharacters(in: .whitespaces).hasPrefix(String(unit.label.prefix(56)))
        }
        if declaration == true, let first = hits.first {
            print("\(range)\t\(clip(file.source.lines[first - 1]))")
            hits = hits.dropFirst()
        } else {
            print("\(range)  \(unit.label.prefix(56))")
        }
        count += 1
    }
    for hit in hits {
        print("\(hit)\t\(clip(file.source.lines[hit - 1]))")
        count += 1
    }
    if unit.hits.count > compactPerUnit {
        print("   … \(unit.hits.count - compactPerUnit) more hits in this unit")
        count += 1
    }
    return count
}

/// Prints one unit with its body, or only its hit lines when it is long. Returns the lines printed.
func printFull(_ unit: Unit, of file: Found, options: Options) -> Int {
    let rows = shownLines(unit, context: options.context, unitMax: options.unitMax)
    print(
        "\(unit.start + 1)-\(unit.end + 1)  \(unit.label)  hits \(unit.hits.map(String.init).joined(separator: ","))")
    for row in rows {
        if let n = row { print("\(n + 1)\t\(file.source.lines[n])") } else { print("   …") }
    }
    return rows.count + 1
}

/// Prints the matches for every file; returns whether anything matched. Output is compact unless `--bodies` asks for
/// whole units. A file prints once as `== path #hash` with the first six digits of the hash `edit --hash` accepts.
func printSearch(_ files: [String], options: Options) -> Bool {
    let matches = makeMatcher(options)
    var found: [Found] = []
    for path in files {
        guard let source = load(path) else { continue }
        let units = search(source, path: path, matches: matches, options: options)
        if !units.isEmpty { found.append(Found(path: path, source: source, units: units)) }
    }
    if found.isEmpty { return false }
    if options.filesOnly {
        for file in found { print("\(file.path)  \(file.units.reduce(0) { $0 + $1.hits.count })") }
        return true
    }
    let style = options.style ?? .compact
    let limit = style == .compact ? compactTotal : options.maxLines
    var printed = 0
    var hidden = 0
    for file in found {
        print("== \(file.path) #\(file.source.hash.prefix(6))")
        for unit in file.units {
            if printed >= limit {
                print("\(unit.start + 1)-\(unit.end + 1)  \(unit.label.prefix(56))  (not shown)")
                hidden += 1
            } else {
                printed +=
                    style == .compact
                    ? printCompact(unit, of: file) : printFull(unit, of: file, options: options)
            }
        }
    }
    if hidden > 0 { print("\(hidden) units not shown: narrow the term or PATH") }
    return true
}

/// Prints each file's units with ranges: Swift declarations, markdown headings, closure fields.
func printOutline(_ files: [String], options: Options) -> Bool {
    let matches = makeMatcher(options)
    var any = false
    for path in files {
        guard let source = load(path) else { continue }
        let lines = source.lines
        var rows: [String] = []
        let ext = (path as NSString).pathExtension
        switch ext {
        case _ where braceLanguageExts.contains(ext) || ext == "py":
            let blocks = ext == "py" ? pythonBlocks(lines) : swiftBlocks(lines, cFamily: cFamilyExts.contains(ext))
            var open: [Int] = []
            for block in blocks {
                while let last = open.last, last < block.start { open.removeLast() }
                if matches(block.label) {
                    rows.append(
                        "\(String(repeating: "  ", count: open.count))\(block.start + 1)-\(block.end + 1)  \(block.label)"
                    )
                }
                open.append(block.end)
            }
        case "md":
            let heads = headings(lines)
            for (index, head) in heads.enumerated() {
                let end = heads[(index + 1)...].first(where: { $0.level <= head.level })?.line ?? lines.count
                let text = String(repeating: "#", count: head.level) + " " + head.text
                if matches(text) { rows.append("\(head.line + 1)-\(end)  \(text)") }
            }
        case "closure":
            for (number, line) in lines.enumerated() where line.first != nil && line.first != " " && line.first != "}" {
                var end = number
                while end < lines.count - 1, lines[end].first != "}" { end += 1 }
                if matches(line) { rows.append("\(number + 1)-\(end + 1)  \(line.prefix(90))") }
            }
        default:
            rows.append("(no outline for this file type: \(lines.count) lines; use seek TERM)")
        }
        if rows.isEmpty { continue }
        any = true
        print("== \(path)  hash \(source.hash)  (\(lines.count) lines)")
        for row in rows.prefix(400) { print(row) }
        if rows.count > 400 { print("… \(rows.count - 400) more (narrow with -e TERM)") }
    }
    return any
}

// MARK: - Main
let options = parseArguments()
let files = collectFiles(options.paths)
let found = options.outline ? printOutline(files, options: options) : printSearch(files, options: options)
exit(found ? 0 : 1)
