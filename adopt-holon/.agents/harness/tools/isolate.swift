// isolate.swift — reads the project's build manifests (SwiftPM Package.swift, Cargo.toml, or Node package.json / pnpm-workspace.yaml) under the project root and decides which tasks can run in parallel without touching each other's compile inputs (rules/DELEGATION.md).
// ADOPTION NOTE (/adopt-holon): SwiftPM, Cargo, and Node/pnpm workspaces work out of the box. For CMake, Meson, Ninja, Go, Bazel, or Make, add a loader to `loadGraph` while keeping `Graph`, `Claim`, and the CLI unchanged.
// A worker's write set is one or more targets. Two workers conflict when either one's write set falls in the other's read closure (itself plus everything it depends on).
// Usage: isolate graph | plan [--max N] [--choke a,b] [--package file] <task…> | owner <path…> | claim <name> <task…> | release <name…|--all> | claims
//   task: a target name, several joined by commas (`Syntax,Theme`), or a path under a target's folder.
//   --max N: the worker cap; the default is $HOLON_WORKERS, else 2. Choke points and external packages always go to the orchestrator.
// Exit 0 on success, 2 on bad usage or when no manifest is found.
// The project root is the repository or collection folder that holds the package(s); a path argument is relative to it (`Sources/MyTarget`).
// `--package file` reads one manifest alone, with its paths relative to that file's folder.
import Foundation

// MARK: - Target
/// One SwiftPM target: its name, package, source folder (relative to the project root), the targets it depends on, and the packages outside the project it pulls in.
struct Target {
    let name: String
    let package: String
    let path: String
    let deps: [String]
    let externals: [String]
}

// MARK: - Source Scanning

/// Takes the text as characters, an index at an opening bracket and its pair; returns the index of the matching close, skipping quoted strings, or nil.
func matching(_ chars: [Character], from start: Int, open: Character, close: Character) -> Int? {
    var depth = 0
    var inString = false
    var i = start
    while i < chars.count {
        let c = chars[i]
        if inString {
            // a backslash escapes the next character, so a quote after it does not end the string
            if c == "\\" { i += 1 } else if c == "\"" { inString = false }
        } else if c == "\"" {
            inString = true
        } else if c == open {
            depth += 1
        } else if c == close {
            depth -= 1
            if depth == 0 { return i }
        }
        i += 1
    }
    return nil
}

/// Takes a regex pattern and a string; returns the first capture group of the first match, or nil.
func firstCapture(_ pattern: String, in s: String) -> String? {
    // a bad pattern is a bug here, treated as no match
    guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
    let range = NSRange(s.startIndex..., in: s)
    guard let m = re.firstMatch(in: s, range: range), m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: s) else {
        return nil
    }
    return String(s[r])
}

/// Takes a regex pattern and a string; returns the first capture group of every match, in order.
func allCaptures(_ pattern: String, in s: String) -> [String] {
    // a bad pattern is a bug here, treated as no match
    guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
    let range = NSRange(s.startIndex..., in: s)
    return re.matches(in: s, range: range).compactMap { m in
        guard m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: s) else { return nil }
        return String(s[r])
    }
}

// MARK: - Package Parsing

/// Takes a target's call text (`name: "X", dependencies: […], path: "…"`); returns the dependency names and the `.product` references as (product, package) pairs.
func parseDependencies(_ block: String) -> (deps: [String], products: [(name: String, package: String)]) {
    guard let key = block.range(of: "dependencies:") else { return ([], []) }
    let chars = Array(block[key.upperBound...])
    guard let open = chars.firstIndex(of: "["), let close = matching(chars, from: open, open: "[", close: "]") else {
        return ([], [])
    }
    var text = String(chars[open...close])
    // .product(...) entries name a product and its package; take both, then drop them so their strings are not read as targets
    var products: [(name: String, package: String)] = []
    while let r = text.range(of: ".product(") {
        let tail = Array(text[r.lowerBound...])
        guard let end = matching(tail, from: tail.firstIndex(of: "(") ?? 0, open: "(", close: ")") else { break }
        let call = String(tail[0...end])
        if let pkg = firstCapture("package:\\s*\"([^\"]+)\"", in: call),
            let product = firstCapture("name:\\s*\"([^\"]+)\"", in: call)
        {
            products.append((product, pkg))
        }
        text.replaceSubrange(r.lowerBound..<text.index(r.lowerBound, offsetBy: end + 1), with: "")
    }
    return (allCaptures("\"([^\"]+)\"", in: text), products)
}

