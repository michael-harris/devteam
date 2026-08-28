#!/bin/bash
# DevTeam Event Logging Functions
# Provides secure event logging for DevTeam hooks and commands
#
# SECURITY: All SQL queries use proper escaping and input validation
# ERROR HANDLING: Uses set -euo pipefail and validates all inputs
#
# Usage: source this file in hooks and commands
#   source "$(dirname "$0")/../scripts/events.sh"

set -euo pipefail

# Get script directory and source state functions (which also sources common.sh)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/state.sh"

# ============================================================================
# VALID EVENT TYPES AND CATEGORIES
# ============================================================================

readonly VALID_EVENT_TYPES=(
    "session_started"
    "session_ended"
    "phase_changed"
    "agent_started"
    "agent_completed"
    "agent_failed"
    "model_escalated"
    "model_deescalated"
    "gate_passed"
    "gate_failed"
    "bug_council_activated"
    "bug_council_completed"
    "interview_started"
    "interview_question"
    "interview_completed"
    "research_started"
    "research_finding"
    "research_completed"
    "task_started"
    "task_completed"
    "task_failed"
    "error_occurred"
    "warning_issued"
    "abandonment_detected"
    "abandonment_prevented"
)

readonly VALID_EVENT_CATEGORIES=(
    "general"
    "session"
    "phase"
    "agent"
    "escalation"
    "gate"
    "bug_council"
    "interview"
    "research"
    "task"
    "error"
    "warning"
    "persistence"
)

# ============================================================================
# VALIDATION HELPERS
# ============================================================================

# Validate event type
validate_event_type() {
    local event_type="$1"
    if ! _in_array "$event_type" "${VALID_EVENT_TYPES[@]}"; then
        log_warn "Unknown event type: $event_type (allowing anyway)" "events"
    fi
    return 0  # Allow unknown types but log warning
}

# Validate event category
validate_event_category() {
    local category="$1"
    if ! _in_array "$category" "${VALID_EVENT_CATEGORIES[@]}"; then
        log_warn "Unknown event category: $category (allowing anyway)" "events"
    fi
    return 0  # Allow unknown categories but log warning
}

# ============================================================================
# CORE EVENT LOGGING
# ============================================================================

# Log an event to the database
# Args: event_type, [category], [message], [data], [agent], [model], [tokens_input], [tokens_output], [cost_cents]
log_event() {
    local event_type="$1"
    local category="${2:-general}"
    local message="${3:-}"
    local data="${4:-null}"
    local agent="${5:-}"
    local model="${6:-}"
    local tokens_input="${7:-0}"
    local tokens_output="${8:-0}"
    local cost_cents="${9:-0}"

    # Get current session
    local session_id
    session_id=$(get_current_session_id) || true

    if [ -z "$session_id" ]; then
        log_debug "No active session, skipping event log" "events"
        return 0
    fi

    # Validate numeric values
    if ! validate_numeric "$tokens_input" "tokens_input" 2>/dev/null; then
        tokens_input=0
    fi
    if ! validate_numeric "$tokens_output" "tokens_output" 2>/dev/null; then
        tokens_output=0
    fi
    if ! validate_decimal "$cost_cents" "cost_cents" 2>/dev/null; then
        cost_cents=0
    fi

    # Get current iteration and phase
    local iteration phase
    iteration=$(get_current_iteration) || iteration=0
    phase=$(get_current_phase) || phase=""

    # Escape all string values for SQL safety
    local esc_session_id esc_event_type esc_category esc_message esc_data esc_agent esc_model esc_phase
    esc_session_id=$(sql_escape "$session_id")
    esc_event_type=$(sql_escape "$event_type")
    esc_category=$(sql_escape "$category")
    esc_message=$(sql_escape "$message")
    esc_data=$(sql_escape "$data")
    esc_agent=$(sql_escape "$agent")
    esc_model=$(sql_escape "$model")
    esc_phase=$(sql_escape "$phase")

    local query="INSERT INTO events (
            session_id, event_type, event_category, message, data,
            agent, model, iteration, phase,
            tokens_input, tokens_output, cost_cents
        ) VALUES (
            '$esc_session_id', '$esc_event_type', '$esc_category', '$esc_message', '$esc_data',
            '$esc_agent', '$esc_model', ${iteration:-0}, '$esc_phase',
            ${tokens_input:-0}, ${tokens_output:-0}, ${cost_cents:-0}
        );"

    if ! sql_exec "$query" > /dev/null; then
        log_warn "Failed to log event: $event_type" "events"
        return 1
    fi

    log_debug "Event logged: $event_type" "events"
}

