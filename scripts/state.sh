#!/bin/bash
# DevTeam State Management Functions
# Provides secure session and state management for DevTeam hooks and commands
#
# SECURITY: All SQL queries use proper escaping and input validation
# ERROR HANDLING: Uses set -euo pipefail and validates all inputs
#
# Usage: source this file in hooks and commands
#   source "$(dirname "$0")/../scripts/state.sh"

set -euo pipefail

# Get script directory and source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh" || { echo "ERROR: Cannot source common.sh" >&2; exit 1; }

# ============================================================================
# SESSION MANAGEMENT
# ============================================================================

# Generate a unique session ID
# Returns: session-YYYYMMDD-HHMMSS-hexstring
generate_session_id() {
    generate_id "session"
}

# Start a new session
# Args: command, command_type, [execution_mode]
# Returns: session_id on success, exits on failure
start_session() {
    local command="$1"
    local command_type="$2"
    local execution_mode="${3:-normal}"

    # Validate inputs
    if [ -z "$command" ]; then
        log_error "Command cannot be empty" "session"
        return 1
    fi

    ensure_db || return 1

    local session_id
    session_id=$(generate_session_id)

    # Phase 0 (2026-08-26): pick up autonomous-mode limits from
    # .devteam/config.yaml (parsed by hooks/session-start.sh into
    # DEVTEAM_DIR/autonomous-runtime.env) instead of silently falling back to
    # the schema's own hardcoded column defaults (max_iterations=10,
    # max_consecutive_failures=5), which never matched config.yaml's shipped
    # defaults (50 / 5). See docs/reviews/ARCHITECTURE_AUDIT_2026-08-26.md §7.
    local resolved_max_iterations resolved_max_failures
    resolved_max_iterations=$(_autonomous_runtime_value "DEVTEAM_MAX_ITERATIONS" "50")
    resolved_max_failures=$(_autonomous_runtime_value "DEVTEAM_MAX_CONSECUTIVE_FAILURES" "$CIRCUIT_BREAKER_DEFAULT_THRESHOLD")

    # Escape values for safe SQL
    local esc_command esc_type esc_mode
    esc_command=$(sql_escape "$command")
    esc_type=$(sql_escape "$command_type")
    esc_mode=$(sql_escape "$execution_mode")

    local query="INSERT INTO sessions (id, command, command_type, execution_mode, status, current_phase, max_iterations, max_consecutive_failures)
        VALUES ('$session_id', '$esc_command', '$esc_type', '$esc_mode', 'running', 'initializing', ${resolved_max_iterations}, ${resolved_max_failures});"

    if ! sql_exec "$query" > /dev/null; then
        log_error "Failed to create session" "session"
        return 1
    fi

    log_info "Session started: $session_id (max_iterations=${resolved_max_iterations}, max_consecutive_failures=${resolved_max_failures})" "session"
    echo "$session_id"
}

# End the current session
# Args: [status], [exit_reason]
end_session() {
    local status="${1:-completed}"
    local exit_reason="${2:-Success}"

    # Validate status
    if ! validate_status "$status"; then
        status="completed"  # Default to safe value
    fi

    local esc_status esc_reason
    esc_status=$(sql_escape "$status")
    esc_reason=$(sql_escape "$exit_reason")

    # Target the specific running session instead of blanket update
    local session_id
    session_id=$(get_current_session_id)

    local query
    if [ -n "$session_id" ]; then
        local esc_id
        esc_id=$(sql_escape "$session_id")
        query="UPDATE sessions
            SET status = '$esc_status',
                exit_reason = '$esc_reason',
                ended_at = CURRENT_TIMESTAMP
            WHERE id = '$esc_id';"
    else
        log_error "No active session found to end" "state"
        return 1
    fi

    if ! sql_exec "$query" > /dev/null; then
        log_error "Failed to end session" "session"
        return 1
    fi

    log_info "Session ended: $status - $exit_reason" "session"
}

# Get current session ID
# Returns: session_id or empty string if none running
get_current_session_id() {
    ensure_db || return 1

    local result
    result=$(sql_exec "SELECT id FROM sessions WHERE status = 'running' ORDER BY started_at DESC LIMIT 1;")
    echo "$result"
}