// MARK: - RawTarget
/// A target as the manifest declares it, before its product dependencies are resolved to targets.
struct RawTarget {
    let name: String
    let path: String
    let deps: [String]
    let products: [(name: String, package: String)]
}

// MARK: - Manifest
/// One parsed Package.swift: the package name, its folder relative to the project root, its targets and the targets each product holds.
struct Manifest {
    let name: String
    let dir: String
    let targets: [RawTarget]
    let products: [String: [String]]
}

/// Takes one `.target(…)` or `.executableTarget(…)` call text; returns the RawTarget it declares, or nil without a name.
func parseTarget(_ block: String) -> RawTarget? {
    guard let name = firstCapture("name:\\s*\"([^\"]+)\"", in: block) else { return nil }
    let path = firstCapture("path:\\s*\"([^\"]+)\"", in: block) ?? "Sources/" + name
    let parsed = parseDependencies(block)
    return RawTarget(name: name, path: path, deps: parsed.deps, products: parsed.products)
}

/// Takes the Package.swift text; returns its non-test targets in declaration order.
func parseTargets(_ text: String) -> [RawTarget] {
    let chars = Array(text)
    guard let marker = text.range(of: "targets:\\s*\\[\\s*\\n", options: .regularExpression),
        let open = text[marker].lastIndex(of: "["),
        let close = matching(chars, from: text.distance(from: text.startIndex, to: open), open: "[", close: "]")
    else { return [] }
    let start = text.distance(from: text.startIndex, to: open)
    var found: [RawTarget] = []
    var i = start + 1
    while i < close {
        let rest = String(chars[i..<min(i + 20, chars.count)])
        let isTarget = rest.hasPrefix(".target(") || rest.hasPrefix(".executableTarget(")
        guard isTarget, let paren = chars[i...].firstIndex(of: "("),
            let end = matching(chars, from: paren, open: "(", close: ")")
        else {
            i += 1
            continue
        }
        if let t = parseTarget(String(chars[paren...end])) { found.append(t) }
        i = end + 1
    }
    return found
}

/// Takes the Package.swift text; returns each `.library` and `.executable` product's name with the targets it holds.
func parseProducts(_ text: String) -> [String: [String]] {
    let chars = Array(text)
    var found: [String: [String]] = [:]
    var i = 0
    while i < chars.count {
        let rest = String(chars[i..<min(i + 13, chars.count)])
        guard rest.hasPrefix(".library(") || rest.hasPrefix(".executable("),
            let paren = chars[i...].firstIndex(of: "("), let end = matching(chars, from: paren, open: "(", close: ")")
        else {
            i += 1
            continue
        }
        let call = String(chars[paren...end])
        if let name = firstCapture("name:\\s*\"([^\"]+)\"", in: call),
            let list = firstCapture("targets:\\s*\\[([^\\]]*)\\]", in: call)
        {
            found[name] = allCaptures("\"([^\"]+)\"", in: list)
        }
        i = end + 1
    }
    return found
}

/// Takes a Package.swift's text and its folder relative to the project root; returns its manifest.
func parseManifest(_ text: String, dir: String) -> Manifest {
    let name = firstCapture("Package\\(\\s*name:\\s*\"([^\"]+)\"", in: text) ?? dir
    return Manifest(name: name, dir: dir, targets: parseTargets(text), products: parseProducts(text))
}

/// Takes the manifests; returns the graph. A product dependency on a package in the project becomes that product's targets; any other package stays external.
func buildGraph(_ manifests: [Manifest]) -> Graph {
    var byKey: [String: Manifest] = [:]
    for m in manifests {
        byKey[m.name] = m
        byKey[m.dir] = m
    }
    var targets: [Target] = []
    for m in manifests {
        for raw in m.targets {
            var deps = raw.deps
            var externals: [String] = []
            for product in raw.products {
                guard let owner = byKey[product.package] else {
                    externals.append(product.package)
                    continue
                }
                let named = owner.targets.contains { $0.name == product.name } ? [product.name] : []
                deps += owner.products[product.name] ?? named
            }
            let path = m.dir.isEmpty ? raw.path : m.dir + "/" + raw.path
            targets.append(Target(name: raw.name, package: m.name, path: path, deps: deps, externals: externals))
        }
    }
    return Graph(targets)
}

