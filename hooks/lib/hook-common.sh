#!/bin/bash
# Hook-Common Library
# Bridge between hook scripts and DevTeam infrastructure (scripts/lib/common.sh, scripts/state.sh, scripts/events.sh)
# All hook scripts source this file for a stable API layer.

# Resolve plugin root from this file's location (hooks/lib/ -> project root)
HOOK_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$HOOK_LIB_DIR/../.." && pwd)"

# Source the existing infrastructure (graceful degradation if missing)
source "${PLUGIN_ROOT}/scripts/lib/common.sh" 2>/dev/null || true
source "${PLUGIN_ROOT}/scripts/state.sh" 2>/dev/null || true
source "${PLUGIN_ROOT}/scripts/events.sh" 2>/dev/null || true

# ============================================================================
# CONFIGURATION DEFAULTS
# ============================================================================

DEVTEAM_DIR="${DEVTEAM_DIR:-.devteam}"
DB_FILE="${DEVTEAM_DIR}/devteam.db"
MAX_ITERATIONS="${DEVTEAM_MAX_ITERATIONS:-100}"
MAX_FAILURES="${DEVTEAM_MAX_FAILURES:-5}"
ECO_MODE="${DEVTEAM_ECO_MODE:-false}"
AUTONOMOUS_MARKER="${DEVTEAM_DIR}/autonomous-mode"
CIRCUIT_BREAKER_FILE="${DEVTEAM_DIR}/circuit-breaker.json"

# ============================================================================
# HOOK INITIALIZATION
# ============================================================================

init_hook() {
    local hook_name="${1:-unknown}"
    export CURRENT_HOOK="$hook_name"

    # Ensure runtime directories exist
    mkdir -p "$DEVTEAM_DIR" 2>/dev/null || true

    # Auto-initialize database if it doesn't exist
    if [[ ! -f "$DB_FILE" ]] && command -v sqlite3 &>/dev/null; then
        _auto_init_database
    fi
}

# Auto-initialize the SQLite database using schema files from the plugin
_auto_init_database() {
    local schema_dir="${PLUGIN_ROOT}/scripts"
    local schema_file="${schema_dir}/schema.sql"
    local schema_version=5

    # Need the base schema file at minimum
    if [[ ! -f "$schema_file" ]]; then
        return 0
    fi

    # Create database with base schema
    if ! sqlite3 "$DB_FILE" < "$schema_file" 2>/dev/null; then
        return 0
    fi

    # Create schema_version table
    sqlite3 "$DB_FILE" "CREATE TABLE IF NOT EXISTS schema_version (version INTEGER PRIMARY KEY, applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP);" 2>/dev/null || true

    # Apply migrations v2 through v5 (keep in sync with scripts/db-init.sh's
    # SCHEMA_VERSION -- this is a separate auto-init path used when a hook
    # fires before db-init.sh has ever run, so it must not drift behind it)
    local migration_file
    for v in 2 3 4 5; do
        migration_file="${schema_dir}/schema-v${v}.sql"
        if [[ -f "$migration_file" ]]; then
            sqlite3 "$DB_FILE" < "$migration_file" 2>/dev/null || true
        fi
    done

    # Record final schema version
    sqlite3 "$DB_FILE" "INSERT OR REPLACE INTO schema_version (version) VALUES ($schema_version);" 2>/dev/null || true

    log_info "hook-common" "Auto-initialized database: $DB_FILE (schema v${schema_version})" 2>/dev/null || true
}

# ============================================================================
# LOGGING (delegates to scripts/lib/common.sh if available)
# ============================================================================

# If common.sh was not sourced, provide fallback logging
if ! declare -f log_debug &>/dev/null; then
    log_debug() { echo "[debug] [$1] $2" >&2; }
    log_info()  { echo "[info]  [$1] $2" >&2; }
    log_warn()  { echo "[warn]  [$1] $2" >&2; }
    log_error() { echo "[error] [$1] $2" >&2; }
fi

# ============================================================================
# SESSION & STATE ACCESSORS
# ============================================================================

get_current_session() {
    if declare -f get_current_session_id &>/dev/null; then
        get_current_session_id
    elif [[ -f "$DB_FILE" ]] && command -v sqlite3 &>/dev/null; then
        sqlite3 "$DB_FILE" "SELECT id FROM sessions WHERE status = 'running' ORDER BY started_at DESC LIMIT 1;" 2>/dev/null || echo ""
    else
        echo ""
    fi
}

get_current_task() {
    local session_id
    session_id=$(get_current_session)
    if [[ -z "$session_id" ]]; then
        echo ""
        return
    fi
    if [[ -f "$DB_FILE" ]] && command -v sqlite3 &>/dev/null; then
        local safe_id="${session_id//\'/\'\'}"
        sqlite3 "$DB_FILE" "SELECT current_task_id FROM sessions WHERE id = '$safe_id';" 2>/dev/null || echo ""
    else
        echo ""
    fi
}

