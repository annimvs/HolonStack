// edit.swift — the exact-match file editor agents use for every change to a project file (rules/EDITING.md).
//   edit FILE --read                      print the file with line numbers, then its hash
//   edit FILE [--hash H] [--check] [--all] --old TEXT --new TEXT [--at LINE] [--after TEXT] [--before TEXT] [...]
//   edit FILE --batch-file F|-            a JSON array of {"old","new","at","after","before"}: no shell quoting
//   edit FILE --create (--content TEXT | --content-file F|-)
// Matching is by bytes, so non-UTF-8 text survives. A write goes through a temp file and a rename, keeps the file's
// permissions, and prints a unified diff and the new hash. Exit codes: 0 ok, 1 no match or I/O error, 2 ambiguous,
// 3 stale hash, 4 file exists (--create), 5 refused (binary or over the size limit), 64 usage. `edit --help` lists them.
import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

/// Files over this size are refused: they are not source an agent should edit through a shell argument.
let maxFileBytes = 8 * 1024 * 1024

// MARK: - Exit Codes
/// The exit statuses `edit` returns, fixed so hooks and agents can react to them.
enum ExitCode {
    static let noMatch: Int32 = 1
    static let ambiguous: Int32 = 2
    static let staleHash: Int32 = 3
    static let exists: Int32 = 4
    static let refused: Int32 = 5
    static let usage: Int32 = 64
}

// MARK: - Failure
/// A failed run: the message for standard error and the exit status, plus whether to repeat the usage lines.
struct EditFailure: Error {
    let code: Int32
    let message: String
    var showUsage = false
}

// MARK: - Output
/// Writes lines to standard output and standard error.
enum Output {
    /// Writes one line to standard output.
    static func line(_ text: String) { FileHandle.standardOutput.write(Data((text + "\n").utf8)) }

    /// Writes one line to standard error.
    static func error(_ text: String) { FileHandle.standardError.write(Data((text + "\n").utf8)) }
}

// MARK: - Editor Buffer
/// A file's bytes with exact-match search and replace, a content hash and a unified diff.
struct EditorBuffer {
    private(set) var bytes: [UInt8]

    /// Wraps the given bytes.
    init(bytes: [UInt8]) { self.bytes = bytes }

    /// Reads `path` fully, throwing an `EditFailure` that carries the errno text.
    static func read(path: String) throws -> EditorBuffer {
        guard let fp = fopen(path, "rb") else {
            throw EditFailure(code: ExitCode.noMatch, message: "\(path): \(String(cString: strerror(errno)))")
        }
        defer { fclose(fp) }
        var data = [UInt8]()
        var chunk = [UInt8](repeating: 0, count: 65536)
        while true {
            let count = fread(&chunk, 1, chunk.count, fp)
            if count > 0 { data.append(contentsOf: chunk[0..<count]) }
            if count < chunk.count {
                if ferror(fp) != 0 {
                    throw EditFailure(code: ExitCode.noMatch, message: "\(path): \(String(cString: strerror(errno)))")
                }
                break
            }
        }
        return EditorBuffer(bytes: data)
    }

    // MARK: Hash

    /// The FNV-1a 64-bit hash of the content as 16 lowercase hex digits; it only has to notice a changed file.
    var hash: String {
        var value: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in bytes { value = (value ^ UInt64(byte)) &* 0x100_0000_01b3 }
        let digits = String(value, radix: 16)
        return String(repeating: "0", count: 16 - digits.count) + digits
    }

    // MARK: Lines

    /// The lines without terminators; a trailing newline does not make an empty last line.
    var lines: [String] {
        var out: [String] = []
        var start = 0
        for (index, byte) in bytes.enumerated() where byte == 0x0A {
            out.append(String(decoding: bytes[start..<index], as: UTF8.self))
            start = index + 1
        }
        if start < bytes.count { out.append(String(decoding: bytes[start...], as: UTF8.self)) }
        return out
    }