/// Loads a Cargo workspace graph via `cargo metadata --no-deps --format-version 1`, or nil when Cargo is absent or fails.
func loadCargoGraph(root: String) -> Graph? {
    guard FileManager.default.fileExists(atPath: root + "/Cargo.toml") else { return nil }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["cargo", "metadata", "--no-deps", "--format-version", "1"]
    process.currentDirectoryURL = URL(fileURLWithPath: root)
    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return nil }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0,
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let packages = json["packages"] as? [[String: Any]]
    else { return nil }
    let names = Set(packages.compactMap { $0["name"] as? String })
    let prefix = URL(fileURLWithPath: root).resolvingSymlinksInPath().path + "/"
    let targets: [Target] = packages.compactMap { pkg in
        guard let name = pkg["name"] as? String, let manifest = pkg["manifest_path"] as? String else { return nil }
        let dir = URL(fileURLWithPath: manifest).deletingLastPathComponent().resolvingSymlinksInPath().path
        let rel = dir.hasPrefix(prefix) ? String(dir.dropFirst(prefix.count)) : "."
        let rawDeps = (pkg["dependencies"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
        return Target(
            name: name, package: name, path: rel,
            deps: rawDeps.filter { names.contains($0) },
            externals: rawDeps.filter { !names.contains($0) })
    }
    return targets.isEmpty ? nil : Graph(targets)
}

/// Loads a Node workspace graph from root `package.json` workspaces, or nil when none is found.
func loadNodeGraph(root: String) -> Graph? {
    let fm = FileManager.default
    let rootPkg = root + "/package.json"
    guard let data = fm.contents(atPath: rootPkg),
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }
    var wsList =
        (json["workspaces"] as? [String]) ?? ((json["workspaces"] as? [String: Any])?["packages"] as? [String])
    if wsList == nil, let pnpm = try? String(contentsOfFile: root + "/pnpm-workspace.yaml", encoding: .utf8) {
        wsList = pnpm.split(separator: "\n").compactMap { raw -> String? in
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("-") else { return nil }
            let item = trimmed.dropFirst().trimmingCharacters(in: CharacterSet(charactersIn: " \t'\""))
            return item.isEmpty || item.hasPrefix("!") ? nil : item
        }
    }
    var pkgDirs: [String] = []
    for pattern in wsList ?? [] {
        if pattern.hasSuffix("/*") {
            let base = String(pattern.dropLast(2))
            let subs = ((try? fm.contentsOfDirectory(atPath: root + "/" + base)) ?? []).sorted()
            for sub in subs where fm.fileExists(atPath: root + "/" + base + "/" + sub + "/package.json") {
                pkgDirs.append(base + "/" + sub)
            }
        } else if fm.fileExists(atPath: root + "/" + pattern + "/package.json") {
            pkgDirs.append(pattern)
        }
    }
    if pkgDirs.isEmpty { pkgDirs = ["."] }
    var parsed: [(name: String, path: String, deps: [String])] = []
    for rel in pkgDirs {
        let file = rel == "." ? rootPkg : root + "/" + rel + "/package.json"
        guard let d = fm.contents(atPath: file), let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
            let name = obj["name"] as? String
        else { continue }
        let deps =
            Array((obj["dependencies"] as? [String: Any] ?? [:]).keys)
            + Array((obj["devDependencies"] as? [String: Any] ?? [:]).keys)
        parsed.append((name, rel, deps))
    }
    let names = Set(parsed.map(\.name))
    let targets = parsed.map { item in
        Target(
            name: item.name, package: item.name, path: item.path,
            deps: item.deps.filter { names.contains($0) },
            externals: item.deps.filter { !names.contains($0) })
    }
    return targets.isEmpty ? nil : Graph(targets)
}