# ============================================================================
# SESSION EVENTS
# ============================================================================

# Log session started event
# Args: command, command_type
log_session_started() {
    local command="$1"
    local command_type="$2"

    local json_data
    json_data=$(json_object "command_type" "$command_type")
    log_event "session_started" "session" "Session started: $command" "$json_data"
}

# Log session ended event
# Args: status, reason
log_session_ended() {
    local status="$1"
    local reason="$2"

    local json_data
    json_data=$(json_object "status" "$status" "reason" "$reason")
    log_event "session_ended" "session" "Session ended: $status" "$json_data"
}

# ============================================================================
# PHASE EVENTS
# ============================================================================

# Log phase change event
# Args: new_phase, [previous_phase]
log_phase_changed() {
    local new_phase="$1"
    local previous_phase="${2:-}"

    local json_data
    json_data=$(json_object "previous" "$previous_phase" "current" "$new_phase")
    log_event "phase_changed" "phase" "Phase: $new_phase" "$json_data"
}

# ============================================================================
# AGENT EVENTS
# ============================================================================

# Log agent started event
# Args: agent, model, [task_id], [invoked_by_agent], [invoked_by_run_id]
#
# invoked_by_agent/invoked_by_run_id record the call hierarchy (schema v5,
# agent_runs.invoked_by_agent / invoked_by_run_id) -- the dispatching
# orchestrator's own agent id and its own agent_runs.id, so chains like
# sprint-orchestrator -> task-loop -> frontend:developer can be reconstructed
# via v_agent_call_chain instead of guessed from timestamps. Leave both empty
# when the caller is a command/skill (no parent agent run to attribute to).
#
# On success, echoes the new agent_runs.id to stdout so the caller can pass
# it as invoked_by_run_id to any agent IT dispatches:
#   run_id=$(log_agent_started "orchestration:task-loop" "opus" "$task_id" \
#       "orchestration:sprint-orchestrator" "$parent_run_id")
log_agent_started() {
    local agent="$1"
    local model="$2"
    local task_id="${3:-}"
    local invoked_by_agent="${4:-}"
    local invoked_by_run_id="${5:-}"

    if [ -z "$agent" ]; then
        log_error "Agent name required" "events"
        return 1
    fi

    if [ -n "$invoked_by_run_id" ] && ! validate_numeric "$invoked_by_run_id" "invoked_by_run_id" 2>/dev/null; then
        log_warn "Ignoring non-numeric invoked_by_run_id: $invoked_by_run_id" "events"
        invoked_by_run_id=""
    fi

    local json_data
    json_data=$(json_object "task_id" "$task_id" "invoked_by_agent" "$invoked_by_agent" "invoked_by_run_id" "$invoked_by_run_id")
    log_event "agent_started" "agent" "Agent started: $agent ($model)" \
        "$json_data" "$agent" "$model"

    # Also insert into agent_runs table
    local session_id
    session_id=$(get_current_session_id) || true

    if [ -z "$session_id" ]; then
        return 0
    fi

    local iteration
    iteration=$(get_current_iteration) || iteration=0

    local esc_session_id esc_agent esc_model esc_task_id esc_invoked_by_agent
    esc_session_id=$(sql_escape "$session_id")
    esc_agent=$(sql_escape "$agent")
    esc_model=$(sql_escape "$model")
    esc_task_id=$(sql_escape "$task_id")
    esc_invoked_by_agent=$(sql_escape "$invoked_by_agent")

    # agent_runs.task_id REFERENCES tasks(id) -- but nothing in this codebase
    # ever inserts a row into `tasks` (task state is tracked via the kv-state
    # store, e.g. `task.TASK-XXX.status`, not the relational `tasks` table).
    # Under `PRAGMA foreign_keys = ON` (which sql_exec always sets), that made
    # EVERY task-scoped agent_runs insert silently fail its FK constraint --
    # confirmed empirically: a real sprint/task-loop run produced zero
    # agent_runs rows with a non-NULL task_id, only the task_id-less
    # sprint-level rows ever succeeded. That silently broke all per-task cost
    # and call-hierarchy attribution (the exact thing orchestration:task-loop
    # and orchestration:sprint-orchestrator populate `invoked_by_*` for, and
    # what orchestration:execution-ledger, Phase 6, depends on to answer "what
    # ran under TASK-XXX"). Fix: ensure a minimal placeholder `tasks` row
    # exists before referencing task_id -- the table already has the right
    # shape (schema.sql), it was just never populated. INSERT OR IGNORE is
    # idempotent and never overwrites a fuller row a future planning-pipeline
    # write might add for this id.
    if [ -n "$task_id" ]; then
        local task_insert_query="INSERT OR IGNORE INTO tasks (id, name, status) VALUES ('$esc_task_id', '$esc_task_id', 'in_progress');"
        sql_exec "$task_insert_query" > /dev/null || log_warn "Failed to ensure tasks row for task_id=$task_id" "events"
    fi

    # INSERT + last_insert_rowid() must run in the same sqlite3 invocation
    # (same connection) for last_insert_rowid() to reflect this row.
    local query="INSERT INTO agent_runs (session_id, agent, model, task_id, iteration, status, invoked_by_agent, invoked_by_run_id)
        VALUES ('$esc_session_id', '$esc_agent', '$esc_model', NULLIF('$esc_task_id', ''), ${iteration:-0}, 'running',
                NULLIF('$esc_invoked_by_agent', ''), NULLIF(${invoked_by_run_id:-NULL}, ''));
        SELECT last_insert_rowid();"

    # Matches every other function in this file (log_agent_completed,
    # log_agent_failed, log_gate_passed, etc.): a logging/state-tracking
    # failure must never itself abort the caller (hooks in this codebase are
    # deliberately "fail silently -- never block Claude Code"). On failure,
    # warn and echo nothing; a caller doing `run_id=$(log_agent_started ...)`
    # then simply gets an empty run_id and its own dispatches are recorded
    # parentless instead of attributed -- degraded, not broken.
    local new_run_id
    if ! new_run_id=$(sql_exec "$query"); then
        log_warn "Failed to insert agent_runs record" "events"
        return 0
    fi

    echo "$new_run_id"
}

