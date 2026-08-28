#!/bin/bash
# DevTeam Common Library
# Shared utilities for security, logging, and validation
# Source this file in other scripts

set -euo pipefail

# Idempotent-include guard: state.sh/events.sh/hook-common.sh already source
# this file, so anything that sources one of those *and* sources this file
# directly (as tests/run-tests.sh's test_* functions each do, to reach
# sql_escape/validate_* in isolation) would otherwise hit "readonly variable"
# on the second pass and abort under set -e.
if [ -n "${_DEVTEAM_COMMON_LOADED:-}" ]; then
    return 0 2>/dev/null || exit 0
fi
_DEVTEAM_COMMON_LOADED=1

# ============================================================================
# CONFIGURATION
# ============================================================================

DEVTEAM_DIR="${DEVTEAM_DIR:-.devteam}"
DB_FILE="${DEVTEAM_DIR}/devteam.db"
LOG_LEVEL="${DEVTEAM_LOG_LEVEL:-info}"  # debug, info, warn, error

# Numeric value for a log-level name. A function, not an associative array --
# stock macOS ships /bin/bash 3.2 (pre-4.0), which has no `declare -A`; this
# form works identically on bash 3.2+ and on Linux's bash 4/5.
_log_level_num() {
    case "$1" in
        debug) echo 0 ;;
        info)  echo 1 ;;
        warn)  echo 2 ;;
        error) echo 3 ;;
        *)     echo 1 ;;
    esac
}

# Colors for output
readonly COLOR_RED='\033[0;31m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_NC='\033[0m'

# ============================================================================
# STRUCTURED LOGGING
# ============================================================================

# Internal: Check if log level should be output
_should_log() {
    local level="$1"
    local current_level msg_level
    current_level="$(_log_level_num "$LOG_LEVEL")"
    msg_level="$(_log_level_num "$level")"
    [ "$msg_level" -ge "$current_level" ]
}

# Log with timestamp and level
log() {
    local level="$1"
    local message="$2"
    local context="${3:-}"

    if ! _should_log "$level"; then
        return 0
    fi

    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    local color=""
    case "$level" in
        debug) color="$COLOR_BLUE" ;;
        info)  color="$COLOR_GREEN" ;;
        warn)  color="$COLOR_YELLOW" ;;
        error) color="$COLOR_RED" ;;
    esac

    local ctx_str=""
    if [ -n "$context" ]; then
        ctx_str=" [$context]"
    fi

    echo -e "${color}[$timestamp] [devteam] [$level]${ctx_str}${COLOR_NC} $message" >&2
}

log_debug() { log "debug" "$1" "${2:-}"; }
log_info()  { log "info" "$1" "${2:-}"; }
log_warn()  { log "warn" "$1" "${2:-}"; }
log_error() { log "error" "$1" "${2:-}"; }

# ============================================================================
# INPUT VALIDATION
# ============================================================================

# Valid session field names (whitelist)
readonly VALID_SESSION_FIELDS=(
    "status"
    "current_phase"
    "current_agent"
    "current_model"
    "current_iteration"
    "consecutive_failures"
    "execution_mode"
    "bug_council_activated"
    "bug_council_reason"
    "circuit_breaker_state"
    "max_consecutive_failures"
    "max_iterations"
    "plan_id"
    "sprint_id"
    "exit_reason"
    "ended_at"
    "total_tokens_input"
    "total_tokens_output"
    "total_cost_cents"
)

# Valid phase values
readonly VALID_PHASES=(
    "initializing"
    "interview"
    "research"
    "planning"
    "executing"
    "quality_check"
    "bug_council"
    "completed"
    "aborted"
    "failed"
)

# Valid model values
readonly VALID_MODELS=(
    "haiku"
    "sonnet"
    "opus"
    "bug_council"
)

# Valid status values
readonly VALID_STATUSES=(
    "running"
    "completed"
    "aborted"
    "failed"
)

# Check if value is in array
_in_array() {
    local needle="$1"
    shift
    local item
    for item in "$@"; do
        if [ "$item" = "$needle" ]; then
            return 0
        fi
    done
    return 1
}

# Validate session field name
validate_field_name() {
    local field="$1"
    if ! _in_array "$field" "${VALID_SESSION_FIELDS[@]}"; then
        log_error "Invalid field name: $field" "validation"
        return 1
    fi
    return 0
}