# Check if a session is running
# Returns: 0 if running, 1 otherwise
is_session_running() {
    local count
    count=$(sql_exec "SELECT COUNT(*) FROM sessions WHERE status = 'running';")
    [ "${count:-0}" -gt 0 ]
}

# Get session as JSON
# Args: [session_id]
get_session_json() {
    local session_id="${1:-}"

    if [ -z "$session_id" ]; then
        session_id=$(get_current_session_id)
    fi

    if [ -z "$session_id" ]; then
        log_warn "No session ID provided or found" "session"
        echo "[]"
        return 0
    fi

    # Validate session ID format
    if ! validate_session_id "$session_id"; then
        echo "[]"
        return 1
    fi

    local esc_id
    esc_id=$(sql_escape "$session_id")
    sql_exec_json "SELECT * FROM sessions WHERE id = '$esc_id';"
}

# ============================================================================
# STATE GETTERS (with validation)
# ============================================================================

# Get a specific session field
# Args: field, [session_id]
# SECURITY: Field name is validated against whitelist
get_state() {
    local field="$1"
    local session_id="${2:-}"

    # Validate field name against whitelist
    if ! validate_field_name "$field"; then
        return 1
    fi

    if [ -z "$session_id" ]; then
        session_id=$(get_current_session_id)
    fi

    if [ -z "$session_id" ]; then
        log_debug "No active session" "state"
        return 0
    fi

    # Validate session ID
    if ! validate_session_id "$session_id"; then
        return 1
    fi

    local esc_id
    esc_id=$(sql_escape "$session_id")
    sql_exec "SELECT $field FROM sessions WHERE id = '$esc_id';"
}

# Get current phase
get_current_phase() {
    get_state "current_phase"
}

# Get current agent
get_current_agent() {
    get_state "current_agent"
}

# Get current model
get_current_model() {
    get_state "current_model"
}

# Get current iteration
get_current_iteration() {
    local result
    result=$(get_state "current_iteration")
    echo "${result:-0}"
}

# Get consecutive failures
get_consecutive_failures() {
    local result
    result=$(get_state "consecutive_failures")
    echo "${result:-0}"
}

# Get execution mode
get_execution_mode() {
    get_state "execution_mode"
}

# Check if eco mode
is_eco_mode() {
    local mode
    mode=$(get_execution_mode)
    [ "$mode" = "eco" ]
}

# Check if bug council activated
is_bug_council_active() {
    local activated
    activated=$(get_state "bug_council_activated")
    [ "$activated" = "1" ]
}

# ============================================================================
# STATE SETTERS (with validation)
# ============================================================================

# Set a specific session field
# Args: field, value, [session_id]
# SECURITY: Field name is validated, value is escaped
set_state() {
    local field="$1"
    local value="$2"
    local session_id="${3:-}"

    # Validate field name
    if ! validate_field_name "$field"; then
        return 1
    fi

    if [ -z "$session_id" ]; then
        session_id=$(get_current_session_id)
    fi

    if [ -z "$session_id" ]; then
        log_error "No active session" "state"
        return 1
    fi

    # Validate session ID
    if ! validate_session_id "$session_id"; then
        return 1
    fi

    local esc_value esc_id
    esc_value=$(sql_escape "$value")
    esc_id=$(sql_escape "$session_id")

    local query="UPDATE sessions SET $field = '$esc_value' WHERE id = '$esc_id';"

    if ! sql_exec "$query" > /dev/null; then
        log_error "Failed to set state: $field" "state"
        return 1
    fi

    log_debug "Set $field = $value" "state"
}

# Set current phase (with validation)
set_phase() {
    local phase="$1"

    if ! validate_phase "$phase"; then
        return 1
    fi

    set_state "current_phase" "$phase"
}

# Set current agent
set_current_agent() {
    local agent="$1"

    if [ -z "$agent" ]; then
        log_error "Agent name cannot be empty" "state"
        return 1
    fi

    set_state "current_agent" "$agent"
}

# Set current model (with validation)
set_current_model() {
    local model="$1"

    if ! validate_model "$model"; then
        return 1
    fi

    set_state "current_model" "$model"
}