# Log agent completed event
# Args: agent, model, [files_changed], [tokens_input], [tokens_output], [cost_cents], [run_id], [output_summary]
#
# run_id is the agent_runs.id returned by the log_agent_started call this is
# closing (callers already hold it, captured for invoked_by_run_id
# propagation -- see log_agent_started's docstring). Pass it whenever you
# have it: without it, the close falls back to matching the most recent
# 'running' row for this agent+model+session, which mis-closes a DIFFERENT
# task's row whenever two task-loops dispatch the same agent at the same
# model concurrently (observed live in a concurrent E2E run: TASK-006's and
# TASK-007's workflow-compliance rows cross-closed). The exact-id path is
# always correct; the fallback is a best-effort default for old callers.
#
# output_summary is a short, human-readable, 1-2 SENTENCE description of what
# this specific run actually did (e.g. "Added the /dashboard endpoint with
# per-course progress aggregation; 3 files changed." or "Requirements FAILED:
# 2/5 acceptance criteria unmet -- missing course-filter query param."). The
# column already existed in schema.sql but nothing ever wrote to it, so every
# agent_runs row was previously legible only as agent+model+status -- no record
# of what happened. Every dispatching orchestrator (task-loop, sprint-orchestrator)
# MUST ask the dispatched agent to state this in its own final output, then pass
# it straight through here. This is the field execution-ledger's per-task report
# renders as the one-line "what happened" next to each agent in its call table.
log_agent_completed() {
    local agent="$1"
    local model="$2"
    local files_changed="${3:-[]}"
    local tokens_input="${4:-0}"
    local tokens_output="${5:-0}"
    local cost_cents="${6:-0}"
    local run_id="${7:-}"
    local output_summary="${8:-}"

    if [ -n "$run_id" ] && ! validate_numeric "$run_id" "run_id" 2>/dev/null; then
        log_warn "Ignoring non-numeric run_id: $run_id" "events"
        run_id=""
    fi

    # Cap length defensively -- this is a summary line, not a report.
    output_summary=$(sanitize_input "$output_summary" 500)

    if [ -z "$agent" ]; then
        log_error "Agent name required" "events"
        return 1
    fi

    # Validate numeric values
    if ! validate_numeric "$tokens_input" "tokens_input" 2>/dev/null; then
        tokens_input=0
    fi
    if ! validate_numeric "$tokens_output" "tokens_output" 2>/dev/null; then
        tokens_output=0
    fi
    if ! validate_decimal "$cost_cents" "cost_cents" 2>/dev/null; then
        cost_cents=0
    fi

    log_event "agent_completed" "agent" "Agent completed: $agent" \
        "{\"files_changed\": $files_changed}" "$agent" "$model" \
        "$tokens_input" "$tokens_output" "$cost_cents"

    # Update agent_runs table
    local session_id
    session_id=$(get_current_session_id) || true

    if [ -z "$session_id" ]; then
        return 0
    fi

    local esc_session_id esc_agent esc_files_changed esc_output_summary
    esc_session_id=$(sql_escape "$session_id")
    esc_agent=$(sql_escape "$agent")
    esc_files_changed=$(sql_escape "$files_changed")
    esc_output_summary=$(sql_escape "$output_summary")

    local esc_model
    esc_model=$(sql_escape "$model")

    # Exact-id path when the caller passed its own run_id (see docstring above);
    # otherwise fall back to the agent+model+session heuristic, which is only
    # safe when at most one 'running' row for this agent+model exists at once.
    local where_clause
    if [ -n "$run_id" ]; then
        where_clause="id = ${run_id} AND session_id = '$esc_session_id'"
    else
        where_clause="rowid = (
            SELECT rowid FROM agent_runs
            WHERE session_id = '$esc_session_id'
            AND agent = '$esc_agent'
            AND model = '$esc_model'
            AND status = 'running'
            ORDER BY started_at DESC
            LIMIT 1
        )"
    fi

    local query="BEGIN IMMEDIATE TRANSACTION;
        UPDATE agent_runs
        SET status = 'success',
            ended_at = CURRENT_TIMESTAMP,
            duration_seconds = CAST((julianday(CURRENT_TIMESTAMP) - julianday(started_at)) * 86400 AS INTEGER),
            files_changed = '$esc_files_changed',
            tokens_input = ${tokens_input:-0},
            tokens_output = ${tokens_output:-0},
            cost_cents = ${cost_cents:-0},
            output_summary = NULLIF('$esc_output_summary', '')
        WHERE $where_clause;
        COMMIT;"

    sql_exec "$query" > /dev/null || log_warn "Failed to update agent_runs record" "events"

    # Update session totals
    add_tokens "$tokens_input" "$tokens_output" "$cost_cents" || log_warn "Failed to update session token totals" "events"
}

