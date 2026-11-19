// filter-run.swift — runs a command with /bin/sh, keeps its full output in a log, and prints only what an agent needs:
// errors with three lines of context, failed tests, totals and step headers (150 lines at most), then
// `[exit N] full log: <path>`. Exits with the command's own status. The `rewrite-bash` hook routes build commands here.
// Usage: filter-run '<command>'. The log goes to `<project>/.agents/harness/.cache/run-logs/<time>-<pid>.log`.
import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

// MARK: - Filter
/// Decides, line by line, what of a command's output reaches the agent, and counts what it drops.
struct Filter {
    /// The most lines kept; past it the view says it was cut.
    static let maxKept = 150
    let keep = Filter.regex(
        #"(error:|fatal error:|undefined reference|FAIL\b|FAILED|✘|✕|\bfailed\b|Fatal error|Issue recorded|recorded an issue|AssertionError|panic:|Test run with|Executed \d+ tests?|test result:|Build complete|^==>|warning: unre|Segmentation|Test Suite .* (passed|failed))"#
    )
    let drop = Filter.regex(
        #"^(✔|◇|\[\d+/\d+\]|Compiling|Linking|Planning build|Building for|Fetching|Computing|Write auxiliary)"#)
    let summary = Filter.regex(#"Test run with|Executed \d+ tests?|test result:|Tests:\s+\d+"#)
    let diagnostic = Filter.regex(#"(error:|fatal error:|undefined reference|FAIL\b|FAILED|✘|✕|AssertionError|panic:)"#)
    var kept: [String] = []
    var dropped = 0
    var context = 0
    var truncated = false

    /// Compiles a pattern that is known to be valid; an invalid one matches nothing.
    static func regex(_ pattern: String) -> NSRegularExpression? { try? NSRegularExpression(pattern: pattern) }

    /// Returns true when `re` matches anywhere in `line`.
    func hit(_ re: NSRegularExpression?, _ line: String) -> Bool {
        re?.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
    }

    /// Takes one output line: keeps it (with up to three lines after an error), or drops and counts it.
    mutating func consume(_ line: String) {
        if !hit(summary, line), hit(drop, line) {
            dropped += 1
            context = 0
            return
        }
        if hit(keep, line) {
            if hit(diagnostic, line) { context = 3 }
            if kept.count < Filter.maxKept { kept.append(line) } else { truncated = true }
        } else if context > 0 {
            context -= 1
            if kept.count < Filter.maxKept { kept.append(line) }
        } else {
            dropped += 1
        }
    }
}

// MARK: - Running

/// Starts `/bin/sh -c command` with its stdout and stderr on one pipe (`posix_spawn`, so arguments reach it unchanged),
/// writes every byte to `log`, feeds each line to `filter`, and returns the command's exit status.
func runFiltered(_ command: String, log: FileHandle, filter: inout Filter) -> Int32 {
    var fds: [Int32] = [0, 0]
    guard pipe(&fds) == 0 else { return 127 }
    #if canImport(Darwin)
        var actions: posix_spawn_file_actions_t?
    #else
        var actions = posix_spawn_file_actions_t()
    #endif
    posix_spawn_file_actions_init(&actions)
    defer { posix_spawn_file_actions_destroy(&actions) }
    posix_spawn_file_actions_adddup2(&actions, fds[1], STDOUT_FILENO)
    posix_spawn_file_actions_adddup2(&actions, fds[1], STDERR_FILENO)
    posix_spawn_file_actions_addclose(&actions, fds[0])
    posix_spawn_file_actions_addclose(&actions, fds[1])
    let argv: [UnsafeMutablePointer<CChar>?] = ["/bin/sh", "-c", command].map { strdup($0) } + [nil]
    defer { argv.forEach { free($0) } }
    var pid: pid_t = 0
    #if canImport(Darwin)
        let spawned = posix_spawn(&pid, "/bin/sh", &actions, nil, argv, environ)
    #else
        let envp: [UnsafeMutablePointer<CChar>?] =
            ProcessInfo.processInfo.environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { envp.forEach { free($0) } }
        let spawned = posix_spawn(&pid, "/bin/sh", &actions, nil, argv, envp)
    #endif
    close(fds[1])
    guard spawned == 0 else {
        close(fds[0])
        let reason = String(cString: strerror(spawned))
        FileHandle.standardError.write(Data("filter-run: cannot start /bin/sh: \(reason)\n".utf8))
        return 127
    }
    let reader = FileHandle(fileDescriptor: fds[0], closeOnDealloc: true)
    var pending = Data()
    while true {
        let chunk = reader.availableData
        if chunk.isEmpty { break }
        log.write(chunk)
        pending.append(chunk)
        while let newline = pending.firstIndex(of: 0x0A) {
            filter.consume(String(decoding: pending[pending.startIndex..<newline], as: UTF8.self))
            pending = pending[(newline + 1)...]
        }
    }
    if !pending.isEmpty { filter.consume(String(decoding: pending, as: UTF8.self)) }
    var status: Int32 = 0
    while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
    // the exit code, or 128 plus the signal that ended it, as a shell reports it
    let signal = status & 0x7f
    return signal == 0 ? (status >> 8) & 0xff : 128 + signal
}

// MARK: - Main

/// Runs the command given as the only argument and prints the filtered view and where the full log is.
func main() -> Int32 {
    guard CommandLine.arguments.count > 1 else {
        FileHandle.standardError.write(Data("usage: filter-run '<command>'\n".utf8))
        return 64
    }
    let environment = ProcessInfo.processInfo.environment
    let project = environment["CLAUDE_PROJECT_DIR"] ?? FileManager.default.currentDirectoryPath
    let logDir = project + "/.agents/harness/.cache/run-logs"
    // an existing folder is fine; a real failure shows up when the log can't be opened below
    try? FileManager.default.createDirectory(atPath: logDir, withIntermediateDirectories: true)
    let stamp = DateFormatter()
    stamp.dateFormat = "yyyyMMdd-HHmmss"
    stamp.locale = Locale(identifier: "en_US_POSIX")
    let logPath = "\(logDir)/\(stamp.string(from: Date()))-\(getpid()).log"
    guard FileManager.default.createFile(atPath: logPath, contents: nil),
        let log = FileHandle(forWritingAtPath: logPath)
    else {
        FileHandle.standardError.write(Data("filter-run: cannot write \(logPath)\n".utf8))
        return 1
    }
    var filter = Filter()
    let status = runFiltered(CommandLine.arguments[1], log: log, filter: &filter)
    if !filter.kept.isEmpty { print(filter.kept.joined(separator: "\n")) }
    if filter.truncated { print("… filtered output cut at \(Filter.maxKept) lines") }
    print("[filter] kept \(filter.kept.count), dropped \(filter.dropped) lines")
    print("[exit \(status)] full log: \(logPath)")
    return status
}

exit(main())