# Validate phase value
validate_phase() {
    local phase="$1"
    if ! _in_array "$phase" "${VALID_PHASES[@]}"; then
        log_error "Invalid phase: $phase" "validation"
        return 1
    fi
    return 0
}

# Validate model value
validate_model() {
    local model="$1"
    if ! _in_array "$model" "${VALID_MODELS[@]}"; then
        log_error "Invalid model: $model" "validation"
        return 1
    fi
    return 0
}

# Validate status value
validate_status() {
    local status="$1"
    if ! _in_array "$status" "${VALID_STATUSES[@]}"; then
        log_error "Invalid status: $status" "validation"
        return 1
    fi
    return 0
}

# Validate session ID format (prevents injection)
validate_session_id() {
    local session_id="$1"
    # Session IDs should match: session-YYYYMMDD-HHMMSS-hexchars
    if [[ ! "$session_id" =~ ^session-[0-9]{8}-[0-9]{6}-[a-f0-9]+$ ]]; then
        log_error "Invalid session ID format: $session_id" "validation"
        return 1
    fi
    return 0
}

# Validate numeric value
validate_numeric() {
    local value="$1"
    local name="${2:-value}"
    if [[ ! "$value" =~ ^[0-9]+$ ]]; then
        log_error "Invalid numeric $name: $value" "validation"
        return 1
    fi
    return 0
}

