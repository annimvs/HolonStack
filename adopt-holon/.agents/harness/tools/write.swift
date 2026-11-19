// write.swift — deterministic writer, checker and linter for the .agents closure records. One JIT script.
//
//   write <kind> new [file|-]        file a draft (closure with `_` for ids), fill ids/index/defaults, validate, write
//   write <kind> check-draft [file|-]  validate a draft only (the first-write check)
//   write check [path…]              validate stored records, ids, refs, filenames, cycles (exit 1 on any problem)
//   write lint <file…>               syntax + canonical form of any .closure file, templates included
//   write get <id>                   print the file holding a record or nested record
//   write list [kind]                one line per record
//   write done <id> | reopen <id>    tick or untick a task (phase-nested or ad-hoc)
//   write answer <id> "<text>"       answer a question
//   write set <id|plan> <field> <value>  update a scalar, grok, text or enum field on a record or nested task
//   write link|unlink <id> <field> <ref> add or remove a ref in a list field (such as depends)
//   write move <id> before|after <id>    reorder a phase in PLAN.closure, a task in TODO.closure, or a nested task
//   write del <task-id>              remove a nested task inside an open phase
//   write next                       the first phase that is not done and whose depends are done
//   write status [--peek]            worker results not yet reported, as markdown (blocked, failed, done); empty when nothing is new
//   write render                     regenerate MEMORY.md and OPEN.md (human views)
//   write skeleton [file|-]          print a draft's skeleton and its hash
//   write measure <dir>              first-write pass rate and distinct skeletons over a folder of drafts
//
// Kinds are the templates in `.agents/harness/templates/*.closure`: plan, phase, task, memory, question (todo is the task index).
// Each template starts with `// store: <path>` (placeholders {id} {n} {name}). Grammar and placeholders: rules/NOTATION.md.
import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

// MARK: - model

// MARK: - Value
/// A parsed record value: a quoted string, a bare word, a list, a { } block, or a nested call.
indirect enum Value {
    case str(String)
    case atom(String)
    case list([Value])
    case block([Field])
    case form(Form)
}
// MARK: - Field
/// One key and value inside a { } block, with the line it was read from.
struct Field {
    var key: String
    var value: Value
    var line: Int
}
// MARK: - Form
/// A call such as head(args) with an optional { } body, with the line it was read from.
struct Form {
    var head: String
    var args: [Value]
    var body: [Field]?
    var line: Int
}
// MARK: - Fail
/// A parse error with the line, column and message to show the user.
struct Fail: Error {
    let line: Int
    let col: Int
    let msg: String
}
// MARK: - Err
/// A plain error that carries a message for the user.
struct Err: Error { let msg: String }

// MARK: - parser

// MARK: - Parser
/// A character reader that turns record text into Value and Form trees, tracking line and column.
struct Parser {
    let s: [Character]
    var i = 0
    var line = 1
    var col = 1
    init(_ text: String) { s = Array(text) }

    /// Returns the character at the current position plus an offset, or nil past the end of the text.
    func peek(_ o: Int = 0) -> Character? { i + o < s.count ? s[i + o] : nil }
    /// Moves the reader one character forward and updates the line and column.
    mutating func adv() {
        if s[i] == "\n" {
            line += 1
            col = 1
        } else {
            col += 1
        }
        i += 1
    }
    /// Builds a parse error at the current line and column with the given message.
    func err(_ m: String) -> Fail { Fail(line: line, col: col, msg: m) }

    /// Skips whitespace, commas and // line comments.
    mutating func skip() {
        while let c = peek() {
            if c.isWhitespace || c == "," {
                adv()
            } else if c == "/", peek(1) == "/" {
                while let d = peek(), d != "\n" { adv() }
            } else {
                break
            }
        }
    }
    /// Skips whitespace, then consumes the expected character or throws a parse error.
    mutating func expect(_ c: Character) throws {
        skip()
        guard let d = peek(), d == c else {
            throw err("expected '\(c)'" + (peek().map { ", found '\($0)'" } ?? ", found end of file"))
        }
        adv()
    }
    /// True for characters allowed in a bare word: letters, digits, and _ - . /.
    static func isWord(_ c: Character) -> Bool { c.isLetter || c.isNumber || "_-./".contains(c) }
    /// Reads a bare word and throws a parse error when there is none.
    mutating func word() throws -> String {
        skip()
        var w = ""
        while let c = peek(), Parser.isWord(c) {
            w.append(c)
            adv()
        }
        if w.isEmpty { throw err(peek().map { "unexpected '\($0)'" } ?? "unexpected end of file") }
        return w
    }
    /// Reads a quoted string, or a """ multi-line string, and returns its text with escapes applied.
    mutating func string() throws -> String {
        if peek() == "\"", peek(1) == "\"", peek(2) == "\"" { return try multiline() }
        try expect("\"")
        var r = ""
        while let c = peek(), c != "\"" {
            if c == "\n" { throw err("unterminated string (use \"\"\" for several lines)") }
            if c == "\\" {
                adv()
                guard let n = peek() else { break }
                switch n {
                case "n": r.append("\n")
                case "t": r.append("\t")
                default: r.append(n)
                }
            } else {
                r.append(c)
            }
            adv()
        }
        guard peek() == "\"" else { throw err("unterminated string") }
        adv()
        return r
    }
    /// Reads a """ string, drops the common indent and the blank first and last lines, and returns the text.
    mutating func multiline() throws -> String {
        adv()
        adv()
        adv()
        var raw = ""
        while true {
            guard let c = peek() else { throw err("unterminated \"\"\" string") }
            if c == "\"", peek(1) == "\"", peek(2) == "\"" {
                adv()
                adv()
                adv()
                break
            }
            raw.append(c)
            adv()
        }
        var lines = raw.components(separatedBy: "\n")
        if let f = lines.first, f.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeFirst() }
        if let l = lines.last, l.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
        let indents = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.map { line in
            line.prefix(while: { $0 == " " }).count
        }
        let m = indents.min() ?? 0
        return lines.map { $0.count >= m ? String($0.dropFirst(m)) : "" }.joined(separator: "\n")
    }

    /// Reads one value: a quoted string, a [ ] list, a { } block, a call, or a bare word.
    mutating func value() throws -> Value {
        skip()
        guard let c = peek() else { throw err("expected a value, found end of file") }
        switch c {
        case "\"": return .str(try string())
        case "[":
            adv()
            var items: [Value] = []
            while true {
                skip()
                guard let d = peek() else { throw err("unclosed '['") }
                if d == "]" {
                    adv()
                    break
                }
                items.append(try value())
            }
            return .list(items)
        case "{": return .block(try block())
        default:
            let save = (i, line, col)
            let startLine = line
            let w = try word()
            skip()
            if w == "many", peek() == "[" {
                let l = try value()
                return .form(Form(head: "many", args: [l], body: nil, line: startLine))
            }
            if peek() == "(" {
                (i, line, col) = save
                return .form(try form())
            }
            return .atom(w)
        }
    }
    /// Reads a { } block of key: value fields and returns them in the order written.
    mutating func block() throws -> [Field] {
        try expect("{")
        var fs: [Field] = []
        while true {
            skip()
            guard let c = peek() else { throw err("unclosed '{'") }
            if c == "}" {
                adv()
                return fs
            }
            let startLine = line
            let w = try word()
            skip()
            guard peek() == ":" else { throw err("'\(w)' must be followed by ':'") }
            adv()
            fs.append(Field(key: w, value: try value(), line: startLine))
        }
    }
    /// Reads a call head(args) with an optional { } body.
    mutating func form() throws -> Form {
        skip()
        let startLine = line
        let h = try word()
        try expect("(")
        var args: [Value] = []
        while true {
            skip()
            guard let c = peek() else { throw err("unclosed '('") }
            if c == ")" {
                adv()
                break
            }
            args.append(try value())
        }
        skip()
        var body: [Field]? = nil
        if peek() == "{" { body = try block() }
        return Form(head: h, args: args, body: body, line: startLine)
    }
}

/// Parses a whole record text into one top-level call, and throws when extra text follows it.
func parseRecord(_ text: String) throws -> Form {
    var p = Parser(text)
    let f = try p.form()
    p.skip()
    if p.i < p.s.count { throw p.err("unexpected text after the record's closing '}'") }
    return f
}

// MARK: - canonical emitter

/// Escapes backslash, quote, newline and tab so the text can sit inside a quoted string.
func esc(_ s: String) -> String {
    s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\t", with: "\\t")
}
/// True when a value fits on one line: an atom, or a string without line breaks.
func isScalar(_ v: Value) -> Bool {
    switch v {
    case .atom: return true
    case .str(let s): return !s.contains("\n") || s.contains("\"\"\"")
    default: return false
    }
}
/// Writes a value in canonical form at the given indent, using """ strings for text with line breaks.
func emit(_ v: Value, _ ind: Int) -> String {
    let pad = String(repeating: " ", count: ind)
    switch v {
    case .atom(let a): return a
    case .str(let s):
        if s.contains("\n"), !s.contains("\"\"\"") {
            let body = s.components(separatedBy: "\n").map { $0.isEmpty ? "" : pad + "  " + $0 }.joined(separator: "\n")
            return "\"\"\"\n" + body + "\n" + pad + "  \"\"\""
        }
        return "\"" + esc(s) + "\""
    case .list(let items):
        if items.isEmpty { return "[]" }
        if items.allSatisfy(isScalar) { return "[" + items.map { emit($0, ind) }.joined(separator: ", ") + "]" }
        return "[\n" + items.map { pad + "  " + emit($0, ind + 2) + "," }.joined(separator: "\n") + "\n" + pad + "]"
    case .block(let fs): return emitBlock(fs, ind)
    case .form(let f): return emitForm(f, ind)
    }
}
/// Writes a { } block in canonical form, one field per line, at the given indent.
func emitBlock(_ fs: [Field], _ ind: Int) -> String {
    if fs.isEmpty { return "{}" }
    let pad = String(repeating: " ", count: ind)
    return "{\n" + fs.map { pad + "  " + $0.key + ": " + emit($0.value, ind + 2) }.joined(separator: "\n") + "\n" + pad
        + "}"
}
/// Writes a call and its optional body in canonical form.
func emitForm(_ f: Form, _ ind: Int) -> String {
    var s = f.head + "(" + f.args.map { emit($0, ind) }.joined(separator: ", ") + ")"
    if let b = f.body { s += " " + emitBlock(b, ind) }
    return s
}
/// Writes a whole record in canonical form, ending with a newline.
func canonical(_ f: Form) -> String { emitForm(f, 0) + "\n" }

// MARK: - helpers

