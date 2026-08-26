#!/bin/bash
# DevTeam Database Initialization
# Creates and initializes the SQLite database if it doesn't exist

set -euo pipefail

# Configuration
DEVTEAM_DIR="${DEVTEAM_DIR:-.devteam}"
DB_FILE="${DEVTEAM_DIR}/devteam.db"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEMA_FILE="${SCRIPT_DIR}/schema.sql"
SCHEMA_V2_FILE="${SCRIPT_DIR}/schema-v2.sql"
SCHEMA_V3_FILE="${SCRIPT_DIR}/schema-v3.sql"
SCHEMA_V4_FILE="${SCRIPT_DIR}/schema-v4.sql"
SCHEMA_V5_FILE="${SCRIPT_DIR}/schema-v5.sql"

# Current schema version - increment when schema changes
SCHEMA_VERSION="5"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[devteam]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[devteam]${NC} $1"
}

log_error() {
    echo -e "${RED}[devteam]${NC} $1" >&2
}

# Check for sqlite3
check_sqlite() {
    if ! command -v sqlite3 &> /dev/null; then
        log_error "sqlite3 is not installed. Please install it:"
        log_error "  macOS: brew install sqlite3"
        log_error "  Ubuntu/Debian: sudo apt-get install sqlite3"
        log_error "  Windows: Download from https://sqlite.org/download.html"
        exit 1
    fi
}

# Create .devteam directory if needed
ensure_devteam_dir() {
    if [ ! -d "$DEVTEAM_DIR" ]; then
        mkdir -p "$DEVTEAM_DIR"
        log_info "Created $DEVTEAM_DIR directory"
    fi
}

# Execute SQL with foreign keys enabled
sql_exec() {
    sqlite3 "$DB_FILE" "PRAGMA foreign_keys = ON; $1"
}

# Get current schema version from database
get_db_schema_version() {
    if [ ! -f "$DB_FILE" ]; then
        echo "0"
        return
    fi

    # Check if schema_version table exists
    local table_exists
    table_exists=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='schema_version';" 2>/dev/null || echo "0")

    if [ "$table_exists" = "0" ]; then
        echo "0"
        return
    fi

    # Get the version
    local version
    # Order by version DESC (not just applied_at DESC): CURRENT_TIMESTAMP has only
    # second-level resolution, so two migrations applied in the same second tie on
    # applied_at and SQLite's tie-break order is unspecified without this.
    version=$(sqlite3 "$DB_FILE" "SELECT version FROM schema_version ORDER BY version DESC, applied_at DESC LIMIT 1;" 2>/dev/null || echo "0")
    echo "${version:-0}"
}