# Log agent failed event
# Args: agent, model, error_message, [error_type], [run_id]
#
# run_id: see log_agent_completed's docstring -- pass it whenever you have it
# to close the exact row instead of the racy agent+model+session heuristic.
log_agent_failed() {
    local agent="$1"
    local model="$2"
    local error_message="$3"
    local error_type="${4:-unknown}"
    local run_id="${5:-}"

    if [ -n "$run_id" ] && ! validate_numeric "$run_id" "run_id" 2>/dev/null; then
        log_warn "Ignoring non-numeric run_id: $run_id" "events"
        run_id=""
    fi

    if [ -z "$agent" ]; then
        log_error "Agent name required" "events"
        return 1
    fi

    local json_data
    json_data=$(json_object "error_type" "$error_type")
    log_event "agent_failed" "agent" "Agent failed: $agent - $error_message" \
        "$json_data" "$agent" "$model"

    # Update agent_runs table
    local session_id
    session_id=$(get_current_session_id) || true

    if [ -z "$session_id" ]; then
        return 0
    fi

    local esc_session_id esc_agent esc_error_message esc_error_type
    esc_session_id=$(sql_escape "$session_id")
    esc_agent=$(sql_escape "$agent")
    esc_error_message=$(sql_escape "$error_message")
    esc_error_type=$(sql_escape "$error_type")

    local esc_model
    esc_model=$(sql_escape "$model")

    # Exact-id path when available; see log_agent_completed() for the same pattern.
    local where_clause
    if [ -n "$run_id" ]; then
        where_clause="id = ${run_id} AND session_id = '$esc_session_id'"
    else
        where_clause="rowid = (
            SELECT rowid FROM agent_runs
            WHERE session_id = '$esc_session_id'
            AND agent = '$esc_agent'
            AND model = '$esc_model'
            AND status = 'running'
            ORDER BY started_at DESC
            LIMIT 1
        )"
    fi

    local query="UPDATE agent_runs
        SET status = 'failed',
            ended_at = CURRENT_TIMESTAMP,
            duration_seconds = CAST((julianday(CURRENT_TIMESTAMP) - julianday(started_at)) * 86400 AS INTEGER),
            error_message = '$esc_error_message',
            error_type = '$esc_error_type'
        WHERE $where_clause;"

    sql_exec "$query" > /dev/null || log_warn "Failed to update agent_runs record" "events"

    # Increment failure counter
    increment_failures || true
}