let hexDigits = Set("0123456789abcdef")
/// True when a string is an 8-character lowercase hex id.
func isID(_ s: String) -> Bool { s.count == 8 && s.allSatisfy { hexDigits.contains($0) } }
/// True when a string matches a regular expression pattern.
func matches(_ s: String, _ pattern: String) -> Bool { s.range(of: pattern, options: .regularExpression) != nil }
/// Returns the text of an atom value, or nil for any other value.
func atomOf(_ v: Value?) -> String? {
    if case .atom(let a)? = v { return a }
    return nil
}
/// Returns the text of a string value, or nil for any other value.
func strOf(_ v: Value?) -> String? {
    if case .str(let a)? = v { return a }
    return nil
}
/// Returns the value stored under a key in a form's body, or nil when the key is missing.
func field(_ f: Form, _ key: String) -> Value? { f.body?.first(where: { $0.key == key })?.value }
/// Returns the first argument of a form as text, which is the id for a record.
func idOf(_ f: Form) -> String? { atomOf(f.args.first) }
/// Trims each line, drops the empty ones, and joins the rest with single spaces.
func joinLines(_ s: String) -> String {
    s.split(whereSeparator: { $0 == "\n" }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        .joined(separator: " ")
}

/// Makes a lowercase, dash-joined file name slug from the first 8 ASCII words of a text.
func slug(_ t: String) -> String {
    var words: [String] = []
    var cur = ""
    for ch in t.lowercased() {
        if ch.isASCII && (ch.isLetter || ch.isNumber) {
            cur.append(ch)
        } else if !cur.isEmpty {
            words.append(cur)
            cur = ""
        }
    }
    if !cur.isEmpty { words.append(cur) }
    return words.prefix(8).joined(separator: "-")
}
/// Calls a function on every form inside a value, including the value itself when it is a form.
func walk(_ v: Value, _ fn: (Form) -> Void) {
    switch v {
    case .form(let f):
        fn(f)
        f.args.forEach { walk($0, fn) }
        f.body?.forEach { walk($0.value, fn) }
    case .list(let items): items.forEach { walk($0, fn) }
    case .block(let fs): fs.forEach { walk($0.value, fn) }
    default: break
    }
}

// MARK: - store

// MARK: - Template
/// One kind's template: its kind name, the parsed template form, and the store path pattern.
struct Template {
    let kind: String
    let form: Form
    let pattern: String
}

// MARK: - Store
/// The records folder and the loaded templates, with helpers to find, load and name record files.
final class Store {
    let root: URL
    var templates: [String: Template] = [:]
    let fm = FileManager.default

    init() throws {
        let env = ProcessInfo.processInfo.environment
        var r: URL? = nil
        if let p = env["CLAUDE_PROJECT_DIR"] {
            let a = URL(fileURLWithPath: p).appendingPathComponent(".agents")
            if fm.fileExists(atPath: a.appendingPathComponent("harness/templates").path) { r = a }
        }
        var c = URL(fileURLWithPath: fm.currentDirectoryPath)
        while r == nil, c.path != "/" {
            let a = c.appendingPathComponent(".agents")
            if fm.fileExists(atPath: a.appendingPathComponent("harness/templates").path) { r = a }
            c.deleteLastPathComponent()
        }
        guard let found = r else { throw Err(msg: "no .agents/harness/templates found") }
        root = found
        // the records folder may already exist; creating it again is harmless, so a failure is ignored
        try? fm.createDirectory(at: root.appendingPathComponent("records"), withIntermediateDirectories: true)
        let dir = root.appendingPathComponent("harness/templates")
        // a missing templates folder just means no templates; the empty list is the right answer
        for name in ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).sorted() where name.hasSuffix(".closure") {
            let text = try String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)
            let pattern =
                text.components(separatedBy: "\n").first(where: { $0.hasPrefix("// store:") })
                .map { String($0.dropFirst("// store:".count)).trimmingCharacters(in: .whitespaces) } ?? ""
            do {
                let f = try parseRecord(text)
                if pattern.isEmpty { throw Err(msg: "\(name): missing '// store: <path>' line") }
                templates[f.head] = Template(kind: f.head, form: f, pattern: pattern)
            } catch let x as Fail { throw Err(msg: "templates/\(name):\(x.line):\(x.col): \(x.msg)") }
        }
    }

    /// Every store, view, draft, the id ledger and the lock live under `.agents/records/`; template `// store:` paths are relative to it.
    func url(_ rel: String) -> URL { root.appendingPathComponent("records").appendingPathComponent(rel) }
    /// Files of the harness itself, next to the templates (reasons.closure): `.agents/harness/`.
    func top(_ rel: String) -> URL { root.appendingPathComponent("harness").appendingPathComponent(rel) }
    /// True when a template's path has no {id}, {n} or {name} part, so one file holds the record.
    func isSingleton(_ t: Template) -> Bool { !t.pattern.contains("{") }
    /// Returns the folder part of a template's store path, or an empty string when it has none.
    func folder(_ t: Template) -> String {
        t.pattern.contains("/") ? String(t.pattern.split(separator: "/").first!) : ""
    }

    /// Lists the record files of a kind, or the single file for a singleton kind.
    func files(_ kind: String) -> [URL] {
        guard let t = templates[kind] else { return [] }
        if isSingleton(t) {
            let u = url(t.pattern)
            return fm.fileExists(atPath: u.path) ? [u] : []
        }
        let dir = url(folder(t))
        // a folder that cannot be read has no records yet, so an empty list is the right answer
        return ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.hasSuffix(".closure") }.sorted().map
        { dir.appendingPathComponent($0) }
    }
    /// Lists every record file of every kind as (kind, file) pairs, sorted by kind.
    func allFiles() -> [(String, URL)] { templates.keys.sorted().flatMap { k in files(k).map { (k, $0) } } }

    /// Reads and parses one record file into a Form.
    func load(_ u: URL) throws -> Form { try parseRecord(String(contentsOf: u, encoding: .utf8)) }

    /// Reads the .ids ledger and returns its ids, one per line.
    func ledger() -> [String] {
        // a missing ledger just means no ids have been minted yet
        ((try? String(contentsOf: url(".ids"), encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
    }
    /// Maps each kind to the set of ids its files currently use.
    func known() -> [String: Set<String>] {
        var out: [String: Set<String>] = [:]
        // a file that does not load is skipped here; the full check reports it
        for (k, u) in allFiles() { if let f = try? load(u), let id = idOf(f) { out[k, default: []].insert(id) } }
        return out
    }
    /// Collects every id in the ledger and in every stored record.
    func allIDs() -> Set<String> {
        var s = Set(ledger())
        for (_, u) in allFiles() {
            // a file that does not load adds no ids here; the full check reports it
            if let f = try? load(u) { walk(.form(f)) { if let id = idOf($0), isID(id) { s.insert(id) } } }
        }
        return s
    }
    /// Returns the highest number used by a kind's records, or 0 when there are none.
    func maxIndex(_ kind: String) -> Int {
        // a record that does not load cannot raise the maximum; the full check reports it
        files(kind).compactMap { try? load($0) }.compactMap { Int(atomOf(field($0, "n")) ?? "") }.max() ?? 0
    }
    /// Works out the file name prefix and suffix a record of this kind should have, and whether the name has a slug.
    func expectedName(_ t: Template, _ f: Form) -> (prefix: String, suffix: String, slugged: Bool) {
        var p = t.pattern.components(separatedBy: "/").last ?? t.pattern
        let n = atomOf(field(f, "n")) ?? ""
        p = p.replacingOccurrences(of: "{id}", with: idOf(f) ?? "").replacingOccurrences(
            of: "{n}", with: String(repeating: "0", count: max(0, 2 - n.count)) + n)
        let parts = p.components(separatedBy: "{name}")
        return (parts[0], parts.count > 1 ? parts[1] : "", parts.count > 1)
    }
    /// Returns the store-relative path a record should be written to, from its template and its name.
    func path(_ t: Template, _ f: Form) throws -> String {
        let (pre, suf, slugged) = expectedName(t, f)
        var name = pre
        if slugged {
            let s = slug(strOf(field(f, "name")) ?? "")
            if s.isEmpty { throw Err(msg: "name has no ASCII letters or digits to make a file name from") }
            name += s + suf
        }
        let dir = folder(t)
        return dir.isEmpty ? name : dir + "/" + name
    }
}

// MARK: - checker (template walk)

// MARK: - Mode
/// Whether the checker is validating a draft (ids and numbers still blank) or a stored record.
enum Mode { case draft, stored }

// MARK: - Checker
/// Walks a record against its template and collects every mismatch as a message.
struct Checker {
    let templates: [String: Template]
    let known: [String: Set<String>]
    let mode: Mode
    var errs: [String] = []

    /// Records one problem with its line and path.
    mutating func err(_ line: Int, _ path: String, _ m: String) { errs.append("line \(line): \(path): \(m)") }

    /// True when a template field may be left out: derived and opt always, and bool, many and index in drafts.
    func isOptional(_ t: Value) -> Bool {
        guard case .form(let f) = t else { return false }
        switch f.head {
        case "derived", "opt": return true
        case "bool", "many", "index": return mode == .draft
        default: return false
        }
    }

    /// Checks one value against its template node and records any mismatch.
    mutating func value(_ v: Value, _ t: Value, _ path: String, _ line: Int) {
        switch t {
        case .form(let tf): placeholder(v, tf, path, line)
        case .atom(let a): if atomOf(v) != a { err(line, path, "must be '\(a)'") }
        case .str(let s): if strOf(v) != s { err(line, path, "must be \"\(s)\"") }
        case .block(let tfs):
            guard case .block(let rfs) = v else {
                err(line, path, "expected a { … } block")
                return
            }
            fields(rfs, tfs, path, line)
        case .list: err(line, path, "template error: bare list; use many [ … ]")
        }
    }

    static let placeholderHeads: Set<String> = [
        "grok", "text", "id", "index", "duration", "bool", "enum", "ref", "opt", "many", "use", "derived", "score",
        "detect",
    ]

    /// Checks a value against a template placeholder such as grok, id, index, enum or ref.
    // lint-ignore: func-length: kept whole so its steps read in order; split it when it grows
    mutating func placeholder(_ v: Value, _ tf: Form, _ path: String, _ line: Int) {
        // a template's own placeholder copied into a draft: say so plainly instead of a generic type error
        if Checker.placeholderHeads.contains(tf.head), case .form(let rf) = v,
            Checker.placeholderHeads.contains(rf.head)
        {
            err(
                line, path,
                "\(rf.head)(…) is a template placeholder, not a value; write the value itself (for a ref, the id of an existing record, or [] if there is none)"
            )
            return
        }
        switch tf.head {
        case "grok": grok(v, tf, path, line)
        case "text":
            guard let s = strOf(v), !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                err(line, path, "expected a non-empty string")
                return
            }
        case "id":
            guard let a = atomOf(v) else {
                err(line, path, "expected an id")
                return
            }
            if mode == .draft {
                if a != "_", !(path.hasPrefix("plan.phases[") && path.hasSuffix("(arg)") && !isID(a)) {
                    err(line, path, "write _ here; the tool generates ids")
                }
            } else if !isID(a) {
                err(line, path, "id must be 8 lowercase hex characters")
            }
        case "index":
            guard let a = atomOf(v) else {
                err(line, path, "expected a number")
                return
            }
            if mode == .draft {
                if a != "_" { err(line, path, "write _ here or leave it out; the tool assigns the number") }
            } else if Int(a).map({ $0 > 0 }) != true {
                err(line, path, "must be a positive integer")
            }
        case "duration":
            guard let a = atomOf(v), matches(a, "^[0-9]+(\\.[0-9]+)?[mhd]$") else {
                err(line, path, "must look like 30m, 2h or 1.5d")
                return
            }
        case "bool":
            guard let a = atomOf(v), a == "true" || a == "false" else {
                err(line, path, "must be true or false")
                return
            }
        case "detect":
            guard let a = atomOf(v), a == "true" || a == "false" else {
                err(line, path, "must be true or false")
                return
            }
        case "score":
            scoreCheck(v, tf, path, line)
        case "enum":
            let allowed = tf.args.compactMap { atomOf($0) }
            guard let a = atomOf(v), allowed.contains(a) else {
                err(line, path, "must be one of: \(allowed.joined(separator: " | "))")
                return
            }
        case "ref":
            guard let a = atomOf(v), let kind = atomOf(tf.args.first) else {
                err(line, path, "expected an id")
                return
            }
            if known[kind]?.contains(a) != true { err(line, path, "'\(a)' is not a \(kind) id") }
        case "opt":
            if let inner = tf.args.first { value(v, inner, path, line) }
        case "derived": err(line, path, "is derived; don't write it")
        case "many":
            guard case .list(let items) = v else {
                err(line, path, "expected a [ … ] list")
                return
            }
            guard case .list(let titems)? = tf.args.first, let it = titems.first else {
                err(line, path, "template error: many needs an item")
                return
            }
            for (i, item) in items.enumerated() { value(item, it, "\(path)[\(i)]", line) }
        case "use":
            guard let kind = atomOf(tf.args.first), let t = templates[kind] else {
                err(line, path, "template error: unknown kind in use(…)")
                return
            }
            if mode == .draft {
                value(v, .form(t.form), path, line)
            } else {
                placeholder(v, Form(head: "ref", args: tf.args, body: nil, line: tf.line), path, line)
            }
        default: formMatch(v, tf, path, line)
        }
    }

    /// Checks that a score is a number inside the min..max range the template gives.
    mutating func scoreCheck(_ v: Value, _ tf: Form, _ path: String, _ line: Int) {
        guard let a = atomOf(v) else {
            err(line, path, "expected a numeric score")
            return
        }
        guard let num = Double(a) else {
            err(line, path, "'\(a)' is not a valid number")
            return
        }
        if let boundArg = tf.args.first {
            var minVal: Double? = nil
            var maxVal: Double? = nil
            let spec: String
            if let str = strOf(boundArg) {
                spec = str
            } else if let atom = atomOf(boundArg) {
                spec = atom
            } else {
                spec = ""
            }

            let parts = spec.components(separatedBy: "..")
            if parts.count == 2 {
                minVal = Double(parts[0].trimmingCharacters(in: .whitespaces))
                maxVal = Double(parts[1].trimmingCharacters(in: .whitespaces))
            }
            if let mn = minVal, num < mn {
                err(line, path, "score \(a) is below minimum \(parts[0].trimmingCharacters(in: .whitespaces))")
            }
            if let mx = maxVal, num > mx {
                err(line, path, "score \(a) is above maximum \(parts[1].trimmingCharacters(in: .whitespaces))")
            }
        }
    }

    /// Checks a call against a template call: same head, same argument count, and the same body.
    mutating func formMatch(_ v: Value, _ tf: Form, _ path: String, _ line: Int) {
        guard case .form(let rf) = v, rf.head == tf.head else {
            err(line, path, "expected \(tf.head)(…)")
            return
        }
        let here = path.isEmpty ? tf.head : path
        if rf.args.count != tf.args.count {
            err(rf.line, here, "\(tf.head)(…) takes \(tf.args.count) argument(s)")
        } else {
            for (a, ta) in zip(rf.args, tf.args) { value(a, ta, here + "(arg)", rf.line) }
        }
        switch (tf.body, rf.body) {
        case (nil, nil): break
        case (let tb?, let rb?): fields(rb, tb, here, rf.line)
        case (nil, _?): err(rf.line, here, "takes no { … } body")
        case (_?, nil): err(rf.line, here, "needs a { … } body")
        }
    }

    /// Checks a record's fields against the template's fields: required, derived, order (stored only) and duplicates.
    mutating func fields(_ rec: [Field], _ tmpl: [Field], _ path: String, _ line: Int) {
        var last = -1
        for tf in tmpl {
            guard let i = rec.firstIndex(where: { $0.key == tf.key }) else {
                if !isOptional(tf.value) { err(line, path, "missing field '\(tf.key)'") }
                continue
            }
            if case .form(let f) = tf.value, f.head == "derived" {
                err(rec[i].line, path, "'\(tf.key)' is derived; don't write it")
                continue
            }
            // a draft may list fields in any order; the writer stores the template's order
            if mode == .stored, i < last {
                err(
                    rec[i].line, path,
                    "'\(tf.key)' is out of order; the order is: \(tmpl.map { $0.key }.joined(separator: ", "))")
            }
            last = max(last, i)
            value(rec[i].value, tf.value, path + "." + tf.key, rec[i].line)
        }
        var seen = Set<String>()
        for f in rec {
            if !tmpl.contains(where: { $0.key == f.key }) { err(f.line, path, "unknown field '\(f.key)'") }
            if !seen.insert(f.key).inserted { err(f.line, path, "duplicate field '\(f.key)'") }
        }
    }

    /// Checks a grok text: a non-empty, single line with no stray outer spaces. Word limits are guidance only.
    mutating func grok(_ v: Value, _ tf: Form, _ path: String, _ line: Int) {
        guard case .str(let raw) = v else {
            err(line, path, "expected a quoted string")
            return
        }
        // in a draft, stray line breaks are joined with a space (the writer stores the joined line)
        let full = mode == .draft ? joinLines(raw) : raw
        // limits apply to the prose: each `code span` counts as one word, and its contents are not checked
        let s = full.replacingOccurrences(of: "`[^`]*`", with: "C", options: .regularExpression)
        let spec = strOf(tf.args.first) ?? ""
        if s.isEmpty {
            err(line, path, "is empty")
            return
        }
        if s.contains("\n") {
            err(line, path, "must be one line: no line breaks inside the quotes, and no \"\"\" string")
            return
        }
        if s != s.trimmingCharacters(in: .whitespaces) { err(line, path, "has leading or trailing space") }
        // the spec ("<= 8 words, no dashes", …) is guidance for the writer of the prose, not a limit: only the
        // file name slug is capped (`slug`, 8 words), so a long or dashed grok line is stored as written
        _ = spec
    }
    /// Reads a "<= N unit" upper limit from a spec string, or nil when there is none.
    func limit(_ spec: String, _ unit: String) -> Int? {
        guard let r = spec.range(of: "<=\\s*[0-9]+\\s*\(unit)", options: .regularExpression) else { return nil }
        return Int(spec[r].filter { $0.isNumber })
    }
    /// Reads a ">= N unit" lower limit from a spec string, or nil when there is none.
    func minimum(_ spec: String, _ unit: String) -> Int? {
        guard let r = spec.range(of: ">=\\s*[0-9]+\\s*\(unit)", options: .regularExpression) else { return nil }
        return Int(spec[r].filter { $0.isNumber })
    }
}

/// Walks a depends map (node -> targets) and returns one error line per dependency cycle.
func edgeCycles(_ edges: [String: [String]]) -> [String] {
    var errs: [String] = []
    var state: [String: Int] = [:]
    /// Walks the depends edges from a node and records a cycle when the walk reaches the current stack again.
    func visit(_ n: String, _ stack: [String]) {
        if state[n] == 2 { return }
        if state[n] == 1 {
            errs.append("depends cycle: \((stack + [n]).joined(separator: " -> "))")
            return
        }
        state[n] = 1
        for m in edges[n] ?? [] { visit(m, stack + [n]) }
        state[n] = 2
    }
    for n in edges.keys.sorted() { visit(n, []) }
    return errs
}

/// Parses a draft and checks it against its kind's template; returns the parsed form (nil on a parse error) and any problems.
func checkDraft(_ text: String, _ store: Store, kind: String?) -> (Form?, [String]) {
    let f: Form
    do { f = try parseRecord(text) } catch let x as Fail { return (nil, ["line \(x.line):\(x.col): \(x.msg)"]) } catch {
        return (nil, ["\(error)"])
    }
    guard let t = store.templates[f.head] else {
        return (
            nil,
            [
                "line \(f.line): unknown kind '\(f.head)' (known: \(store.templates.keys.sorted().joined(separator: ", ")))"
            ]
        )
    }
    if let k = kind, k != f.head { return (nil, ["line \(f.line): this is a \(f.head), not a \(k)"]) }
    var known = store.known()
    var preErrs: [String] = []
    var draftEdges: [String: [String]] = [:]
    if f.head == "plan", case .list(let items)? = field(f, "phases") {
        var labels = Set<String>()
        for (idx, item) in items.enumerated() {
            guard case .form(let pf) = item, pf.head == "phase" else { continue }
            let label = idOf(pf) ?? "_"
            if label != "_" {
                if isID(label) {
                    preErrs.append(
                        "line \(pf.line): plan.phases[\(idx)](arg): draft phase label '\(label)' looks like a hex id; use a word or _"
                    )
                } else if !labels.insert(label).inserted {
                    preErrs.append("line \(pf.line): plan.phases[\(idx)](arg): duplicate draft phase label '\(label)'")
                } else {
                    known["phase", default: []].insert(label)
                }
            }
            let key = label == "_" ? "@\(idx)" : label
            if case .list(let dl)? = field(pf, "depends") { draftEdges[key] = dl.compactMap(atomOf) }
        }
    }
    var c = Checker(templates: store.templates, known: known, mode: .draft)
    c.value(.form(f), .form(t.form), "", f.line)
    return (f, preErrs + c.errs + edgeCycles(draftEdges))
}

// MARK: - filler (draft -> stored)

// MARK: - Filler
/// Turns a checked draft into a stored record by minting ids and numbers and by filing nested records.
final class Filler {
    let store: Store
    var used: Set<String>
    var counters: [String: Int] = [:]
    var pending: [(kind: String, form: Form)] = []
    var minted: [String] = []
    var labels: [String: String] = [:]
    init(_ s: Store) {
        store = s
        used = s.allIDs()
    }

    /// Mints a random 8-character hex id that is not used yet, and records it as used.
    func newID() -> String {
        var id = ""
        repeat { id = String(format: "%08x", UInt32.random(in: 0...UInt32.max)) } while used.contains(id)
        used.insert(id)
        minted.append(id)
        return id
    }
    /// Returns the next number for a kind, counting from the stored records and the picks made so far.
    func nextIndex(_ kind: String) -> Int {
        let n = (counters[kind] ?? store.maxIndex(kind)) + 1
        counters[kind] = n
        return n
    }

    /// Fills a template call: mints ids for id placeholders, then fills the body fields.
    func fillForm(_ rec: Form, _ tf: Form, _ kind: String) -> Form {
        var args: [Value] = []
        for (i, ta) in tf.args.enumerated() {
            if case .form(let p) = ta, p.head == "id" {
                let id = newID()
                if i < rec.args.count, let label = atomOf(rec.args[i]), label != "_", !isID(label) {
                    labels[label] = id
                }
                args.append(.atom(id))
            } else {
                args.append(ta)
            }
        }
        var out = Form(head: tf.head, args: args, body: nil, line: 0)
        if let tb = tf.body { out.body = fillFields(rec.body ?? [], tb, kind) }
        return out
    }
    /// Replaces any draft phase labels in `depends` lists of pending records with their minted hex ids.
    func resolvePendingLabels() {
        guard !labels.isEmpty else { return }
        for i in pending.indices {
            guard var body = pending[i].form.body,
                let di = body.firstIndex(where: { $0.key == "depends" }),
                case .list(let items) = body[di].value
            else { continue }
            body[di].value = .list(
                items.map { v in
                    if let a = atomOf(v), let mapped = labels[a] { return .atom(mapped) }
                    return v
                })
            pending[i].form.body = body
        }
    }
    /// Fills each template field from the draft: joins grok text, keeps values, numbers indexes, and fills nested lists.
    func fillFields(_ rec: [Field], _ tmpl: [Field], _ kind: String) -> [Field] {
        var out: [Field] = []
        for tf in tmpl {
            let rv = rec.first(where: { $0.key == tf.key })?.value
            guard case .form(let p) = tf.value else {
                if let rv = rv { out.append(Field(key: tf.key, value: rv, line: 0)) }
                continue
            }
            switch p.head {
            case "derived": continue
            case "grok":
                if let s = strOf(rv) {
                    out.append(Field(key: tf.key, value: .str(joinLines(s)), line: 0))
                } else if let rv = rv {
                    out.append(Field(key: tf.key, value: rv, line: 0))
                }
            case "opt":
                if case .form(let inner)? = p.args.first, inner.head == "many" {
                    // an optional list is filled item by item like a required one, and left out when the draft has none
                    if case .list(let ri)? = rv, case .list(let ti)? = inner.args.first, let it = ti.first {
                        out.append(Field(key: tf.key, value: .list(ri.map { fillItem($0, it) }), line: 0))
                    }
                } else if case .form(let inner)? = p.args.first, inner.head == "grok", let s = strOf(rv) {
                    out.append(Field(key: tf.key, value: .str(joinLines(s)), line: 0))
                } else if let rv = rv {
                    out.append(Field(key: tf.key, value: rv, line: 0))
                }
            case "index":
                if rv == nil || atomOf(rv) == "_" {
                    out.append(Field(key: tf.key, value: .atom(String(nextIndex(kind))), line: 0))
                } else if let rv = rv {
                    out.append(Field(key: tf.key, value: rv, line: 0))
                }
            case "bool": out.append(Field(key: tf.key, value: rv ?? p.args.first ?? .atom("false"), line: 0))
            case "many":
                var items: [Value] = []
                if case .list(let ri)? = rv, case .list(let ti)? = p.args.first, let it = ti.first {
                    for item in ri { items.append(fillItem(item, it)) }
                }
                out.append(Field(key: tf.key, value: .list(items), line: 0))
            default: if let rv = rv { out.append(Field(key: tf.key, value: rv, line: 0)) }
            }
        }
        return out
    }
    /// Fills one list item; a use(...) item is stored as its own record and replaced by that record's id.
    func fillItem(_ item: Value, _ it: Value) -> Value {
        guard case .form(let tf) = it else { return item }
        if tf.head == "use", let k = atomOf(tf.args.first), let t = store.templates[k], case .form(let rf) = item {
            let stored = fillForm(rf, t.form, k)
            pending.append((k, stored))
            return .atom(idOf(stored) ?? "")
        }
        if ["ref", "grok", "text", "enum", "duration", "score", "detect"].contains(tf.head) { return item }
        if case .form(let rf) = item { return .form(fillForm(rf, tf, tf.head)) }
        return item
    }
}

// MARK: - lock, ledger, output

/// Runs a body while holding the .write.lock file, waiting up to about 10 seconds for it.
func withLock<T>(_ store: Store, _ body: () throws -> T) throws -> T {
    let fd = open(store.url(".write.lock").path, O_CREAT | O_RDWR, 0o644)
    guard fd >= 0 else { throw Err(msg: "cannot open .write.lock") }
    defer { close(fd) }
    var waited = 0
    while flock(fd, LOCK_EX | LOCK_NB) != 0 {
        waited += 1
        if waited > 100 { throw Err(msg: "timed out waiting for .write.lock") }
        usleep(100_000)
    }
    defer { flock(fd, LOCK_UN) }
    return try body()
}
/// Creates the parent folder when needed, then writes the text to the file atomically.
func writeFile(_ u: URL, _ text: String) throws {
    try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
    try text.write(to: u, atomically: true, encoding: .utf8)
}
/// Prints a one-line JSON result with a status, a message and any extra fields.
func envelope(_ status: String, _ message: String, _ extra: [String: Any] = [:]) {
    var d = extra
    d["status"] = status
    d["message"] = message
    if let data = try? JSONSerialization.data(withJSONObject: d, options: [.sortedKeys]),
        let s = String(data: data, encoding: .utf8)
    {
        print(s)
    }
}
/// Reads text from the file at the given path, or from standard input when the path is nil or "-".
func readInput(_ arg: String?) throws -> String {
    if let a = arg, a != "-" { return try String(contentsOfFile: a, encoding: .utf8) }
    return String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
}

// MARK: - full store check

/// Checks one stored record: its kind, its template, its fields, and that its file name matches the template.
func checkStored(_ u: URL, _ kind: String, _ store: Store, _ known: [String: Set<String>]) -> [String] {
    var errs: [String] = []
    let rel = u.path.replacingOccurrences(of: store.root.path + "/", with: ".agents/")
    /// Adds one error line for this file, prefixed with its relative path.
    func e(_ m: String) { errs.append("\(rel):\(m)") }
    let f: Form
    do { f = try store.load(u) } catch let x as Fail { return ["\(rel):\(x.line):\(x.col): \(x.msg)"] } catch {
        return ["\(rel): \(error)"]
    }
    guard let t = store.templates[f.head] else { return ["\(rel):\(f.line): unknown kind '\(f.head)'"] }
    if f.head != kind { e("\(f.line): is a \(f.head) but lives in the \(kind) store") }
    var c = Checker(templates: store.templates, known: known, mode: .stored)
    c.value(.form(f), .form(t.form), "", f.line)
    errs += c.errs.map { "\(rel):\($0)" }
    if !store.isSingleton(t) {
        let (pre, suf, slugged) = store.expectedName(t, f)
        let name = u.lastPathComponent
        if !name.hasPrefix(pre) || !name.hasSuffix(suf) {
            e("1: file name must be '\(pre)\(slugged ? "<slug>" : "")\(suf)'")
        } else if slugged {
            let mid = String(name.dropFirst(pre.count).dropLast(suf.count))
            if !matches(mid, "^[a-z0-9]+(-[a-z0-9]+){0,7}$") {
                e("1: file name description '\(mid)' must be 1 to 8 lowercase words joined by '-'")
            }
        }
    }
    return errs
}

/// Finds dependency cycles among the records of a kind by walking their depends edges, and describes each cycle.
func cycleErrors(_ store: Store, _ kind: String) -> [String] {
    var edges: [String: [String]] = [:]
    for u in store.files(kind) {
        guard let f = try? store.load(u), let id = idOf(f), case .list(let l)? = field(f, "depends") else { continue }
        edges[id] = l.compactMap(atomOf)
    }
    return edgeCycles(edges)
}

/// Checks the stored records (all of them, or only the listed files) and, for a full check, ids, indexes and views.
/// Returns the errors, the warnings, and how many records were checked.
// lint-ignore: func-length: kept whole so its steps read in order; split it when it grows
func storeProblems(_ store: Store, only: [URL]?) -> (errs: [String], warns: [String], count: Int) {
    var errs: [String] = []
    var warns: [String] = []
    let known = store.known()
    let all = store.allFiles()
    let targets =
        only.map { o in
            all.filter { a in o.contains(where: { $0.standardizedFileURL.path == a.1.standardizedFileURL.path }) }
        } ?? all
    for (kind, u) in targets { errs += checkStored(u, kind, store, known) }
    if let o = only, targets.count != o.count {
        let listed = Set(targets.map { $0.1.standardizedFileURL.path })
        for u in o where !listed.contains(u.standardizedFileURL.path) {
            errs.append("\(u.path): not a record in any store")
        }
    }
    if only == nil {
        var owner: [String: [String]] = [:]
        for (_, u) in all {
            if let f = try? store.load(u) {
                walk(.form(f)) {
                    if let id = idOf($0), isID($0.args.first.flatMap(atomOf) ?? "") {
                        owner[id, default: []].append(u.lastPathComponent)
                    }
                }
            }
        }
        let led = Set(store.ledger())
        for (id, fs) in owner.sorted(by: { $0.key < $1.key }) {
            if fs.count > 1 { errs.append("id \(id) is used \(fs.count) times (\(fs.joined(separator: ", ")))") }
            if !led.contains(id) { errs.append("id \(id) is not in the .ids ledger") }
        }
        errs += cycleErrors(store, "phase") + cycleErrors(store, "task")
        var ns: [Int: String] = [:]
        for u in store.files("phase") {
            if let f = try? store.load(u), let n = Int(atomOf(field(f, "n")) ?? "") {
                if let o = ns[n] { errs.append("phase number \(n) is used by \(o) and \(u.lastPathComponent)") }
                ns[n] = u.lastPathComponent
            }
        }
        // indexes list exactly the records in their folders
        func index(_ file: String, _ fieldName: String, _ kind: String) {
            let have = Set(known[kind] ?? [])
            guard let u = store.templates[file == "PLAN.closure" ? "plan" : "todo"].map({ _ in store.url(file) }),
                let f = try? store.load(u), case .list(let l)? = field(f, fieldName)
            else {
                if !have.isEmpty { errs.append("\(file) is missing but \(kind) records exist") }
                return
            }
            let listed = l.compactMap(atomOf)
            for id in have where !listed.contains(id) { errs.append("\(kind) \(id) is not listed in \(file)") }
            for id in listed where !have.contains(id) { errs.append("\(file) lists \(id), which is not a \(kind)") }
        }
        index("PLAN.closure", "phases", "phase")
        index("TODO.closure", "tasks", "task")
        if let m = try? String(contentsOf: store.url("MEMORY.md"), encoding: .utf8), m != renderMemory(store) {
            warns.append("MEMORY.md is stale (run write render)")
        } else if !store.files("memory").isEmpty, !FileManager.default.fileExists(atPath: store.url("MEMORY.md").path) {
            warns.append("MEMORY.md is missing (run write render)")
        }
        if let o = try? String(contentsOf: store.url("OPEN.md"), encoding: .utf8), o != renderOpen(store) {
            warns.append("OPEN.md is stale (run write render)")
        }
        if store.templates["issue"] != nil, let b = try? String(contentsOf: store.url("BUGS.md"), encoding: .utf8),
            b != renderBugs(store)
        {
            warns.append("BUGS.md is stale (run write render)")
        }
        if store.templates["proposal"] != nil,
            let p = try? String(contentsOf: store.url("PROPOSALS.md"), encoding: .utf8), p != renderProposals(store)
        {
            warns.append("PROPOSALS.md is stale (run write render)")
        }
        if let want = renderPlan(store), (try? String(contentsOf: store.url("PLAN.md"), encoding: .utf8)) != want {
            warns.append("PLAN.md is stale or missing (run write render)")
        }
    }
    return (errs, warns, targets.count)
}

// MARK: - human views

/// Parses each file and sorts the results by their position in the ledger, so records keep their filing order.
func orderByLedger(_ store: Store, _ files: [URL]) -> [(URL, Form)] {
    let led = store.ledger()
    return files.compactMap { u in (try? store.load(u)).map { (u, $0) } }
        .sorted {
            (led.firstIndex(of: idOf($0.1) ?? "") ?? Int.max) < (led.firstIndex(of: idOf($1.1) ?? "") ?? Int.max)
        }
}
/// Builds MEMORY.md text: one linked line per memory record, with its description.
func renderMemory(_ store: Store) -> String {
    var s = "# Memory\n\nOne fact per record in `MEMORIES/`. Generated by `write render`; do not edit.\n\n"
    for (u, f) in orderByLedger(store, store.files("memory")) {
        s +=
            "- [\(strOf(field(f, "name")) ?? "?")](MEMORIES/\(u.lastPathComponent)) — \(strOf(field(f, "description")) ?? "")\n"
    }
    return s
}
/// Builds OPEN.md text: one line per open question, or a note saying nothing is waiting on the user.
func renderOpen(_ store: Store) -> String {
    var s = "# Open questions\n\nGenerated by `write render`; do not edit. Answer with `write answer <id> \"…\"`.\n\n"
    var n = 0
    for (u, f) in orderByLedger(store, store.files("question")) where atomOf(field(f, "status")) == "open" {
        n += 1
        s +=
            "- **\(strOf(field(f, "name")) ?? "?")** — \(strOf(field(f, "ask")) ?? "") ([\(u.lastPathComponent)](QUESTIONS/\(u.lastPathComponent)))\n"
    }
    if n == 0 { s += "Nothing is waiting on the user.\n" }
    return s
}
/// Builds BUGS.md text: open issues first, then closed ones, each as a linked line.
func renderBugs(_ store: Store) -> String {
    var s =
        "# Bugs\n\nOne issue per record in `ISSUES/`. Generated by `write render`; do not edit. Close one with `write fix <id> \"<where it was fixed>\"`.\n"
    let all = orderByLedger(store, store.files("issue"))
    /// Builds one markdown line for an issue, with its area and its fix note when it has one.
    func line(_ u: URL, _ f: Form) -> String {
        "- **\(strOf(field(f, "name")) ?? "?")** (\(strOf(field(f, "area")) ?? "?"))"
            + (strOf(field(f, "fix")).map { " — fixed: \($0)" } ?? "")
            + " ([\(u.lastPathComponent)](ISSUES/\(u.lastPathComponent)))\n"
    }
    let open = all.filter { atomOf(field($0.1, "status")) == "open" }
    let closed = all.filter { atomOf(field($0.1, "status")) != "open" }
    s += "\n## Open\n\n" + (open.isEmpty ? "None.\n" : open.map { line($0.0, $0.1) }.joined())
    s += "\n## Closed\n\n" + (closed.isEmpty ? "None.\n" : closed.map { line($0.0, $0.1) }.joined())
    return s
}
/// A phase or task name asks for a design when it starts with a creating verb ("Build the template parser") and is not docs, tests, a fix or a removal (rules/DESIGN.md).
func nameNeedsDesign(_ name: String) -> Bool {
    let words = name.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
    let creates: Set<String> = [
        "make", "create", "build", "implement", "add", "write", "develop", "introduce", "design",
    ]
    let skips: Set<String> = [
        "doc", "docs", "readme", "test", "tests", "fix", "rename", "typo", "comment", "comments", "delete", "remove",
        "update",
    ]
    guard let first = words.first else { return false }
    return creates.contains(first) && skips.isDisjoint(with: words)
}
/// Worker results not yet reported, as markdown: blocked first, then failed, then done; running workers have no result and show nothing.
/// Returns the text and the `id:status` keys it covered, so a result is reported once per status and an empty text means nothing is new.
func renderStatus(_ store: Store, seen: Set<String>) -> (String, [String]) {
    let order = ["blocked", "failed", "done"]
    let news = orderByLedger(store, store.files("result")).compactMap { (_, f) -> (String, Form, String)? in
        guard let id = idOf(f), let st = atomOf(field(f, "status")), !seen.contains("\(id):\(st)") else { return nil }
        return (st, f, "\(id):\(st)")
    }.sorted { (order.firstIndex(of: $0.0) ?? 9) < (order.firstIndex(of: $1.0) ?? 9) }
    var s = ""
    for (st, f, _) in news {
        let report = (strOf(field(f, "report")) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let touched = strs(field(f, "touched")).map { "`\($0)`" }.joined(separator: ", ")
        s += "### \(st.prefix(1).uppercased() + st.dropFirst()): \(strOf(field(f, "name")) ?? "?")\n\n\(report)\n"
        if !touched.isEmpty { s += "\nTouched: \(touched)\n" }
        s += "\n"
    }
    return (s, news.map { $0.2 })
}
/// Returns the text items of a list value, or an empty list for anything else.
func strs(_ v: Value?) -> [String] {
    if case .list(let l)? = v { return l.compactMap(strOf) }
    return []
}
/// A proposal in reply style: summary, numbered steps with points, what the user must do, the question. No ids.
func renderProposal(_ f: Form) -> String {
    var s = (strOf(field(f, "summary")).map { $0 + "\n\n" }) ?? ""
    if case .list(let steps)? = field(f, "steps") {
        for (i, v) in steps.enumerated() {
            guard case .form(let st) = v else { continue }
            let title = strOf(field(st, "title")) ?? ""
            s +=
                "\(i + 1). **\(title)\(title.hasSuffix(".") ? "" : ".")**"
                + (strOf(field(st, "detail")).map { " " + $0 } ?? "") + "\n"
            for p in strs(field(st, "points")) { s += "   * \(p)\n" }
        }
    }
    let yours = strs(field(f, "yours"))
    if !yours.isEmpty { s += "\n**Yours:**\n" + yours.map { "* \($0)\n" }.joined() }
    if let a = strOf(field(f, "ask")) { s += "\n\(a)\n" }
    return s
}
/// Builds PROPOSALS.md text: open proposals with their steps first, then a list of decided ones.
func renderProposals(_ store: Store) -> String {
    var s =
        "# Proposals\n\nGenerated by `write render`; do not edit. Decide with `write accept <name>` or `write reject <name>`.\n"
    let all = orderByLedger(store, store.files("proposal"))
    let open = all.filter { atomOf(field($0.1, "status")) == "open" }
    let decided = all.filter { atomOf(field($0.1, "status")) != "open" }
    s +=
        "\n## Open\n\n"
        + (open.isEmpty
            ? "None.\n"
            : open.map {
                "### \(strOf(field($0.1, "name")) ?? "?")\n\n" + renderProposal($0.1)
                    + "\n([record](PROPOSALS/\($0.0.lastPathComponent)))\n"
            }.joined(separator: "\n"))
    s +=
        "\n## Decided\n\n"
        + (decided.isEmpty
            ? "None.\n"
            : decided.map { "- **\(strOf(field($0.1, "name")) ?? "?")** — \(atomOf(field($0.1, "status")) ?? "?")\n" }
                .joined())
    return s
}
/// A record file by id prefix, or by a word of its `name`: the key and a name word share a prefix of at least 4 letters,
/// so `records` finds "One folder for all record stores". An ambiguous word finds nothing.
func findRecord(_ store: Store, _ kind: String, _ key: String) -> URL? {
    let files = store.files(kind)
    if key.count >= 4, let u = files.first(where: { u in (try? store.load(u)).flatMap(idOf)?.hasPrefix(key) ?? false })
    {
        return u
    }
    let k = key.lowercased()
    /// Counts how many leading characters two words share.
    func common(_ a: Substring, _ b: String) -> Int { zip(a, b).prefix { $0 == $1 }.count }
    let hits = files.filter { u in
        guard let f = try? store.load(u), let name = strOf(field(f, "name")) else { return false }
        return slug(name).split(separator: "-").contains { common($0, k) >= 4 }
    }
    return hits.count == 1 ? hits[0] : nil
}

/// The plan as a checklist for people: title, synopsis, abstract, then each phase with its tasks, estimates before names, no ids.
/// A phase is ticked when it has tasks and all are done (derived, as in the record). Nil when there is no plan yet.
func renderPlan(_ store: Store) -> String? {
    guard let pu = store.files("plan").first, let plan = try? store.load(pu) else { return nil }
    var s = "<!-- Generated by `write render`; do not edit. -->\n# \(strOf(field(plan, "title")) ?? "Plan")\n\n"
    if let syn = strOf(field(plan, "synopsis")) { s += syn + "\n\n" }
    if let ab = strOf(field(plan, "abstract")) { s += "> " + ab + "\n\n" }
    var byID: [String: Form] = [:]
    for u in store.files("phase") { if let f = try? store.load(u), let id = idOf(f) { byID[id] = f } }
    for id in listOf(field(plan, "phases")) {
        guard let ph = byID[id] else { continue }
        var tasks: [Form] = []
        if case .list(let l)? = field(ph, "tasks") { for case .form(let t) in l { tasks.append(t) } }
        let done = !tasks.isEmpty && tasks.allSatisfy { atomOf(field($0, "done")) == "true" }
        let after = listOf(field(ph, "depends")).compactMap { byID[$0] }.compactMap { atomOf(field($0, "n")) }.map {
            "Phase " + $0
        }
        s += "- [\(done ? "x" : " ")] **Phase \(atomOf(field(ph, "n")) ?? "?") — \(strOf(field(ph, "name")) ?? "?")**"
        s += (after.isEmpty ? "" : " (after \(after.joined(separator: ", ")))") + "\n"
        for t in tasks {
            s +=
                "  - [\(atomOf(field(t, "done")) == "true" ? "x" : " ")] [\(atomOf(field(t, "est")) ?? "?")] \(strOf(field(t, "name")) ?? "?")\n"
        }
    }
    return s
}

/// Builds TODO.md text: the ad-hoc tasks in `TASKS/`, open ones first, each as a checkbox with its estimate and file.
func renderTodo(_ store: Store) -> String {
    var s = "# To do\n\nAd-hoc tasks, one per record in `TASKS/`; phased work is in `PLAN.md`. "
    s += "Generated by `write render`; do not edit. Finish one with `write done <id>`, which runs its checks first.\n\n"
    let all = orderByLedger(store, store.files("task"))
    let open = all.filter { atomOf(field($0.1, "done")) != "true" }
    let done = all.filter { atomOf(field($0.1, "done")) == "true" }
    /// Builds one checkbox line for a task, linked to its record.
    func line(_ u: URL, _ f: Form) -> String {
        let box = atomOf(field(f, "done")) == "true" ? "x" : " "
        let est = atomOf(field(f, "est")) ?? "?"
        let file = u.lastPathComponent
        return "- [\(box)] [\(est)] \(strOf(field(f, "name")) ?? "?") ([\(file)](TASKS/\(file)))\n"
    }
    if all.isEmpty { s += "Nothing to do.\n" }
    for (u, f) in open { s += line(u, f) }
    if !done.isEmpty {
        s += "\n## Done\n\n"
        for (u, f) in done { s += line(u, f) }
    }
    return s
}

/// Regenerates PLAN.md, TODO.md, PROPOSALS.md, MEMORY.md, OPEN.md and BUGS.md, skipping any view whose kind is not in the
/// store.
func render(_ store: Store) throws {
    if let p = renderPlan(store) { try writeFile(store.url("PLAN.md"), p) }
    if store.templates["task"] != nil { try writeFile(store.url("TODO.md"), renderTodo(store)) }
    if store.templates["proposal"] != nil { try writeFile(store.url("PROPOSALS.md"), renderProposals(store)) }
    try writeFile(store.url("MEMORY.md"), renderMemory(store))
    try writeFile(store.url("OPEN.md"), renderOpen(store))
    if store.templates["issue"] != nil { try writeFile(store.url("BUGS.md"), renderBugs(store)) }
}

// MARK: - skeleton

/// Turns a value into its shape: ids, durations and numbers become placeholders. Loose mode also drops repeated list shapes.
func skeleton(_ v: Value, loose: Bool) -> String {
    switch v {
    case .str: return "\"\""
    case .atom(let a):
        if isID(a) { return "<id>" }
        if matches(a, "^[0-9]+(\\.[0-9]+)?[mhd]$") { return "<dur>" }
        if Int(a) != nil { return "<int>" }
        return a
    case .list(let items):
        var shapes = items.map { skeleton($0, loose: loose) }
        if loose {
            var seen = Set<String>()
            shapes = shapes.filter { seen.insert($0).inserted }
        }
        return "[" + shapes.joined(separator: " ") + "]"
    case .block(let fs):
        return "{" + fs.map { "\($0.key): " + skeleton($0.value, loose: loose) }.joined(separator: " ") + "}"
    case .form(let f):
        return f.head + "(" + f.args.map { skeleton($0, loose: loose) }.joined(separator: " ") + ")"
            + (f.body.map { skeleton(.block($0), loose: loose) } ?? "")
    }
}
/// Hashes a string with 64-bit FNV-1a and returns the hash as hex text.
func fnv(_ s: String) -> String {
    var h: UInt64 = 14_695_981_039_346_656_037
    for b in s.utf8 {
        h ^= UInt64(b)
        h = h &* 1_099_511_628_211
    }
    return String(h, radix: 16)
}

// MARK: - filing and escalations

/// Fill a checked draft, validate what it becomes, write it and its indexes, and refresh the views. Call inside the lock.
// lint-ignore: func-length: kept whole so its steps read in order; split it when it grows
func fileRecord(_ store: Store, kind: String, template t: Template, draft: Form) throws -> (
    minted: [String], written: [String]
) {
    let filler = Filler(store)
    let root = filler.fillForm(draft, t.form, kind)
    filler.resolvePendingLabels()
    let batch = filler.pending + [(kind, root)]
    if kind == "plan", FileManager.default.fileExists(atPath: store.url("PLAN.closure").path) {
        throw Err(msg: "PLAN.closure already exists; add phases with write phase new")
    }
    var known = store.known()
    for (k, f) in batch { if let id = idOf(f) { known[k, default: []].insert(id) } }
    var problems: [String] = []
    for (k, f) in batch {
        var c = Checker(templates: store.templates, known: known, mode: .stored)
        c.value(.form(f), .form(store.templates[k]!.form), "", 0)
        problems += c.errs
    }
    if !problems.isEmpty {
        throw Err(
            msg: "internal: filled record failed its own template; nothing written\n" + problems.joined(separator: "\n")
        )
    }
    var written: [String] = []
    for (k, f) in batch {
        let rel = try store.path(store.templates[k]!, f)
        if FileManager.default.fileExists(atPath: store.url(rel).path) {
            throw Err(msg: "\(rel) already exists; edit that \(k) or give this one a different name")
        }
    }
    for (k, f) in batch {
        let rel = try store.path(store.templates[k]!, f)
        try writeFile(store.url(rel), canonical(f))
        written.append(rel)
    }
    try String((store.ledger() + filler.minted).map { $0 + "\n" }.joined()).write(
        to: store.url(".ids"), atomically: true, encoding: .utf8)
    // indexes
    func append(_ file: String, _ idxKind: String, _ fieldName: String, _ id: String) throws {
        var f: Form
        if FileManager.default.fileExists(atPath: store.url(file).path) {
            f = try store.load(store.url(file))
        } else if idxKind == "todo" {
            f = Form(head: "todo", args: [], body: [Field(key: "tasks", value: .list([]), line: 0)], line: 0)
        } else {
            throw Err(msg: "no \(file); file a plan first with write plan new")
        }
        var body = f.body ?? []
        guard let i = body.firstIndex(where: { $0.key == fieldName }), case .list(var l) = body[i].value else {
            throw Err(msg: "\(file) has no \(fieldName) list")
        }
        l.append(.atom(id))
        body[i].value = .list(l)
        f.body = body
        try writeFile(store.url(file), canonical(f))
    }
    if kind == "phase" { try append("PLAN.closure", "plan", "phases", idOf(root) ?? "") }
    if kind == "task" { try append("TODO.closure", "todo", "tasks", idOf(root) ?? "") }
    try render(store)
    return (filler.minted, written)
}

/// The model tiers a `model`-routed escalation climbs, in order, after the agent that wrote the draft.
let tiers = ["sonnet", "opus"]

/// Lists the .escalate files in the drafts folder, sorted by name.
func escalationFiles(_ store: Store) -> [URL] {
    let dir = store.url("drafts")
    return ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.hasSuffix(".escalate") }
        .sorted().map { dir.appendingPathComponent($0) }
}
/// Returns the atom items of a list value, or an empty list for anything else.
func listOf(_ v: Value?) -> [String] {
    if case .list(let l)? = v { return l.compactMap(atomOf) }
    return []
}
/// Sets a key in a form's body to a value, adding the key when it is missing.
func setField(_ f: inout Form, _ key: String, _ v: Value) {
    var body = f.body ?? []
    if let i = body.firstIndex(where: { $0.key == key }) {
        body[i].value = v
    } else {
        body.append(Field(key: key, value: v, line: 0))
    }
    f.body = body
}
/// The meaning of a reason code, from reasons.closure (`code: reason(route, "meaning")`).
func reasonMeaning(_ store: Store, _ code: String) -> String? {
    guard let f = try? parseRecord(String(contentsOf: store.top("reasons.closure"), encoding: .utf8)),
        case .form(let r)? = field(f, code), r.args.count == 2
    else { return nil }
    return strOf(r.args[1])
}

/// Finds the task form with the given id anywhere inside a value, or nil when there is none.
func findTask(_ v: Value, _ id: String) -> Form? {
    var hit: Form? = nil
    walk(v) { if $0.head == "task", idOf($0) == id { hit = $0 } }
    return hit
}

// MARK: - Criteria

/// Takes a shell command and a folder; runs the command there under `sh -c` as the project and returns its exit status
/// and its output. A command that cannot start returns status 127.
func runShell(_ command: String, in dir: String) -> (Int32, String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/sh")
    p.arguments = ["-c", command]
    p.currentDirectoryURL = URL(fileURLWithPath: dir)
    var env = ProcessInfo.processInfo.environment
    env["CLAUDE_PROJECT_DIR"] = dir
    p.environment = env
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    guard (try? p.run()) != nil else { return (127, "could not run sh") }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
}

/// Takes the store, a task id, and the text that confirms its manual criteria (nil when none was given).
/// Runs every criterion of the task: a command passes when it exits 0, and a `manual` one passes only with a confirmation.
/// Returns whether all passed, with one evidence line per criterion (a failure also shows the command and its last output).
func runCriteria(_ store: Store, taskId: String, confirmed: String?) -> (ok: Bool, lines: [String]) {
    let proj = store.root.deletingLastPathComponent().path
    var task: Form? = nil
    for (_, u) in store.allFiles() {
        if let f = try? store.load(u), let t = findTask(.form(f), taskId) { task = t }
    }
    // a task that is already done, or has no criteria, has nothing to check
    guard let task = task, atomOf(field(task, "done")) != "true", case .list(let items)? = field(task, "criteria")
    else {
        return (true, [])
    }
    var ok = true
    var lines: [String] = []
    for case .form(let c) in items {
        let text = strOf(field(c, "text")) ?? "?"
        let check = strOf(field(c, "check")) ?? "manual"
        if check == "manual" {
            if let who = confirmed {
                lines.append("confirmed: \(text) (\(who))")
            } else {
                ok = false
                lines.append(
                    "FAIL: \(text)\n    needs a person's confirmation: write done \(taskId) --confirmed \"<who checked what>\""
                )
            }
            continue
        }
        let (status, output) = runShell(check, in: proj)
        if status == 0 {
            lines.append("pass: \(text)  [\(check)]")
        } else {
            ok = false
            let tail = output.split(separator: "\n").suffix(8).map { "    " + $0 }.joined(separator: "\n")
            lines.append("FAIL: \(text)\n    $ \(check)  (exit \(status))" + (tail.isEmpty ? "" : "\n" + tail))
        }
    }
    return (ok, lines)
}

// MARK: - main

/// Runs the write command named by the arguments (kind, then command) and returns the process exit code.
// lint-ignore: func-length: kept whole so its steps read in order; split it when it grows
func run() throws -> Int32 {
    var args = Array(CommandLine.arguments.dropFirst())
    guard !args.isEmpty else {
        throw Err(
            msg:
                "usage: write <kind> new|check-draft | check | lint | get | list | done | reopen | answer | next | render | skeleton | measure"
        )
    }
    let store = try Store()
    let kinds = Set(store.templates.keys)
    var kind: String? = nil
    if kinds.contains(args[0]) { kind = args.removeFirst() }
    guard !args.isEmpty else { throw Err(msg: "missing command after '\(kind ?? "")'") }
    let cmd = args.removeFirst()

    switch cmd {
    case "check-draft":
        let (_, errs) = checkDraft(try readInput(args.first), store, kind: kind)
        errs.forEach { print($0) }
        print(errs.isEmpty ? "ok: draft passes" : "\(errs.count) problem(s)")
        return errs.isEmpty ? 0 : 1

    case "new":
        guard let kind = kind else { throw Err(msg: "usage: write <kind> new [file|-]") }
        let (draft, errs) = checkDraft(try readInput(args.first), store, kind: kind)
        if !errs.isEmpty || draft == nil {
            errs.forEach { print($0) }
            print("\(errs.count) problem(s); nothing written")
            return 1
        }
        guard let t = store.templates[kind], !store.isSingleton(t) || kind == "plan" else {
            throw Err(msg: "cannot file a \(kind)")
        }
        return try withLock(store) {
            let (minted, written) = try fileRecord(store, kind: kind, template: t, draft: draft!)
            // names in this record that ask for a design (rules/DESIGN.md): the task itself, or a phase's tasks
            var names: [String] = []
            if kind == "task", let n = strOf(field(draft!, "name")) { names = [n] }
            if case .list(let l)? = field(draft!, "tasks") {
                for case .form(let t) in l { if let n = strOf(field(t, "name")) { names.append(n) } }
            }
            let design = names.filter(nameNeedsDesign)
            envelope(
                "ok", "filed \(kind)",
                design.isEmpty
                    ? ["ids": minted, "files": written] : ["ids": minted, "files": written, "design": design])
            return 0
        }

    case "escalations":
        // one JSON object per open escalation, for the orchestrator (rules/ESCALATION.md)
        for u in escalationFiles(store) {
            guard let f = try? parseRecord(String(contentsOf: u, encoding: .utf8)) else {
                print("{\"escalation\":\"\(u.lastPathComponent)\",\"error\":\"does not parse\"}")
                continue
            }
            let tried = listOf(field(f, "tried"))
            var d: [String: Any] = [
                "escalation": "records/drafts/" + u.lastPathComponent, "draft": strOf(field(f, "draft")) ?? "",
                "reason": atomOf(field(f, "reason")) ?? "", "route": atomOf(field(f, "route")) ?? "", "tried": tried,
            ]
            if let q = atomOf(field(f, "question")) { d["question"] = q }
            if let i = atomOf(field(f, "issue")) { d["issue"] = i }
            if atomOf(field(f, "route")) == "model", let next = tiers.first(where: { !tried.contains($0) }) {
                d["next"] = next
            }
            if let data = try? JSONSerialization.data(withJSONObject: d, options: [.sortedKeys]),
                let s = String(data: data, encoding: .utf8)
            {
                print(s)
            }
        }
        return 0

    case "escalation":
        guard args.count >= 2 else {
            throw Err(msg: "usage: write escalation <draft> resolve | bump <sonnet|opus> | ask")
        }
        let draftPath = args[0].hasSuffix(".escalate") ? String(args[0].dropLast(".escalate".count)) : args[0]
        let draftURL = URL(
            fileURLWithPath: draftPath.hasPrefix("/")
                ? draftPath : store.root.deletingLastPathComponent().appendingPathComponent(draftPath).path)
        let escURL = URL(fileURLWithPath: draftURL.path + ".escalate")
        // a fixer's own stop hook clears the escalation when its draft passes, so resolve accepts that as done
        if args[1] == "resolve", !FileManager.default.fileExists(atPath: escURL.path),
            FileManager.default.fileExists(atPath: draftURL.path)
        {
            let (_, errs) = checkDraft(try String(contentsOf: draftURL, encoding: .utf8), store, kind: nil)
            if errs.isEmpty {
                envelope("ok", "resolved (the escalation was already cleared)", ["draft": draftURL.lastPathComponent])
                return 0
            }
            errs.forEach { print($0) }
            print("still failing, and no escalation is open for it")
            return 1
        }
        guard FileManager.default.fileExists(atPath: escURL.path) else {
            throw Err(msg: "no escalation for \(draftURL.lastPathComponent)")
        }
        var esc = try parseRecord(String(contentsOf: escURL, encoding: .utf8))
        switch args[1] {
        case "resolve":
            let (_, errs) = checkDraft(try String(contentsOf: draftURL, encoding: .utf8), store, kind: nil)
            if !errs.isEmpty {
                errs.forEach { print($0) }
                print("still failing; the escalation stays")
                return 1
            }
            try FileManager.default.removeItem(at: escURL)
            envelope("ok", "resolved", ["draft": draftURL.lastPathComponent])
            return 0
        case "bump":
            guard args.count >= 3, tiers.contains(args[2]) else {
                throw Err(msg: "usage: write escalation <draft> bump <\(tiers.joined(separator: "|"))>")
            }
            var tried = listOf(field(esc, "tried"))
            if !tried.contains(args[2]) { tried.append(args[2]) }
            setField(&esc, "tried", .list(tried.map { .atom($0) }))
            if tiers.allSatisfy(tried.contains) {
                setField(&esc, "route", .atom("user"))
                setField(
                    &esc, "note",
                    .str(
                        ((strOf(field(esc, "note")) ?? "") + " (\(tiers.joined(separator: " and ")) could not fix it)")
                            .trimmingCharacters(in: .whitespaces)))
            }
            try writeFile(escURL, canonical(esc))
            let next = atomOf(field(esc, "route")) == "model" ? tiers.first(where: { !tried.contains($0) }) : nil
            envelope("ok", "tried \(args[2])", ["route": atomOf(field(esc, "route")) ?? "", "next": next ?? NSNull()])
            return 0
        case "ask":
            if let q = atomOf(field(esc, "question")) {
                envelope("ok", "already asked", ["question": q])
                return 0
            }
            if let i = atomOf(field(esc, "issue")) {
                envelope("ok", "already reported", ["issue": i])
                return 0
            }
            let stem = draftURL.deletingPathExtension().lastPathComponent
            let code = atomOf(field(esc, "reason")) ?? "none"
            let meaning = reasonMeaning(store, code) ?? "the draft still fails after the agents tried to fix it"
            let rel = draftURL.path.replacingOccurrences(
                of: store.root.deletingLastPathComponent().path + "/", with: "")
            let context =
                "Draft: \(rel)\nReason: \(code), route \(atomOf(field(esc, "route")) ?? "?")\nNote: \(strOf(field(esc, "note")) ?? "")\nChecker:\n\(strOf(field(esc, "checker")) ?? "")"
            // a harness route is a bug in the tool or a template: report it as an issue (BUGS.md) when that kind exists
            if atomOf(field(esc, "route")) == "harness", let it = store.templates["issue"] {
                let issue = Form(
                    head: "issue", args: [.atom("_")],
                    body: [
                        Field(key: "name", value: .str("Harness rejects draft \(stem)"), line: 0),
                        Field(key: "area", value: .str("writer or templates"), line: 0),
                        Field(key: "status", value: .atom("open"), line: 0),
                        Field(key: "repro", value: .str("\(meaning).\n\(context)"), line: 0),
                    ], line: 0)
                var ci = Checker(templates: store.templates, known: store.known(), mode: .draft)
                ci.value(.form(issue), .form(it.form), "", 0)
                if !ci.errs.isEmpty {
                    ci.errs.forEach { print($0) }
                    print("internal: the issue draft fails its template")
                    return 2
                }
                return try withLock(store) {
                    let (minted, written) = try fileRecord(store, kind: "issue", template: it, draft: issue)
                    if let id = minted.last { setField(&esc, "issue", .atom(id)) }
                    try writeFile(escURL, canonical(esc))
                    envelope("ok", "reported", ["issue": minted.last ?? "", "files": written])
                    return 0
                }
            }
            guard let qt = store.templates["question"] else { throw Err(msg: "no question template") }
            let q = Form(
                head: "question", args: [.atom("_")],
                body: [
                    Field(key: "name", value: .str("Escalated draft \(stem)"), line: 0),
                    Field(
                        key: "ask", value: .str("How should draft \(stem) be fixed? Reason given: \(meaning)."), line: 0
                    ),
                    Field(key: "context", value: .str(context), line: 0),
                    Field(key: "status", value: .atom("open"), line: 0),
                ], line: 0)
            var c = Checker(templates: store.templates, known: store.known(), mode: .draft)
            c.value(.form(q), .form(qt.form), "", 0)
            if !c.errs.isEmpty {
                c.errs.forEach { print($0) }
                print("internal: the question draft fails its template")
                return 2
            }
            return try withLock(store) {
                let (minted, written) = try fileRecord(store, kind: "question", template: qt, draft: q)
                if let id = minted.last { setField(&esc, "question", .atom(id)) }
                try writeFile(escURL, canonical(esc))
                envelope("ok", "asked", ["question": minted.last ?? "", "files": written])
                return 0
            }
        default: throw Err(msg: "unknown escalation command '\(args[1])'")
        }

    case "check":
        let only = args.isEmpty ? nil : args.map { URL(fileURLWithPath: $0) }
        let (errs, warns, n) = storeProblems(store, only: only)
        errs.forEach { print($0) }
        warns.forEach { print("warning: \($0)") }
        print(errs.isEmpty ? "ok: \(n) record(s)" : "\(errs.count) problem(s)")
        return errs.isEmpty ? 0 : 1

    case "lint":
        let fix = args.first == "--fix"
        let files = fix ? Array(args.dropFirst()) : args
        guard !files.isEmpty else { throw Err(msg: "usage: write lint [--fix] <file…>") }
        var bad = 0
        for a in files {
            let text = try String(contentsOfFile: a, encoding: .utf8)
            do {
                let f = try parseRecord(text)
                // only records must be exactly what the writer emits; templates, test fixtures and config like reasons.closure
                // (a head that is no record kind) keep their hand-written layout and comments
                if store.templates[f.head] != nil, !a.contains("/templates/"), !a.contains("/tests/"),
                    canonical(f) != text
                {
                    if fix {
                        try canonical(f).write(toFile: a, atomically: true, encoding: .utf8)
                        print("\(a): rewritten in canonical form")
                    } else {
                        print("\(a): not in canonical form (run: write lint --fix \(a))")
                        bad += 1
                    }
                }
            } catch let x as Fail {
                print("\(a):\(x.line):\(x.col): \(x.msg)")
                bad += 1
            }
        }
        print(bad == 0 ? "ok: \(files.count) file(s)" : "\(bad) problem(s)")
        return bad == 0 ? 0 : 1

    case "get":
        guard let id = args.first else { throw Err(msg: "usage: write get <id>") }
        for (_, u) in store.allFiles() {
            if let t = try? String(contentsOf: u, encoding: .utf8), t.contains("(\(id))") {
                print("// \(u.path)")
                print(t, terminator: "")
                return 0
            }
        }
        throw Err(msg: "no record with id \(id)")

    case "list":
        for k in (kind.map { [$0] } ?? args.first.map { [$0] } ?? store.templates.keys.sorted()) {
            for (u, f) in orderByLedger(store, store.files(k)) {
                let label = strOf(field(f, "name")) ?? strOf(field(f, "title")) ?? ""
                let extra =
                    (atomOf(field(f, "n")).map { " n=\($0)" } ?? "")
                    + (atomOf(field(f, "status")).map { " \($0)" } ?? "")
                    + (atomOf(field(f, "done")).map { " done=\($0)" } ?? "")
                print("\(k) \(idOf(f) ?? "?")\(extra) \(label)  [\(u.lastPathComponent)]")
            }
        }
        return 0

    case "done", "reopen":
        guard let id = args.first else { throw Err(msg: "usage: write \(cmd) <task-id>") }
        // a task is not done until each of its criteria passes; the evidence is printed with the result
        var evidence: [String] = []
        if cmd == "done" {
            let confirmed = args.firstIndex(of: "--confirmed").flatMap {
                args.indices.contains($0 + 1) ? args[$0 + 1] : nil
            }
            let result = runCriteria(store, taskId: id, confirmed: confirmed)
            result.lines.forEach { print($0) }
            if !result.ok {
                print("criteria not met; fix them before marking the task done")
                return 1
            }
            evidence = result.lines
        }
        return try withLock(store) {
            for (k, u) in store.allFiles() {
                guard let f = try? store.load(u) else { continue }
                var v: Value = .form(f)
                let wasDone = findTask(.form(f), id).flatMap { atomOf(field($0, "done")) } == "true"
                if setDone(&v, id, cmd == "done" ? "true" : "false"), case .form(let nf) = v {
                    var c = Checker(templates: store.templates, known: store.known(), mode: .stored)
                    c.value(.form(nf), .form(store.templates[k]!.form), "", 0)
                    if !c.errs.isEmpty {
                        c.errs.forEach { print($0) }
                        return 1
                    }
                    try writeFile(u, canonical(nf))
                    try render(store)  // PLAN.md shows the new checkbox
                    // Nothing is committed: commits are the user's. The criteria evidence is reported instead.
                    _ = wasDone
                    envelope("ok", "\(cmd) \(id)", ["file": u.lastPathComponent, "evidence": evidence])
                    return 0
                }
            }
            throw Err(msg: "no task with id \(id)")
        }

    case "answer":
        guard args.count >= 2, let q = findRecord(store, "question", args[0]) else {
            throw Err(msg: "usage: write answer <question-id> \"<text>\"")
        }
        return try withLock(store) {
            var f = try store.load(q)
            var body = f.body ?? []
            for key in ["status", "answer"] { body.removeAll { $0.key == key } }
            body.append(Field(key: "status", value: .atom("answered"), line: 0))
            body.append(Field(key: "answer", value: .str(args[1]), line: 0))
            f.body = body
            var c = Checker(templates: store.templates, known: store.known(), mode: .stored)
            c.value(.form(f), .form(store.templates["question"]!.form), "", 0)
            if !c.errs.isEmpty {
                c.errs.forEach { print($0) }
                return 1
            }
            try writeFile(q, canonical(f))
            try render(store)
            envelope("ok", "answered", ["file": q.lastPathComponent])
            return 0
        }

    case "show":
        // a proposal draft or record, in reply style; a draft is checked first so what is shown is what would be filed
        guard let key = args.first else { throw Err(msg: "usage: write show <draft file | proposal id or name>") }
        let f: Form
        if FileManager.default.fileExists(atPath: key) {
            let (d, errs) = checkDraft(
                try String(contentsOf: URL(fileURLWithPath: key), encoding: .utf8), store, kind: "proposal")
            guard let draft = d, errs.isEmpty else {
                errs.forEach { print($0) }
                print("\(errs.count) problem(s); fix the draft before showing it")
                return 1
            }
            f = draft
        } else if let u = findRecord(store, "proposal", key) {
            f = try store.load(u)
        } else {
            throw Err(msg: "no proposal draft or record '\(key)'")
        }
        print(renderProposal(f), terminator: "")
        return 0

    case "accept", "reject":
        guard let key = args.first else { throw Err(msg: "usage: write \(cmd) <proposal id or name>") }
        guard let u = findRecord(store, "proposal", key) else {
            throw Err(
                msg: "no single proposal matches '\(key)'; give its id or a word from its name (write list proposal)")
        }
        return try withLock(store) {
            var f = try store.load(u)
            setField(&f, "status", .atom(cmd == "accept" ? "accepted" : "rejected"))
            var c = Checker(templates: store.templates, known: store.known(), mode: .stored)
            c.value(.form(f), .form(store.templates["proposal"]!.form), "", 0)
            if !c.errs.isEmpty {
                c.errs.forEach { print($0) }
                return 1
            }
            try writeFile(u, canonical(f))
            try render(store)
            envelope("ok", cmd == "accept" ? "accepted" : "rejected", ["file": u.lastPathComponent])
            return 0
        }

    case "fix":
        guard args.count >= 2, let u = findRecord(store, "issue", args[0]) else {
            throw Err(msg: "usage: write fix <issue-id> \"<where it was fixed>\"")
        }
        return try withLock(store) {
            var f = try store.load(u)
            setField(&f, "status", .atom("fixed"))
            setField(&f, "fix", .str(args[1]))
            var c = Checker(templates: store.templates, known: store.known(), mode: .stored)
            c.value(.form(f), .form(store.templates["issue"]!.form), "", 0)
            if !c.errs.isEmpty {
                c.errs.forEach { print($0) }
                return 1
            }
            try writeFile(u, canonical(f))
            try render(store)
            envelope("ok", "fixed", ["file": u.lastPathComponent])
            return 0
        }

    case "set": return try runSet(store, args)
    case "link": return try runLink(store, args, add: true)
    case "unlink": return try runLink(store, args, add: false)
    case "move": return try runMove(store, args)
    case "del": return try runDel(store, args)

    case "next":
        var phases: [(n: Int, id: String, name: String, deps: [String], done: Bool)] = []
        for u in store.files("phase") {
            guard let f = try? store.load(u), let id = idOf(f), let n = Int(atomOf(field(f, "n")) ?? "") else {
                continue
            }
            var tasks: [Bool] = []
            if case .list(let l)? = field(f, "tasks") {
                for case .form(let t) in l { tasks.append(atomOf(field(t, "done")) == "true") }
            }
            let deps: [String] = {
                if case .list(let l)? = field(f, "depends") { return l.compactMap(atomOf) }
                return []
            }()
            phases.append((n, id, strOf(field(f, "name")) ?? "", deps, !tasks.isEmpty && tasks.allSatisfy { $0 }))
        }
        phases.sort { $0.n < $1.n }
        let doneIDs = Set(phases.filter { $0.done }.map { $0.id })
        let open = phases.filter { !$0.done }
        let ready = open.filter { $0.deps.allSatisfy(doneIDs.contains) }
        // open tasks whose names ask for a design, by phase id
        var designs: [String: [String]] = [:]
        for u in store.files("phase") {
            guard let f = try? store.load(u), let id = idOf(f), case .list(let l)? = field(f, "tasks") else { continue }
            for case .form(let t) in l where atomOf(field(t, "done")) != "true" {
                if let name = strOf(field(t, "name")), nameNeedsDesign(name) { designs[id, default: []].append(name) }
            }
        }
        /// Lists one design note line for each open task of a phase whose name asks for a design.
        func designLines(_ id: String) -> String {
            (designs[id] ?? []).map { "\n  design \($0): ask Opus first (rules/DESIGN.md)" }.joined()
        }
        for (i, p) in ready.enumerated() {
            print("\(i == 0 ? "next" : "ready") \(p.id) Phase \(p.n) — \(p.name)" + designLines(p.id))
        }
        for p in open where !ready.contains(where: { $0.id == p.id }) {
            print("blocked \(p.id) Phase \(p.n) — \(p.name)")
        }
        if open.isEmpty { print("nothing open") }
        return 0

    case "render":
        // under the lock, so a render never reads a store another write is halfway through
        try withLock(store) { try render(store) }
        envelope("ok", "rendered")
        return 0

    case "status":
        // worker results the user has not been told about, as markdown; nothing printed when there is nothing new
        let peek = args.contains("--peek")
        let seenURL = store.url(".status-seen")
        let seen = Set(
            ((try? String(contentsOf: seenURL, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init))
        let (text, keys) = renderStatus(store, seen: seen)
        print(text, terminator: "")
        if !peek, !keys.isEmpty { try writeFile(seenURL, (seen.union(keys)).sorted().joined(separator: "\n") + "\n") }
        return 0

    case "skeleton":
        let (f, errs) = checkDraft(try readInput(args.first), store, kind: kind)
        guard let rec = f else {
            errs.forEach { print($0) }
            return 1
        }
        let strict = skeleton(.form(rec), loose: false)
        let loose = skeleton(.form(rec), loose: true)
        print("strict \(fnv(strict)) \(strict)")
        print("loose  \(fnv(loose)) \(loose)")
        return 0

    case "measure":
        guard let dir = args.first else { throw Err(msg: "usage: write measure <dir of drafts>") }
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).filter {
            $0.hasSuffix(".closure")
        }.sorted()
        var pass = 0
        var fails: [String] = []
        var strict: [String: Int] = [:]
        var loose: [String: Int] = [:]
        for n in names {
            let text = try String(contentsOfFile: dir + "/" + n, encoding: .utf8)
            let (f, errs) = checkDraft(text, store, kind: kind)
            if errs.isEmpty, let rec = f {
                pass += 1
                strict[fnv(skeleton(.form(rec), loose: false)), default: 0] += 1
                loose[fnv(skeleton(.form(rec), loose: true)), default: 0] += 1
            } else {
                fails.append("\(n): \(errs.first ?? "?")")
            }
        }
        let total = names.count
        print(
            "drafts: \(total)  first-write pass: \(pass)  fail: \(total - pass)  pass rate: \(total == 0 ? 0 : pass * 100 / total)%"
        )
        print("distinct skeletons among passes: strict \(strict.count), loose \(loose.count)")
        for (h, c) in strict.sorted(by: { $0.value > $1.value }) { print("  strict \(h) x\(c)") }
        fails.forEach { print("  fail \($0)") }
        return 0

    default: throw Err(msg: "unknown command '\(cmd)'")
    }
}

/// Sets the done flag of the task with the given id anywhere inside a value; returns true when it found the task.
func setDone(_ v: inout Value, _ id: String, _ val: String) -> Bool {
    switch v {
    case .form(var f):
        if f.head == "task", atomOf(f.args.first) == id, var body = f.body,
            let i = body.firstIndex(where: { $0.key == "done" })
        {
            body[i].value = .atom(val)
            f.body = body
            v = .form(f)
            return true
        }
        guard var body = f.body else { return false }
        for i in body.indices {
            var x = body[i].value
            if setDone(&x, id, val) {
                body[i].value = x
                f.body = body
                v = .form(f)
                return true
            }
        }
        return false
    case .list(var items):
        for i in items.indices {
            var x = items[i]
            if setDone(&x, id, val) {
                items[i] = x
                v = .list(items)
                return true
            }
        }
        return false
    default: return false
    }
}

// MARK: - mutations (set, link, unlink, move, del)

/// Parses a CLI argument into a closure Value, falling back to a quoted string when raw text has spaces or fails to parse.
func parseCLIValue(_ raw: String, expectsString: Bool) throws -> Value {
    if expectsString {
        var p = Parser(raw)
        if let v = try? p.value() {
            p.skip()
            if p.i == p.s.count, case .str(let s) = v { return .str(joinLines(s)) }
        }
        return .str(joinLines(raw))
    }
    var p = Parser(raw)
    if let v = try? p.value() {
        p.skip()
        if p.i == p.s.count { return v }
    }
    return .str(raw)
}

/// Inserts or replaces a field on a form while keeping the template's field order.
func setOrderedField(_ f: inout Form, _ tmpl: [Field], _ key: String, _ val: Value) {
    var body = f.body ?? []
    if let i = body.firstIndex(where: { $0.key == key }) {
        body[i].value = val
        f.body = body
        return
    }
    let order = tmpl.map { $0.key }
    let targetIdx = order.firstIndex(of: key) ?? order.count
    var insertAt = body.count
    for (i, existing) in body.enumerated() {
        if (order.firstIndex(of: existing.key) ?? order.count) > targetIdx {
            insertAt = i
            break
        }
    }
    body.insert(Field(key: key, value: val, line: 0), at: insertAt)
    f.body = body
}

/// Validates a modified form against its kind template and returns any checker or cycle errors.
func validateModified(_ store: Store, kind: String, form: Form) -> [String] {
    guard let t = store.templates[kind] else { return ["unknown kind '\(kind)'"] }
    var c = Checker(templates: store.templates, known: store.known(), mode: .stored)
    c.value(.form(form), .form(t.form), "", 0)
    return c.errs
}

/// Updates a field on the record or nested task with `<id>` (or `plan`) under `.write.lock`.
// lint-ignore: func-length: kept whole so target lookup, template check and write stay in one lock scope
func runSet(_ store: Store, _ args: [String]) throws -> Int32 {
    guard args.count >= 3 else { throw Err(msg: "usage: write set <id|plan> <field> <value>") }
    let target = args[0]
    let key = args[1]
    let rawVal = args.dropFirst(2).joined(separator: " ")
    let forbidden: Set<String> = ["id", "n", "criteria", "phases", "tasks"]
    if forbidden.contains(key) {
        throw Err(msg: "field '\(key)' cannot be modified with write set")
    }
    return try withLock(store) {
        for (k, u) in store.allFiles() {
            guard var f = try? store.load(u), let t = store.templates[k] else { continue }
            if (target == "plan" && k == "plan") || idOf(f) == target {
                guard let tb = t.form.body, let tf = tb.first(where: { $0.key == key }) else {
                    throw Err(msg: "\(k) has no field '\(key)'")
                }
                if case .form(let pf) = tf.value, pf.head == "derived" || pf.head == "index" {
                    throw Err(msg: "field '\(key)' on \(k) cannot be set directly")
                }
                let wantsStr: Bool = {
                    guard case .form(let pf) = tf.value else { return false }
                    if pf.head == "grok" || pf.head == "text" { return true }
                    if pf.head == "opt", case .form(let inner)? = pf.args.first {
                        return inner.head == "grok" || inner.head == "text"
                    }
                    return false
                }()
                let val = try parseCLIValue(rawVal, expectsString: wantsStr)
                setOrderedField(&f, tb, key, val)
                let errs = validateModified(store, kind: k, form: f)
                if !errs.isEmpty {
                    errs.forEach { print($0) }
                    return 1
                }
                try writeFile(u, canonical(f))
                try render(store)
                envelope("ok", "set \(key) on \(idOf(f) ?? k)", ["file": u.lastPathComponent])
                return 0
            }
            if k == "phase", var body = f.body, let ti = body.firstIndex(where: { $0.key == "tasks" }),
                case .list(var tasks) = body[ti].value,
                let ttf = t.form.body?.first(where: { $0.key == "tasks" })?.value,
                case .form(let manyForm) = ttf, case .list(let manyArgs)? = manyForm.args.first,
                case .form(let taskTmpl)? = manyArgs.first, let taskTb = taskTmpl.body
            {
                for idx in tasks.indices {
                    guard case .form(var tf) = tasks[idx], idOf(tf) == target else { continue }
                    guard let fieldTmpl = taskTb.first(where: { $0.key == key }) else {
                        throw Err(msg: "nested task has no field '\(key)'")
                    }
                    let wantsStr: Bool = {
                        if case .form(let pf) = fieldTmpl.value { return pf.head == "grok" || pf.head == "text" }
                        return false
                    }()
                    let val = try parseCLIValue(rawVal, expectsString: wantsStr)
                    setOrderedField(&tf, taskTb, key, val)
                    tasks[idx] = .form(tf)
                    body[ti].value = .list(tasks)
                    f.body = body
                    let errs = validateModified(store, kind: k, form: f)
                    if !errs.isEmpty {
                        errs.forEach { print($0) }
                        return 1
                    }
                    try writeFile(u, canonical(f))
                    try render(store)
                    envelope("ok", "set \(key) on \(target)", ["file": u.lastPathComponent])
                    return 0
                }
            }
        }
        throw Err(msg: "no record or nested task with id '\(target)'")
    }
}

/// Appends or removes a reference in a list field (such as `depends`) and checks for dependency cycles.
func runLink(_ store: Store, _ args: [String], add: Bool) throws -> Int32 {
    let verb = add ? "link" : "unlink"
    guard args.count == 3 else { throw Err(msg: "usage: write \(verb) <id> <field> <target-id>") }
    let (id, key, refID) = (args[0], args[1], args[2])
    if key == "criteria" || key == "phases" || key == "tasks" {
        throw Err(msg: "field '\(key)' cannot be changed with write \(verb)")
    }
    return try withLock(store) {
        for (k, u) in store.allFiles() {
            guard var f = try? store.load(u), idOf(f) == id, let tb = store.templates[k]?.form.body else { continue }
            guard tb.contains(where: { $0.key == key }), case .list(var items)? = field(f, key) else {
                throw Err(msg: "\(k) \(id) has no list field '\(key)'")
            }
            if add {
                if !items.contains(where: { atomOf($0) == refID }) { items.append(.atom(refID)) }
            } else {
                items.removeAll { atomOf($0) == refID }
            }
            setOrderedField(&f, tb, key, .list(items))
            var errs = validateModified(store, kind: k, form: f)
            if errs.isEmpty, key == "depends" {
                var edges: [String: [String]] = [:]
                for cu in store.files(k) {
                    let cf = (cu == u) ? f : (try? store.load(cu))
                    if let cf = cf, let cid = idOf(cf), case .list(let l)? = field(cf, "depends") {
                        edges[cid] = l.compactMap(atomOf)
                    }
                }
                errs += edgeCycles(edges)
            }
            if !errs.isEmpty {
                errs.forEach { print($0) }
                return 1
            }
            try writeFile(u, canonical(f))
            try render(store)
            envelope("ok", "\(verb) \(refID) on \(id).\(key)", ["file": u.lastPathComponent])
            return 0
        }
        throw Err(msg: "no record with id '\(id)'")
    }
}

/// Reorders `<id>` before or after `<target-id>` in `PLAN.closure`, `TODO.closure`, or a phase's `tasks` list.
// lint-ignore: func-length: handles index lists and phase-nested task lists together under one lock
func runMove(_ store: Store, _ args: [String]) throws -> Int32 {
    guard args.count == 3, args[1] == "before" || args[1] == "after" else {
        throw Err(msg: "usage: write move <id> before|after <target-id>")
    }
    let (id, dir, target) = (args[0], args[1], args[2])
    guard id != target else { throw Err(msg: "cannot move '\(id)' \(dir) itself") }
    return try withLock(store) {
        for (file, listKey) in [("PLAN.closure", "phases"), ("TODO.closure", "tasks")] {
            let u = store.url(file)
            guard FileManager.default.fileExists(atPath: u.path), var f = try? store.load(u),
                case .list(var items)? = field(f, listKey)
            else { continue }
            let ids = items.compactMap(atomOf)
            if let from = ids.firstIndex(of: id), ids.contains(target) {
                let moved = items.remove(at: from)
                guard let to = items.firstIndex(where: { atomOf($0) == target }) else { continue }
                items.insert(moved, at: dir == "before" ? to : to + 1)
                setField(&f, listKey, .list(items))
                try writeFile(u, canonical(f))
                try render(store)
                envelope("ok", "moved \(id) \(dir) \(target)", ["file": file])
                return 0
            }
        }
        for u in store.files("phase") {
            guard var f = try? store.load(u), case .list(var tasks)? = field(f, "tasks") else { continue }
            let taskIDs = tasks.compactMap { v -> String? in
                if case .form(let tf) = v { return idOf(tf) }
                return nil
            }
            if let from = taskIDs.firstIndex(of: id), taskIDs.contains(target) {
                let moved = tasks.remove(at: from)
                guard
                    let to = tasks.firstIndex(where: { v in
                        if case .form(let tf) = v { return idOf(tf) == target }
                        return false
                    })
                else { continue }
                tasks.insert(moved, at: dir == "before" ? to : to + 1)
                setField(&f, "tasks", .list(tasks))
                try writeFile(u, canonical(f))
                try render(store)
                envelope("ok", "moved \(id) \(dir) \(target)", ["file": u.lastPathComponent])
                return 0
            }
        }
        throw Err(msg: "'\(id)' and '\(target)' were not found in the same phase or index list")
    }
}

/// Removes a nested `task` inside an open `phase`; refuses to delete stored top-level records.
func runDel(_ store: Store, _ args: [String]) throws -> Int32 {
    guard let id = args.first, args.count == 1 else { throw Err(msg: "usage: write del <nested-task-id>") }
    return try withLock(store) {
        for (k, u) in store.allFiles() {
            if let f = try? store.load(u), idOf(f) == id {
                throw Err(
                    msg:
                        "stored top-level \(k) records are never deleted (\(u.lastPathComponent)); only a nested task inside an open phase can be removed"
                )
            }
        }
        for u in store.files("phase") {
            guard var f = try? store.load(u), case .list(var tasks)? = field(f, "tasks") else { continue }
            guard
                let idx = tasks.firstIndex(where: { v in
                    if case .form(let tf) = v { return idOf(tf) == id }
                    return false
                })
            else { continue }
            let allDone =
                !tasks.isEmpty
                && tasks.allSatisfy { v in
                    if case .form(let tf) = v { return atomOf(field(tf, "done")) == "true" }
                    return false
                }
            if allDone { throw Err(msg: "phase \(idOf(f) ?? "?") is already done; reopen a task before removing one") }
            tasks.remove(at: idx)
            setField(&f, "tasks", .list(tasks))
            let errs = validateModified(store, kind: "phase", form: f)
            if !errs.isEmpty {
                errs.forEach { print($0) }
                return 1
            }
            try writeFile(u, canonical(f))
            try render(store)
            envelope("ok", "deleted nested task \(id)", ["file": u.lastPathComponent])
            return 0
        }
        throw Err(msg: "no nested task with id '\(id)'")
    }
}

do { exit(try run()) } catch let e as Err {
    fputs("write: \(e.msg)\n", stderr)
    exit(2)
} catch {
    fputs("write: \(error)\n", stderr)
    exit(2)
}