# Increment iteration
# Args: [session_id]
increment_iteration() {
    local session_id="${1:-}"

    if [ -z "$session_id" ]; then
        session_id=$(get_current_session_id)
    fi

    if [ -z "$session_id" ]; then
        log_error "No active session" "state"
        return 1
    fi

    if ! validate_session_id "$session_id"; then
        return 1
    fi

    local esc_id
    esc_id=$(sql_escape "$session_id")

    local query="UPDATE sessions SET current_iteration = current_iteration + 1 WHERE id = '$esc_id';"

    if ! sql_exec "$query" > /dev/null; then
        log_error "Failed to increment iteration" "state"
        return 1
    fi

    log_debug "Iteration incremented" "state"
}

# Increment consecutive failures
increment_failures() {
    local session_id="${1:-}"

    if [ -z "$session_id" ]; then
        session_id=$(get_current_session_id)
    fi

    if [ -z "$session_id" ]; then
        log_error "No active session" "state"
        return 1
    fi

    if ! validate_session_id "$session_id"; then
        return 1
    fi

    local esc_id
    esc_id=$(sql_escape "$session_id")

    local query="UPDATE sessions SET consecutive_failures = consecutive_failures + 1 WHERE id = '$esc_id';"

    if ! sql_exec "$query" > /dev/null; then
        log_error "Failed to increment failures" "state"
        return 1
    fi

    log_debug "Consecutive failures incremented" "state"
}

# Reset consecutive failures
reset_failures() {
    local session_id="${1:-}"

    if [ -z "$session_id" ]; then
        session_id=$(get_current_session_id)
    fi

    if [ -z "$session_id" ]; then
        log_error "No active session" "state"
        return 1
    fi

    if ! validate_session_id "$session_id"; then
        return 1
    fi

    local esc_id
    esc_id=$(sql_escape "$session_id")

    local query="UPDATE sessions SET consecutive_failures = 0 WHERE id = '$esc_id';"

    if ! sql_exec "$query" > /dev/null; then
        log_error "Failed to reset failures" "state"
        return 1
    fi

    log_debug "Consecutive failures reset" "state"
}

# Activate bug council
# Args: reason, [session_id]
activate_bug_council() {
    local reason="$1"
    local session_id="${2:-}"

    if [ -z "$reason" ]; then
        log_error "Bug council reason cannot be empty" "state"
        return 1
    fi

    if [ -z "$session_id" ]; then
        session_id=$(get_current_session_id)
    fi

    if [ -z "$session_id" ]; then
        log_error "No active session" "state"
        return 1
    fi

    if ! validate_session_id "$session_id"; then
        return 1
    fi

    local esc_reason esc_id
    esc_reason=$(sql_escape "$reason")
    esc_id=$(sql_escape "$session_id")

    local query="UPDATE sessions SET bug_council_activated = TRUE, bug_council_reason = '$esc_reason' WHERE id = '$esc_id';"

    if ! sql_exec "$query" > /dev/null; then
        log_error "Failed to activate bug council" "state"
        return 1
    fi

    log_info "Bug council activated: $reason" "state"
}

# ============================================================================
# KEY-VALUE STATE (for complex data)
# ============================================================================

# Set a key-value pair
# Args: key, value, [session_id]
set_kv_state() {
    local key="$1"
    local value="$2"
    local session_id="${3:-}"

    if [ -z "$key" ]; then
        log_error "Key cannot be empty" "kv"
        return 1
    fi

    if [ -z "$session_id" ]; then
        session_id=$(get_current_session_id)
    fi

    if [ -z "$session_id" ]; then
        log_error "No active session" "kv"
        return 1
    fi

    if ! validate_session_id "$session_id"; then
        return 1
    fi

    local esc_key esc_value esc_id
    esc_key=$(sql_escape "$key")
    esc_value=$(sql_escape "$value")
    esc_id=$(sql_escape "$session_id")

    local query="INSERT OR REPLACE INTO session_state (session_id, key, value, updated_at)
        VALUES ('$esc_id', '$esc_key', '$esc_value', CURRENT_TIMESTAMP);"

    if ! sql_exec "$query" > /dev/null; then
        log_error "Failed to set KV state: $key" "kv"
        return 1
    fi

    log_debug "KV set: $key" "kv"
}