# Initialize database
init_database() {
    local current_version
    current_version=$(get_db_schema_version)

    if [ ! -f "$DB_FILE" ]; then
        log_info "Initializing DevTeam database..."

        if [ ! -f "$SCHEMA_FILE" ]; then
            log_error "Schema file not found: $SCHEMA_FILE"
            exit 1
        fi

        # Create database with schema
        if ! sqlite3 "$DB_FILE" < "$SCHEMA_FILE"; then
            log_error "Failed to create database schema"
            exit 1
        fi

        # Create schema_version table BEFORE migrations (H1)
        sql_exec "CREATE TABLE IF NOT EXISTS schema_version (version INTEGER PRIMARY KEY, applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP);"

        # Apply schema v2 (acceptance criteria, features, context management)
        if [ -f "$SCHEMA_V2_FILE" ]; then
            if ! sqlite3 "$DB_FILE" < "$SCHEMA_V2_FILE"; then
                log_error "Failed to apply schema v2"
                exit 1
            fi
            log_info "Applied schema v2 (acceptance criteria, features, context management)"
        fi

        # Apply schema v3 (tasks table for hook integration)
        if [ -f "$SCHEMA_V3_FILE" ]; then
            if ! sqlite3 "$DB_FILE" < "$SCHEMA_V3_FILE"; then
                log_error "Failed to apply schema v3"
                exit 1
            fi
            log_info "Applied schema v3 (tasks table for hook integration)"
        fi

        # Apply schema v4 (fix plans.research_session_id foreign key)
        if [ -f "$SCHEMA_V4_FILE" ]; then
            if ! sqlite3 "$DB_FILE" < "$SCHEMA_V4_FILE"; then
                log_error "Failed to apply schema v4"
                exit 1
            fi
            log_info "Applied schema v4 (plans.research_session_id ON DELETE SET NULL)"
        fi

        # Apply schema v5 (agent_runs call-hierarchy columns)
        if [ -f "$SCHEMA_V5_FILE" ]; then
            if ! sqlite3 "$DB_FILE" < "$SCHEMA_V5_FILE"; then
                log_error "Failed to apply schema v5"
                exit 1
            fi
            log_info "Applied schema v5 (agent_runs.invoked_by_agent / invoked_by_run_id)"
        fi

        # Validate SCHEMA_VERSION is numeric before SQL interpolation
        if [[ ! "$SCHEMA_VERSION" =~ ^[0-9]+$ ]]; then
            log_error "Invalid SCHEMA_VERSION: $SCHEMA_VERSION"
            exit 1
        fi

        # Record schema version
        sql_exec "INSERT INTO schema_version (version) VALUES ($SCHEMA_VERSION);"

        log_info "Database created: $DB_FILE (schema v$SCHEMA_VERSION)"
    elif [ "$current_version" = "0" ]; then
        log_info "Database exists but no schema version, updating..."

        # Create schema version table
        sql_exec "CREATE TABLE IF NOT EXISTS schema_version (version INTEGER PRIMARY KEY, applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP);"

        # Re-run base schema to add any missing tables (IF NOT EXISTS handles this safely)
        if ! sqlite3 "$DB_FILE" < "$SCHEMA_FILE"; then
            log_error "Failed to update database schema"
            exit 1
        fi

        # Record v1 as the base version from schema.sql
        sql_exec "INSERT OR IGNORE INTO schema_version (version) VALUES (1);"

        # Apply remaining migrations (v2, v3, v4) that the base schema doesn't include
        run_migrations 1

        # Validate schema after migrations
        validate_schema
        log_info "Schema updated to v$SCHEMA_VERSION"
    elif [ "$current_version" -lt "$SCHEMA_VERSION" ]; then
        log_info "Database schema upgrade needed: v$current_version → v$SCHEMA_VERSION"
        run_migrations "$current_version"

        # Validate schema version after migration (M11)
        validate_schema
    else
        log_info "Database schema is current (v$current_version)"
    fi
}

# Run migrations from current version to target version
run_migrations() {
    local from_version="$1"

    # Helper: apply a single migration file within a transaction (single sqlite3 process)
    apply_migration() {
        local version="$1"
        local file="$2"
        local description="$3"

        local applied
        applied=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM schema_version WHERE version = $version;" 2>/dev/null || echo "0")
        if [ "$applied" != "0" ]; then
            return 0  # Already applied
        fi
        if [ ! -f "$file" ]; then
            return 0  # File not found, skip
        fi

        log_info "Running migration v$((version - 1)) → v$version..."

        # Pipe BEGIN + schema file + version record + COMMIT through a single sqlite3 process
        # so the transaction actually works. On failure, sqlite3 auto-rolls back.
        if ! { echo "BEGIN TRANSACTION;"; cat "$file"; echo "INSERT INTO schema_version (version) VALUES ($version);"; echo "COMMIT;"; } | sqlite3 "$DB_FILE" 2>/dev/null; then
            log_error "Failed to apply schema v$version migration — rolled back"
            exit 1
        fi
        log_info "Applied schema v$version: $description"
    }

    # Migration v1 → v2: Add acceptance criteria, features, context management
    if [ "$from_version" -lt 2 ]; then
        apply_migration 2 "$SCHEMA_V2_FILE" "acceptance_criteria, features, context_snapshots, context_budgets, progress_summaries, session_phases"
    fi

    # Migration v2 → v3: Add tasks table for hook integration
    if [ "$from_version" -lt 3 ]; then
        apply_migration 3 "$SCHEMA_V3_FILE" "tasks, task_attempts, task_files tables"
    fi

    # Migration v3 → v4: Fix plans.research_session_id foreign key
    if [ "$from_version" -lt 4 ]; then
        apply_migration 4 "$SCHEMA_V4_FILE" "plans.research_session_id ON DELETE SET NULL"
    fi

    # Migration v4 → v5: Add agent_runs call-hierarchy columns
    if [ "$from_version" -lt 5 ]; then
        apply_migration 5 "$SCHEMA_V5_FILE" "agent_runs.invoked_by_agent / invoked_by_run_id"
    fi

    log_info "Migrations complete, now at v$SCHEMA_VERSION"
}