    /// Byte offsets from the start of the first line to the end (after its newline) of the last line in `range`, or nil past the end.
    func byteWindow(lines range: ClosedRange<Int>) -> Range<Int>? {
        guard !bytes.isEmpty else { return nil }
        var starts = [0]
        for (index, byte) in bytes.enumerated() where byte == 0x0A && index + 1 < bytes.count {
            starts.append(index + 1)
        }
        guard range.upperBound <= starts.count else { return nil }
        let end = range.upperBound < starts.count ? starts[range.upperBound] : bytes.count
        return starts[range.lowerBound - 1]..<end
    }

    /// Replaces whole lines `range` with `new`, adding the newline the replaced lines had when `new` lacks one.
    mutating func replaceLines(_ range: ClosedRange<Int>, with new: [UInt8], path: String) throws {
        guard let window = byteWindow(lines: range) else {
            throw EditFailure(
                code: ExitCode.noMatch,
                message:
                    "\(path): --range \(range.lowerBound)-\(range.upperBound) is past the last line (\(lines.count))")
        }
        var text = new
        if !text.isEmpty, text.last != 0x0A, window.upperBound > 0, bytes[window.upperBound - 1] == 0x0A {
            text.append(0x0A)
        }
        bytes.replaceSubrange(window, with: text)
    }

    /// The 1-based line number that holds the byte at `offset`.
    func lineNumber(at offset: Int) -> Int {
        var line = 1
        for index in 0..<min(offset, bytes.count) where bytes[index] == 0x0A { line += 1 }
        return line
    }

    // MARK: Search and Replace

    /// Byte offsets of every non-overlapping occurrence of `needle` inside `range`, or the whole buffer.
    func matches(of needle: [UInt8], in range: Range<Int>? = nil) -> [Int] {
        let span = range ?? 0..<bytes.count
        guard !needle.isEmpty, span.count >= needle.count else { return [] }
        var found: [Int] = []
        var index = span.lowerBound
        let last = span.upperBound - needle.count
        while index <= last {
            if bytes[index] == needle[0] {
                var offset = 1
                while offset < needle.count, bytes[index + offset] == needle[offset] { offset += 1 }
                if offset == needle.count {
                    found.append(index)
                    index += needle.count
                    continue
                }
            }
            index += 1
        }
        return found
    }

    /// Replaces the occurrences at `offsets` (ascending, from `matches`), each `length` bytes long, with `new`.
    mutating func replace(offsets: [Int], length: Int, with new: [UInt8]) {
        var out = [UInt8]()
        out.reserveCapacity(bytes.count)
        var position = 0
        for offset in offsets {
            out.append(contentsOf: bytes[position..<offset])
            out.append(contentsOf: new)
            position = offset + length
        }
        out.append(contentsOf: bytes[position...])
        bytes = out
    }

    // MARK: Atomic Write

    /// Writes the bytes to `path` through a temp file in the same directory and a rename. It keeps the file's
    /// permissions and owner (when allowed) and follows a symlink, so the link itself survives.
    func writeAtomically(to path: String) throws {
        var target = path
        if let resolved = realpath(path, nil) {
            target = String(cString: resolved)
            free(resolved)
        }
        var info = stat()
        let existed = stat(target, &info) == 0
        let directory = (target as NSString).deletingLastPathComponent
        var template = Array(((directory.isEmpty ? "." : directory) + "/.edit.XXXXXX").utf8CString)
        let descriptor = mkstemp(&template)
        guard descriptor >= 0 else {
            throw EditFailure(
                code: ExitCode.noMatch,
                message: "\(path): cannot create a temporary file: \(String(cString: strerror(errno)))")
        }
        let temp = String(decoding: template.map { UInt8(bitPattern: $0) }.dropLast(), as: UTF8.self)
        do {
            try writeAll(to: descriptor)
            applyMode(of: info, existed: existed, to: descriptor)
            fsync(descriptor)
            close(descriptor)
        } catch {
            close(descriptor)
            unlink(temp)
            throw error
        }
        if rename(temp, target) != 0 {
            let why = String(cString: strerror(errno))
            unlink(temp)
            throw EditFailure(code: ExitCode.noMatch, message: "\(path): write failed: \(why)")
        }
    }

