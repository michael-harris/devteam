# SQLite Database Schema

DevTeam uses SQLite for state management, event logging, cost tracking, and metrics. This document describes the complete database schema across all migration versions (v1 through v5).

## Database Location

```
.devteam/devteam.db
```

## Schema Overview

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│    sessions     │────▶│     events      │     │   agent_runs    │
└────────┬────────┘     └─────────────────┘     └─────────────────┘
         │                                               │
         ├───────────────────┬───────────────────────────┘
         │                   │
         ▼                   ▼
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│  session_state  │  │  gate_results   │  │   escalations   │
└─────────────────┘  └─────────────────┘  └─────────────────┘

┌─────────────────┐     ┌─────────────────────┐
│   interviews    │────▶│ interview_questions  │
└─────────────────┘     └─────────────────────┘

┌─────────────────────┐     ┌─────────────────────┐
│  research_sessions  │────▶│  research_findings  │
└──────────┬──────────┘     └─────────────────────┘
           │
           ▼
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│      plans      │────▶│     tasks       │────▶│   task_files    │
└─────────────────┘     └────────┬────────┘     └─────────────────┘
                                 │
                                 ▼
                        ┌─────────────────┐
                        │  task_attempts  │
                        └─────────────────┘

┌─────────────────┐     ┌──────────────────────┐
│      bugs       │     │ acceptance_criteria   │
└─────────────────┘     └──────────────────────┘

┌─────────────────┐     ┌──────────────────────┐
│    features     │     │  context_snapshots    │
└─────────────────┘     └──────────────────────┘

┌──────────────────┐    ┌──────────────────────┐
│ context_budgets  │    │ progress_summaries    │
└──────────────────┘    └──────────────────────┘

┌──────────────────┐    ┌──────────────────────┐
│ session_phases   │    │     baselines         │
└──────────────────┘    └──────────────────────┘

┌──────────────────┐    ┌──────────────────────┐    ┌──────────────────────┐
│   checkpoints    │───▶│ checkpoint_restores  │    │     rollbacks        │
└──────────────────┘    └──────────────────────┘    └──────────────────────┘