/// Takes the project root and an optional single Package.swift file; returns that manifest, or root and child manifests.
func loadManifests(root: String, file: String?) -> [Manifest]? {
    if let file {
        // an unreadable file is reported by the caller
        guard let text = try? String(contentsOfFile: file, encoding: .utf8) else { return nil }
        return [parseManifest(text, dir: "")]
    }
    var found: [Manifest] = []
    if let text = try? String(contentsOfFile: root + "/Package.swift", encoding: .utf8) {
        found.append(parseManifest(text, dir: ""))
    }
    // an unreadable root just means no manifests; the caller reports it
    let dirs = ((try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []).filter { !$0.hasPrefix(".") }
        .sorted()
    for dir in dirs {
        let file = root + "/" + dir + "/Package.swift"
        // a folder with no manifest is not a package
        if let text = try? String(contentsOfFile: file, encoding: .utf8) { found.append(parseManifest(text, dir: dir)) }
    }
    return found.isEmpty ? nil : found
}

/// Loads the target graph from SwiftPM (`Package.swift`), Cargo (`Cargo.toml`), or Node (`package.json`).
func loadGraph(root: String, file: String?) -> Graph? {
    if let manifests = loadManifests(root: root, file: file) { return buildGraph(manifests) }
    if file == nil, let cargo = loadCargoGraph(root: root) { return cargo }
    if file == nil, let node = loadNodeGraph(root: root) { return node }
    return nil
}

// MARK: - Graph
/// The target graph: reads closures and dependents, and decides which targets are choke points.
struct Graph {
    let targets: [Target]
    let byName: [String: Target]

    /// Takes the parsed targets; indexes them by name.
    init(_ targets: [Target]) {
        self.targets = targets
        self.byName = Dictionary(targets.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Takes target names; returns them plus everything they depend on, transitively. Unknown names are kept as themselves.
    func closure(_ names: [String]) -> Set<String> {
        var seen = Set<String>()
        var stack = names
        while let n = stack.popLast() {
            guard seen.insert(n).inserted else { continue }
            stack.append(contentsOf: byName[n]?.deps ?? [])
        }
        return seen
    }

    /// Takes a target name; returns every target that depends on it, directly or not.
    func dependents(of name: String) -> Set<String> {
        Set(targets.map(\.name).filter { $0 != name && closure([$0]).contains(name) })
    }

    /// Takes the share of targets that must depend on one for it to count; returns the choke points: widely depended-on targets.
    func choke(share: Double) -> [String] {
        let need = Int((share * Double(targets.count - 1)).rounded(.up))
        return targets.map(\.name).filter { dependents(of: $0).count >= need && need > 0 }
    }

    /// Takes a path relative to the project; returns the target whose folder holds it (the longest folder wins), or nil.
    func owner(of path: String) -> String? {
        let clean = path.hasPrefix("./") ? String(path.dropFirst(2)) : path
        let hits = targets.filter { clean == $0.path || clean.hasPrefix($0.path + "/") }
        return hits.max { $0.path.count < $1.path.count }?.name
    }

    /// Takes a task word: a comma list of target names or one path; returns the targets it names, or nil if a word names none.
    func resolve(_ task: String) -> [String]? {
        let words = task.split(separator: ",").map(String.init)
        let names = words.compactMap { byName[$0] != nil ? $0 : owner(of: $0) }
        return names.count == words.count && !names.isEmpty ? names : nil
    }
}

// MARK: - Planning
/// One task the plan placed: its words, the targets it writes and its read closure.
struct Placed {
    let task: String
    let writes: [String]
    let reads: Set<String>
}

/// Takes the graph, the cap, the choke points and the tasks in priority order; returns the printed plan lines.
func plan(_ graph: Graph, max cap: Int, choke: Set<String>, tasks: [String]) -> [String] {
    var workers: [Placed] = []
    var lines: [String] = []
    var orchestrator: [String] = []
    var deferred: [String] = []
    for task in tasks {
        guard let writes = graph.resolve(task) else {
            lines.append("unknown: \(task)  names no target or path")
            continue
        }
        if let hit = writes.first(where: { choke.contains($0) }) {
            orchestrator.append("orchestrator: \(task)  (\(hit) is a choke point)")
            continue
        }
        let reads = graph.closure(writes)
        if workers.count >= cap {
            deferred.append("deferred: \(task)  cap of \(cap) workers reached")
        } else if let clash = workers.enumerated().first(where: { overlaps(writes, reads, $0.element) }) {
            deferred.append("deferred: \(task)  overlaps worker \(clash.offset + 1) (\(clash.element.task))")
        } else {
            workers.append(Placed(task: task, writes: writes, reads: reads))
        }
    }
    let placed = workers.enumerated().map {
        "worker \($0.offset + 1): \($0.element.task)  writes \($0.element.writes.joined(separator: " "))  reads \($0.element.reads.sorted().joined(separator: " "))"
    }
    return ["max \(cap)"] + placed + orchestrator + deferred + lines
}

/// Takes a new task's writes and reads and an already placed worker; returns true when either writes into the other's read closure.
func overlaps(_ writes: [String], _ reads: Set<String>, _ other: Placed) -> Bool {
    writes.contains(where: other.reads.contains) || other.writes.contains(where: reads.contains)
}

// MARK: - Claim
/// One worker's claim, kept as a JSON file under `.agents/harness/.cache/claims/`: the targets and folders it may write, and the agent id once bound.
/// The `guard-edit` hook reads these files; a claim older than `claimTTL` seconds is ignored there.
struct Claim: Codable {
    let name: String
    let writes: [String]
    let reads: [String]
    let paths: [String]
    let created: Double
    var agent: String?
}

let claimTTL: Double = 6 * 3600

/// Takes the project root; returns the folder the claim files live in.
func claimsDirectory(_ root: String) -> String { root + "/.agents/harness/.cache/claims" }

/// Takes the project root; returns every unexpired claim, sorted by name.
func liveClaims(_ root: String) -> [Claim] {
    let dir = claimsDirectory(root)
    // a missing folder just means no claims yet
    let files = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).filter { $0.hasSuffix(".json") }
    let now = Date().timeIntervalSince1970
    return files.sorted().compactMap { file in
        guard let data = FileManager.default.contents(atPath: dir + "/" + file),
            let claim = try? JSONDecoder().decode(Claim.self, from: data), now - claim.created < claimTTL
        else { return nil }
        return claim
    }
}

/// Takes a claim name, its tasks and the planning inputs; files the claim and returns the text to print, or an error message and false.
func fileClaim(
    _ name: String, tasks: [String], graph: Graph, choke: Set<String>, cap: Int, root: String
) -> (ok: Bool, text: String) {
    guard !name.isEmpty, name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }), !tasks.isEmpty else {
        return (false, "isolate: claim needs a name of letters, digits and dashes, then at least one task")
    }
    var writes: [String] = []
    for task in tasks {
        guard let found = graph.resolve(task) else { return (false, "isolate: \(task) names no target or path") }
        writes += found
    }
    if let hit = writes.first(where: { choke.contains($0) }) {
        return (false, "isolate: \(hit) is a choke point; the orchestrator changes it, not a worker")
    }
    let others = liveClaims(root).filter { $0.name != name }
    if others.count >= cap {
        return (false, "isolate: cap of \(cap) workers reached (\(others.map(\.name).joined(separator: " ")))")
    }
    let reads = graph.closure(writes)
    let placed = others.map { Placed(task: $0.name, writes: $0.writes, reads: Set($0.reads)) }
    if let clash = placed.first(where: { overlaps(writes, reads, $0) }) {
        return (false, "isolate: overlaps claim \(clash.task) (writes \(clash.writes.joined(separator: " ")))")
    }
    let paths = writes.compactMap { graph.byName[$0]?.path }
    let claim = Claim(
        name: name, writes: writes, reads: reads.sorted(), paths: paths, created: Date().timeIntervalSince1970,
        agent: nil)
    let dir = claimsDirectory(root)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    do {
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try encoder.encode(claim).write(to: URL(fileURLWithPath: dir + "/" + name + ".json"))
    } catch {
        return (false, "isolate: cannot write the claim: \(error.localizedDescription)")
    }
    let bind = ".agents/harness/.cache/claims/\(name).bind"
    return (
        true,
        "claimed \(name): writes \(writes.joined(separator: " ")) in \(paths.joined(separator: " "))\nthe worker binds it by writing an empty file at \(bind)"
    )
}