    /// Writes every byte to the descriptor, retrying an interrupted write.
    private func writeAll(to descriptor: Int32) throws {
        var offset = 0
        while offset < bytes.count {
            let written = bytes[offset...].withUnsafeBytes { pointer -> Int in
                #if canImport(Darwin)
                    return Darwin.write(descriptor, pointer.baseAddress, pointer.count)
                #elseif canImport(Glibc)
                    return Glibc.write(descriptor, pointer.baseAddress, pointer.count)
                #endif
            }
            if written < 0 {
                if errno == EINTR { continue }
                throw EditFailure(code: ExitCode.noMatch, message: "write failed: \(String(cString: strerror(errno)))")
            }
            offset += written
        }
    }

    /// Gives the temp file the original's owner and mode, or the default mode (the umask applied) for a new file.
    private func applyMode(of info: stat, existed: Bool, to descriptor: Int32) {
        if existed {
            _ = fchown(descriptor, info.st_uid, info.st_gid)
            fchmod(descriptor, info.st_mode & 0o7777)
        } else {
            // umask can only be read by setting it, so set it back at once.
            let mask = umask(0)
            umask(mask)
            fchmod(descriptor, 0o666 & ~mask)
        }
    }
}

// MARK: - Unified Diff
/// One step of a line diff: a line kept in both versions (old and new index), deleted from the old, or added to the new.
enum DiffOp {
    case keep(Int, Int)
    case del(Int)
    case add(Int)
}

extension EditorBuffer {
    /// The unified diff from `old` to this buffer, three lines of context, or an empty string when the lines match.
    func unifiedDiff(from old: EditorBuffer, path: String) -> String {
        let before = old.lines
        let after = lines
        let ops = Self.diffOps(old: before, new: after)
        return Self.render(ops: ops, old: before, new: after, path: path, context: 3)
    }

