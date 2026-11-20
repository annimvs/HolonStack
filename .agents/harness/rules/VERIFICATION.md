# VERIFICATION

> **AGENTS: maintain this file with Haiku or a similar-class model, in grok'd prose.** Style rules: [QUIET](QUIET.md), [PROSE](PROSE.md).

Run the verification command in the current turn and read its result before you mark a task done or say that a fix works.

## The Rule

```
func completeTask(taskId) {
  let result = runVerificationCommand()
  guard result.exitCode == 0 else {
    reportFailure(result.output)
    return .stayInTurn
  }
  showCommandEvidence(result.command, result.output)
  return writeDone(taskId)
}
```

## Requirements

1. **Proof Before `write done`:**
   Run the verification command right before you run `.agents/harness/bin/write done <id>`. A task marked done with no proof in the transcript is invalid.
2. **Positional Error Inspection:**
   When a checker, compiler or test tool fails, read the line and column numbers in its output. Fix the reported line directly instead of guessing.
3. **No Unverified Assumptions:**
   Do not say "the tests should pass now" or "the build will succeed." Run the test or build and state the actual exit status.
