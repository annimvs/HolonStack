#!/usr/bin/env sh
# End-to-end smoke test for HolonStack's adopt-holon bundle.
# Runs bootstrap, lint, check-docs, write, edit, seek, isolate, guard-agent, and guard-edit
# in an isolated temp workspace so the repository stays clean.
set -eu

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/holonstack-smoke.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

echo "==> Staging synthetic multi-language repo in $WORK"
mkdir -p "$WORK/packages/core" "$WORK/packages/app" "$WORK/src"
printf '{"name":"smoke-mono","private":true}\n' > "$WORK/package.json"
printf 'packages:\n  - "packages/*"\n' > "$WORK/pnpm-workspace.yaml"
printf '{"name":"@smoke/core","version":"1.0.0"}\n' > "$WORK/packages/core/package.json"
printf '{"name":"@smoke/app","version":"1.0.0","dependencies":{"@smoke/core":"1.0.0","express":"^4.18.0"}}\n' > "$WORK/packages/app/package.json"
printf 'export function greet(name: string) {\n  return `hi ${name}`;\n}\n' > "$WORK/packages/core/index.ts"
printf 'def hello(name):\n    return f"hi {name}"\n' > "$WORK/packages/core/helper.py"
printf 'int main(int argc, char **argv) {\n  return 0;\n}\n' > "$WORK/src/main.c"

cp -R "$REPO_ROOT/adopt-holon/.agents" "$WORK/"
cp -P "$REPO_ROOT/adopt-holon/AGENTS.md" "$REPO_ROOT/adopt-holon/CLAUDE.md" "$REPO_ROOT/adopt-holon/GEMINI.md" "$WORK/"

cd "$WORK"

echo "==> 1. Bootstrap & wiring"
.agents/harness/bin/bootstrap.sh
.agents/harness/bin/sync-settings --check

echo "==> 2. Lint, check-docs, and write check"
.agents/harness/bin/lint .agents/harness/hooks/*.swift .agents/harness/tools/*.swift
.agents/harness/bin/check-docs
.agents/harness/bin/write check

echo "==> 3. Multi-language seek --outline"
.agents/harness/bin/seek --outline packages/core/index.ts packages/core/helper.py src/main.c | tee "$WORK/seek.out"
grep -q "export function greet" "$WORK/seek.out"
grep -q "def hello" "$WORK/seek.out"
grep -q "int main" "$WORK/seek.out"

echo "==> 4. Exact-match edit & check"
HASH="$(.agents/harness/bin/edit src/main.c --read | awk '/^hash: /{print $2}')"
.agents/harness/bin/edit src/main.c --hash "$HASH" --old "return 0;" --new "return 1;" --check | grep -q "+  return 1;"

echo "==> 5. Isolate graph, claim, guard-agent, and guard-edit"
.agents/harness/bin/isolate graph | tee "$WORK/graph.out"
grep -q "choke (orchestrator owns): @smoke/core" "$WORK/graph.out"
grep -q "@smoke/app  packages/app  reads @smoke/core" "$WORK/graph.out"

# Unclaimed worker spawn must be denied (exit 2)
set +e
echo '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","prompt":"edit app"}}' | .agents/harness/bin/guard-agent >/dev/null 2>&1
rc=$?
set -e
[ "$rc" -eq 2 ] || { echo "FAIL: expected guard-agent exit 2 for unclaimed worker, got $rc" >&2; exit 1; }

# Explore read-only spawn must be allowed (exit 0)
echo '{"tool_name":"Agent","tool_input":{"subagent_type":"Explore","prompt":"inspect app"}}' | .agents/harness/bin/guard-agent >/dev/null

# Unclaimed subagent edit must be denied (exit 2)
set +e
echo '{"agent_id":"sub1","tool_name":"Edit","tool_input":{"file_path":"'"$WORK"'/packages/app/package.json"}}' | .agents/harness/bin/guard-edit >/dev/null 2>&1
rc=$?
set -e
[ "$rc" -eq 2 ] || { echo "FAIL: expected guard-edit exit 2 for unclaimed subagent, got $rc" >&2; exit 1; }

# Filing a claim allows spawning when the prompt names it
.agents/harness/bin/isolate claim w-app @smoke/app >/dev/null
echo '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","prompt":"claim w-app: edit app"}}' | .agents/harness/bin/guard-agent >/dev/null
.agents/harness/bin/isolate release --all >/dev/null

echo "==> 6. Record lifecycle: write task new -> write done"
mkdir -p .agents/records/drafts
cat > .agents/records/drafts/smoke-task.closure <<'DRAFT'
task(_) {
  name: "Smoke test task"
  est: 15m
  criteria: [
    criterion(_) {
      text: "main.c exists"
      check: "test -f src/main.c"
    },
  ]
}
DRAFT
.agents/harness/bin/write task check-draft .agents/records/drafts/smoke-task.closure
OUT="$(.agents/harness/bin/write task new .agents/records/drafts/smoke-task.closure)"
TASK_ID="$(printf '%s\n' "$OUT" | sed -nE 's/.*"ids":\["([0-9a-f]{8})".*/\1/p')"
[ -n "$TASK_ID" ] || { echo "FAIL: could not parse task id from $OUT" >&2; exit 1; }
rm -f .agents/records/drafts/smoke-task.closure
.agents/harness/bin/write done "$TASK_ID"
.agents/harness/bin/write check

echo "==> Smoke test passed."