    /// Turns two line lists into diff steps: the shared prefix and suffix are kept, and the changed middle gets a
    /// longest-common-subsequence table (or a plain delete-then-add when the table would pass four million cells).
    static func diffOps(old: [String], new: [String]) -> [DiffOp] {
        var prefix = 0
        while prefix < old.count, prefix < new.count, old[prefix] == new[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < old.count - prefix, suffix < new.count - prefix,
            old[old.count - 1 - suffix] == new[new.count - 1 - suffix]
        {
            suffix += 1
        }
        let a = Array(old[prefix..<(old.count - suffix)])
        let b = Array(new[prefix..<(new.count - suffix)])
        if a.isEmpty && b.isEmpty { return [] }
        var ops: [DiffOp] = (0..<prefix).map { .keep($0, $0) }
        if a.count * b.count <= 4_000_000 {
            let width = b.count + 1
            var table = [Int32](repeating: 0, count: (a.count + 1) * width)
            for i in stride(from: a.count - 1, through: 0, by: -1) {
                for j in stride(from: b.count - 1, through: 0, by: -1) {
                    table[i * width + j] =
                        a[i] == b[j]
                        ? table[(i + 1) * width + j + 1] + 1 : max(table[(i + 1) * width + j], table[i * width + j + 1])
                }
            }
            var i = 0
            var j = 0
            while i < a.count || j < b.count {
                if i < a.count, j < b.count, a[i] == b[j] {
                    ops.append(.keep(prefix + i, prefix + j))
                    i += 1
                    j += 1
                } else if i < a.count, j == b.count || table[(i + 1) * width + j] >= table[i * width + j + 1] {
                    ops.append(.del(prefix + i))
                    i += 1
                } else {
                    ops.append(.add(prefix + j))
                    j += 1
                }
            }
        } else {
            ops += (0..<a.count).map { .del(prefix + $0) } + (0..<b.count).map { .add(prefix + $0) }
        }
        for k in 0..<suffix { ops.append(.keep(old.count - suffix + k, new.count - suffix + k)) }
        return ops
    }

    /// Groups the changed steps with `context` lines around them into `@@` hunks and prints them under a file header.
    static func render(ops: [DiffOp], old: [String], new: [String], path: String, context: Int) -> String {
        let changed = ops.indices.filter { if case .keep = ops[$0] { return false } else { return true } }
        if changed.isEmpty { return "" }
        var out = "--- \(path)\n+++ \(path)\n"
        var index = 0
        while index < changed.count {
            let low = max(0, changed[index] - context)
            var high = min(ops.count - 1, changed[index] + context)
            index += 1
            while index < changed.count, changed[index] - context <= high + 1 {
                high = min(ops.count - 1, changed[index] + context)
                index += 1
            }
            out += hunk(ops[low...high], old: old, new: new)
        }
        return out
    }

    /// Prints one hunk: its `@@ -a,b +c,d @@` header, then each step as a context, `-` or `+` line.
    static func hunk(_ steps: ArraySlice<DiffOp>, old: [String], new: [String]) -> String {
        var oldStart = 0
        var newStart = 0
        var oldCount = 0
        var newCount = 0
        var body = ""
        var first = true
        // The first step decides where both ranges start; a pure add or delete borrows the other side's position
        // from the nearest kept or opposite step, falling back to the end of that file.
        let firstOld =
            steps.compactMap { step -> Int? in
                if case .keep(let o, _) = step { return o }
                if case .del(let o) = step { return o }
                return nil
            }.first ?? old.count
        let firstNew =
            steps.compactMap { step -> Int? in
                if case .keep(_, let n) = step { return n }
                if case .add(let n) = step { return n }
                return nil
            }.first ?? new.count
        for step in steps {
            switch step {
            case .keep(let o, let n):
                if first {
                    oldStart = o
                    newStart = n
                }
                oldCount += 1
                newCount += 1
                body += " \(old[o])\n"
            case .del(let o):
                if first {
                    oldStart = o
                    newStart = firstNew
                }
                oldCount += 1
                body += "-\(old[o])\n"
            case .add(let n):
                if first {
                    newStart = n
                    oldStart = firstOld
                }
                newCount += 1
                body += "+\(new[n])\n"
            }
            first = false
        }
        /// Prints a hunk range as unified diff does: a single line as `n`, an empty range at its start, else `n,count`.
        func range(_ start: Int, _ count: Int) -> String {
            count == 1 ? "\(start + 1)" : "\(count == 0 ? start : start + 1),\(count)"
        }
        return "@@ -\(range(oldStart, oldCount)) +\(range(newStart, newCount)) @@\n" + body
    }
}

// MARK: - Options
/// One replacement: the text to find, its replacement, and the optional narrowing by line or by surrounding text.
struct EditBlock {
    var old: [UInt8]?
    var new: [UInt8]?
    var at: Int?
    var after: [UInt8]?
    var before: [UInt8]?
}

// MARK: - Options
/// What the command line asked for.
struct Options {
    var file: String?
    var read = false
    var check = false
    var all = false
    var create = false
    var hash: String?
    var range: ClosedRange<Int>?
    var rangeNew: [UInt8]?
    var delete = false
    var content: [UInt8]?
    var edits: [EditBlock] = []
}

// MARK: - Argument Parser
/// Reads the command line into `Options`, taking text from files or standard input where asked.
struct ArgumentParser {
    private(set) var options = Options()
    private var stdinUsed = false
    private let args: [String]
    private var index = 0

    /// Starts a parser over the arguments after the program name.
    init(_ args: [String]) { self.args = args }

