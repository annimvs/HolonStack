// Claude Code PreToolUse(Bash): deterministic mutation guard.
// Exit 2 (reason on stderr) blocks the call. Escape hatch: the user runs the command themselves.
// Project-specific rules are data: each `.agents/harness/guards.d/*.json` is {"pattern": <regex>, "message": <reason>}
// (or an array of those), tested against the whole command.
import Foundation

let environment = ProcessInfo.processInfo.environment
let proj = environment["CLAUDE_PROJECT_DIR"] ?? FileManager.default.currentDirectoryPath

// lint-ignore: no-unsafe-sendable: a hook reads its one input at start-up and only this single thread ever uses it
nonisolated(unsafe) let rawInput =
    (try? JSONSerialization.jsonObject(with: FileHandle.standardInput.readDataToEndOfFile()) as? [String: Any]) ?? [:]
let isGemini = rawInput["hookEventName"] != nil

/// Prints the block reason to stderr and exits with status 2 for Claude Code, or prints a deny JSON decision for
/// Antigravity and exits 0. Never returns.
func deny(_ reason: String) -> Never {
    let message = "BLOCKED by .agents/harness/hooks/guard-bash.swift: \(reason)"
    if isGemini {
        let reply: [String: Any] = ["decision": "deny", "reason": message]
        if let data = try? JSONSerialization.data(withJSONObject: reply, options: [.sortedKeys]) {
            FileHandle.standardOutput.write(data)
            print()
        }
        exit(0)
    }
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}

/// Tests a regular expression against a string.
/// Takes the pattern and the text; returns true when the pattern matches anywhere in the text, and false for an invalid pattern.
func matches(_ pattern: String, _ s: String) -> Bool {
    guard let re = try? NSRegularExpression(pattern: pattern) else { return false }
    return re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
}

let toolInput =
    (rawInput["tool_input"] as? [String: Any])
    ?? ((rawInput["toolCall"] as? [String: Any])?["args"] as? [String: Any]) ?? [:]
guard let cmd = (toolInput["command"] as? String) ?? (toolInput["CommandLine"] as? String), !cmd.isEmpty else {
    if isGemini { print("{\"decision\":\"allow\"}") }
    exit(0)
}

// MARK: - Destructive git
// ── destructive git ───────────────────────────────────────────────────────────
// Global options sit between `git` and the subcommand (`git -c k=v reset --hard`); drop them before matching.
let gitCmd = cmd.replacingOccurrences(
    of:
        #"git([[:space:]]+(-[cC][[:space:]]+[^[:space:]]+|--(git-dir|work-tree|namespace)(=|[[:space:]]+)[^[:space:]]+|--no-pager|-P|--bare))+"#,
    with: "git", options: .regularExpression)