# Get a key-value pair
# Args: key, [session_id]
get_kv_state() {
    local key="$1"
    local session_id="${2:-}"

    if [ -z "$key" ]; then
        log_error "Key cannot be empty" "kv"
        return 1
    fi

    if [ -z "$session_id" ]; then
        session_id=$(get_current_session_id)
    fi

    if [ -z "$session_id" ]; then
        return 0  # No session, return empty
    fi

    if ! validate_session_id "$session_id"; then
        return 1
    fi

    local esc_key esc_id
    esc_key=$(sql_escape "$key")
    esc_id=$(sql_escape "$session_id")

    sql_exec "SELECT value FROM session_state WHERE session_id = '$esc_id' AND key = '$esc_key';"
}

# Delete a key-value pair
# Args: key, [session_id]
delete_kv_state() {
    local key="$1"
    local session_id="${2:-}"

    if [ -z "$key" ]; then
        log_error "Key cannot be empty" "kv"
        return 1
    fi

    if [ -z "$session_id" ]; then
        session_id=$(get_current_session_id)
    fi

    if [ -z "$session_id" ]; then
        log_error "No active session" "kv"
        return 1
    fi

    if ! validate_session_id "$session_id"; then
        return 1
    fi

    local esc_key esc_id
    esc_key=$(sql_escape "$key")
    esc_id=$(sql_escape "$session_id")

    local query="DELETE FROM session_state WHERE session_id = '$esc_id' AND key = '$esc_key';"

    if ! sql_exec "$query" > /dev/null; then
        log_error "Failed to delete KV state: $key" "kv"
        return 1
    fi

    log_debug "KV deleted: $key" "kv"
}

# ============================================================================
# COST TRACKING
# ============================================================================

# Add tokens to session total
# Args: tokens_input, tokens_output, cost_cents, [session_id]
# NOTE: cost_cents is in CENTS (integer). Do NOT pass USD dollars here.
# - cost-tracking.sh calculate_cost() returns USD — multiply by 100 before passing here
add_tokens() {
    local tokens_input="$1"
    local tokens_output="$2"
    local cost_cents="$3"
    local session_id="${4:-}"

    # Validate numeric inputs
    if ! validate_numeric "$tokens_input" "tokens_input"; then
        return 1
    fi
    if ! validate_numeric "$tokens_output" "tokens_output"; then
        return 1
    fi
    if ! validate_decimal "$cost_cents" "cost_cents"; then
        return 1
    fi

    # Reject negative values (validate_numeric already ensures non-negative integers,
    # but guard against future changes; cost_cents is decimal so check explicitly)
    if [[ "$cost_cents" == -* ]]; then
        log_error "Negative cost_cents not allowed: $cost_cents" "cost"
        return 1
    fi

    if [ -z "$session_id" ]; then
        session_id=$(get_current_session_id)
    fi

    if [ -z "$session_id" ]; then
        log_error "No active session" "cost"
        return 1
    fi

    if ! validate_session_id "$session_id"; then
        return 1
    fi

    local esc_id
    esc_id=$(sql_escape "$session_id")

    local query="UPDATE sessions
        SET total_tokens_input = total_tokens_input + $tokens_input,
            total_tokens_output = total_tokens_output + $tokens_output,
            total_cost_cents = total_cost_cents + $cost_cents
        WHERE id = '$esc_id';"

    if ! sql_exec "$query" > /dev/null; then
        log_error "Failed to add tokens" "cost"
        return 1
    fi

    log_debug "Added tokens: +$tokens_input input, +$tokens_output output, +$cost_cents cents" "cost"
}

# Get total cost in dollars
# Args: [session_id]
get_total_cost_dollars() {
    local session_id="${1:-}"

    if [ -z "$session_id" ]; then
        session_id=$(get_current_session_id)
    fi

    if [ -z "$session_id" ]; then
        echo "0.0000"
        return 0
    fi

    if ! validate_session_id "$session_id"; then
        echo "0.0000"
        return 1
    fi

    local esc_id
    esc_id=$(sql_escape "$session_id")
    sql_exec "SELECT ROUND(total_cost_cents / 100.0, 4) FROM sessions WHERE id = '$esc_id';"
}