┌──────────────────┐    ┌──────────────────────┐    ┌──────────────────────┐
│   token_usage    │    │     error_log         │    │    dead_letter       │
└──────────────────┘    └──────────────────────┘    └──────────────────────┘
```

## Tables

### sessions

Tracks execution sessions (one per command invocation).

```sql
CREATE TABLE sessions (
    id TEXT PRIMARY KEY,
    started_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    ended_at TIMESTAMP,
    command TEXT NOT NULL,                      -- "/devteam:implement --sprint 1"
    command_type TEXT NOT NULL,                 -- plan, implement, bug, issue
    status TEXT DEFAULT 'running',              -- running, completed, failed, aborted
    exit_reason TEXT,                           -- Success, user_abort, max_iterations, error
    current_phase TEXT,                         -- interview, research, planning, executing, quality_gates
    current_task_id TEXT,
    current_agent TEXT,
    current_model TEXT,                         -- haiku, sonnet, opus
    current_iteration INTEGER DEFAULT 0,
    max_iterations INTEGER DEFAULT 10,
    consecutive_failures INTEGER DEFAULT 0,
    max_consecutive_failures INTEGER DEFAULT 5,
    circuit_breaker_state TEXT DEFAULT 'closed', -- closed, open, half-open
    plan_id TEXT,
    sprint_id TEXT,
    execution_mode TEXT DEFAULT 'normal',       -- normal, eco
    total_tokens_input INTEGER DEFAULT 0,
    total_tokens_output INTEGER DEFAULT 0,
    total_cost_cents INTEGER DEFAULT 0,
    bug_council_activated BOOLEAN DEFAULT FALSE,
    bug_council_reason TEXT
);
```

### session_state

Key-value state storage for sessions. Values are stored as JSON.

```sql
CREATE TABLE session_state (
    session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    key TEXT NOT NULL,
    value JSON NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (session_id, key)
);
```

### events

Full event log for debugging and analytics. Each event captures context, cost, and a JSON payload.

```sql
CREATE TABLE events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    event_type TEXT NOT NULL,
    event_category TEXT,                    -- agent, gate, escalation, interview, etc.
    agent TEXT,
    model TEXT,
    iteration INTEGER,
    phase TEXT,
    data JSON,
    metadata JSON,
    message TEXT,
    tokens_input INTEGER,
    tokens_output INTEGER,
    cost_cents INTEGER
);
```

**Event Types:**
- `session_started`, `session_ended`
- `phase_changed`
- `agent_started`, `agent_completed`, `agent_failed`
- `model_escalated`, `model_deescalated`
- `gate_passed`, `gate_failed`
- `bug_council_activated`, `bug_council_completed`
- `interview_started`, `interview_question`, `interview_completed`
- `research_started`, `research_finding`, `research_completed`
- `task_started`, `task_completed`, `task_failed`
- `error_occurred`, `warning_issued`
- `abandonment_detected`, `abandonment_prevented`

### agent_runs

Tracks individual agent executions with cost and output metadata.

```sql
CREATE TABLE agent_runs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    agent TEXT NOT NULL,                    -- e.g., 'api-developer-typescript'
    agent_type TEXT,                        -- orchestration, backend, frontend, etc.
    model TEXT NOT NULL,
    started_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    ended_at TIMESTAMP,
    duration_seconds INTEGER,
    status TEXT,                            -- running, success, failed, escalated
    error_message TEXT,
    error_type TEXT,                        -- test_failure, type_error, lint_error, etc.
    task_id TEXT,
    iteration INTEGER,
    attempt INTEGER DEFAULT 1,
    tokens_input INTEGER,
    tokens_output INTEGER,
    cost_cents INTEGER,
    files_changed JSON,                    -- ["src/foo.ts", "src/bar.ts"]
    output_summary TEXT,
    invoked_by_agent TEXT,                  -- added in v5: dispatching agent's id, e.g. 'orchestration:task-loop'; NULL if dispatched directly by a command/skill
    invoked_by_run_id INTEGER REFERENCES agent_runs(id) ON DELETE SET NULL  -- added in v5: FK to the parent run, for call-chain reconstruction
);
```

### gate_results

Quality gate execution results. Tracks pass/fail status per gate per iteration.

```sql
CREATE TABLE gate_results (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    gate TEXT NOT NULL,                    -- tests, lint, typecheck, security, coverage
    iteration INTEGER NOT NULL,
    passed BOOLEAN NOT NULL,
    details JSON,
    error_count INTEGER,
    warning_count INTEGER,
    coverage_percent REAL,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    duration_seconds INTEGER
);
```

### interviews

Interview session records for gathering requirements.

```sql
CREATE TABLE interviews (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    interview_type TEXT NOT NULL,           -- feature, bug, issue, task
    started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP,
    status TEXT DEFAULT 'in_progress',      -- in_progress, completed, skipped
    questions_asked INTEGER DEFAULT 0,
    questions_answered INTEGER DEFAULT 0
);
```

### interview_questions

Individual Q&A entries from interviews.

```sql
CREATE TABLE interview_questions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    interview_id INTEGER NOT NULL REFERENCES interviews(id) ON DELETE CASCADE,
    question_key TEXT NOT NULL,             -- expected_behavior, repro_steps, etc.
    question_text TEXT NOT NULL,
    question_type TEXT DEFAULT 'text',      -- text, choice, confirm
    response TEXT,
    responded_at TIMESTAMP,
    sequence INTEGER NOT NULL,
    required BOOLEAN DEFAULT TRUE
);
```

### research_sessions

Research phase tracking.

```sql
CREATE TABLE research_sessions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP,
    status TEXT DEFAULT 'in_progress',
    findings_count INTEGER DEFAULT 0,
    recommendations_count INTEGER DEFAULT 0,
    blockers_found INTEGER DEFAULT 0
);
```

### research_findings

Individual findings from research.

```sql
CREATE TABLE research_findings (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    research_session_id INTEGER NOT NULL REFERENCES research_sessions(id) ON DELETE CASCADE,
    finding_type TEXT NOT NULL,             -- pattern, technology, blocker, recommendation
    title TEXT NOT NULL,
    description TEXT,
    source TEXT,                            -- codebase, documentation, web
    file_path TEXT,
    evidence JSON,
    priority TEXT DEFAULT 'medium',         -- high, medium, low
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### bugs

Local bug tracking (not GitHub).

```sql
CREATE TABLE bugs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT REFERENCES sessions(id) ON DELETE CASCADE,
    description TEXT NOT NULL,
    severity TEXT,                          -- critical, high, medium, low
    complexity TEXT,                        -- simple, moderate, complex
    root_cause TEXT,
    diagnosis_method TEXT,                  -- direct, bug_council
    fix_summary TEXT,
    files_changed JSON,
    prevention_measures TEXT,
    status TEXT DEFAULT 'open',             -- open, in_progress, resolved, wont_fix
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    resolved_at TIMESTAMP,
    council_activated BOOLEAN DEFAULT FALSE,
    council_votes JSON
);
```

### plans

Plan tracking. Links to plan JSON files on disk and optionally to a research session.

```sql
CREATE TABLE plans (
    id TEXT PRIMARY KEY,                   -- plan-001, plan-002
    name TEXT NOT NULL,
    description TEXT,
    plan_type TEXT,                         -- feature, project, maintenance
    prd_path TEXT,
    tasks_path TEXT,
    sprints_path TEXT,
    status TEXT DEFAULT 'draft',            -- draft, ready, in_progress, completed, archived
    total_sprints INTEGER DEFAULT 0,
    completed_sprints INTEGER DEFAULT 0,
    total_tasks INTEGER DEFAULT 0,
    completed_tasks INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    research_session_id INTEGER REFERENCES research_sessions(id) ON DELETE SET NULL
);
```

**Note:** The `plans` table was recreated in schema-v4.sql to add the proper `ON DELETE SET NULL` constraint on `research_session_id`.

### tasks

Task tracking for scope validation, progress, and hook integration.

```sql
CREATE TABLE tasks (
    id TEXT PRIMARY KEY,                          -- TASK-001, sprint-1-task-3, etc.
    name TEXT NOT NULL,
    description TEXT,
    task_type TEXT,                               -- feature, bugfix, refactor, test, docs
    plan_id TEXT REFERENCES plans(id) ON DELETE SET NULL,
    sprint_id TEXT,
    parent_task_id TEXT,
    session_id TEXT REFERENCES sessions(id) ON DELETE SET NULL,
    status TEXT DEFAULT 'pending',                -- pending, in_progress, completed, failed, blocked
    scope_files TEXT,                             -- Comma-separated allowed file patterns
    scope_json JSON,                             -- Full scope definition as JSON
    assigned_agent TEXT,
    assigned_model TEXT,
    priority TEXT DEFAULT 'medium',               -- critical, high, medium, low
    sequence INTEGER DEFAULT 0,
    depends_on JSON,                             -- Array of task IDs this depends on
    blocks JSON,                                 -- Array of task IDs this blocks
    estimated_effort TEXT,                        -- small, medium, large, xl
    actual_iterations INTEGER DEFAULT 0,
    files_changed JSON,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    result_summary TEXT,
    error_message TEXT,
    commit_sha TEXT
);
```

**Note:** The `tasks` table (along with `task_attempts` and `task_files`) was recreated in schema-v3.sql with hook integration support.

### task_attempts

Track retry attempts for tasks, including model escalation.

```sql
CREATE TABLE task_attempts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    task_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    session_id TEXT REFERENCES sessions(id) ON DELETE SET NULL,
    attempt_number INTEGER NOT NULL,
    model TEXT,
    agent TEXT,
    started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    ended_at TIMESTAMP,
    duration_seconds INTEGER,
    status TEXT,                                  -- success, failed, escalated
    error_type TEXT,
    error_message TEXT,
    tokens_input INTEGER,
    tokens_output INTEGER,
    cost_cents INTEGER
);
```

### task_files

Files associated with each task for scope validation. Supports both literal paths and glob patterns.

```sql
CREATE TABLE task_files (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    task_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    file_path TEXT NOT NULL,
    file_type TEXT,                               -- source, test, config, docs
    access_type TEXT DEFAULT 'allowed',           -- allowed, forbidden, read_only
    is_pattern BOOLEAN DEFAULT FALSE,
    UNIQUE(task_id, file_path)
);
```

### escalations

Model escalation history (e.g., haiku to sonnet, sonnet to opus).

```sql
CREATE TABLE escalations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    from_model TEXT NOT NULL,
    to_model TEXT NOT NULL,
    agent TEXT,
    reason TEXT NOT NULL,                  -- consecutive_failures, complexity_increase, etc.
    failure_count INTEGER,
    iteration INTEGER,
    task_id TEXT,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### acceptance_criteria

JSON-backed acceptance criteria tracking with a `passes` boolean field. Criteria are scoped to a plan via a composite unique constraint on `(plan_id, criterion_id)`.

```sql
CREATE TABLE acceptance_criteria (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    task_id TEXT,
    sprint_id TEXT,
    plan_id TEXT,
    criterion_id TEXT NOT NULL,            -- AC-001, AC-002, etc.
    description TEXT NOT NULL,
    category TEXT,                         -- functional, visual, performance, security
    passes BOOLEAN NOT NULL DEFAULT FALSE,
    verified_at TIMESTAMP,
    verified_by TEXT,
    verification_method TEXT,              -- automated_test, manual, visual
    verification_evidence TEXT,
    last_failure_reason TEXT,
    failure_count INTEGER DEFAULT 0,
    priority TEXT DEFAULT 'medium',        -- critical, high, medium, low
    sequence INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(plan_id, criterion_id)
);
```

### features

Granular feature breakdown with step-level tracking. Supports enumerating 200+ features for large projects.

```sql
CREATE TABLE features (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    plan_id TEXT,
    sprint_id TEXT,
    feature_id TEXT NOT NULL UNIQUE,       -- FEAT-001, FEAT-002
    name TEXT NOT NULL,
    description TEXT,
    category TEXT,                         -- auth, ui, api, data, etc.
    steps JSON,                            -- [{"step": "click button", "passes": false}, ...]
    passes BOOLEAN NOT NULL DEFAULT FALSE,
    all_steps_pass BOOLEAN DEFAULT FALSE,
    steps_total INTEGER DEFAULT 0,
    steps_passed INTEGER DEFAULT 0,
    verified_at TIMESTAMP,
    verified_by TEXT,
    priority TEXT DEFAULT 'medium',
    sequence INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### context_snapshots

Context window management snapshots. Records when context is summarized or checkpointed to prevent overflow.

```sql
CREATE TABLE context_snapshots (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    snapshot_type TEXT NOT NULL,            -- auto, checkpoint, overflow_prevention
    tokens_before INTEGER,
    tokens_after INTEGER,
    tokens_saved INTEGER,
    preserved_items JSON,
    summarized_items JSON,
    summary_text TEXT,
    trigger_reason TEXT,                   -- approaching_limit, iteration_complete, phase_change
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### context_budgets

Real-time context/token budget tracking per model per session.

```sql
CREATE TABLE context_budgets (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    model TEXT NOT NULL,
    context_limit INTEGER NOT NULL,
    current_usage INTEGER DEFAULT 0,
    usage_percent REAL DEFAULT 0.0,
    warn_threshold INTEGER NOT NULL DEFAULT 0,
    summarize_threshold INTEGER NOT NULL DEFAULT 0,
    status TEXT DEFAULT 'ok',              -- ok, warning, critical
    last_action TEXT,                      -- none, warned, summarized
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### progress_summaries

Human-readable progress tracking with iteration-level metrics.

```sql
CREATE TABLE progress_summaries (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    summary_text TEXT NOT NULL,
    from_iteration INTEGER,
    to_iteration INTEGER,
    tasks_completed INTEGER DEFAULT 0,
    tasks_remaining INTEGER DEFAULT 0,
    tests_passing INTEGER DEFAULT 0,
    tests_failing INTEGER DEFAULT 0,
    features_passing INTEGER DEFAULT 0,
    features_total INTEGER DEFAULT 0,
    last_commit_sha TEXT,
    files_changed JSON,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### session_phases

Two-phase architecture tracking (initializer phase vs. coding phase).

```sql
CREATE TABLE session_phases (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    phase_type TEXT NOT NULL,              -- initializer, coding, resume
    is_first_run BOOLEAN DEFAULT FALSE,
    init_script_created BOOLEAN DEFAULT FALSE,
    features_enumerated BOOLEAN DEFAULT FALSE,
    progress_file_created BOOLEAN DEFAULT FALSE,
    baseline_commit_sha TEXT,
    features_attempted INTEGER DEFAULT 0,
    features_completed INTEGER DEFAULT 0,
    resumed_from_session TEXT,
    resume_point TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### baselines

Checkpoint commits for rollback. Each baseline tags a known-good commit.

```sql
CREATE TABLE baselines (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    tag_name TEXT NOT NULL UNIQUE,             -- baseline/sprint-01/20250201-120000
    commit_hash TEXT NOT NULL,
    milestone TEXT NOT NULL,                   -- sprint-start, feature-complete, etc.
    description TEXT,
    branch TEXT,
    files_changed INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### checkpoints

Full state snapshots for session resume.

```sql
CREATE TABLE checkpoints (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    checkpoint_id TEXT NOT NULL UNIQUE,        -- chkpt-20250201-120000-abc123
    path TEXT NOT NULL,                        -- .devteam/checkpoints/chkpt-xxx
    description TEXT,
    git_commit TEXT,
    session_id TEXT,
    task_id TEXT,
    sprint_id TEXT,
    can_restore BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### checkpoint_restores

Tracks when checkpoints are restored.

```sql
CREATE TABLE checkpoint_restores (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    checkpoint_id TEXT NOT NULL REFERENCES checkpoints(checkpoint_id) ON DELETE CASCADE,
    restored_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

**Note:** The foreign key references `checkpoints(checkpoint_id)`, not `checkpoints(id)`.

### rollbacks

Records all rollback operations (automatic, manual, or smart).

```sql
CREATE TABLE rollbacks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    rollback_type TEXT NOT NULL,               -- auto, manual, smart
    target_commit TEXT NOT NULL,
    target_tag TEXT,
    reason TEXT,
    from_commit TEXT,
    trigger_type TEXT,                         -- regression, user_request, error
    check_type TEXT,                           -- build, test, typecheck, lint
    backup_branch TEXT,
    rolled_back_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### token_usage

Granular cost and token tracking per API call. Costs are stored in USD (not cents).

```sql
CREATE TABLE token_usage (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT,
    task_id TEXT,
    sprint_id TEXT,
    model TEXT NOT NULL,
    input_tokens INTEGER NOT NULL DEFAULT 0,
    output_tokens INTEGER NOT NULL DEFAULT 0,
    cost_usd REAL NOT NULL DEFAULT 0,
    operation TEXT,                            -- code-gen, test, review, etc.
    agent_name TEXT,
    recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### error_log

Tracks errors for recovery analysis and circuit breaker state.

```sql
CREATE TABLE error_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT,
    task_id TEXT,
    operation TEXT,
    error_type TEXT NOT NULL,                  -- transient, permanent, recoverable
    error_message TEXT NOT NULL,
    error_pattern TEXT,                        -- Matched pattern from error-recovery.yaml
    recovery_action TEXT,
    recovery_success BOOLEAN,
    retry_count INTEGER DEFAULT 0,
    circuit_opened BOOLEAN DEFAULT FALSE,
    logged_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### dead_letter

Failed operations queued for later retry or manual inspection.

```sql
CREATE TABLE dead_letter (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    operation_type TEXT NOT NULL,
    operation_params JSON,
    error_message TEXT,
    stack_trace TEXT,
    attempt_count INTEGER DEFAULT 1,
    session_id TEXT,
    task_id TEXT,
    status TEXT DEFAULT 'pending',             -- pending, retried, failed, expired
    retry_after TIMESTAMP,
    expires_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

## Foreign Key Constraints

All foreign keys use either `ON DELETE CASCADE` or `ON DELETE SET NULL`:

| Table | Column | References | On Delete |
|-------|--------|------------|-----------|
| session_state | session_id | sessions(id) | CASCADE |
| events | session_id | sessions(id) | CASCADE |
| agent_runs | session_id | sessions(id) | CASCADE |
| gate_results | session_id | sessions(id) | CASCADE |
| interviews | session_id | sessions(id) | CASCADE |
| interview_questions | interview_id | interviews(id) | CASCADE |
| research_sessions | session_id | sessions(id) | CASCADE |
| research_findings | research_session_id | research_sessions(id) | CASCADE |
| bugs | session_id | sessions(id) | CASCADE |
| plans | research_session_id | research_sessions(id) | SET NULL |
| tasks | plan_id | plans(id) | SET NULL |
| tasks | session_id | sessions(id) | SET NULL |
| task_attempts | task_id | tasks(id) | CASCADE |
| task_attempts | session_id | sessions(id) | SET NULL |
| task_files | task_id | tasks(id) | CASCADE |
| escalations | session_id | sessions(id) | CASCADE |
| context_snapshots | session_id | sessions(id) | CASCADE |
| context_budgets | session_id | sessions(id) | CASCADE |
| progress_summaries | session_id | sessions(id) | CASCADE |
| session_phases | session_id | sessions(id) | CASCADE |
| checkpoint_restores | checkpoint_id | checkpoints(checkpoint_id) | CASCADE |

Deleting a session cascades to: `session_state`, `events`, `agent_runs`, `gate_results`, `interviews` (and their `interview_questions`), `research_sessions` (and their `research_findings`), `bugs`, `escalations`, `context_snapshots`, `context_budgets`, `progress_summaries`, and `session_phases`. Tasks and task_attempts linked to a deleted session have their `session_id` set to NULL rather than being deleted.

## Views

### v_current_session

Current running session.

```sql
CREATE VIEW v_current_session AS
SELECT * FROM sessions WHERE status = 'running' ORDER BY started_at DESC LIMIT 1;
```

### v_session_summary

Session summary with token totals and cost.

```sql
CREATE VIEW v_session_summary AS
SELECT
    s.id, s.command, s.status, s.started_at, s.ended_at,
    s.current_phase, s.current_agent, s.current_model,
    s.current_iteration, s.execution_mode,
    s.total_tokens_input + s.total_tokens_output as total_tokens,
    ROUND(s.total_cost_cents / 100.0, 2) as total_cost_dollars,
    (SELECT COUNT(*) FROM agent_runs ar WHERE ar.session_id = s.id) as agent_runs,
    (SELECT COUNT(*) FROM escalations e WHERE e.session_id = s.id) as escalations,
    s.bug_council_activated
FROM sessions s;
```

### v_model_usage

Model usage breakdown by session.

```sql
CREATE VIEW v_model_usage AS
SELECT
    session_id, model,
    COUNT(*) as runs,
    SUM(CASE WHEN status = 'success' THEN 1 ELSE 0 END) as successes,
    SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) as failures,
    ROUND(AVG(CASE WHEN status = 'success' THEN 1.0 ELSE 0.0 END) * 100, 1) as success_rate,
    SUM(tokens_input) as tokens_input,
    SUM(tokens_output) as tokens_output,
    SUM(cost_cents) as cost_cents
FROM agent_runs
GROUP BY session_id, model;
```

### v_agent_performance

Agent success rates and cost.

```sql
CREATE VIEW v_agent_performance AS
SELECT
    agent,
    COUNT(*) as total_runs,
    SUM(CASE WHEN status = 'success' THEN 1 ELSE 0 END) as successes,
    ROUND(AVG(CASE WHEN status = 'success' THEN 1.0 ELSE 0.0 END) * 100, 1) as success_rate,
    AVG(duration_seconds) as avg_duration_seconds,
    SUM(cost_cents) as total_cost_cents
FROM agent_runs
GROUP BY agent;
```

### v_agent_call_chain

Added in v5. One row per agent run, joined to its immediate parent (if any) via `invoked_by_run_id`, for reconstructing "who dispatched this task" chains (e.g. `sprint-orchestrator -> task-loop -> frontend:developer`) without a recursive CTE for the common single-level case.

```sql
CREATE VIEW v_agent_call_chain AS
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
```

### v_current_task

Current in-progress task.

```sql
CREATE VIEW v_current_task AS
SELECT * FROM tasks WHERE status = 'in_progress' ORDER BY started_at DESC LIMIT 1;
```

### v_sprint_progress

Sprint completion rates.

```sql
CREATE VIEW v_sprint_progress AS
SELECT
    sprint_id,
    COUNT(*) as total_tasks,
    SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) as completed,
    SUM(CASE WHEN status = 'in_progress' THEN 1 ELSE 0 END) as in_progress,
    SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) as failed,
    SUM(CASE WHEN status = 'pending' THEN 1 ELSE 0 END) as pending,
    ROUND(AVG(CASE WHEN status = 'completed' THEN 1.0 ELSE 0.0 END) * 100, 1) as completion_rate
FROM tasks
WHERE sprint_id IS NOT NULL
GROUP BY sprint_id;
```

### v_task_attempts_summary

Retry statistics per task.

```sql
CREATE VIEW v_task_attempts_summary AS
SELECT
    task_id,
    COUNT(*) as total_attempts,
    SUM(CASE WHEN status = 'success' THEN 1 ELSE 0 END) as successes,
    SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) as failures,
    MAX(attempt_number) as last_attempt,
    SUM(tokens_input + tokens_output) as total_tokens,
    SUM(cost_cents) as total_cost_cents
FROM task_attempts
GROUP BY task_id;
```

### v_gate_pass_rates

Quality gate pass rates.

```sql
CREATE VIEW v_gate_pass_rates AS
SELECT
    gate,
    COUNT(*) as total_runs,
    SUM(CASE WHEN passed THEN 1 ELSE 0 END) as passes,
    ROUND(AVG(CASE WHEN passed THEN 1.0 ELSE 0.0 END) * 100, 1) as pass_rate
FROM gate_results
GROUP BY gate;
```

### v_acceptance_criteria_status

Acceptance criteria pass rates by task.

```sql
CREATE VIEW v_acceptance_criteria_status AS
SELECT
    task_id,
    COUNT(*) as total_criteria,
    SUM(CASE WHEN passes THEN 1 ELSE 0 END) as passing,
    SUM(CASE WHEN NOT passes THEN 1 ELSE 0 END) as failing,
    ROUND(AVG(CASE WHEN passes THEN 1.0 ELSE 0.0 END) * 100, 1) as pass_rate
FROM acceptance_criteria
GROUP BY task_id;
```

### v_feature_status

Feature pass rates by plan.

```sql
CREATE VIEW v_feature_status AS
SELECT
    plan_id,
    COUNT(*) as total_features,
    SUM(CASE WHEN passes THEN 1 ELSE 0 END) as passing,
    SUM(CASE WHEN NOT passes THEN 1 ELSE 0 END) as failing,
    SUM(steps_total) as total_steps,
    SUM(steps_passed) as steps_passed,
    ROUND(AVG(CASE WHEN passes THEN 1.0 ELSE 0.0 END) * 100, 1) as feature_pass_rate
FROM features
GROUP BY plan_id;
```

### v_context_status

Context budget status per session and model.

```sql
CREATE VIEW v_context_status AS
SELECT
    cb.session_id, cb.model, cb.context_limit,
    cb.current_usage, cb.usage_percent, cb.status,
    (SELECT COUNT(*) FROM context_snapshots cs
     WHERE cs.session_id = cb.session_id) as snapshots_created
FROM context_budgets cb;
```

### v_session_cost

Per-session cost totals from the `token_usage` table.

```sql
CREATE VIEW v_session_cost AS
SELECT
    session_id,
    COUNT(*) as api_calls,
    SUM(input_tokens) as total_input_tokens,
    SUM(output_tokens) as total_output_tokens,
    SUM(input_tokens + output_tokens) as total_tokens,
    ROUND(SUM(cost_usd), 4) as total_cost_usd,
    MIN(recorded_at) as first_call,
    MAX(recorded_at) as last_call
FROM token_usage
GROUP BY session_id;
```

### v_daily_cost

Daily cost aggregation from the `token_usage` table.

```sql
CREATE VIEW v_daily_cost AS
SELECT
    date(recorded_at) as date,
    COUNT(*) as api_calls,
    SUM(input_tokens + output_tokens) as total_tokens,
    ROUND(SUM(cost_usd), 4) as total_cost_usd
FROM token_usage
GROUP BY date(recorded_at);
```

### v_error_summary

Error type breakdown with recovery statistics.

```sql
CREATE VIEW v_error_summary AS
SELECT
    error_type,
    COUNT(*) as occurrences,
    SUM(CASE WHEN recovery_success THEN 1 ELSE 0 END) as recovered,
    SUM(CASE WHEN circuit_opened THEN 1 ELSE 0 END) as circuits_opened
FROM error_log
GROUP BY error_type;
```

## Example Queries

### Get current session status
```sql
SELECT * FROM v_current_session;
```

### Get cost breakdown by model
```sql
SELECT
    model,
    cost_cents / 100.0 as cost_dollars,
    runs
FROM v_model_usage
ORDER BY cost_cents DESC;
```

### Find failed gates in last session
```sql
SELECT gr.*
FROM gate_results gr
JOIN sessions s ON gr.session_id = s.id
WHERE s.id = (SELECT id FROM sessions ORDER BY started_at DESC LIMIT 1)
AND NOT gr.passed;
```

### Get escalation history
```sql
SELECT
    e.from_model,
    e.to_model,
    e.reason,
    e.timestamp,
    s.command
FROM escalations e
JOIN sessions s ON e.session_id = s.id
ORDER BY e.timestamp DESC
LIMIT 10;
```

### Calculate session costs for today
```sql
SELECT
    SUM(total_cost_cents) / 100.0 as total_cost_dollars,
    COUNT(*) as session_count
FROM sessions
WHERE date(started_at) = date('now');
```

### Get agent performance ranked by success rate
```sql
SELECT
    agent,
    total_runs,
    successes,
    success_rate,
    total_cost_cents / 100.0 as total_cost_dollars
FROM v_agent_performance
ORDER BY success_rate DESC;
```

### Get sprint progress
```sql
SELECT
    sprint_id,
    total_tasks,
    completed,
    in_progress,
    failed,
    completion_rate
FROM v_sprint_progress;
```

### Get daily cost trend
```sql
SELECT date, api_calls, total_tokens, total_cost_usd
FROM v_daily_cost
ORDER BY date DESC
LIMIT 7;
```

### Find tasks blocked by dependencies
```sql
SELECT id, name, status, depends_on
FROM tasks
WHERE status = 'blocked'
ORDER BY priority, sequence;
```

### Get error recovery success rate
```sql
SELECT
    error_type,
    occurrences,
    recovered,
    ROUND(100.0 * recovered / occurrences, 1) as recovery_rate
FROM v_error_summary;
```

## Helper Scripts

### Bash (`scripts/state.sh`)
```bash
source scripts/state.sh

# Start session
SESSION_ID=$(start_session "/devteam:implement" "implement")

# Get/set state
set_state "current_phase" "executing"
phase=$(get_state "current_phase")

# Track tokens
add_tokens 1000 500 15  # in, out, cost_cents

# End session
end_session "completed" "All tasks done"
```

### PowerShell (`scripts/state.ps1`)
```powershell
. scripts/state.ps1

$sessionId = Start-DevTeamSession "/devteam:implement" "implement"
Set-DevTeamState "current_phase" "executing"
$phase = Get-DevTeamState "current_phase"
Add-DevTeamTokens 1000 500 15
End-DevTeamSession "completed" "All tasks done"
```

## Maintenance

### Backup
```bash
cp .devteam/devteam.db .devteam/devteam.db.backup
```

### Reset
```bash
rm .devteam/devteam.db
bash scripts/db-init.sh
```

### Query from command line
```bash
sqlite3 .devteam/devteam.db "SELECT * FROM v_session_summary LIMIT 5"
```

### Vacuum (reclaim space)
```bash
sqlite3 .devteam/devteam.db "VACUUM"
```

## Schema Version History

| Version | File | Tables | Views | Description |
|---------|------|--------|-------|-------------|
| 1.0.0 | `schema.sql` | 15 | 8 | Core tables: sessions, session_state, events, agent_runs, gate_results, interviews, interview_questions, research_sessions, research_findings, bugs, plans, tasks, task_attempts, task_files, escalations. 25+ indexes. |
| 2.0.0 | `schema-v2.sql` | +13 | +6 | Added acceptance_criteria, features, context_snapshots, context_budgets, progress_summaries, session_phases, baselines, checkpoints, checkpoint_restores, rollbacks, token_usage, error_log, dead_letter. Added views for criteria status, feature status, context status, session cost, daily cost, error summary. |
| 3.0.0 | `schema-v3.sql` | 0 (recreated) | 0 (recreated) | Recreated tasks, task_attempts, and task_files tables with hook integration support. Recreated v_current_task, v_sprint_progress, and v_task_attempts_summary views. |
| 4.0.0 | `schema-v4.sql` | 0 (recreated) | 0 | Recreated plans table to add proper `ON DELETE SET NULL` FK constraint on `research_session_id`. Migration is wrapped in a transaction. |
| 5.0.0 | `schema-v5.sql` | 0 | +1 | Added `invoked_by_agent` and `invoked_by_run_id` columns to `agent_runs` for call-hierarchy tracking (Architecture Audit Phase 1, prerequisite for the Phase 6 `execution-ledger` agent). Added `v_agent_call_chain` view. |

Schema versions are managed by `scripts/db-init.sh`, which applies each migration file in order. `hooks/lib/hook-common.sh`'s `_auto_init_database()` is a separate, minimal auto-init path used when a hook fires before `db-init.sh` has run; its migration list must be kept in sync manually.