let gitRules: [(String, String)] = [
    (
        #"git[[:space:]]+(-C[[:space:]]+[^[:space:]]+[[:space:]]+)?reset[[:space:]].*--hard"#,
        "git reset --hard discards uncommitted work"
    ),
    (
        #"git[[:space:]]+checkout[[:space:]]+(--[[:space:]]+)?\.([[:space:]]|$)"#,
        "git checkout . discards working-tree changes"
    ),
    (#"git[[:space:]]+clean[[:space:]]+-[a-zA-Z]*[fdx]"#, "git clean deletes untracked files"),
    (#"git[[:space:]]+stash[[:space:]]+(drop|clear)"#, "git stash drop/clear is unrecoverable"),
    (
        #"git[[:space:]]+push[[:space:]]+(.*[[:space:]])?(--force|-[a-zA-Z]*f[a-zA-Z]*([[:space:]]|$)|\+[^[:space:]])"#,
        "force push (--force, -f or a +refspec)"
    ),
    (#"git[[:space:]]+push[[:space:]]+(.*[[:space:]])?--delete"#, "git push --delete removes a remote branch"),
    (#"git[[:space:]]+branch[[:space:]]+-D"#, "git branch -D"),
]
for (pattern, why) in gitRules where matches(pattern, gitCmd) { deny(why) }
if matches(#"git[[:space:]]+restore[[:space:]]+([^|;&]*[[:space:]])?\.([[:space:]]|$)"#, gitCmd),
    !cmd.contains("--staged")
{
    deny("git restore . discards working-tree changes")
}

// MARK: - Recursive delete and word parsing
// ── recursive rm is allowed only on build output / scratch ────────────────────
func shellWords(_ s: String) -> [String] {
    var words: [String] = []
    var cur = ""
    var inWord = false
    var quote: Character? = nil
    var it = s.makeIterator()
    /// Ends the current word and appends it to `words` if a word is open.
    func flush() {
        if inWord {
            words.append(cur)
            cur = ""
            inWord = false
        }
    }
    while let c = it.next() {
        if let q = quote {
            if c == q { quote = nil } else { cur.append(c) }
        } else if c == "'" || c == "\"" {
            quote = c
            inWord = true
        } else if c == "\\" {
            if let n = it.next() {
                cur.append(n)
                inWord = true
            }
        } else if c == " " || c == "\t" || c == "\n" || c == ";" || c == "&" || c == "|" || c == "(" || c == ")" {
            flush()
        } else {
            cur.append(c)
            inWord = true
        }
    }
    flush()
    return words
}
/// The command's simple commands, each as its words: split at `;`, `&`, `|`, newlines and parentheses outside quotes.
/// A rule about one command (`sed -i`, `dd`) looks only at that command's words, not at every word on the line.
func shellSegments(_ s: String) -> [[String]] {
    var segs: [[String]] = []
    var words: [String] = []
    var cur = ""
    var inWord = false
    var quote: Character? = nil
    var it = s.makeIterator()
    /// Ends the current word and appends it to `words` if a word is open.
    func flush() {
        if inWord {
            words.append(cur)
            cur = ""
            inWord = false
        }
    }
    /// Ends the current word, then saves the words so far as one simple command when there are any.
    func cut() {
        flush()
        if !words.isEmpty {
            segs.append(words)
            words = []
        }
    }
    while let c = it.next() {
        if let q = quote {
            if c == q { quote = nil } else { cur.append(c) }
        } else if c == "'" || c == "\"" {
            quote = c
            inWord = true
        } else if c == "\\" {
            if let n = it.next() {
                cur.append(n)
                inWord = true
            }
        } else if c == ";" || c == "&" || c == "|" || c == "\n" || c == "(" || c == ")" {
            cut()
        } else if c == " " || c == "\t" {
            flush()
        } else {
            cur.append(c)
            inWord = true
        }
    }
    cut()
    return segs
}

let home = environment["HOME"] ?? NSHomeDirectory()
let tmpTrim = (environment["TMPDIR"] ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))

/// `~`, `$HOME` and `${HOME}` as the shell would expand them.
func expand(_ w: String) -> String {
    if w == "~" || w.hasPrefix("~/") { return home + w.dropFirst() }
    for v in ["${HOME}", "$HOME"] where w.hasPrefix(v) { return home + w.dropFirst(v.count) }
    return w
}
/// Build output and scratch: the only places a recursive delete may reach.
func isDisposable(_ w: String) -> Bool {
    let w = expand(w)
    let buildDirs = [".build", "build", "builddir", "target", "dist", ".next", "__pycache__"]
    for dir in buildDirs {
        if w == dir || w.hasPrefix(dir + "/") || w == "./" + dir || w.hasPrefix("./" + dir + "/")
            || w.contains("/" + dir + "/")
        {
            return true
        }
    }
    if w.hasPrefix("/private/tmp/") || w.hasPrefix("/tmp/") { return true }
    return !tmpTrim.isEmpty && w.hasPrefix("/" + tmpTrim + "/")
}
/// Checks whether a path is inside the project, the build output or the scratch folder, so a write there is allowed.
/// Takes the path as written in the command; returns true when it is inside one of those places.
func isInsideProject(_ w: String) -> Bool {
    let w = expand(w)
    // the project root itself counts, with or without a trailing slash
    let root = w.hasSuffix("/") && w.count > 1 ? String(w.dropLast()) : w
    return w.hasPrefix("/dev/") || isDisposable(w) || root == proj || root == realProjPath || w.hasPrefix(proj + "/")
        || w.hasPrefix(realProjPath + "/")
}
let realProjPath = URL(fileURLWithPath: proj).resolvingSymlinksInPath().path

if matches(#"(^|[;&|(`[:space:]])rm[[:space:]]+(-[a-zA-Z]*[rR][a-zA-Z]*|--recursive)"#, cmd) {
    let bad = shellWords(cmd).filter { w in !(w.hasPrefix("-") || w == "rm" || isDisposable(w)) }
    if !bad.isEmpty { deny("recursive rm outside .build/ and scratch: \(bad.prefix(3).joined(separator: " "))") }
}
// find -delete / -exec rm and scripting-language recursive deletes are the same thing spelled differently.
if matches(#"(^|[;&|(`[:space:]])find[[:space:]].*(-delete|-exec(dir)?[[:space:]]+(/bin/)?rm)"#, cmd) {
    let bad = shellWords(cmd).drop { $0 != "find" }.dropFirst().prefix { !$0.hasPrefix("-") && $0 != "(" && $0 != "!" }
        .filter { !isDisposable($0) }
    if !bad.isEmpty {
        deny("find -delete/-exec rm outside .build/ and scratch: \(bad.prefix(3).joined(separator: " "))")
    }
}
if matches(#"(rmtree|removeItem|FileUtils\.rm_rf?|File\.delete|os\.remove)"#, cmd), !cmd.contains(".build"),
    !cmd.contains("/tmp/")
{
    deny("recursive delete from a script; delete with rm -r on .build/ or scratch only")
}
// In-place editors, dd and truncate write to the paths they name: keep those inside the project.
if matches(
    #"(^|[;&|(`[:space:]])(sed[[:space:]]+(-[a-zA-Z]*i|--in-place)|perl[[:space:]]+-[a-zA-Z]*i|truncate[[:space:]]|dd[[:space:]])"#,
    cmd)
{
    // only the words of the in-place command itself: a path or a `//` comment in another command on the line is not its target
    let editors = shellSegments(cmd).filter { seg in
        guard let i = seg.firstIndex(where: { !$0.contains("=") || $0.hasPrefix("-") }) else { return false }
        let rest = seg[seg.index(after: i)...]
        switch seg[i] {
        case "sed": return rest.contains { matches(#"^(-[a-zA-Z]*i.*|--in-place.*)$"#, $0) }
        case "perl": return rest.contains { matches(#"^-[a-zA-Z]*i"#, $0) }
        case "truncate", "dd": return true
        default: return false
        }
    }
    let bad = editors.flatMap { $0.dropFirst() }.compactMap { w -> String? in
        let t = w.hasPrefix("of=") ? String(w.dropFirst(3)) : w
        let e = expand(t)
        // A sed address like `/foo/d` also starts with `/`: only count words whose parent directory exists.
        let parent = (e as NSString).deletingLastPathComponent
        let isPath =
            (e.hasPrefix("/") && FileManager.default.fileExists(atPath: parent)) || t.hasPrefix("~")
            || t.hasPrefix("$HOME")
        return isPath && !isInsideProject(t) ? t : nil
    }
    if !bad.isEmpty { deny("in-place edit outside the project: \(bad.prefix(3).joined(separator: " "))") }
}

// MARK: - Redirects and tee
// ── redirects / tee to absolute paths outside the project and scratch ─────────
let realProj = URL(fileURLWithPath: proj).resolvingSymlinksInPath().path
let tmpDir =
    (environment["TMPDIR"] ?? "").hasSuffix("/")
    ? String((environment["TMPDIR"] ?? "").dropLast()) : (environment["TMPDIR"] ?? "")
/// Drops heredoc bodies (`<< 'DELIM' ... DELIM`) so text inside data payloads is not misread as shell redirects.
func stripHeredocBodies(_ command: String) -> String {
    guard let startRe = try? NSRegularExpression(pattern: #"<<-?[[:space:]]*['\"]?([A-Za-z_][A-Za-z0-9_]*)['\"]?"#)
    else { return command }
    var kept: [String] = []
    var delimiter: String? = nil
    for line in command.components(separatedBy: "\n") {
        if let delim = delimiter {
            if line.trimmingCharacters(in: .whitespaces) == delim { delimiter = nil }
            continue
        }
        kept.append(line)
        let range = NSRange(line.startIndex..., in: line)
        if let match = startRe.firstMatch(in: line, range: range), let r = Range(match.range(at: 1), in: line) {
            delimiter = String(line[r])
        }
    }
    return kept.joined(separator: "\n")
}
let redirectCmd = stripHeredocBodies(cmd)
if let re = try? NSRegularExpression(pattern: #"(>>?|tee( -a)?)[[:space:]]*((/|~|\$HOME|\$\{HOME\})[^[:space:];&|)]*)"#)
{
    for m in re.matches(in: redirectCmd, range: NSRange(redirectCmd.startIndex..., in: redirectCmd)) {
        guard let r = Range(m.range(at: 3), in: redirectCmd) else { continue }
        let t = String(redirectCmd[r])
        if !isInsideProject(t) && !(!tmpDir.isEmpty && expand(t).hasPrefix(tmpDir + "/")) {
            deny("write outside the project: \(t)")
        }
    }
}

// MARK: - Signals and Keychain
// ── broadcast signals ─────────────────────────────────────────────────────────
// `kill -9 -1` / `kill -- -1` signal every process you own; `-1` right after a signal option is the pid, while
// `kill -1 1234` is just SIGHUP to 1234 and stays allowed. killall and pkill match by name across the machine.
if matches(
    #"(^|[;&|(`[:space:]])kill[[:space:]]+((-s[[:space:]]+[A-Za-z0-9]+|-[^[:space:]]+)[[:space:]]+)+-1([[:space:]]|$)"#,
    cmd)
{
    deny("kill -1 signals every process you own (broadcast); name the pids")
}
if matches(#"(^|[;&|(`[:space:]])(killall|pkill)[[:space:]]"#, cmd) {
    deny("killall/pkill signal by name across the machine; find the pids and kill them by number")
}

// ── Keychain ──────────────────────────────────────────────────────────────────
if matches(#"(^|[;&|[:space:]])security[[:space:]]+[^|;&]*(keychain|-password|find-|add-|delete-|import|export)"#, cmd)
{
    deny("Keychain access")
}

// MARK: - Record files
// ── record files: only `write` changes them; templates and reasons only the user ─
// This looks at what each command writes to (redirect targets, `tee`, `rm`, `mv`, `truncate`, `dd of=`, the destination of
// `cp`/`install`/`ln`, and the file operands of `sed -i`/`perl -i`), not at every word, so a script that only mentions a
// record path passes. A target built in a variable is not seen.
let protectedPath =
    #"(^|/)\.agents/(records/(PLAN\.closure|PLAN\.md|TODO\.closure|TODO\.md|MEMORY\.md|OPEN\.md|BUGS\.md|PROPOSALS\.md|SEMANTICS\.md|\.ids|\.write\.lock)$|harness/reasons\.closure$|harness/lint\.closure$|harness/templates(/|$))"#
let redirect = #"^[0-9]*>>?"#
/// The flags of `tools/edit.swift` that take a value, so the value is not mistaken for the file operand.
let editValueFlags: Set<String> = [
    "--old", "--new", "--old-file", "--new-file", "--at", "--after", "--before",
    "--hash", "--content", "--content-file", "--batch-file",
]
/// Finds the file an `edit` call changes: its first operand that is not a flag or a flag's value.
/// Takes the command's words after `edit`; returns nil for `--read` (no write) or when no file is named.
func editFileOperand(_ words: [String]) -> String? {
    if words.contains("--read") { return nil }
    var skipNext = false
    for word in words {
        if skipNext {
            skipNext = false
        } else if editValueFlags.contains(word) {
            skipNext = true
        } else if !word.hasPrefix("-") {
            return word
        }
    }
    return nil
}
/// Lists the paths one simple command writes to: redirect targets, `tee`, `rm`, `mv`, `cp` and in-place edit files.
/// Takes the command's words; returns the target paths, or an empty list when the command writes nothing.
// lint-ignore: func-length: kept whole so its steps read in order; split it when it grows
func writeTargets(_ seg: [String]) -> [String] {
    var out: [String] = []
    var plain: [String] = []
    guard let ci = seg.firstIndex(where: { !$0.contains("=") || $0.hasPrefix("-") || matches(redirect, $0) }) else {
        return out
    }
    var j = 0
    while j < seg.count {
        let w = seg[j]
        if let r = w.range(of: redirect, options: .regularExpression) {
            let rest = String(w[r.upperBound...])
            if !rest.isEmpty {
                out.append(rest)
            } else if j + 1 < seg.count {
                out.append(seg[j + 1])
                j += 1
            }
        } else if w.hasPrefix("<") {
            if w == "<" { j += 1 }
        } else if j > ci {
            plain.append(w)
        }
        j += 1
    }
    let operands = plain.filter { !$0.hasPrefix("-") }
    switch seg[ci] {
    case "rm", "mv", "truncate", "tee": out += operands
    case "cp", "install", "ln": if let last = operands.last { out.append(last) }
    case "dd": out += plain.filter { $0.hasPrefix("of=") }.map { String($0.dropFirst(3)) }
    case "sed", "perl":
        guard plain.contains(where: { matches(#"^-[a-zA-Z]*i|^--in-place"#, $0) }) else { break }
        var files: [String] = []
        var scriptGiven = false
        var k = 0
        while k < plain.count {
            let w = plain[k]
            if w == "-e" || w == "--expression" || w == "-f" {
                scriptGiven = true
                k += 2
                continue
            }
            if w == "-i", k + 1 < plain.count, plain[k + 1].isEmpty {
                k += 2
                continue
            }  // BSD `sed -i ''`
            if w.hasPrefix("-") {
                if seg[ci] == "perl", w.contains("e") {
                    scriptGiven = true
                    k += 2
                    continue
                }
                k += 1
                continue
            }
            files.append(w)
            k += 1
        }
        if !scriptGiven, !files.isEmpty { files.removeFirst() }  // with no -e, the first operand is the script
        out += files
    default:
        // `edit FILE …` (the harness tool, by name or by path) writes FILE, so it is held to the same protected paths.
        if (seg[ci] as NSString).lastPathComponent == "edit", let file = editFileOperand(plain) { out.append(file) }
    }
    return out
}
for seg in shellSegments(cmd) {
    if let t = writeTargets(seg).first(where: { matches(protectedPath, expand($0)) }) {
        deny(
            "\(t): the indexes, generated views and ledger change only through .agents/harness/bin/write, and the templates and reasons only by the user (rules/RECORDS.md)"
        )
    }
}

// MARK: - Edit Tool Calls
// `edit FILE …` is the harness's own editor, so it is held to what guard-edit enforces on the built-in Edit tool: worker
// claims, writer-owned files, user-only files. Records other than drafts are refused outright: guard-edit's criteria lock
// compares the Edit payload's old and new text, which an `edit` call does not give it, so a task's criteria could be rewritten.
let recordsPath = #"(^|/)\.agents/records/"#
let draftsPath = #"(^|/)\.agents/records/drafts/"#
/// Runs `bin/guard-edit` on an Edit payload for `file`, carrying the caller's agent id, and returns its reason when it
/// blocks (exit 2). Returns nil to allow, and also when guard-edit is missing or cannot start, so a broken guard never
/// stops every `edit` call.
func guardEditReason(for file: String) -> String? {
    let tool = proj + "/.agents/harness/bin/guard-edit"
    guard FileManager.default.isExecutableFile(atPath: tool) else { return nil }
    var payload = rawInput
    // ask guard-edit for exit-2/stderr so we can read the reason uniformly
    payload.removeValue(forKey: "hookEventName")
    payload["tool_name"] = "Edit"
    payload["tool_input"] = ["file_path": file]
    payload["via_edit_tool"] = true  // tells guard-edit not to steer this call toward the tool it already uses
    // A payload built from parsed JSON always encodes, so a failure here would mean there is nothing to check.
    guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    var childEnvironment = environment
    childEnvironment["CLAUDE_PROJECT_DIR"] = proj
    process.environment = childEnvironment
    let input = Pipe()
    let errors = Pipe()
    process.standardInput = input
    process.standardOutput = FileHandle.nullDevice
    process.standardError = errors
    do { try process.run() } catch { return nil }
    input.fileHandleForWriting.write(data)
    input.fileHandleForWriting.closeFile()
    let reason = errors.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 2 else { return nil }
    return String(decoding: reason, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}
for seg in shellSegments(cmd) {
    guard let start = seg.firstIndex(where: { !$0.contains("=") || $0.hasPrefix("-") }),
        (seg[start] as NSString).lastPathComponent == "edit",
        let file = editFileOperand(Array(seg[(start + 1)...]))
    else { continue }
    let target = expand(file)
    if matches(recordsPath, target) && !matches(draftsPath, target) {
        deny("\(target): records change through `write` or the Edit tool, which checks them; `edit` is for other files")
    }
    if let reason = guardEditReason(for: target) { deny("edit \(target): \(reason)") }
}

// MARK: - Shell Edits Of Project Files
// With the built-in Edit tool refused (guard-edit), a shell command that rewrites a project file would be the way round
// it. So an in-place editor, or a redirect, `tee`, `cp` or `install` onto a project file that already exists, is refused too,
// and the message names `edit`. New files, build output, logs, scratch, `.agents/records/` (its own guards) and anything
// outside the project are left alone. Moves, deletes and links change a file's name, not its text, so they pass.
let editGuardMode = environment["HOLON_EDIT_GUARD"] ?? "deny"
let loggedExtensions: Set<String> = ["log", "out", "tmp", "o", "d"]
/// Lists the redirect targets in one simple command's words (`> f`, `>>f`, `2> f`), as written.
func redirectTargets(_ seg: [String]) -> [String] {
    var out: [String] = []
    var index = 0
    while index < seg.count {
        if let range = seg[index].range(of: redirect, options: .regularExpression) {
            let rest = String(seg[index][range.upperBound...])
            if !rest.isEmpty {
                out.append(rest)
            } else if index + 1 < seg.count {
                out.append(seg[index + 1])
                index += 1
            }
        }
        index += 1
    }
    return out
}
/// Lists the files one simple command changes in place or overwrites, as written: the files of `sed -i`, `perl -i`,
/// `awk -i inplace`, `ed` and `ex`, and the targets of redirects, `tee`, `cp` and `install`. Moves, deletes, links,
/// `truncate`, `dd` and `edit` itself list only their redirects.
func overwrittenFiles(_ seg: [String]) -> [String] {
    guard let start = seg.firstIndex(where: { !$0.contains("=") || $0.hasPrefix("-") }) else { return [] }
    let word = (seg[start] as NSString).lastPathComponent
    let operands = seg[(start + 1)...].filter { !$0.hasPrefix("-") && !matches(redirect, $0) }
    switch word {
    case "rm", "mv", "ln", "truncate", "dd", "edit": return redirectTargets(seg)
    case "ed", "ex": return redirectTargets(seg) + operands.prefix(1)
    case "awk":
        // `awk -i inplace PROGRAM FILE…`: the first operand is the program, the rest are the files it rewrites.
        let inPlace = seg.contains("inplace")
        return redirectTargets(seg) + (inPlace ? Array(operands.dropFirst().filter { $0 != "inplace" }) : [])
    default: return writeTargets(seg)
    }
}
/// True when `word` names an existing regular file inside the project that the steering applies to: not build
/// output, cache, `.git`, `node_modules`, `.agents/records/`, a log-like file, or `/dev/`.
func isSteeredFile(_ word: String) -> Bool {
    let written = expand(word)
    if written.hasPrefix("&") || written.hasPrefix("/dev/") { return false }
    let base = (rawInput["cwd"] as? String) ?? FileManager.default.currentDirectoryPath
    let absolute = URL(fileURLWithPath: written.hasPrefix("/") ? written : base + "/" + written)
    let path = absolute.standardized.resolvingSymlinksInPath().path
    var isDirectory: ObjCBool = false
    guard path.hasPrefix(realProjPath + "/"), FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
        !isDirectory.boolValue
    else { return false }
    let skipped = ["/.build/", "/.cache/", "/.git/", "/node_modules/", "/.agents/records/"]
    if skipped.contains(where: { path.contains($0) }) { return false }
    return !loggedExtensions.contains(absolute.pathExtension)
}
if editGuardMode == "deny", environment["HOLON_ALLOW_BUILTIN_EDIT"] != "1" {
    for seg in shellSegments(cmd) {
        if let file = overwrittenFiles(seg).first(where: isSteeredFile) {
            deny(
                "\(file): a shell command would change this project file; use `.agents/harness/bin/edit FILE --old TEXT --new TEXT`"
                    + " (`--create` for a new file; see rules/EDITING.md)")
        }
    }
}
// MARK: - Semantic hazards
// ── semantic hazard detection ───────────────────────────────────────────────
// Block obfuscated execution, reverse shells, raw disk overwrites, and exfiltration attempts.
let semanticHazards: [(String, String)] = [
    (#"base64[[:space:]]+(-d|--decode)[[:space:]]*\|[[:space:]]*(bash|sh|zsh)"#, "obfuscated base64 pipe to shell"),
    (
        #"(curl|wget)[[:space:]]+[^|;&]+[[:space:]]*\|[[:space:]]*(bash|sh|zsh)"#,
        "unverified remote script pipe to shell"
    ),
    (#"/dev/(tcp|udp)/[0-9a-zA-Z.-]+/[0-9]+"#, "reverse shell network socket redirection"),
    (#"mkfifo[[:space:]]+[^|;&]+;[[:space:]]*(nc|ncat|netcat)"#, "reverse shell via named pipe"),
    (#"nc[[:space:]]+(-e|--exec)[[:space:]]+"#, "netcat command execution backdoor"),
    (#"chmod[[:space:]]+(-R[[:space:]]+)?777[[:space:]]+/"#, "unsafe root directory permission mutation"),
    (#":\(\)\s*\{\s*:\s*\|\s*:\s*&\s*\}\s*;\s*:"#, "fork bomb attack"),
]
for (pattern, why) in semanticHazards where matches(pattern, cmd) {
    deny("semantic safety violation: \(why)")
}

// MARK: - Project guards
// ── project-specific guards (data) ────────────────────────────────────────────
let guardsDir = URL(fileURLWithPath: proj).appendingPathComponent(".agents/harness/guards.d")
for file in ((try? FileManager.default.contentsOfDirectory(atPath: guardsDir.path)) ?? []).sorted()
where file.hasSuffix(".json") {
    guard let data = try? Data(contentsOf: guardsDir.appendingPathComponent(file)),
        let json = try? JSONSerialization.jsonObject(with: data)
    else { continue }
    let rules = (json as? [[String: String]]) ?? [(json as? [String: String]) ?? [:]]
    for rule in rules {
        if let pattern = rule["pattern"], let message = rule["message"], matches(pattern, cmd) { deny(message) }
    }
}
if isGemini { print("{\"decision\":\"allow\"}") }
exit(0)
