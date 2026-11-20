# TESTS

> **AGENTS: maintain this file with Haiku or a similar-class model, in grok'd prose.** Style rules: [QUIET](QUIET.md), [PROSE](PROSE.md).

> **AGENTS: this rule applies whenever you plan, divide or order work on a list of failures checked against a suite or oracle:** test suite failures, conformance probes, lint findings, or output that differs from a reference specification. It is about the order of fixes.

Treat each failure as a node, link failures that share a root cause, cluster the graph, and fix the clusters in greedy set-cover order: most failures cleared per fix first. Each cluster becomes one brief, handed out per [DELEGATION](DELEGATION.md).

## Here

- **The lists:** the project's test or verification suite failures and any regression reports.
- **Where a cluster goes:** a phase or task with the cluster's checks as its `check:` criteria ([plan-and-enact](../skills/plan-and-enact/SKILL.md)). A cause that is confirmed is an `issue` ([log-bug](../skills/log-bug/SKILL.md)).

## Why

One cause often breaks checks in many files. Fixing file by file finds the same cause again and again, and each find costs a build. Fixing the cause, not the instance, also cuts regressions, because the fix covers every place the bug shows up.

## How to apply

- **Start from a clean baseline.**
  - Run the full list once and keep which items fail before any fix.
  - Rerun anything that fails only sometimes. A flaky item goes on its own list and stays out of the graph, or it links to everything.
- **Build the edges.** Link two failures when they share any of these:
  - a feature in their source: an option, a command, a type, a transformation;
  - a suspect function in `Sources/`, one that failing items run and passing ones don't;
  - a minimal repro: the same smallest input once each failure is shrunk until it still fails.

  A shared repro is strong evidence. A shared feature alone is weak, since many unrelated tests use common features.
- **Cluster, then rank.** Rank the clusters by failures cleared per fix. A narrow cluster with a known cause comes before a broad one with a vague cause. Diagnose a vague cluster before anyone tries to fix it.
- **One cluster, one owner.** The brief holds:
  - the cause or the hypothesis;
  - the shrunk repro;
  - the cluster's items as the check;
  - the paths in scope.

  Independent clusters can run in parallel. Clusters whose suspect functions overlap run one after another.
- **Check the clustering after each fix.** If most of the cluster now passes, split the stragglers into a new cluster and rerank. If few pass, the edges were wrong: change what you link on and recluster.
- **Guard against regressions.** A fix lands only if its cluster clears and nothing that passed at baseline now fails.
- **Write back.** File each resolved cause as an `issue` record and fix it there with `write fix`. When a cause keeps returning, note the feature or function it lives in, so the next clustering links on it from the start.