    /// Parses every argument, throwing a usage failure for anything it cannot read.
    mutating func parse() throws -> Options {
        while index < args.count {
            let argument = args[index]
            switch argument {
            case "--read": options.read = true
            case "--check": options.check = true
            case "--all": options.all = true
            case "--create": options.create = true
            case "--content": options.content = Array(try value(for: argument, "TEXT").utf8)
            case "--content-file":
                options.content = try slurp(try value(for: argument, "FILE (or - for standard input)"))
            case "--batch-file": try parseBatch(try slurp(try value(for: argument, "FILE (or - for standard input)")))
            case "--hash": options.hash = try value(for: argument, "HASH")
            case "--delete": options.delete = true
            case "--range": options.range = try parseRange(try value(for: argument, "A-B (1-based, inclusive)"))
            default: try parseEditFlag(argument)
            }
            index += 1
        }
        return options
    }

    /// The argument after `flag`, or a usage failure that names what the flag needs.
    private mutating func value(for flag: String, _ what: String) throws -> String {
        index += 1
        guard index < args.count else { throw usage("\(flag) needs \(what)") }
        return args[index]
    }

    /// Handles the flags that build or narrow a replacement, and the file operand.
    private mutating func parseEditFlag(_ argument: String) throws {
        switch argument {
        case "--old": options.edits.append(EditBlock(old: Array(try value(for: argument, "TEXT").utf8)))
        case "--old-file": options.edits.append(EditBlock(old: try slurp(try value(for: argument, "FILE"))))
        // The value is read before `lastEdit` starts: its closure runs while `self` is being modified.
        case "--new":
            let text = Array(try value(for: argument, "TEXT").utf8)
            if options.edits.isEmpty {
                options.rangeNew = text
                break
            }
            try lastEdit(argument) { $0.new = text }
        case "--new-file":
            let bytes = try slurp(try value(for: argument, "FILE"))
            if options.edits.isEmpty {
                options.rangeNew = bytes
                break
            }
            try lastEdit(argument) { $0.new = bytes }
        case "--at":
            let text = try value(for: argument, "a 1-based LINE number")
            guard let line = Int(text), line > 0 else { throw usage("--at needs a 1-based LINE number") }
            try lastEdit(argument) { $0.at = line }
        case "--after":
            let text = Array(try value(for: argument, "TEXT").utf8)
            try lastEdit(argument) { $0.after = text }
        case "--before":
            let text = Array(try value(for: argument, "TEXT").utf8)
            try lastEdit(argument) { $0.before = text }
        default:
            if argument.hasPrefix("-") { throw usage("unknown flag '\(argument)'") }
            if options.file != nil {
                throw usage("unexpected argument '\(argument)' (edit operates on one file at a time)")
            }
            options.file = argument
        }
    }

    /// Applies `change` to the most recent `--old`, or fails when the flag came before any `--old`.
    private mutating func lastEdit(_ flag: String, _ change: (inout EditBlock) throws -> Void) throws {
        guard !options.edits.isEmpty else { throw usage("\(flag) without --old") }
        try change(&options.edits[options.edits.count - 1])
    }

    /// Adds the replacements in a JSON array of objects with string `old` and `new`, and optional `at`, `after`, `before`.
    private mutating func parseBatch(_ data: [UInt8]) throws {
        let parsed: Any
        do { parsed = try JSONSerialization.jsonObject(with: Data(data)) } catch {
            throw usage("--batch-file: not valid JSON: \(error.localizedDescription)")
        }
        guard let items = parsed as? [[String: Any]] else {
            throw usage("--batch-file: expected a JSON array of objects with \"old\" and \"new\"")
        }
        for (number, item) in items.enumerated() {
            guard let old = item["old"] as? String, let new = item["new"] as? String else {
                throw usage("--batch-file: item \(number + 1) needs string \"old\" and \"new\"")
            }
            var block = EditBlock(old: Array(old.utf8), new: Array(new.utf8))
            if let at = item["at"] as? Int, at > 0 { block.at = at }
            if let after = item["after"] as? String { block.after = Array(after.utf8) }
            if let before = item["before"] as? String { block.before = Array(before.utf8) }
            options.edits.append(block)
        }
    }