# Validate numeric (allows decimals)
validate_decimal() {
    local value="$1"
    local name="${2:-value}"
    # Must have at least one digit before optional decimal point
    # Accepts: 0, 123, 0.5, 123.456 - Rejects: ., .5, empty
    if [[ ! "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        log_error "Invalid decimal $name: $value" "validation"
        return 1
    fi
    return 0
}

# ============================================================================
# SQL SECURITY
# ============================================================================

# Valid table names (whitelist to prevent SQL injection)
readonly VALID_TABLES=(
    "sessions"
    "session_state"
    "events"
    "schema_version"
    "agent_runs"
    "gate_results"
    "interviews"
    "interview_questions"
    "research_sessions"
    "research_findings"
    "bugs"
    "plans"
    "escalations"
    "acceptance_criteria"
    "features"
    "context_snapshots"
    "context_budgets"
    "progress_summaries"
    "session_phases"
    "baselines"
    "checkpoints"
    "checkpoint_restores"
    "rollbacks"
    "token_usage"
    "error_log"
    "dead_letter"
    "tasks"
    "task_attempts"
    "task_files"
)

# Valid column names per table (whitelist to prevent SQL injection). A
# function, not an associative array -- stock macOS ships /bin/bash 3.2
# (pre-4.0), which has no `declare -A`; this form works identically on
# bash 3.2+ and on Linux's bash 4/5.
_valid_columns_for_table() {
    case "$1" in
        sessions) echo "id,started_at,ended_at,command,command_type,status,exit_reason,current_phase,current_task_id,current_agent,current_model,current_iteration,max_iterations,consecutive_failures,max_consecutive_failures,circuit_breaker_state,plan_id,sprint_id,execution_mode,total_tokens_input,total_tokens_output,total_cost_cents,bug_council_activated,bug_council_reason" ;;
        session_state) echo "session_id,key,value,updated_at" ;;
        events) echo "id,session_id,timestamp,event_type,event_category,agent,model,iteration,phase,data,metadata,message,tokens_input,tokens_output,cost_cents" ;;
        schema_version) echo "version,applied_at" ;;
        agent_runs) echo "id,session_id,agent,agent_type,model,started_at,ended_at,duration_seconds,status,error_message,error_type,task_id,iteration,attempt,tokens_input,tokens_output,cost_cents,files_changed,output_summary" ;;
        gate_results) echo "id,session_id,gate,iteration,passed,details,error_count,warning_count,coverage_percent,timestamp,duration_seconds" ;;
        interviews) echo "id,session_id,interview_type,started_at,completed_at,status,questions_asked,questions_answered" ;;
        interview_questions) echo "id,interview_id,question_key,question_text,question_type,response,responded_at,sequence,required" ;;
        research_sessions) echo "id,session_id,started_at,completed_at,status,findings_count,recommendations_count,blockers_found" ;;
        research_findings) echo "id,research_session_id,finding_type,title,description,source,file_path,evidence,priority,timestamp" ;;
        bugs) echo "id,session_id,description,severity,complexity,root_cause,diagnosis_method,fix_summary,files_changed,prevention_measures,status,created_at,resolved_at,council_activated,council_votes" ;;
        plans) echo "id,name,description,plan_type,prd_path,tasks_path,sprints_path,status,total_sprints,completed_sprints,total_tasks,completed_tasks,created_at,started_at,completed_at,research_session_id" ;;
        escalations) echo "id,session_id,from_model,to_model,agent,reason,failure_count,iteration,task_id,timestamp" ;;
        acceptance_criteria) echo "id,task_id,sprint_id,plan_id,criterion_id,description,category,passes,verified_at,verified_by,verification_method,verification_evidence,last_failure_reason,failure_count,priority,sequence,created_at,updated_at" ;;
        features) echo "id,plan_id,sprint_id,feature_id,name,description,category,steps,passes,all_steps_pass,steps_total,steps_passed,verified_at,verified_by,priority,sequence,created_at,updated_at" ;;
        context_snapshots) echo "id,session_id,snapshot_type,tokens_before,tokens_after,tokens_saved,preserved_items,summarized_items,summary_text,trigger_reason,created_at" ;;
        context_budgets) echo "id,session_id,model,context_limit,current_usage,usage_percent,warn_threshold,summarize_threshold,status,last_action,updated_at" ;;
        progress_summaries) echo "id,session_id,summary_text,from_iteration,to_iteration,tasks_completed,tasks_remaining,tests_passing,tests_failing,features_passing,features_total,last_commit_sha,files_changed,created_at" ;;
        session_phases) echo "id,session_id,phase_type,is_first_run,init_script_created,features_enumerated,progress_file_created,baseline_commit_sha,features_attempted,features_completed,resumed_from_session,resume_point,created_at" ;;
        baselines) echo "id,tag_name,commit_hash,milestone,description,branch,files_changed,created_at" ;;
        checkpoints) echo "id,checkpoint_id,path,description,git_commit,session_id,task_id,sprint_id,can_restore,created_at" ;;
        checkpoint_restores) echo "id,checkpoint_id,restored_at" ;;
        rollbacks) echo "id,rollback_type,target_commit,target_tag,reason,from_commit,trigger_type,check_type,backup_branch,rolled_back_at" ;;
        token_usage) echo "id,session_id,task_id,sprint_id,model,input_tokens,output_tokens,cost_usd,operation,agent_name,recorded_at" ;;
        error_log) echo "id,session_id,task_id,operation,error_type,error_message,error_pattern,recovery_action,recovery_success,retry_count,circuit_opened,logged_at" ;;
        dead_letter) echo "id,operation_type,operation_params,error_message,stack_trace,attempt_count,session_id,task_id,status,retry_after,expires_at,created_at" ;;
        tasks) echo "id,name,description,task_type,plan_id,sprint_id,parent_task_id,session_id,status,scope_files,scope_json,assigned_agent,assigned_model,priority,sequence,depends_on,blocks,estimated_effort,actual_iterations,files_changed,created_at,started_at,completed_at,result_summary,error_message,commit_sha" ;;
        task_attempts) echo "id,task_id,session_id,attempt_number,model,agent,started_at,ended_at,duration_seconds,status,error_type,error_message,tokens_input,tokens_output,cost_cents" ;;
        task_files) echo "id,task_id,file_path,file_type,access_type,is_pattern" ;;
        *) echo "" ;;
    esac
}

# Validate table name against whitelist
validate_table_name() {
    local table="$1"
    if ! _in_array "$table" "${VALID_TABLES[@]}"; then
        log_error "Invalid table name: $table" "validation"
        return 1
    fi
    return 0
}

# Validate column name against whitelist for specific table
validate_column_name() {
    local table="$1"
    local column="$2"

    # Get valid columns for this table
    local valid_cols
    valid_cols="$(_valid_columns_for_table "$table")"
    if [ -z "$valid_cols" ]; then
        log_error "Unknown table for column validation: $table" "validation"
        return 1
    fi

    # Check if column is in the comma-separated list (exact match)
    local col_item
    IFS=',' read -ra _col_check_arr <<< "$valid_cols"
    for col_item in "${_col_check_arr[@]}"; do
        if [ "$col_item" = "$column" ]; then
            return 0
        fi
    done
    log_error "Invalid column name '$column' for table '$table'" "validation"
    return 1
}