/// Takes the project root and the names to release (or `--all`); removes those claims and their bind files, and returns the printed line.
func releaseClaims(_ names: [String], root: String) -> String {
    let all = names.contains("--all")
    let targets = all ? liveClaims(root).map(\.name) : names
    let dir = claimsDirectory(root)
    for name in targets {
        try? FileManager.default.removeItem(atPath: dir + "/" + name + ".json")  // already gone is fine
        try? FileManager.default.removeItem(atPath: dir + "/" + name + ".bind")  // already gone is fine
    }
    return "released " + (targets.isEmpty ? "nothing" : targets.joined(separator: " "))
}

/// Takes the project root; returns one line per live claim: its name, whether an agent is bound, and what it writes.
func describeClaims(_ root: String) -> [String] {
    let claims = liveClaims(root)
    if claims.isEmpty { return ["no claims"] }
    return claims.map {
        "\($0.name)  \($0.agent == nil ? "unbound" : "bound")  writes \($0.writes.joined(separator: " "))"
    }
}

// MARK: - Commands

/// Takes the graph and the choke points; returns the lines `isolate graph` prints.
func describe(_ graph: Graph, choke: [String]) -> [String] {
    let external = Set(graph.targets.flatMap(\.externals)).sorted()
    var lines = [
        "choke (orchestrator owns): " + choke.joined(separator: " "),
        "external packages (orchestrator owns): " + external.joined(separator: " "),
    ]
    for t in graph.targets {
        let reads = graph.closure([t.name]).subtracting([t.name]).sorted()
        lines.append("\(t.name)  \(t.path)  reads \(reads.isEmpty ? "-" : reads.joined(separator: " "))")
    }
    return lines
}

