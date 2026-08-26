-- DevTeam SQLite Schema v5
-- Adds: call-hierarchy tracking on agent_runs (which orchestrator/parent
-- agent dispatched a given run), required by the orchestration:execution-ledger
-- agent (Phase 6) to answer "which orchestrators were involved in Sprint N".
-- Migrates from v4
-- Transaction management handled by db-init.sh run_migrations()
-- Version: 5.0.0
--
-- ROLLBACK (manual, SQLite >= 3.35.0 required for DROP COLUMN):
--   BEGIN TRANSACTION;
--   DROP INDEX IF EXISTS idx_agent_runs_invoked_by_run_id;
--   DROP INDEX IF EXISTS idx_agent_runs_invoked_by_agent;
--   ALTER TABLE agent_runs DROP COLUMN invoked_by_run_id;
--   ALTER TABLE agent_runs DROP COLUMN invoked_by_agent;
--   DELETE FROM schema_version WHERE version = 5;
--   COMMIT;

-- ============================================================================
-- AGENT_RUNS: call-hierarchy columns
-- ============================================================================
-- invoked_by_agent: the dispatching agent's id (e.g. "orchestration:task-loop"),
--   matching the `id` format used in agent-registry.json. NULL means this run
--   was dispatched directly by a command/skill (no parent agent), e.g. the
--   first Task() call a command makes.
-- invoked_by_run_id: FK to the parent's own agent_runs.id, so the full call
--   chain for a task (e.g. sprint-orchestrator -> task-loop -> frontend:developer)
--   can be reconstructed by walking the reference instead of guessing from
--   timestamps/ordering.

ALTER TABLE agent_runs ADD COLUMN invoked_by_agent TEXT;
ALTER TABLE agent_runs ADD COLUMN invoked_by_run_id INTEGER REFERENCES agent_runs(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_agent_runs_invoked_by_agent ON agent_runs(invoked_by_agent);
CREATE INDEX IF NOT EXISTS idx_agent_runs_invoked_by_run_id ON agent_runs(invoked_by_run_id);

-- ============================================================================
-- VIEW: call chain reconstruction helper
-- ============================================================================
-- One row per run, with its immediate parent's agent id and model alongside
-- it, so a task's full chain can be built without a recursive CTE for the
-- common case (single level of "who called me").

CREATE VIEW IF NOT EXISTS v_agent_call_chain AS
SELECT
    child.id AS run_id,
    child.session_id,
    child.task_id,
    child.agent,
    child.model,
    child.status,
    child.invoked_by_agent,
    child.invoked_by_run_id,
    parent.agent AS parent_agent,
    parent.model AS parent_model
FROM agent_runs child
LEFT JOIN agent_runs parent ON parent.id = child.invoked_by_run_id;

-- Note: Schema version is managed by db-init.sh