    /// Reads a file, or standard input for `-` (once per run).
    private mutating func slurp(_ path: String) throws -> [UInt8] {
        guard path == "-" else { return try EditorBuffer.read(path: path).bytes }
        guard !stdinUsed else {
            throw EditFailure(code: ExitCode.noMatch, message: "-: standard input already consumed")
        }
        stdinUsed = true
        return [UInt8](FileHandle.standardInput.readDataToEndOfFile())
    }

    /// A usage failure with the given message.
    private func usage(_ message: String) -> EditFailure {
        EditFailure(code: ExitCode.usage, message: message, showUsage: true)
    }

    /// Reads `A-B` (1-based, inclusive) into a line range.
    private func parseRange(_ text: String) throws -> ClosedRange<Int> {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2, let low = Int(parts[0]), let high = Int(parts[1]), low > 0, high >= low else {
            throw usage("--range needs A-B, 1-based and inclusive, such as 12-30")
        }
        return low...high
    }
}

// MARK: - Commands
/// The three things `edit` does with a file: print it, create it, or change it.
enum Commands {
    /// Runs the command the options ask for and returns the exit status.
    static func run(_ options: Options) throws -> Int32 {
        guard let path = options.file else { throw usageFailure("missing FILE") }
        if options.content != nil && !options.create {
            throw usageFailure("--content and --content-file need --create")
        }
        if options.create { return try create(path, options) }
        let rangeEdit = options.range != nil && (options.rangeNew != nil || options.delete)
        if rangeEdit && (!options.edits.isEmpty || options.read) {
            throw usageFailure(
                "--range with --new or --delete replaces whole lines; it cannot be combined with --old or --read")
        }
        if (options.rangeNew != nil || options.delete) && options.range == nil {
            throw usageFailure("--new without --old, and --delete, need --range A-B")
        }
        if options.rangeNew != nil && options.delete { throw usageFailure("--delete and --new are exclusive") }
        if !options.read && options.edits.isEmpty && !rangeEdit {
            throw usageFailure("nothing to do (pass --read, --old TEXT --new TEXT, or --range A-B --new TEXT)")
        }
        for (number, edit) in options.edits.enumerated() {
            let label = options.edits.count > 1 ? " (edit \(number + 1))" : ""
            if edit.old == nil { throw usageFailure("incomplete edit: missing --old\(label)") }
            if edit.new == nil { throw usageFailure("incomplete edit: missing --new\(label)") }
        }
        if options.read && !options.edits.isEmpty { throw usageFailure("--read cannot be combined with edits") }
        let original = try EditorBuffer.read(path: path)
        try refuseUnsuitable(original.bytes, path: path)
        if options.read { return printFile(original, range: options.range) }
        return try change(original, path: path, options: options)
    }

    /// A usage failure with the given message.
    private static func usageFailure(_ message: String) -> EditFailure {
        EditFailure(code: ExitCode.usage, message: message, showUsage: true)
    }

    /// Fails with exit 5 for a file over the size limit or one holding a NUL byte (binary).
    private static func refuseUnsuitable(_ bytes: [UInt8], path: String) throws {
        if bytes.count > maxFileBytes {
            throw EditFailure(
                code: ExitCode.refused,
                message: "\(path): \(bytes.count) bytes is over the \(maxFileBytes) byte limit; use another tool")
        }
        if bytes.prefix(8192).contains(0) {
            throw EditFailure(
                code: ExitCode.refused, message: "\(path): binary file (contains a NUL byte); use another tool")
        }
    }

    // MARK: Read

    /// Prints each line with its number, then the hash a later `--hash` can check.
    private static func printFile(_ buffer: EditorBuffer, range: ClosedRange<Int>? = nil) -> Int32 {
        for (number, line) in buffer.lines.enumerated() where range?.contains(number + 1) ?? true {
            Output.line("\(number + 1)\t\(line)")
        }
        Output.line("hash: \(buffer.hash)")
        return 0
    }