# Delegate to state.sh if sourced, else query DB directly
if ! declare -f get_current_iteration &>/dev/null; then
    get_current_iteration() {
        local session_id
        session_id=$(get_current_session)
        if [[ -z "$session_id" ]]; then echo "0"; return; fi
        if [[ -f "$DB_FILE" ]] && command -v sqlite3 &>/dev/null; then
            local safe_id="${session_id//\'/\'\'}"
            local val
            val=$(sqlite3 "$DB_FILE" "SELECT current_iteration FROM sessions WHERE id = '$safe_id';" 2>/dev/null || echo "0")
            echo "${val:-0}"
        else
            echo "0"
        fi
    }
fi

if ! declare -f get_consecutive_failures &>/dev/null; then
    get_consecutive_failures() {
        local session_id
        session_id=$(get_current_session)
        if [[ -z "$session_id" ]]; then echo "0"; return; fi
        if [[ -f "$DB_FILE" ]] && command -v sqlite3 &>/dev/null; then
            local safe_id="${session_id//\'/\'\'}"
            local val
            val=$(sqlite3 "$DB_FILE" "SELECT consecutive_failures FROM sessions WHERE id = '$safe_id';" 2>/dev/null || echo "0")
            echo "${val:-0}"
        else
            echo "0"
        fi
    }
fi

if ! declare -f get_current_model &>/dev/null; then
    get_current_model() {
        local session_id
        session_id=$(get_current_session)
        if [[ -z "$session_id" ]]; then echo "sonnet"; return; fi
        if [[ -f "$DB_FILE" ]] && command -v sqlite3 &>/dev/null; then
            local safe_id="${session_id//\'/\'\'}"
            local val
            val=$(sqlite3 "$DB_FILE" "SELECT current_model FROM sessions WHERE id = '$safe_id';" 2>/dev/null || echo "sonnet")
            echo "${val:-sonnet}"
        else
            echo "sonnet"
        fi
    }
fi

if ! declare -f increment_failures &>/dev/null; then
    increment_failures() {
        local session_id
        session_id=$(get_current_session)
        if [[ -n "$session_id" ]] && [[ -f "$DB_FILE" ]] && command -v sqlite3 &>/dev/null; then
            local safe_id="${session_id//\'/\'\'}"
            sqlite3 "$DB_FILE" "UPDATE sessions SET consecutive_failures = consecutive_failures + 1 WHERE id = '$safe_id';" 2>/dev/null || true
        fi
    }
fi

if ! declare -f reset_failures &>/dev/null; then
    reset_failures() {
        local session_id
        session_id=$(get_current_session)
        if [[ -n "$session_id" ]] && [[ -f "$DB_FILE" ]] && command -v sqlite3 &>/dev/null; then
            local safe_id="${session_id//\'/\'\'}"
            sqlite3 "$DB_FILE" "UPDATE sessions SET consecutive_failures = 0 WHERE id = '$safe_id';" 2>/dev/null || true
        fi
    }
fi

# ============================================================================
# CONTEXT INJECTION
# ============================================================================

inject_system_message() {
    local id="$1"
    local message="$2"

    # Escape message for JSON
    local escaped_msg
    escaped_msg=$(printf '%s' "$message" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | awk '{printf "%s\\n", $0}' | sed 's/\\n$//')

    # Output JSON context injection to stdout (Claude Code hook protocol)
    cat <<EOF
{"id":"devteam-${id}","type":"system","message":"${escaped_msg}"}
EOF
}

# ============================================================================
# SCOPE CHECKING
# ============================================================================