# Validate schema version and critical tables after migration (M11)
validate_schema() {
    local actual_version
    actual_version=$(get_db_schema_version)

    if [ "$actual_version" != "$SCHEMA_VERSION" ]; then
        log_error "Schema validation failed: expected v$SCHEMA_VERSION, got v$actual_version"
        exit 1
    fi

    # Verify critical tables exist
    local critical_tables=("sessions" "events" "agent_runs" "plans" "tasks" "schema_version")
    for table in "${critical_tables[@]}"; do
        local exists
        exists=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='$table';" 2>/dev/null || echo "0")
        if [ "$exists" = "0" ]; then
            log_error "Schema validation failed: missing critical table '$table'"
            exit 1
        fi
    done

    log_info "Schema validation passed (v$SCHEMA_VERSION)"
}

# Verify database integrity
verify_database() {
    local integrity
    integrity=$(sqlite3 "$DB_FILE" "PRAGMA integrity_check;" 2>/dev/null)

    if [ "$integrity" != "ok" ]; then
        log_error "Database integrity check failed!"
        log_error "Consider backing up and reinitializing: mv $DB_FILE ${DB_FILE}.bak"
        exit 1
    fi
}

# Clean up old state files (migration from YAML to SQLite)
# IMPORTANT: state.yaml is DEPRECATED. SQLite (.devteam/devteam.db) is the source of truth.
cleanup_old_state() {
    local old_files=(
        "${DEVTEAM_DIR}/state.yaml"
        "${DEVTEAM_DIR}/circuit-breaker.json"
        "${DEVTEAM_DIR}/rate-limit-state.json"
        "${DEVTEAM_DIR}/abandonment-attempts.log"
    )

    for file in "${old_files[@]}"; do
        if [ -f "$file" ]; then
            log_warn "DEPRECATED state file found: $file"
            log_warn "  SQLite is now the sole source of truth for all state management."
            log_warn "  The file '$file' is no longer read by any DevTeam component."
            log_warn "  Remove it: rm $file"
        fi
    done

    # Also check for old project-state YAML files in docs/planning/
    local planning_dir="docs/planning"
    if [ -d "$planning_dir" ]; then
        local state_yaml_files
        state_yaml_files=$(find "$planning_dir" -maxdepth 1 -name "*.project-state.yaml" -o -name ".feature-*-state.yaml" -o -name ".issue-*-state.yaml" 2>/dev/null || true)
        if [ -n "$state_yaml_files" ]; then
            log_warn "DEPRECATED planning state YAML files found:"
            while IFS= read -r f; do
                [ -n "$f" ] && log_warn "  $f"
            done <<< "$state_yaml_files"
            log_warn "  State is now managed in SQLite ($DB_FILE). These files are no longer used."
            log_warn "  Remove them after verifying your project state has been migrated."
        fi
    fi
}

# Main
main() {
    check_sqlite
    ensure_devteam_dir
    init_database
    verify_database
    cleanup_old_state

    log_info "Database ready: $DB_FILE"

    # Suggest hook installation if not already set up (L5)
    local hook_install="${SCRIPT_DIR}/../hooks/install.sh"
    if [ -f "$hook_install" ] && [ ! -f "${DEVTEAM_DIR}/.hooks-installed" ]; then
        log_info "Tip: Run 'hooks/install.sh' to set up DevTeam hooks for Claude Code"
    fi
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
