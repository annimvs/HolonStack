#!/bin/sh
# Bootstrap .agents/harness/bin/ shims, .claude/settings.json, .claude/skills/, and .agents/hooks.json,
# then compile all Swift hooks and tools into .agents/harness/.cache/bin/.
set -e
if ! command -v swift >/dev/null 2>&1 || ! command -v swiftc >/dev/null 2>&1; then
    echo "bootstrap.sh: Swift toolchain (swift and swiftc) is required; install Xcode Command Line Tools or Swift from swift.org" >&2
    exit 1
fi
swift_major="$(swift --version 2>/dev/null | sed -nE 's/.*Swift version ([0-9]+)\..*/\1/p' | head -n 1)"
if [ -n "$swift_major" ] && [ "$swift_major" -lt 6 ]; then
    echo "bootstrap.sh: Swift 6+ is required (found Swift $swift_major); upgrade Xcode Command Line Tools or Swift from swift.org" >&2
    exit 1
fi
root="$(cd "$(dirname "$0")/.." && pwd)"
export CLAUDE_PROJECT_DIR="$(cd "$root/../.." && pwd)"
swift "$root/hooks/sync-settings.swift"
"$root/bin/build.sh"
