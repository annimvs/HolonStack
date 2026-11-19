// PostToolUse(Bash/run_command): after a shell command that runs the harness `edit` tool, run the checks that fire on
// Edit, Write and Read for the file it touched: `check-edit` (lint, record check, wiring check) and `route-semantics`
// (the area's card). Both read `tool_input.file_path`, so each is fed a copy of the payload that says Edit (Read for
// `edit FILE --read`) and the file. Exit 2 (or Antigravity JSON) with findings when check-edit fails.
import Foundation

let environment = ProcessInfo.processInfo.environment
let proj = URL(fileURLWithPath: environment["CLAUDE_PROJECT_DIR"] ?? FileManager.default.currentDirectoryPath)
    .resolvingSymlinksInPath().path

// MARK: - Finding Edit Calls

/// The flags of `tools/edit.swift` that take a value, so the value is not mistaken for the file operand.
let editValueFlags: Set<String> = [
    "--old", "--new", "--old-file", "--new-file", "--at", "--after", "--before",
    "--hash", "--content", "--content-file", "--batch-file",
]

// MARK: - EditCall
/// One `edit` invocation found in a command: the file it names and whether it only reads.
struct EditCall {
    let file: String
    let isRead: Bool
}

/// Splits a shell command into simple commands, each a list of words. It honours quotes and backslashes and cuts at
/// `;`, `&`, `|` and newlines outside quotes. A heredoc body is split like any other text, which is harmless here:
/// only a line that starts with `edit` and names an existing file is acted on.
func splitCommands(_ text: String) -> [[String]] {
    var commands: [[String]] = []
    var words: [String] = []
    var word = ""
    var inWord = false
    var quote: Character?
    var escaped = false
    /// Ends the current word.
    func flushWord() {
        if inWord { words.append(word) }
        word = ""
        inWord = false
    }
    /// Ends the current simple command.
    func flushCommand() {
        flushWord()
        if !words.isEmpty { commands.append(words) }
        words = []
    }
    for character in text {
        if escaped {
            word.append(character)
            escaped = false
        } else if character == "\\" && quote != "'" {
            escaped = true
            inWord = true
        } else if let open = quote {
            if character == open { quote = nil } else { word.append(character) }
        } else if character == "'" || character == "\"" {
            quote = character
            inWord = true
        } else if ";&|\n".contains(character) {
            flushCommand()
        } else if character == " " || character == "\t" {
            flushWord()
        } else {
            word.append(character)
            inWord = true
        }
    }
    flushCommand()
    return commands
}

/// Picks out the `edit` calls from a command: those whose command word is `edit` (by name or path), after any
/// `NAME=value` prefixes, with the first operand that is not a flag or a flag's value as the file.
func editCalls(in command: String) -> [EditCall] {
    var calls: [EditCall] = []
    for words in splitCommands(command) {
        guard let start = words.firstIndex(where: { !($0.contains("=") && !$0.hasPrefix("-")) }) else { continue }
        guard (words[start] as NSString).lastPathComponent == "edit" else { continue }
        let rest = Array(words[(start + 1)...])
        var skipNext = false
        for word in rest {
            if skipNext {
                skipNext = false
            } else if editValueFlags.contains(word) {
                skipNext = true
            } else if !word.hasPrefix("-") {
                calls.append(EditCall(file: word, isRead: rest.contains("--read")))
                break
            }
        }
    }
    return calls
}

// MARK: - Running The Checks

/// Runs `.agents/harness/bin/<name>` with the payload on stdin, and returns its exit status, standard output and
/// standard error. A tool that cannot start counts as a pass with no output, so a missing tool never blocks an edit.
func runTool(_ name: String, payload: Data) -> (status: Int32, out: String, err: String) {
    let path = proj + "/.agents/harness/bin/" + name
    guard FileManager.default.isExecutableFile(atPath: path) else { return (0, "", "") }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    var env = environment
    env["CLAUDE_PROJECT_DIR"] = proj
    process.environment = env
    let input = Pipe()
    let output = Pipe()
    let errors = Pipe()
    process.standardInput = input
    process.standardOutput = output
    process.standardError = errors
    do { try process.run() } catch { return (0, "", "") }
    input.fileHandleForWriting.write(payload)
    input.fileHandleForWriting.closeFile()
    let out = output.fileHandleForReading.readDataToEndOfFile()
    let err = errors.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: out, as: UTF8.self), String(decoding: err, as: UTF8.self))
}

/// Pulls the `additionalContext` text out of a hook's JSON reply, or returns nil when there is none.
func additionalContext(of reply: String) -> String? {
    guard let data = reply.data(using: .utf8),
        // Not JSON means the tool printed something else; there is no card to carry over.
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let output = object["hookSpecificOutput"] as? [String: Any]
    else { return nil }
    return output["additionalContext"] as? String
}

// MARK: - Main

let rawInput: [String: Any]
do {
    rawInput =
        try JSONSerialization.jsonObject(with: FileHandle.standardInput.readDataToEndOfFile()) as? [String: Any] ?? [:]
} catch {
    exit(0)
}
let isGemini = rawInput["hookEventName"] != nil
let toolInput =
    (rawInput["tool_input"] as? [String: Any])
    ?? ((rawInput["toolCall"] as? [String: Any])?["args"] as? [String: Any]) ?? [:]
let isShell = isGemini || rawInput["tool_name"] as? String == "Bash"
guard isShell, let command = (toolInput["command"] as? String) ?? (toolInput["CommandLine"] as? String) else {
    if isGemini { print("{}") }
    exit(0)
}
let working = (rawInput["cwd"] as? String) ?? proj
var findings = ""
var routed = ""
for call in editCalls(in: command) {
    let file = call.file.hasPrefix("/") ? call.file : working + "/" + call.file
    guard FileManager.default.fileExists(atPath: file) else { continue }
    var payload = rawInput
    // read uniform stderr/exit-2 from check-edit and JSON from route-semantics
    payload.removeValue(forKey: "hookEventName")
    payload["tool_name"] = call.isRead ? "Read" : "Edit"
    payload["tool_input"] = ["file_path": file]
    // A payload built from parsed JSON always encodes, so a failure here would mean there is nothing to check.
    guard let data = try? JSONSerialization.data(withJSONObject: payload) else { continue }
    if !call.isRead {
        let checked = runTool("check-edit", payload: data)
        if checked.status != 0 { findings += checked.err }
    }
    let routing = runTool("route-semantics", payload: data)
    if !routing.out.isEmpty { routed = routing.out }
}
if !findings.isEmpty {
    let card = additionalContext(of: routed).map { "\n" + $0 + "\n" } ?? ""
    FileHandle.standardError.write(Data((findings + card).utf8))
    if isGemini {
        print("{}")
        exit(0)
    }
    exit(2)
}
if isGemini {
    if let card = additionalContext(of: routed),
        let data = try? JSONSerialization.data(withJSONObject: ["systemMessage": card], options: [.sortedKeys])
    {
        FileHandle.standardOutput.write(data)
        print()
    } else {
        print("{}")
    }
    exit(0)
}
if !routed.isEmpty { print(routed, terminator: "") }
exit(0)