# Validate multiple column names
validate_columns() {
    local table="$1"
    local columns="$2"

    # Split by comma and validate each
    IFS=',' read -ra col_array <<< "$columns"
    for col in "${col_array[@]}"; do
        # Trim all leading/trailing whitespace
        col="${col#"${col%%[![:space:]]*}"}"
        col="${col%"${col##*[![:space:]]}"}"
        if [ -z "$col" ]; then
            continue
        fi
        if ! validate_column_name "$table" "$col"; then
            return 1
        fi
    done
    return 0
}

# Escape string for safe SQL insertion
# Uses proper escaping: doubles single quotes and handles special chars
sql_escape() {
    local value="$1"
    # Escape single quotes by doubling them (SQL standard)
    value="${value//\'/\'\'}"
    # Escape backslashes
    value="${value//\\/\\\\}"
    echo "$value"
}

# Escape string for safe JSON value
# Handles special characters that need escaping in JSON strings
json_escape() {
    local value="$1"
    # Escape backslashes first (must be first)
    value="${value//\\/\\\\}"
    # Escape double quotes
    value="${value//\"/\\\"}"
    # Escape newlines
    value="${value//$'\n'/\\n}"
    # Escape carriage returns
    value="${value//$'\r'/\\r}"
    # Escape tabs
    value="${value//$'\t'/\\t}"
    echo "$value"
}

# Build a JSON object from key-value pairs
# Usage: json_object "key1" "value1" "key2" "value2" ...
json_object() {
    local result="{"
    local first=true

    while [ $# -ge 2 ]; do
        local key="$1"
        local value="$2"
        shift 2

        if [ "$first" = true ]; then
            first=false
        else
            result+=", "
        fi

        local escaped_value
        escaped_value=$(json_escape "$value")
        result+="\"$key\": \"$escaped_value\""
    done

    result+="}"
    echo "$result"
}

# Safe SQL query execution with error handling
# Usage: sql_exec "SELECT * FROM table WHERE id = ?" "value"
# Note: SQLite CLI doesn't support true prepared statements,
# so we use careful escaping and validation
sql_exec() {
    local query="$1"
    shift

    if [ ! -f "$DB_FILE" ]; then
        log_error "Database file not found: $DB_FILE" "sql"
        return 1
    fi

    local result
    if ! result=$(sqlite3 "$DB_FILE" "PRAGMA foreign_keys = ON; $query" 2>&1); then
        log_error "SQL execution failed: $result" "sql"
        log_debug "Query was: $query" "sql"
        return 1
    fi

    echo "$result"
}

# Safe SQL query execution with JSON output
sql_exec_json() {
    local query="$1"

    if [ ! -f "$DB_FILE" ]; then
        log_error "Database file not found: $DB_FILE" "sql"
        return 1
    fi

    local result
    if ! result=$(sqlite3 -json "$DB_FILE" "PRAGMA foreign_keys = ON; $query" 2>&1); then
        log_error "SQL execution failed: $result" "sql"
        return 1
    fi

    echo "$result"
}

# Safe SQL query execution with column headers
sql_exec_table() {
    local query="$1"

    if [ ! -f "$DB_FILE" ]; then
        log_error "Database file not found: $DB_FILE" "sql"
        return 1
    fi

    local result
    if ! result=$(sqlite3 -column -header "$DB_FILE" "PRAGMA foreign_keys = ON; $query" 2>&1); then
        log_error "SQL execution failed: $result" "sql"
        return 1
    fi

    echo "$result"
}

# Build safe INSERT query
# Usage: sql_insert "table" "col1,col2" "val1" "val2"
sql_insert() {
    local table="$1"
    local columns="$2"
    shift 2

    # Validate table name
    if ! validate_table_name "$table"; then
        return 1
    fi

    # Validate column names
    if ! validate_columns "$table" "$columns"; then
        return 1
    fi

    local values=""
    local first=true
    for val in "$@"; do
        if [ "$first" = true ]; then
            first=false
        else
            values+=","
        fi
        local escaped
        escaped=$(sql_escape "$val")
        values+="'$escaped'"
    done

    local query="INSERT INTO $table ($columns) VALUES ($values);"
    sql_exec "$query"
}

# Build safe UPDATE query with validated table/column names
# Usage: sql_update "table" "col1" "val1" "where_col" "where_val"
sql_update() {
    local table="$1"
    local set_column="$2"
    local set_value="$3"
    local where_column="$4"
    local where_value="$5"

    # Validate table name
    if ! validate_table_name "$table"; then
        return 1
    fi

    # Validate column names
    if ! validate_column_name "$table" "$set_column"; then
        return 1
    fi
    if ! validate_column_name "$table" "$where_column"; then
        return 1
    fi

    local escaped_set_value
    escaped_set_value=$(sql_escape "$set_value")
    local escaped_where_value
    escaped_where_value=$(sql_escape "$where_value")

    local query="UPDATE $table SET $set_column = '$escaped_set_value' WHERE $where_column = '$escaped_where_value';"
    sql_exec "$query"
}

# Build safe UPDATE query with multiple SET clauses
# Usage: sql_update_multi "table" "where_col" "where_val" "col1" "val1" "col2" "val2" ...
sql_update_multi() {
    local table="$1"
    local where_column="$2"
    local where_value="$3"
    shift 3

    # Validate table name
    if ! validate_table_name "$table"; then
        return 1
    fi

    # Validate where column
    if ! validate_column_name "$table" "$where_column"; then
        return 1
    fi

    # Build SET clause from pairs
    local set_clause=""
    local first=true
    while [ $# -ge 2 ]; do
        local col="$1"
        local val="$2"
        shift 2

        # Validate column name
        if ! validate_column_name "$table" "$col"; then
            return 1
        fi

        if [ "$first" = true ]; then
            first=false
        else
            set_clause+=", "
        fi

        local escaped_val
        escaped_val=$(sql_escape "$val")
        set_clause+="$col = '$escaped_val'"
    done

    local escaped_where_value
    escaped_where_value=$(sql_escape "$where_value")

    local query="UPDATE $table SET $set_clause WHERE $where_column = '$escaped_where_value';"
    sql_exec "$query"
}

# Build safe SELECT query
# Usage: sql_select "field1,field2" "table" "where_col" "where_val"
sql_select() {
    local fields="$1"
    local table="$2"
    local where_column="$3"
    local where_value="$4"

    # Validate table name
    if ! validate_table_name "$table"; then
        return 1
    fi

    # Validate select fields (can be "*" for all)
    if [ "$fields" != "*" ]; then
        if ! validate_columns "$table" "$fields"; then
            return 1
        fi
    fi

    # Validate where column
    if ! validate_column_name "$table" "$where_column"; then
        return 1
    fi

    local escaped_value
    escaped_value=$(sql_escape "$where_value")

    local query="SELECT $fields FROM $table WHERE $where_column = '$escaped_value';"
    sql_exec "$query"
}

# ============================================================================
# TRANSACTION SUPPORT
# ============================================================================

# Begin a transaction (for atomic multi-step operations)
sql_begin_transaction() {
    if ! sql_exec "BEGIN IMMEDIATE TRANSACTION;"; then
        log_error "Failed to begin transaction" "sql"
        return 1
    fi
}

# Commit a transaction
sql_commit() {
    if ! sql_exec "COMMIT;"; then
        log_error "Failed to commit transaction" "sql"
        return 1
    fi
}

# Rollback a transaction
sql_rollback() {
    if ! sql_exec "ROLLBACK;"; then
        log_error "Failed to rollback transaction" "sql"
        return 1
    fi
}

# Execute multiple statements atomically
# Usage: sql_transaction "stmt1;" "stmt2;" "stmt3;"
sql_transaction() {
    if [ ! -f "$DB_FILE" ]; then
        log_error "Database file not found: $DB_FILE" "sql"
        return 1
    fi

    # Build full transaction
    local full_sql="PRAGMA foreign_keys = ON; BEGIN IMMEDIATE TRANSACTION;"
    for stmt in "$@"; do
        full_sql+=" $stmt"
    done
    full_sql+=" COMMIT;"

    local result
    if ! result=$(sqlite3 "$DB_FILE" "$full_sql" 2>&1); then
        log_error "Transaction failed: $result" "sql"
        # Attempt rollback in case partial execution
        sqlite3 "$DB_FILE" "ROLLBACK;" 2>/dev/null || true
        return 1
    fi

    echo "$result"
}

# ============================================================================
# DATABASE UTILITIES
# ============================================================================

# Ensure database exists and is valid
ensure_db() {
    if [ ! -f "$DB_FILE" ]; then
        local script_dir
        script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
        log_info "Database not found, initializing..." "db"
        if ! bash "${script_dir}/db-init.sh"; then
            log_error "Failed to initialize database" "db"
            return 1
        fi
    fi
    return 0
}

# Check database integrity
check_db_integrity() {
    local integrity
    integrity=$(sqlite3 "$DB_FILE" "PRAGMA integrity_check;" 2>/dev/null || echo "error")
    if [ "$integrity" != "ok" ]; then
        log_error "Database integrity check failed: $integrity" "db"
        return 1
    fi
    return 0
}

# ============================================================================
# ERROR HANDLING
# ============================================================================

# Trap handler for errors
on_error() {
    local line_no="$1"
    local error_code="$2"
    log_error "Error on line $line_no (exit code: $error_code)" "trap"
}

# Set up error trap (call at start of main script)
setup_error_trap() {
    trap 'on_error ${LINENO} $?' ERR
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

# Generate unique ID with prefix
# Uses POSIX-compliant method for portability
generate_id() {
    local prefix="${1:-id}"
    local hex_suffix

    # Try xxd first (common on Linux), fall back to od (POSIX)
    # Use 8 bytes (16 hex chars) to reduce collision risk (M8)
    if command -v xxd &> /dev/null; then
        hex_suffix=$(head -c 8 /dev/urandom | xxd -p)
    else
        # POSIX-compliant alternative using od
        hex_suffix=$(head -c 8 /dev/urandom | od -An -tx1 | tr -d ' \n')
    fi

    echo "${prefix}-$(date +%Y%m%d-%H%M%S)-${hex_suffix}"
}

# Check if command exists
require_command() {
    local cmd="$1"
    if ! command -v "$cmd" &> /dev/null; then
        log_error "Required command not found: $cmd" "setup"
        return 1
    fi
    return 0
}

# ============================================================================
# PORTABLE HELPERS
# ============================================================================

# Ensure we're inside a git repository
# Usage: ensure_git
ensure_git() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        log_error "Not a git repository" "git"
        return 1
    fi
    return 0
}

# Format a number with thousands separators (portable)
# Falls back to plain number on systems without locale support
# Usage: format_number 1234567  =>  "1,234,567"
format_number() {
    local num="$1"
    # Try printf with grouping (glibc); fall back to awk
    if printf "%'d" "$num" 2>/dev/null; then
        return 0
    fi
    # Portable awk fallback
    echo "$num" | awk '{ printf "%d", $1; exit }' | \
        awk '{
            s = $0
            len = length(s)
            result = ""
            for (i = 1; i <= len; i++) {
                if (i > 1 && (len - i + 1) % 3 == 0) result = result ","
                result = result substr(s, i, 1)
            }
            print result
        }'
}

# Get file size in bytes (portable across Linux and macOS)
# Usage: file_size_bytes "/path/to/file"
file_size_bytes() {
    local filepath="$1"
    if [ ! -f "$filepath" ]; then
        echo "0"
        return 1
    fi
    # wc -c is POSIX and works everywhere
    wc -c < "$filepath" | tr -d ' '
}

# Validate a file path is contained within the project root
# Prevents path traversal attacks from untrusted input
# Usage: validate_file_path "$path" "$allowed_root"
validate_file_path() {
    local filepath="$1"
    local allowed_root="${2:-$(pwd)}"

    if [ -z "$filepath" ]; then
        log_error "Empty file path" "validation"
        return 1
    fi

    # Resolve to absolute path (use readlink -f on Linux, realpath or fallback on macOS)
    local resolved
    if command -v realpath &>/dev/null; then
        resolved=$(realpath -m "$allowed_root/$filepath" 2>/dev/null) || resolved=""
    elif readlink -f "/" &>/dev/null 2>&1; then
        resolved=$(readlink -f "$allowed_root/$filepath" 2>/dev/null) || resolved=""
    else
        # Basic fallback: reject paths with ..
        resolved="$allowed_root/$filepath"
    fi

    if [ -z "$resolved" ]; then
        log_error "Cannot resolve path: $filepath" "validation"
        return 1
    fi

    # Resolve allowed_root too
    local resolved_root
    if command -v realpath &>/dev/null; then
        resolved_root=$(realpath -m "$allowed_root" 2>/dev/null) || resolved_root="$allowed_root"
    elif readlink -f "/" &>/dev/null 2>&1; then
        resolved_root=$(readlink -f "$allowed_root" 2>/dev/null) || resolved_root="$allowed_root"
    else
        resolved_root="$allowed_root"
    fi

    # Check containment
    case "$resolved" in
        "$resolved_root"/*)
            return 0
            ;;
        "$resolved_root")
            return 0
            ;;
        *)
            log_error "Path traversal detected: $filepath resolves outside $allowed_root" "validation"
            return 1
            ;;
    esac
}

# Validate database file: exists, non-empty, and responds to queries
# Usage: validate_db
validate_db() {
    if [ ! -f "$DB_FILE" ]; then
        log_error "Database file not found: $DB_FILE" "db"
        return 1
    fi

    local size
    size=$(file_size_bytes "$DB_FILE")
    if [ "$size" -eq 0 ]; then
        log_error "Database file is empty: $DB_FILE" "db"
        return 1
    fi

    if ! sqlite3 "$DB_FILE" "SELECT 1;" >/dev/null 2>&1; then
        log_error "Database file is not valid SQLite: $DB_FILE" "db"
        return 1
    fi

    return 0
}

# Compute a date N days ago (portable across GNU and BSD date)
# Usage: date_days_ago 30  =>  "2025-01-01"
date_days_ago() {
    local days="$1"
    # GNU date
    if date -d "$days days ago" '+%Y-%m-%d' 2>/dev/null; then
        return 0
    fi
    # BSD/macOS date
    if date -v-${days}d '+%Y-%m-%d' 2>/dev/null; then
        return 0
    fi
    # Fallback using awk and current epoch
    local now
    now=$(date '+%s' 2>/dev/null || echo "0")
    local target=$((now - days * 86400))
    date -d "@$target" '+%Y-%m-%d' 2>/dev/null || \
        awk "BEGIN { print strftime(\"%Y-%m-%d\", $target) }" 2>/dev/null || \
        echo "1970-01-01"
}

# ============================================================================
# TEMP FILE MANAGEMENT
# ============================================================================

# Global array to track temp files for cleanup
_DEVTEAM_TEMP_FILES=()

# Create a temp file and register it for cleanup
# Usage: local tmp; tmp=$(safe_mktemp)
safe_mktemp() {
    local tmp
    tmp=$(mktemp)
    _DEVTEAM_TEMP_FILES+=("$tmp")
    echo "$tmp"
}

# Remove all registered temp files
cleanup_temp_files() {
    local f
    for f in "${_DEVTEAM_TEMP_FILES[@]+"${_DEVTEAM_TEMP_FILES[@]}"}"; do
        rm -f "$f" 2>/dev/null || true
    done
    _DEVTEAM_TEMP_FILES=()
}

# Register the cleanup trap (call once per script)
# Chains with existing EXIT traps and catches INT/TERM (M10)
setup_temp_cleanup() {
    # Chain with existing EXIT trap if any
    local existing_trap
    existing_trap=$(trap -p EXIT 2>/dev/null | sed "s/^trap -- '//;s/' EXIT$//" || true)
    if [ -n "$existing_trap" ]; then
        # shellcheck disable=SC2064
        trap "cleanup_temp_files; $existing_trap" EXIT
    else
        trap cleanup_temp_files EXIT
    fi
    trap 'cleanup_temp_files; exit 130' INT
    trap 'cleanup_temp_files; exit 143' TERM
}

# Sanitize user-supplied text: strip control characters and limit length
# Usage: sanitize_input "$value" [max_length]
sanitize_input() {
    local value="$1"
    local max_length="${2:-1024}"

    # Strip control characters except newline and tab
    value=$(printf '%s' "$value" | tr -d '\000-\010\013\014\016-\037')

    # Truncate to max length
    if [ "${#value}" -gt "$max_length" ]; then
        value="${value:0:$max_length}"
    fi

    echo "$value"
}
