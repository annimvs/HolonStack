// PreToolUse(Agent / invoke_subagent): refuse spawning a project-editing subagent unless a live, unbound isolate claim
// exists in `.agents/harness/.cache/claims/` and the prompt names that claim (rules/DELEGATION.md).
// Exempt: read-only subagent types (Explore, Plan, research, browser, image-generator, statusline-setup, claude-code-guide),
// or a prompt explicitly marked `[unrestricted]` / `[read-only]` (or `HOLON_ALLOW_UNCLAIMED_AGENT=1`).
// Exit 2 (stderr) blocks on Claude Code; JSON deny on Antigravity.
import Foundation

let environment = ProcessInfo.processInfo.environment
let proj = URL(fileURLWithPath: environment["CLAUDE_PROJECT_DIR"] ?? FileManager.default.currentDirectoryPath)
    .resolvingSymlinksInPath().path

// lint-ignore: no-unsafe-sendable: a hook reads its one input at start-up and only this single thread ever uses it
nonisolated(unsafe) let rawInput =
    (try? JSONSerialization.jsonObject(with: FileHandle.standardInput.readDataToEndOfFile()) as? [String: Any]) ?? [:]
let isGemini = rawInput["hookEventName"] != nil

/// Allows the agent spawn; Antigravity expects an explicit allow JSON decision.
func allow() -> Never {
    if isGemini { print("{\"decision\":\"allow\"}") }
    exit(0)
}

/// Refuses the agent spawn with `reason`: exit 2 on Claude Code, JSON deny on Antigravity.
func deny(_ reason: String) -> Never {
    let message = "BLOCKED by .agents/harness/hooks/guard-agent.swift: \(reason)"
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

if environment["HOLON_ALLOW_UNCLAIMED_AGENT"] == "1" { allow() }

let toolInput =
    (rawInput["tool_input"] as? [String: Any])
    ?? ((rawInput["toolCall"] as? [String: Any])?["args"] as? [String: Any]) ?? [:]
let subagentType =
    ((toolInput["subagent_type"] as? String) ?? (toolInput["TypeName"] as? String) ?? "").lowercased()
let prompt = (toolInput["prompt"] as? String) ?? (toolInput["Prompt"] as? String) ?? ""

// Read-only or non-code subagents never edit project source, so they do not need an isolate claim.
let exemptTypes: Set<String> = [
    "explore", "plan", "research", "browser", "image-generator", "statusline-setup", "claude-code-guide",
]
if exemptTypes.contains(subagentType) { allow() }
if prompt.contains("[unrestricted]") || prompt.contains("[read-only]") { allow() }

// MARK: - Live Unbound Claims

let claimsDir = proj + "/.agents/harness/.cache/claims"
let claimTTL: Double = 6 * 3600

/// Reads every unexpired, unbound claim name from `.agents/harness/.cache/claims/*.json`.
func unboundClaims() -> [String] {
    let files = ((try? FileManager.default.contentsOfDirectory(atPath: claimsDir)) ?? []).filter {
        $0.hasSuffix(".json")
    }
    var found: [String] = []
    for file in files.sorted() {
        guard let data = FileManager.default.contents(atPath: claimsDir + "/" + file),
            let fields = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let made = fields["created"] as? Double, Date().timeIntervalSince1970 - made < claimTTL
        else { continue }
        let bound = (fields["agent"] as? String)?.isEmpty == false
        if !bound { found.append(String(file.dropLast(5))) }
    }
    return found
}

let unbound = unboundClaims()
if unbound.isEmpty {
    deny(
        "no unbound isolate claim exists; run `.agents/harness/bin/isolate plan <tasks…>` then "
            + "`.agents/harness/bin/isolate claim <name> <task>` before spawning a worker (or use a read-only "
            + "Explore/Plan/research agent, or mark the prompt `[unrestricted]` / `[read-only]`; see rules/DELEGATION.md)"
    )
}
if !unbound.contains(where: { prompt.contains($0) }) {
    let names = unbound.joined(separator: ", ")
    deny(
        "worker prompt does not name an unbound isolate claim (available: \(names)); include the claim name "
            + "and tell the worker to bind `.agents/harness/.cache/claims/<name>.bind` first (rules/DELEGATION.md)"
    )
}
allow()