# ============================================================================
# ESCALATION EVENTS
# ============================================================================

# Log model escalated event
# Args: from_model, to_model, reason, [agent]
log_model_escalated() {
    local from_model="$1"
    local to_model="$2"
    local reason="$3"
    local agent="${4:-}"

    local json_from json_to json_reason
    json_from=$(json_escape "$from_model")
    json_to=$(json_escape "$to_model")
    json_reason=$(json_escape "$reason")

    log_event "model_escalated" "escalation" "Model escalated: $from_model -> $to_model ($reason)" \
        "{\"from\": \"$json_from\", \"to\": \"$json_to\", \"reason\": \"$json_reason\"}" "$agent" "$to_model"

    # Record in escalations table
    record_escalation "$from_model" "$to_model" "$reason" "$agent" || true
}

# Log model de-escalated event
# Args: from_model, to_model, reason
log_model_deescalated() {
    local from_model="$1"
    local to_model="$2"
    local reason="$3"

    local json_from json_to json_reason
    json_from=$(json_escape "$from_model")
    json_to=$(json_escape "$to_model")
    json_reason=$(json_escape "$reason")

    log_event "model_deescalated" "escalation" "Model de-escalated: $from_model -> $to_model ($reason)" \
        "{\"from\": \"$json_from\", \"to\": \"$json_to\", \"reason\": \"$json_reason\"}"
}

# ============================================================================
# QUALITY GATE EVENTS
# ============================================================================

# Log gate passed event
# Args: gate, [details]
log_gate_passed() {
    local gate="$1"
    local details="${2:-{}}"

    if [ -z "$gate" ]; then
        log_error "Gate name required" "events"
        return 1
    fi

    local esc_details
    esc_details=$(sql_escape "$details")
    log_event "gate_passed" "gate" "Gate passed: $gate" "$details"

    # Insert into gate_results table
    local session_id
    session_id=$(get_current_session_id) || true

    if [ -z "$session_id" ]; then
        return 0
    fi

    local iteration
    iteration=$(get_current_iteration) || iteration=0

    local esc_session_id esc_gate
    esc_session_id=$(sql_escape "$session_id")
    esc_gate=$(sql_escape "$gate")

    local query="INSERT INTO gate_results (session_id, gate, iteration, passed, details)
        VALUES ('$esc_session_id', '$esc_gate', ${iteration:-0}, TRUE, '$esc_details');"

    sql_exec "$query" > /dev/null || log_warn "Failed to insert gate_results record" "events"
}

# Log gate failed event
# Args: gate, [error_count], [details]
log_gate_failed() {
    local gate="$1"
    local error_count="${2:-0}"
    local details="${3:-{}}"

    if [ -z "$gate" ]; then
        log_error "Gate name required" "events"
        return 1
    fi

    # Validate error_count
    if ! validate_numeric "$error_count" "error_count" 2>/dev/null; then
        error_count=0
    fi

    local esc_details
    esc_details=$(sql_escape "$details")
    log_event "gate_failed" "gate" "Gate failed: $gate ($error_count errors)" "$details"

    # Insert into gate_results table
    local session_id
    session_id=$(get_current_session_id) || true

    if [ -z "$session_id" ]; then
        return 0
    fi

    local iteration
    iteration=$(get_current_iteration) || iteration=0

    local esc_session_id esc_gate
    esc_session_id=$(sql_escape "$session_id")
    esc_gate=$(sql_escape "$gate")

    local query="INSERT INTO gate_results (session_id, gate, iteration, passed, error_count, details)
        VALUES ('$esc_session_id', '$esc_gate', ${iteration:-0}, FALSE, ${error_count:-0}, '$esc_details');"

    sql_exec "$query" > /dev/null || log_warn "Failed to insert gate_results record" "events"
}