# ============================================================================
# CONFIG (Phase 0, 2026-08-26)
# ============================================================================
# Reads the autonomous-mode limits that hooks/session-start.sh parses out of
# .devteam/config.yaml's `autonomous:` block and writes to
# DEVTEAM_DIR/autonomous-runtime.env on every session start. Uses grep/cut
# rather than sourcing the file, since it may be regenerated by another
# process and this file should never execute arbitrary content.
#
# Args: key (e.g. "DEVTEAM_MAX_ITERATIONS"), default (used if the runtime
# file / key is missing, or the value isn't a positive integer)
_autonomous_runtime_value() {
    local key="$1"
    local default="$2"
    local runtime_file="${DEVTEAM_DIR:-.devteam}/autonomous-runtime.env"

    if [ ! -f "$runtime_file" ]; then
        echo "$default"
        return 0
    fi

    local value
    value=$(grep -m1 -E "^${key}=" "$runtime_file" 2>/dev/null | cut -d'=' -f2- || echo "")

    if [[ "$value" =~ ^[0-9]+$ ]] && [ "$value" -gt 0 ]; then
        echo "$value"
    else
        echo "$default"
    fi
}

# ============================================================================
# CIRCUIT BREAKER
# ============================================================================

# Circuit breaker threshold (configurable via env, M9)
CIRCUIT_BREAKER_DEFAULT_THRESHOLD="${DEVTEAM_CIRCUIT_BREAKER_THRESHOLD:-5}"

# Check if circuit breaker should trip
# Returns: 0 if should trip, 1 otherwise
should_trip_circuit_breaker() {
    local failures
    local max_failures

    failures=$(get_consecutive_failures)
    max_failures=$(get_state "max_consecutive_failures")

    # Use config-derived default if no session/value is set. start_session()
    # now sets sessions.max_consecutive_failures explicitly at creation time,
    # so this is defense in depth for sessions created via another path
    # (e.g. a raw INSERT INTO sessions, or no active session at all).
    max_failures="${max_failures:-$(_autonomous_runtime_value "DEVTEAM_MAX_CONSECUTIVE_FAILURES" "$CIRCUIT_BREAKER_DEFAULT_THRESHOLD")}"

    # Validate both values are numeric before comparison
    if ! [[ "${failures:-0}" =~ ^[0-9]+$ ]]; then
        log_warn "Non-numeric failures value: ${failures:-0}, defaulting to 0" "circuit"
        failures=0
    fi
    if ! [[ "$max_failures" =~ ^[0-9]+$ ]]; then
        log_warn "Non-numeric max_failures value: $max_failures, using default" "circuit"
        max_failures="$CIRCUIT_BREAKER_DEFAULT_THRESHOLD"
    fi

    [ "$failures" -ge "$max_failures" ]
}

# Trip the circuit breaker
trip_circuit_breaker() {
    set_state "circuit_breaker_state" "open"
    log_warn "Circuit breaker tripped!" "circuit"
}

# Reset the circuit breaker
reset_circuit_breaker() {
    set_state "circuit_breaker_state" "closed"
    reset_failures
    log_info "Circuit breaker reset" "circuit"
}

# ============================================================================
# MODEL ESCALATION
# ============================================================================

# Get next model tier
# Args: current_model
# Returns: next model in escalation chain
get_next_model() {
    local current="$1"
    case "$current" in
        haiku)        echo "sonnet" ;;
        sonnet)       echo "opus" ;;
        opus)         echo "bug_council" ;;
        bug_council)  echo "bug_council" ;;  # Already at top of chain (H3)
        *)            echo "sonnet" ;;  # Default fallback
    esac
}

# Get previous model tier (for de-escalation)
# Args: current_model
get_previous_model() {
    local current="$1"
    case "$current" in
        opus)        echo "sonnet" ;;
        sonnet)      echo "haiku" ;;
        bug_council) echo "opus" ;;
        *)           echo "haiku" ;;  # Default fallback
    esac
}