    // MARK: Create

    /// Makes a new file (and its folders) from the content, never overwriting; `--check` only says what it would do.
    private static func create(_ path: String, _ options: Options) throws -> Int32 {
        guard options.edits.isEmpty, !options.read else {
            throw usageFailure("--create cannot be combined with --read or --old/--new")
        }
        guard let data = options.content else {
            throw usageFailure("--create needs --content TEXT or --content-file F")
        }
        var info = stat()
        if lstat(path, &info) == 0 {
            throw EditFailure(
                code: ExitCode.exists,
                message: "\(path): already exists (--create never overwrites; edit it with --old/--new)")
        }
        try refuseUnsuitable(data, path: path)
        let buffer = EditorBuffer(bytes: data)
        if options.check {
            Output.line("would create \(path) (\(buffer.lines.count) lines)")
            return 0
        }
        let directory = (path as NSString).deletingLastPathComponent
        if !directory.isEmpty {
            do { try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true) } catch {
                throw EditFailure(
                    code: ExitCode.noMatch,
                    message: "\(directory): cannot create directory: \(error.localizedDescription)")
            }
        }
        try buffer.writeAtomically(to: path)
        Output.line("created: \(path) (\(buffer.lines.count) lines)")
        Output.line("hash: \(buffer.hash)")
        return 0
    }

    // MARK: Change

    /// Applies every replacement in order to a copy, prints the diff, and writes the result unless `--check`.
    /// A failed replacement leaves the file untouched, so a batch is all or nothing.
    private static func change(_ original: EditorBuffer, path: String, options: Options) throws -> Int32 {
        if let expected = options.hash, expected.count < 6 || !original.hash.hasPrefix(expected) {
            throw EditFailure(
                code: ExitCode.staleHash,
                message: "\(path): hash mismatch: file changed (expected \(expected), current \(original.hash))")
        }
        var buffer = original
        if let range = options.range, options.rangeNew != nil || options.delete {
            try buffer.replaceLines(range, with: options.rangeNew ?? [], path: path)
        }
        for (number, edit) in options.edits.enumerated() {
            let label = options.edits.count > 1 ? " (edit \(number + 1))" : ""
            try apply(edit, to: &buffer, path: path, label: label, all: options.all, range: options.range)
        }
        if buffer.bytes == original.bytes {
            Output.line("\(path): no change (replacement equals original)")
            return 0
        }
        let diff = buffer.unifiedDiff(from: original, path: path)
        Output.line(diff.isEmpty ? "(only the trailing newline changed)" : String(diff.dropLast()))
        if options.check { return 0 }
        try buffer.writeAtomically(to: path)
        Output.line("hash: \(buffer.hash)")
        return 0
    }

    /// Finds the replacement's matches (inside the `--after`/`--before` window, on the `--at` line), requires exactly
    /// one unless `all`, and replaces it. An ambiguous match lists each candidate with a line of context.
    private static func apply(
        _ edit: EditBlock, to buffer: inout EditorBuffer, path: String, label: String, all: Bool,
        range: ClosedRange<Int>?
    ) throws {
        let old = edit.old ?? []
        var low = 0
        var high = buffer.bytes.count
        if let range {
            guard let window = buffer.byteWindow(lines: range) else {
                throw EditFailure(
                    code: ExitCode.noMatch,
                    message: "\(path): --range \(range.lowerBound)-\(range.upperBound) is past the last line")
            }
            low = window.lowerBound
            high = window.upperBound
        }
        if let after = edit.after {
            guard let position = buffer.matches(of: after, in: low..<max(low, high)).first else {
                throw EditFailure(code: ExitCode.noMatch, message: "\(path): no match for --after\(label)")
            }
            low = max(low, position + after.count)
        }
        if let before = edit.before {
            guard let position = buffer.matches(of: before, in: low..<max(low, high)).first else {
                throw EditFailure(code: ExitCode.noMatch, message: "\(path): no match for --before\(label)")
            }
            high = position
        }
        var found = buffer.matches(of: old, in: low..<max(low, high))
        if let line = edit.at { found = found.filter { buffer.lineNumber(at: $0) == line } }
        if found.isEmpty { throw EditFailure(code: ExitCode.noMatch, message: "\(path): no match for --old\(label)") }
        if found.count > 1 && !all { throw ambiguous(found, in: buffer, path: path, label: label) }
        buffer.replace(offsets: found, length: old.count, with: edit.new ?? [])
    }