# ============================================================================
# BUG COUNCIL EVENTS
# ============================================================================

# Log bug council activated event
# Args: reason
log_bug_council_activated() {
    local reason="$1"

    if [ -z "$reason" ]; then
        log_error "Reason required" "events"
        return 1
    fi

    local json_reason
    json_reason=$(json_escape "$reason")
    log_event "bug_council_activated" "bug_council" "Bug Council activated: $reason" \
        "{\"reason\": \"$json_reason\"}"

    activate_bug_council "$reason" || true
}

# Log bug council completed event
# Args: winning_proposal, [votes]
log_bug_council_completed() {
    local winning_proposal="$1"
    local votes="${2:-{}}"

    local esc_votes
    esc_votes=$(sql_escape "$votes")
    log_event "bug_council_completed" "bug_council" "Bug Council decision: $winning_proposal" "$votes"
}

# ============================================================================
# INTERVIEW EVENTS
# ============================================================================

# Log interview started event
# Args: interview_type
log_interview_started() {
    local interview_type="$1"

    if [ -z "$interview_type" ]; then
        log_error "Interview type required" "events"
        return 1
    fi

    local esc_type
    esc_type=$(sql_escape "$interview_type")
    log_event "interview_started" "interview" "Interview started: $interview_type" \
        "{\"type\": \"$esc_type\"}"

    # Create interview record
    local session_id
    session_id=$(get_current_session_id) || true

    if [ -z "$session_id" ]; then
        return 0
    fi

    local esc_session_id
    esc_session_id=$(sql_escape "$session_id")

    local query="INSERT INTO interviews (session_id, interview_type, status)
        VALUES ('$esc_session_id', '$esc_type', 'in_progress');"

    sql_exec "$query" > /dev/null || log_warn "Failed to insert interview record" "events"
}

# Log interview question event
# Args: question_key, question_text, [response]
log_interview_question() {
    local question_key="$1"
    local question_text="$2"
    local response="${3:-}"

    local esc_key esc_response
    esc_key=$(sql_escape "$question_key")
    esc_response=$(sql_escape "$response")
    log_event "interview_question" "interview" "Q: $question_text" \
        "{\"key\": \"$esc_key\", \"response\": \"$esc_response\"}"
}

# Log interview completed event
# Args: questions_count
log_interview_completed() {
    local questions_count="$1"

    # Validate questions_count
    if ! validate_numeric "$questions_count" "questions_count" 2>/dev/null; then
        questions_count=0
    fi

    log_event "interview_completed" "interview" "Interview completed ($questions_count questions)" \
        "{\"questions_count\": ${questions_count:-0}}"

    # Update interview record
    local session_id
    session_id=$(get_current_session_id) || true

    if [ -z "$session_id" ]; then
        return 0
    fi

    local esc_session_id
    esc_session_id=$(sql_escape "$session_id")

    local query="UPDATE interviews
        SET status = 'completed',
            completed_at = CURRENT_TIMESTAMP,
            questions_answered = ${questions_count:-0}
        WHERE rowid = (
            SELECT rowid FROM interviews
            WHERE session_id = '$esc_session_id'
            AND status = 'in_progress'
            ORDER BY started_at DESC
            LIMIT 1
        );"

    sql_exec "$query" > /dev/null || log_warn "Failed to update interview record" "events"
}

# ============================================================================
# RESEARCH EVENTS
# ============================================================================

# Log research started event
log_research_started() {
    log_event "research_started" "research" "Research phase started"

    # Create research session record
    local session_id
    session_id=$(get_current_session_id) || true

    if [ -z "$session_id" ]; then
        return 0
    fi

    local esc_session_id
    esc_session_id=$(sql_escape "$session_id")

    local query="INSERT INTO research_sessions (session_id, status)
        VALUES ('$esc_session_id', 'in_progress');"

    sql_exec "$query" > /dev/null || log_warn "Failed to insert research_sessions record" "events"
}