file_in_scope() {
    local file_path="$1"

    # If no scope is defined, all files are in scope
    local scope_file="${DEVTEAM_DIR}/task-scope.txt"
    if [[ ! -f "$scope_file" ]]; then
        return 0
    fi

    # Normalize the file path
    local normalized
    normalized=$(realpath -m "$file_path" 2>/dev/null || echo "$file_path")
    local project_root
    project_root=$(pwd)

    # Check against scope definitions
    while IFS= read -r scope_pattern; do
        # Skip empty lines and comments
        [[ -z "$scope_pattern" ]] && continue
        [[ "$scope_pattern" == \#* ]] && continue

        # Check if file matches the pattern
        if [[ "$file_path" == $scope_pattern ]] || [[ "$normalized" == *"$scope_pattern"* ]]; then
            return 0
        fi
    done < "$scope_file"

    return 1
}

get_scope_files() {
    local scope_file="${DEVTEAM_DIR}/task-scope.txt"
    if [[ -f "$scope_file" ]]; then
        grep -v '^#' "$scope_file" | grep -v '^$'
    else
        echo "(no scope defined - all files allowed)"
    fi
}

# ============================================================================
# EVENT LOGGING
# ============================================================================

log_event_to_db() {
    local event_type="$1"
    local category="$2"
    local message="$3"
    local data="${4:-"{}"}"

    # Delegate to events.sh log_event if available
    if declare -f log_event &>/dev/null; then
        log_event "$event_type" "$category" "$message" "$data" 2>/dev/null || true
        return
    fi

    # Direct DB insert fallback
    if [[ -f "$DB_FILE" ]] && command -v sqlite3 &>/dev/null; then
        local session_id
        session_id=$(get_current_session)
        local safe_session="${session_id//\'/\'\'}"
        local safe_msg="${message//\'/\'\'}"
        local safe_data="${data//\'/\'\'}"
        local safe_type="${event_type//\'/\'\'}"
        local safe_cat="${category//\'/\'\'}"

        sqlite3 "$DB_FILE" "INSERT INTO events (session_id, event_type, category, message, data, timestamp)
            VALUES ('$safe_session', '$safe_type', '$safe_cat', '$safe_msg', '$safe_data', datetime('now'));" 2>/dev/null || true
    fi
}

# ============================================================================
# MCP NOTIFICATION
# ============================================================================

mcp_notify() {
    local event="$1"
    local data="${2:-"{}"}"

    # Best-effort notification via unix socket
    local sock="${DEVTEAM_DIR}/mcp.sock"
    if [[ -S "$sock" ]]; then
        local safe_event="${event//\"/\\\"}"
        printf '{"event":"%s","data":%s}\n' "$safe_event" "$data" | socat - UNIX-CONNECT:"$sock" 2>/dev/null || true
    fi
    # Silently no-op if socket unavailable
}

# ============================================================================
# CLAUDE CONTEXT
# ============================================================================

get_claude_context() {
    local session_id
    session_id=$(get_current_session)
    local task_id
    task_id=$(get_current_task)
    local iteration
    iteration=$(get_current_iteration)
    local failures
    failures=$(get_consecutive_failures)
    local model
    model=$(get_current_model)

    # JSON-escape values
    local safe_session="${session_id//\"/\\\"}"
    local safe_task="${task_id//\"/\\\"}"

    cat <<EOF
{"session":"${safe_session:-}","task":"${safe_task:-}","iteration":${iteration:-0},"failures":${failures:-0},"model":"${model:-sonnet}","hook":"${CURRENT_HOOK:-unknown}"}
EOF
}

# ============================================================================
# ESCALATION
# ============================================================================

trigger_escalation() {
    local reason="$1"

    log_warn "${CURRENT_HOOK:-hook}" "Escalation triggered: $reason"
    log_event_to_db "model_escalated" "escalation" "Escalation: $reason" "{\"reason\":\"${reason//\"/\\\"}\"}"

    # Record escalation in state.sh if available
    if declare -f record_escalation &>/dev/null; then
        record_escalation "$reason" 2>/dev/null || true
    fi
}

# ============================================================================
# AUTONOMOUS MODE & CIRCUIT BREAKER
# ============================================================================

is_autonomous_mode() {
    [[ -f "$AUTONOMOUS_MARKER" ]]
}

is_circuit_breaker_open() {
    local failures
    failures=$(get_consecutive_failures)
    if ! [[ "$failures" =~ ^[0-9]+$ ]]; then failures=0; fi
    [[ "$failures" -ge "$MAX_FAILURES" ]]
}

is_max_iterations_reached() {
    local iteration
    iteration=$(get_current_iteration)
    if ! [[ "$iteration" =~ ^[0-9]+$ ]]; then iteration=0; fi
    [[ "$iteration" -ge "$MAX_ITERATIONS" ]]
}

# ============================================================================
# CHECKPOINTS
# ============================================================================

save_checkpoint() {
    local message="${1:-Auto-checkpoint}"

    local session_id
    session_id=$(get_current_session)
    if [[ -z "$session_id" ]]; then return; fi

    local safe_session="${session_id//\'/\'\'}"
    local safe_msg="${message//\'/\'\'}"

    if [[ -f "$DB_FILE" ]] && command -v sqlite3 &>/dev/null; then
        sqlite3 "$DB_FILE" "INSERT OR IGNORE INTO checkpoints (session_id, message, created_at)
            VALUES ('$safe_session', '$safe_msg', datetime('now'));" 2>/dev/null || true
    fi
}

# ============================================================================
# DATABASE HELPERS
# ============================================================================

db_exists() {
    [[ -f "$DB_FILE" ]] && command -v sqlite3 &>/dev/null
}

if ! declare -f db_query &>/dev/null; then
    db_query() {
        local sql="$1"
        if db_exists; then
            sqlite3 "$DB_FILE" "$sql" 2>/dev/null || echo ""
        else
            echo ""
        fi
    }
fi