    /// The failure for several matches: how many, and each one's line with its neighbours.
    private static func ambiguous(_ offsets: [Int], in buffer: EditorBuffer, path: String, label: String) -> EditFailure
    {
        var text =
            "\(path): \(offsets.count) matches for --old\(label), need exactly one (narrow with --at, --after, --before, or use --all):"
        let lines = buffer.lines
        for offset in offsets {
            let line = buffer.lineNumber(at: offset)
            text += "\n  line \(line):"
            for number in max(1, line - 1)...min(lines.count, line + 1) {
                text += "\n  \(number == line ? ">" : " ")\(number)\t\(lines[number - 1])"
            }
        }
        return EditFailure(code: ExitCode.ambiguous, message: text)
    }
}

// MARK: - Main
/// The text `edit --help` prints.
let helpText = """
    usage:
      edit FILE --read                       print the file with line numbers, then its hash
      edit FILE [--hash H] [--check] [--all] --old TEXT --new TEXT [--at LINE] [--after TEXT] [--before TEXT] [--old ... --new ...]
      edit FILE --hash H --range A-B (--new TEXT | --new-file F | --delete)   replace or remove whole lines A to B
      edit FILE --batch-file F|-             a JSON array of {"old","new","at","after","before"}: no shell quoting needed
      edit FILE --create (--content TEXT | --content-file F|-)   make a new file; refuses to overwrite
    options:
      --old-file F / --new-file F            take the text from a file, or `-` for standard input
      --hash H        refuse (exit 3) unless the file still has the hash `--read` or a previous edit printed
      --check         print the diff and write nothing
      --all           replace every match, not just a single one
      --at LINE       only the match that starts on line LINE (1-based)
      --after / --before TEXT   only a match after the first TEXT, or before the first TEXT
      --range A-B     lines A to B (1-based, inclusive): with --read print only them; with --old search only them; alone with --new or --delete replace or remove them
    exit codes: 0 ok, 1 no match or I/O error, 2 ambiguous (matches listed), 3 stale hash, 4 file exists (--create),
                5 refused (binary file, or over \(maxFileBytes) bytes), 64 usage
    """

/// The usage lines printed after a usage failure.
let usageText = """
    usage: edit FILE (--read | [--hash H] [--check] [--all] --old TEXT|--old-file F --new TEXT|--new-file F [--at LINE] [--after TEXT] [--before TEXT] ...)
           edit FILE --batch-file F|-  |  edit FILE --create (--content TEXT | --content-file F|-)  |  edit --help
    """

/// Parses the command line, runs the command, and turns a failure into its message and exit status.
func runEdit(_ args: [String]) -> Int32 {
    guard let first = args.first else {
        Output.error("edit: missing FILE")
        Output.error(usageText)
        return ExitCode.usage
    }
    if first == "--help" || first == "-h" {
        Output.line(helpText)
        return 0
    }
    do {
        var parser = ArgumentParser(args)
        return try Commands.run(try parser.parse())
    } catch let failure as EditFailure {
        Output.error("edit: \(failure.message)")
        if failure.showUsage { Output.error(usageText) }
        return failure.code
    } catch {
        Output.error("edit: \(error.localizedDescription)")
        return ExitCode.noMatch
    }
}

exit(runEdit(Array(CommandLine.arguments.dropFirst())))