# Log research finding event
# Args: finding_type, title, [description], [priority]
log_research_finding() {
    local finding_type="$1"
    local title="$2"
    local description="${3:-}"
    local priority="${4:-medium}"

    if [ -z "$finding_type" ] || [ -z "$title" ]; then
        log_error "Finding type and title required" "events"
        return 1
    fi

    local esc_type esc_priority
    esc_type=$(sql_escape "$finding_type")
    esc_priority=$(sql_escape "$priority")
    log_event "research_finding" "research" "Finding: $title" \
        "{\"type\": \"$esc_type\", \"priority\": \"$esc_priority\"}"

    # Insert finding record
    local session_id
    session_id=$(get_current_session_id) || true

    if [ -z "$session_id" ]; then
        return 0
    fi

    local esc_session_id esc_title esc_description
    esc_session_id=$(sql_escape "$session_id")
    esc_title=$(sql_escape "$title")
    esc_description=$(sql_escape "$description")

    local query="INSERT INTO research_findings (
            research_session_id,
            finding_type,
            title,
            description,
            priority
        )
        SELECT id, '$esc_type', '$esc_title', '$esc_description', '$esc_priority'
        FROM research_sessions
        WHERE session_id = '$esc_session_id'
        ORDER BY started_at DESC
        LIMIT 1;"

    sql_exec "$query" > /dev/null || log_warn "Failed to insert research_findings record" "events"
}

# Log research completed event
# Args: findings_count, [blockers_count]
log_research_completed() {
    local findings_count="$1"
    local blockers_count="${2:-0}"

    # Validate numeric values
    if ! validate_numeric "$findings_count" "findings_count" 2>/dev/null; then
        findings_count=0
    fi
    if ! validate_numeric "$blockers_count" "blockers_count" 2>/dev/null; then
        blockers_count=0
    fi

    log_event "research_completed" "research" "Research completed ($findings_count findings, $blockers_count blockers)" \
        "{\"findings\": ${findings_count:-0}, \"blockers\": ${blockers_count:-0}}"

    # Update research session record
    local session_id
    session_id=$(get_current_session_id) || true

    if [ -z "$session_id" ]; then
        return 0
    fi

    local esc_session_id
    esc_session_id=$(sql_escape "$session_id")

    local query="UPDATE research_sessions
        SET status = 'completed',
            completed_at = CURRENT_TIMESTAMP,
            findings_count = ${findings_count:-0},
            blockers_found = ${blockers_count:-0}
        WHERE rowid = (
            SELECT rowid FROM research_sessions
            WHERE session_id = '$esc_session_id'
            AND status = 'in_progress'
            ORDER BY started_at DESC
            LIMIT 1
        );"

    sql_exec "$query" > /dev/null || log_warn "Failed to update research_sessions record" "events"
}

# ============================================================================
# TASK EVENTS
# ============================================================================

# Log task started event
# Args: task_id, task_description
log_task_started() {
    local task_id="$1"
    local task_description="$2"

    if [ -z "$task_id" ]; then
        log_error "Task ID required" "events"
        return 1
    fi

    local esc_task_id
    esc_task_id=$(sql_escape "$task_id")
    log_event "task_started" "task" "Task started: $task_id - $task_description" \
        "{\"task_id\": \"$esc_task_id\"}"
}

# Log task completed event
# Args: task_id
log_task_completed() {
    local task_id="$1"

    if [ -z "$task_id" ]; then
        log_error "Task ID required" "events"
        return 1
    fi

    local esc_task_id
    esc_task_id=$(sql_escape "$task_id")
    log_event "task_completed" "task" "Task completed: $task_id" \
        "{\"task_id\": \"$esc_task_id\"}"
}

# Log task failed event
# Args: task_id, reason
log_task_failed() {
    local task_id="$1"
    local reason="$2"

    if [ -z "$task_id" ]; then
        log_error "Task ID required" "events"
        return 1
    fi

    local esc_task_id esc_reason
    esc_task_id=$(sql_escape "$task_id")
    esc_reason=$(sql_escape "$reason")
    log_event "task_failed" "task" "Task failed: $task_id - $reason" \
        "{\"task_id\": \"$esc_task_id\", \"reason\": \"$esc_reason\"}"
}

# ============================================================================
# ERROR AND WARNING EVENTS
# ============================================================================

# Log error event
# Args: message, [details]
log_error_event() {
    local message="$1"
    local details="${2:-{}}"

    log_event "error_occurred" "error" "$message" "$details"
}

