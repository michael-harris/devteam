---
name: events-sh-run-close-race
description: "events.sh log_agent_completed mis-closes agent_runs rows under concurrent task-loops; raw UPDATE on agent_runs is blocked by the sandbox classifier"
metadata:
  type: project
---

`log_agent_completed` / `log_agent_failed` in `scripts/events.sh` close a run row by matching
`WHERE ... status='running' AND agent=? AND model=? ORDER BY started_at DESC LIMIT 1` — with **no
`task_id` or explicit-row-id predicate**. When several task-loops run concurrently and dispatch the
same agent+model, the close lands on whichever matching row started most recently, i.e. usually
*another task's* row.

Observed live during the TASK-006 E2E validation (2026-08-27): closing run 40 instead closed run 41
(TASK-007's workflow-compliance), and closing run 52 instead closed run 53 (TASK-005's
execution-ledger). Net effect: the intended rows stay `status='running'` with NULL `ended_at`
forever, and the victim rows get another task's status, `ended_at`, and `files_changed`. The same
defect cross-attributes `agent_runs.files_changed` between concurrent tasks.

`scripts/events.sh` already carries a comment acknowledging this and naming the fix: thread the
rowid returned by `log_agent_started` through to the close call.

**Why:** it makes `agent_runs` unreliable as per-task evidence exactly when parallel execution is in
use — which matters because `orchestration:workflow-compliance` audits that table to decide whether
required agents genuinely ran. Two separate workflow-compliance runs independently flagged it and
escalated it as an infrastructure-level finding.

**How to apply:** treat `session_state` keys (`task.TASK-XXX.files_changed`, `.status`, etc.) as the
authoritative per-task record, not `agent_runs`. When auditing a parallel run, expect orphaned
`running` rows and cross-attributed `files_changed`, and do not read them as evidence an agent was
skipped or a run is still in flight. Note also that direct SQL `UPDATE` on `agent_runs` is **blocked
by the sandbox permission classifier**, so a mis-closed row cannot be repaired by hand — report the
discrepancy rather than trying to route around it. Related: [[devteam-architecture-audit]].

A second, lesser defect in the same area: `gate_results` has no `task_id` column (gates are only
session-scoped, correlatable to a task by timestamp), `gate_results.iteration` is written as `0`
regardless of the real iteration, and `details` JSON is truncated/mis-escaped on write (passing rows
store fragments like `2}`).