# Record escalation
# Args: from_model, to_model, reason, [agent], [session_id]
record_escalation() {
    local from_model="$1"
    local to_model="$2"
    local reason="$3"
    local agent="${4:-}"
    local session_id="${5:-}"

    # Validate target model before escalating (M7)
    if ! _in_array "$to_model" "${VALID_MODELS[@]}"; then
        log_error "Invalid escalation target model: $to_model" "escalation"
        return 1
    fi

    if [ -z "$session_id" ]; then
        session_id=$(get_current_session_id)
    fi

    if [ -z "$session_id" ]; then
        log_error "No active session" "escalation"
        return 1
    fi

    if ! validate_session_id "$session_id"; then
        return 1
    fi

    local iteration
    iteration=$(get_current_iteration)

    local esc_from esc_to esc_reason esc_agent esc_id
    esc_from=$(sql_escape "$from_model")
    esc_to=$(sql_escape "$to_model")
    esc_reason=$(sql_escape "$reason")
    esc_agent=$(sql_escape "$agent")
    esc_id=$(sql_escape "$session_id")

    local query="INSERT INTO escalations (session_id, from_model, to_model, reason, agent, iteration)
        VALUES ('$esc_id', '$esc_from', '$esc_to', '$esc_reason', '$esc_agent', ${iteration:-0});"

    if ! sql_exec "$query" > /dev/null; then
        log_error "Failed to record escalation" "escalation"
        return 1
    fi

    # Update current model
    set_current_model "$to_model"

    log_info "Escalated: $from_model -> $to_model ($reason)" "escalation"
}

# ============================================================================
# PLAN MANAGEMENT
# ============================================================================

# Set active plan
# Args: plan_id, [session_id]
set_active_plan() {
    local plan_id="$1"
    local session_id="${2:-}"

    if [ -z "$plan_id" ]; then
        log_error "Plan ID cannot be empty" "plan"
        return 1
    fi

    set_state "plan_id" "$plan_id" "$session_id"
    log_info "Active plan set: $plan_id" "plan"
}

# Set active sprint
# Args: sprint_id, [session_id]
set_active_sprint() {
    local sprint_id="$1"
    local session_id="${2:-}"

    if [ -z "$sprint_id" ]; then
        log_error "Sprint ID cannot be empty" "plan"
        return 1
    fi

    set_state "sprint_id" "$sprint_id" "$session_id"
    log_info "Active sprint set: $sprint_id" "plan"
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

# Get session summary (for status display)
# Args: [session_id]
get_session_summary() {
    local session_id="${1:-}"

    if [ -z "$session_id" ]; then
        session_id=$(get_current_session_id)
    fi

    if [ -z "$session_id" ]; then
        echo "[]"
        return 0
    fi

    if ! validate_session_id "$session_id"; then
        echo "[]"
        return 1
    fi

    local esc_id
    esc_id=$(sql_escape "$session_id")
    sql_exec_json "SELECT * FROM v_session_summary WHERE id = '$esc_id';"
}

# Get model usage for session
# Args: [session_id]
get_model_usage() {
    local session_id="${1:-}"

    if [ -z "$session_id" ]; then
        session_id=$(get_current_session_id)
    fi

    if [ -z "$session_id" ]; then
        return 0
    fi

    if ! validate_session_id "$session_id"; then
        return 1
    fi

    local esc_id
    esc_id=$(sql_escape "$session_id")
    sql_exec_table "SELECT * FROM v_model_usage WHERE session_id = '$esc_id';"
}

# Abort current session
# Args: [reason]
abort_session() {
    local reason="${1:-User aborted}"
    end_session "aborted" "$reason"
}

# Check max iterations
# Returns: 0 if max reached, 1 otherwise
is_max_iterations_reached() {
    local current
    local max

    current=$(get_current_iteration)
    max=$(get_state "max_iterations")

    # Use config-derived default if no session/value is set. start_session()
    # now sets sessions.max_iterations explicitly at creation time, so this
    # is defense in depth for sessions created via another path.
    max="${max:-$(_autonomous_runtime_value "DEVTEAM_MAX_ITERATIONS" "50")}"

    [ "${current:-0}" -ge "${max:-50}" ]
}

# ============================================================================
# INITIALIZATION
# ============================================================================

# Set up error handling when script is sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    # Script is being sourced, set up error trap
    setup_error_trap
fi
