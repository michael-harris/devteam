---
name: events-sh-ledger-defects
description: Two unfixed defects in scripts/events.sh corrupt the agent_runs/gate_results audit trail whenever task-loops run concurrently
metadata:
  type: project
---

Two real, **unfixed** defects in `scripts/events.sh` corrupt the SQLite audit trail. Both were found empirically during a live concurrent E2E validation run (3 task-loops in one session, 2026-08-27) and were reported up to the sprint-orchestrator; neither is fixed yet.

1. **`log_agent_completed` resolves the wrong row.** It targets `WHERE session_id=? AND agent=? AND model=? AND status='running' ORDER BY started_at DESC LIMIT 1` — by agent *name*+model, not by run id. Concurrent task-loops dispatching the same agent at the same model cross-wire their `files_changed`/`status`/`ended_at` writes. An in-file comment already predicts this and names the fix: return the rowid from `log_agent_started()` and pass it in.
2. **`log_gate_passed` / `log_gate_failed` mangle `details`.** `local details="${2:-{}}"` appends a stray `}` to *every* supplied value, so `json_valid(details)` is 0 for all gate rows. Also `log_gate_passed`'s 2nd positional arg is `details`, not `iteration` — callers passing an iteration number store the literal `2}`.

Related schema gaps seen at the same time: `gate_results` has **no `task_id` column** (so rows are not attributable per-task when loops run concurrently), and `agent_runs.iteration` stays 0 because `get_current_iteration()` reads session-global state.

**Why:** these silently produce a false execution record, which matters because `orchestration:execution-ledger` renders published task/sprint reports *from this DB*.

**How to apply:** when validating or reporting on a task, treat `agent_runs.files_changed` and `gate_results.details`/`.iteration` as unreliable under concurrency — prefer `agent_runs` rows filtered by `task_id`, and corroborate with actual file content. Do not close out a run with the `log_agent_completed` helper while sibling loops are active; use a targeted `UPDATE ... WHERE id=<run_id>` so you don't clobber another task's row. Task state lives in the `session_state` table, not `kv_state`.