# Log warning event
# Args: message, [details]
log_warning_event() {
    local message="$1"
    local details="${2:-{}}"

    log_event "warning_issued" "warning" "$message" "$details"
}

# ============================================================================
# ABANDONMENT EVENTS
# ============================================================================

# Log abandonment detected event
# Args: pattern, attempt_number
log_abandonment_detected() {
    local pattern="$1"
    local attempt_number="$2"

    # Validate attempt_number
    if ! validate_numeric "$attempt_number" "attempt_number" 2>/dev/null; then
        attempt_number=0
    fi

    local esc_pattern
    esc_pattern=$(sql_escape "$pattern")
    log_event "abandonment_detected" "persistence" "Abandonment pattern detected: $pattern (attempt $attempt_number)" \
        "{\"pattern\": \"$esc_pattern\", \"attempt\": ${attempt_number:-0}}"
}

# Log abandonment prevented event
# Args: action
log_abandonment_prevented() {
    local action="$1"

    local esc_action
    esc_action=$(sql_escape "$action")
    log_event "abandonment_prevented" "persistence" "Abandonment prevented: $action" \
        "{\"action\": \"$esc_action\"}"
}

# ============================================================================
# QUERY FUNCTIONS
# ============================================================================

# Get recent events for current session
# Args: [limit], [session_id]
get_recent_events() {
    local limit="${1:-20}"
    local session_id="${2:-}"

    # Validate limit
    if ! validate_numeric "$limit" "limit" 2>/dev/null; then
        limit=20
    fi

    if [ -z "$session_id" ]; then
        session_id=$(get_current_session_id) || true
    fi

    if [ -z "$session_id" ]; then
        return 0
    fi

    if ! validate_session_id "$session_id"; then
        return 1
    fi

    local esc_session_id
    esc_session_id=$(sql_escape "$session_id")

    sql_exec_table "SELECT timestamp, event_type, message
        FROM events
        WHERE session_id = '$esc_session_id'
        ORDER BY timestamp DESC
        LIMIT ${limit:-20};"
}

# Get events by type
# Args: event_type, [session_id]
get_events_by_type() {
    local event_type="$1"
    local session_id="${2:-}"

    if [ -z "$event_type" ]; then
        log_error "Event type required" "events"
        return 1
    fi

    if [ -z "$session_id" ]; then
        session_id=$(get_current_session_id) || true
    fi

    if [ -z "$session_id" ]; then
        echo "[]"
        return 0
    fi

    if ! validate_session_id "$session_id"; then
        echo "[]"
        return 1
    fi

    local esc_session_id esc_event_type
    esc_session_id=$(sql_escape "$session_id")
    esc_event_type=$(sql_escape "$event_type")

    sql_exec_json "SELECT * FROM events
        WHERE session_id = '$esc_session_id'
        AND event_type = '$esc_event_type'
        ORDER BY timestamp;"
}

# Get escalation history
# Args: [session_id]
get_escalation_history() {
    local session_id="${1:-}"

    if [ -z "$session_id" ]; then
        session_id=$(get_current_session_id) || true
    fi

    if [ -z "$session_id" ]; then
        return 0
    fi

    if ! validate_session_id "$session_id"; then
        return 1
    fi

    local esc_session_id
    esc_session_id=$(sql_escape "$session_id")

    sql_exec_table "SELECT timestamp, from_model, to_model, reason, agent
        FROM escalations
        WHERE session_id = '$esc_session_id'
        ORDER BY timestamp;"
}

# Get gate results for current session
# Args: [session_id]
get_gate_results() {
    local session_id="${1:-}"

    if [ -z "$session_id" ]; then
        session_id=$(get_current_session_id) || true
    fi

    if [ -z "$session_id" ]; then
        return 0
    fi

    if ! validate_session_id "$session_id"; then
        return 1
    fi

    local esc_session_id
    esc_session_id=$(sql_escape "$session_id")

    sql_exec_table "SELECT iteration, gate, passed, error_count, timestamp
        FROM gate_results
        WHERE session_id = '$esc_session_id'
        ORDER BY timestamp;"
}

# ============================================================================
# INITIALIZATION
# ============================================================================

# Set up error handling when script is sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    setup_error_trap
fi