/// Takes the arguments after the verb; splits out `--max`, `--choke` and `--package`, returning those and the rest.
func parseFlags(_ args: [String]) -> (max: Int?, choke: [String]?, package: String?, rest: [String])? {
    var cap: Int?
    var choke: [String]?
    var package: String?
    var rest: [String] = []
    var i = 0
    while i < args.count {
        let a = args[i]
        let isFlag = ["--max", "--choke", "--package"].contains(a)
        guard !isFlag || i + 1 < args.count else { return nil }
        if a == "--max" {
            guard let n = Int(args[i + 1]), n >= 1 else { return nil }
            cap = n
        } else if a == "--choke" {
            choke = args[i + 1].split(separator: ",").map(String.init)
        } else if a == "--package" {
            package = args[i + 1]
        } else {
            rest.append(a)
            i += 1
            continue
        }
        i += 2
    }
    return (cap, choke, package, rest)
}

/// Takes the verb, its arguments and the project root; prints the answer and returns the exit status.
func run(_ args: [String], root: String) -> Int32 {
    guard let verb = args.first, ["graph", "plan", "owner", "claim", "release", "claims"].contains(verb),
        let flags = parseFlags(Array(args.dropFirst()))
    else {
        FileHandle.standardError.write(
            Data(
                "usage: isolate graph | plan [--max N] [--choke a,b] [--package file] <task…> | owner <path…> | claim <name> <task…> | release <name…|--all> | claims\n"
                    .utf8))
        return 2
    }
    if verb == "release" {
        print(releaseClaims(flags.rest, root: root))
        return 0
    }
    if verb == "claims" {
        print(describeClaims(root).joined(separator: "\n"))
        return 0
    }
    guard let graph = loadGraph(root: root, file: flags.package) else {
        let wherePath = flags.package ?? root
        let msg = "isolate: no readable manifest (Package.swift, Cargo.toml, package.json) under \(wherePath)\n"
        FileHandle.standardError.write(Data(msg.utf8))
        return 2
    }
    let choke = flags.choke ?? graph.choke(share: 0.5)
    let envCap = ProcessInfo.processInfo.environment["HOLON_WORKERS"].flatMap { Int($0) }.flatMap { $0 >= 1 ? $0 : nil }
    let cap = flags.max ?? envCap ?? 2
    if verb == "claim" {
        let result = fileClaim(
            flags.rest.first ?? "", tasks: Array(flags.rest.dropFirst()), graph: graph, choke: Set(choke), cap: cap,
            root: root)
        if result.ok { print(result.text) } else { FileHandle.standardError.write(Data((result.text + "\n").utf8)) }
        return result.ok ? 0 : 1
    }
    var out: [String]
    switch verb {
    case "graph": out = describe(graph, choke: choke)
    case "plan": out = plan(graph, max: cap, choke: Set(choke), tasks: flags.rest)
    default: out = flags.rest.map { "\($0): \(graph.owner(of: $0) ?? "orchestrator (outside every target)")" }
    }
    print(out.joined(separator: "\n"))
    return 0
}

exit(
    run(
        Array(CommandLine.arguments.dropFirst()),
        root: ProcessInfo.processInfo.environment["CLAUDE_PROJECT_DIR"] ?? FileManager.default.currentDirectoryPath))
