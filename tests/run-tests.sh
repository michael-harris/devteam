#!/bin/bash
# DevTeam Test Runner
# Runs all tests and reports results
#
# Usage: ./tests/run-tests.sh [test-file]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Test results
declare -a FAILED_TESTS=()

# ============================================================================
# TEST HELPERS
# ============================================================================

log_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILED_TESTS+=("$1")
}

log_skip() {
    echo -e "${YELLOW}[SKIP]${NC} $1"
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
}

# Assert functions
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Values should be equal}"

    TESTS_RUN=$((TESTS_RUN + 1))

    if [ "$expected" = "$actual" ]; then
        log_pass "$message"
        return 0
    else
        log_fail "$message (expected: '$expected', got: '$actual')"
        return 1
    fi
}

assert_not_empty() {
    local value="$1"
    local message="${2:-Value should not be empty}"

    TESTS_RUN=$((TESTS_RUN + 1))

    if [ -n "$value" ]; then
        log_pass "$message"
        return 0
    else
        log_fail "$message (value was empty)"
        return 1
    fi
}

assert_empty() {
    local value="$1"
    local message="${2:-Value should be empty}"

    TESTS_RUN=$((TESTS_RUN + 1))

    if [ -z "$value" ]; then
        log_pass "$message"
        return 0
    else
        log_fail "$message (value was: '$value')"
        return 1
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-String should contain substring}"

    TESTS_RUN=$((TESTS_RUN + 1))

    if [[ "$haystack" == *"$needle"* ]]; then
        log_pass "$message"
        return 0
    else
        log_fail "$message (string did not contain '$needle')"
        return 1
    fi
}

assert_matches() {
    local value="$1"
    local pattern="$2"
    local message="${3:-Value should match pattern}"

    TESTS_RUN=$((TESTS_RUN + 1))

    if [[ "$value" =~ $pattern ]]; then
        log_pass "$message"
        return 0
    else
        log_fail "$message (value '$value' did not match pattern '$pattern')"
        return 1
    fi
}

assert_file_exists() {
    local file="$1"
    local message="${2:-File should exist}"

    TESTS_RUN=$((TESTS_RUN + 1))

    if [ -f "$file" ]; then
        log_pass "$message"
        return 0
    else
        log_fail "$message (file not found: $file)"
        return 1
    fi
}

assert_command_succeeds() {
    local cmd="$1"
    local message="${2:-Command should succeed}"

    TESTS_RUN=$((TESTS_RUN + 1))

    if eval "$cmd" > /dev/null 2>&1; then
        log_pass "$message"
        return 0
    else
        log_fail "$message (command failed: $cmd)"
        return 1
    fi
}

assert_command_fails() {
    local cmd="$1"
    local message="${2:-Command should fail}"

    TESTS_RUN=$((TESTS_RUN + 1))

    if ! eval "$cmd" > /dev/null 2>&1; then
        log_pass "$message"
        return 0
    else
        log_fail "$message (command succeeded when it should have failed: $cmd)"
        return 1
    fi
}

# ============================================================================
# TEST SETUP/TEARDOWN
# ============================================================================

setup_test_db() {
    export DEVTEAM_DIR="$SCRIPT_DIR/.test-devteam"
    export DB_FILE="$DEVTEAM_DIR/devteam.db"

    # Clean up any existing test database
    rm -rf "$DEVTEAM_DIR"
    mkdir -p "$DEVTEAM_DIR"

    # Initialize fresh database
    bash "$PROJECT_ROOT/scripts/db-init.sh" > /dev/null 2>&1
}

teardown_test_db() {
    rm -rf "$SCRIPT_DIR/.test-devteam"
    unset DEVTEAM_DIR
    unset DB_FILE
}

# ============================================================================
# CALL HIERARCHY TESTS (agent_runs.invoked_by_agent / invoked_by_run_id,
# Architecture Audit Phase 3 -- see scripts/events.sh log_agent_started)
# ============================================================================

test_call_hierarchy() {
    log_test "Testing agent_runs call-hierarchy (invoked_by_*) tracking..."

    setup_test_db
    source "$PROJECT_ROOT/scripts/events.sh"

    local session_id
    session_id=$(start_session "test command" "implement")

    # Root dispatch: no parent (as a command/skill would log before its first Task() call)
    local root_run_id
    root_run_id=$(log_agent_started "orchestration:sprint-orchestrator" "opus" "" "" "")
    assert_not_empty "$root_run_id" "log_agent_started should return a new run id"

    # Child dispatch: attributes back to the root run
    local child_run_id
    child_run_id=$(log_agent_started "orchestration:task-loop" "opus" "" "orchestration:sprint-orchestrator" "$root_run_id")
    assert_not_empty "$child_run_id" "log_agent_started should return a new run id for the child"

    local recorded_parent_agent recorded_parent_run_id
    recorded_parent_agent=$(sqlite3 "$DB_FILE" "SELECT invoked_by_agent FROM agent_runs WHERE id=$child_run_id;")
    recorded_parent_run_id=$(sqlite3 "$DB_FILE" "SELECT invoked_by_run_id FROM agent_runs WHERE id=$child_run_id;")
    assert_equals "orchestration:sprint-orchestrator" "$recorded_parent_agent" "Child run should record its dispatcher's agent id"
    assert_equals "$root_run_id" "$recorded_parent_run_id" "Child run should record its dispatcher's run id"

    local root_invoked_by
    root_invoked_by=$(sqlite3 "$DB_FILE" "SELECT COALESCE(invoked_by_agent, 'NULL') FROM agent_runs WHERE id=$root_run_id;")
    assert_equals "NULL" "$root_invoked_by" "Root run (no caller attribution) should have NULL invoked_by_agent"

    # v_agent_call_chain view resolves the parent's agent id in one query
    local chain_parent_agent
    chain_parent_agent=$(sqlite3 "$DB_FILE" "SELECT parent_agent FROM v_agent_call_chain WHERE run_id=$child_run_id;")
    assert_equals "orchestration:sprint-orchestrator" "$chain_parent_agent" "v_agent_call_chain should resolve the parent agent"

    # Backward compatibility: the pre-existing 3-arg call style (no invoked_by_*) must still work
    if log_agent_started "test-agent" "sonnet" "" > /dev/null; then
        log_pass "3-arg log_agent_started call (no invoked_by_*) still succeeds"
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_fail "3-arg log_agent_started call (no invoked_by_*) should still succeed"
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi

    # Phase 6 fix: agent_runs.task_id REFERENCES tasks(id), but nothing in
    # this codebase ever inserted a row into `tasks` (task state lives in the
    # kv-state store instead) -- so every task-scoped agent_runs insert used
    # to silently fail this FK constraint. log_agent_started now auto-creates
    # a minimal placeholder `tasks` row for any non-empty task_id it's given,
    # confirmed empirically against a real sprint/task-loop simulation before
    # this fix (zero agent_runs rows ever carried a task_id). This must now
    # succeed, and the placeholder row must actually exist.
    local previously_failing_run_id
    previously_failing_run_id=$(log_agent_started "test-agent" "sonnet" "a-task-id-with-no-prior-tasks-row")
    assert_not_empty "$previously_failing_run_id" "log_agent_started should succeed for a task_id with no pre-existing tasks row (auto-creates one)"

    local created_task_status
    created_task_status=$(sqlite3 "$DB_FILE" "SELECT status FROM tasks WHERE id='a-task-id-with-no-prior-tasks-row';")
    assert_equals "in_progress" "$created_task_status" "log_agent_started should have auto-created a placeholder tasks row"

    local recorded_task_id
    recorded_task_id=$(sqlite3 "$DB_FILE" "SELECT task_id FROM agent_runs WHERE id=$previously_failing_run_id;")
    assert_equals "a-task-id-with-no-prior-tasks-row" "$recorded_task_id" "agent_runs row should carry the task_id now that the FK reference resolves"

    # The graceful-degradation contract itself (never abort the caller on a
    # genuine logging failure) is still real -- exercise it with an
    # unreachable DB rather than the now-fixed FK case above.
    local original_db_file="$DB_FILE"
    DB_FILE="/nonexistent-devteam-test-path/does-not-exist.db"
    local truly_failed_run_id
    truly_failed_run_id=$(log_agent_started "test-agent" "sonnet" "" 2>/dev/null)
    assert_empty "$truly_failed_run_id" "log_agent_started should return empty (not error) when the DB is unreachable"
    DB_FILE="$original_db_file"

    teardown_test_db
}

# ============================================================================
# COMMON LIBRARY TESTS
# ============================================================================

test_common_library() {
    log_test "Testing common library..."

    source "$PROJECT_ROOT/scripts/lib/common.sh"

    # Test sql_escape
    local escaped
    escaped=$(sql_escape "test'value")
    assert_equals "test''value" "$escaped" "sql_escape should escape single quotes"

    escaped=$(sql_escape "test\\value")
    assert_equals "test\\\\value" "$escaped" "sql_escape should escape backslashes"

    # Test validate_numeric
    assert_command_succeeds "validate_numeric 123" "validate_numeric should accept integers"
    assert_command_fails "validate_numeric abc" "validate_numeric should reject non-numbers"
    assert_command_fails "validate_numeric 12.34" "validate_numeric should reject decimals"

    # Test validate_decimal
    assert_command_succeeds "validate_decimal 123" "validate_decimal should accept integers"
    assert_command_succeeds "validate_decimal 12.34" "validate_decimal should accept decimals"
    assert_command_fails "validate_decimal abc" "validate_decimal should reject non-numbers"

    # Test generate_id
    local id
    id=$(generate_id "test")
    assert_matches "$id" "^test-[0-9]{8}-[0-9]{6}-[a-f0-9]+$" "generate_id should match expected format"
}

# ============================================================================
# STATE MANAGEMENT TESTS
# ============================================================================

test_state_management() {
    log_test "Testing state management..."

    setup_test_db
    source "$PROJECT_ROOT/scripts/state.sh"

    # Test session creation
    local session_id
    session_id=$(start_session "test command" "feature")
    assert_not_empty "$session_id" "start_session should return session ID"
    assert_matches "$session_id" "^session-" "Session ID should start with 'session-'"

    # Test get_current_session_id
    local current
    current=$(get_current_session_id)
    assert_equals "$session_id" "$current" "get_current_session_id should return current session"

    # Test is_session_running
    if is_session_running; then
        log_pass "is_session_running returns true when session active"
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_fail "is_session_running should return true"
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi

    # Test set_phase and get_current_phase
    set_phase "executing"
    local phase
    phase=$(get_current_phase)
    assert_equals "executing" "$phase" "Phase should be set correctly"

    # Test iteration increment
    increment_iteration
    local iteration
    iteration=$(get_current_iteration)
    assert_equals "1" "$iteration" "Iteration should be incremented to 1"

    # Test failures tracking
    increment_failures
    local failures
    failures=$(get_consecutive_failures)
    assert_equals "1" "$failures" "Failures should be incremented to 1"

    reset_failures
    failures=$(get_consecutive_failures)
    assert_equals "0" "$failures" "Failures should be reset to 0"

    # Test end session
    end_session "completed" "Test finished"
    if ! is_session_running; then
        log_pass "is_session_running returns false after session ended"
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_fail "Session should not be running after end_session"
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi

    teardown_test_db
}

# ============================================================================
# VALIDATION TESTS
# ============================================================================

test_validation() {
    log_test "Testing input validation..."

    source "$PROJECT_ROOT/scripts/lib/common.sh"

    # Test session ID validation
    assert_command_succeeds "validate_session_id 'session-20260129-120000-abcd1234'" \
        "Valid session ID should pass validation"

    assert_command_fails "validate_session_id 'invalid-session'" \
        "Invalid session ID should fail validation"

    assert_command_fails "validate_session_id \"'; DROP TABLE sessions; --\"" \
        "SQL injection attempt should fail validation"

    # Test field name validation
    assert_command_succeeds "validate_field_name 'status'" \
        "Valid field name should pass validation"

    assert_command_fails "validate_field_name 'invalid_field'" \
        "Invalid field name should fail validation"

    assert_command_fails "validate_field_name \"status; DROP TABLE\"" \
        "SQL injection in field name should fail validation"

    # Test phase validation
    assert_command_succeeds "validate_phase 'executing'" \
        "Valid phase should pass validation"

    assert_command_fails "validate_phase 'invalid_phase'" \
        "Invalid phase should fail validation"

    # Test model validation
    assert_command_succeeds "validate_model 'sonnet'" \
        "Valid model should pass validation"

    assert_command_fails "validate_model 'gpt-4'" \
        "Invalid model should fail validation"
}

# ============================================================================
# SQL INJECTION PREVENTION TESTS
# ============================================================================

test_sql_injection_prevention() {
    log_test "Testing SQL injection prevention..."

    setup_test_db
    source "$PROJECT_ROOT/scripts/state.sh"

    # Start a session for testing
    local session_id
    session_id=$(start_session "test" "test")

    # Try SQL injection via command
    local malicious_command="'; DROP TABLE sessions; --"
    end_session "completed" "test"

    session_id=$(start_session "$malicious_command" "test")

    # Verify database still works
    local count
    count=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM sessions;")
    assert_not_empty "$count" "Database should still be intact after injection attempt"

    # Try injection via set_state (should be blocked by validation)
    # This should fail validation, not execute
    if ! set_state "status; DROP TABLE sessions" "value" 2>/dev/null; then
        log_pass "SQL injection via field name blocked"
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_fail "SQL injection via field name should be blocked"
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi

    # Verify tables still exist
    local tables
    tables=$(sqlite3 "$DB_FILE" "SELECT name FROM sqlite_master WHERE type='table' AND name='sessions';")
    assert_equals "sessions" "$tables" "Sessions table should still exist"

    teardown_test_db
}

# ============================================================================
# EVENT LOGGING TESTS
# ============================================================================

test_event_logging() {
    log_test "Testing event logging..."

    setup_test_db
    source "$PROJECT_ROOT/scripts/events.sh"

    # Start a session
    local session_id
    session_id=$(start_session "test command" "feature")

    # Log various events
    log_phase_changed "executing" "initializing"
    log_agent_started "test-agent" "sonnet" "task-1"
    log_agent_completed "test-agent" "sonnet" "[]" 100 50 5
    log_gate_passed "lint" "{}"

    # Query events
    local event_count
    event_count=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM events WHERE session_id='$session_id';")

    if [ "$event_count" -ge 4 ]; then
        log_pass "Events were logged correctly ($event_count events)"
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_fail "Expected at least 4 events, got $event_count"
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi

    teardown_test_db
}

# ============================================================================
# FILE STRUCTURE TESTS
# ============================================================================

test_file_structure() {
    log_test "Testing project file structure..."

    assert_file_exists "$PROJECT_ROOT/agent-registry.json" "agent-registry.json should exist"
    assert_file_exists "$PROJECT_ROOT/scripts/state.sh" "scripts/state.sh should exist"
    assert_file_exists "$PROJECT_ROOT/scripts/events.sh" "scripts/events.sh should exist"
    assert_file_exists "$PROJECT_ROOT/scripts/db-init.sh" "scripts/db-init.sh should exist"
    assert_file_exists "$PROJECT_ROOT/scripts/lib/common.sh" "scripts/lib/common.sh should exist"
    assert_file_exists "$PROJECT_ROOT/scripts/schema.sql" "scripts/schema.sql should exist"

    # Check agent directories
    assert_file_exists "$PROJECT_ROOT/agents/orchestration/task-loop.md" "Task Loop agent should exist"

    # Check commands directory
    local cmd_count
    cmd_count=$(find "$PROJECT_ROOT/commands" -name "*.md" | wc -l)
    if [ "$cmd_count" -ge 10 ]; then
        log_pass "Commands directory has sufficient files ($cmd_count)"
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_fail "Expected at least 10 command files, got $cmd_count"
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# ============================================================================
# AGENT WIRING GOVERNANCE TESTS
# (Architecture Audit Phase 7 -- scripts/validate-agent-wiring.sh)
# ============================================================================

test_agent_wiring() {
    log_test "Testing agent wiring governance check..."

    assert_file_exists "$PROJECT_ROOT/scripts/validate-agent-wiring.sh" \
        "validate-agent-wiring.sh should exist"

    assert_command_succeeds "bash '$PROJECT_ROOT/scripts/validate-agent-wiring.sh'" \
        "validate-agent-wiring.sh should pass against the current repo (no orphaned orchestration/planning/ux agents)"

    # Simulate a newly-orphaned agent by renaming its one live subagent_type
    # reference, and confirm the check actually catches it (not just always
    # exits 0) -- this is the Phase 8 acceptance check for Phase 7, run here
    # as an automated regression test instead of a one-off manual check.
    local target_file="$PROJECT_ROOT/agents/orchestration/task-loop.md"
    local backup
    backup=$(mktemp)
    cp "$target_file" "$backup"

    sed -i.tmp 's/subagent_type: "orchestration:workflow-compliance"/subagent_type: "orchestration:workflow-compliance-RENAMED"/' "$target_file"
    rm -f "${target_file}.tmp"

    assert_command_fails "bash '$PROJECT_ROOT/scripts/validate-agent-wiring.sh'" \
        "validate-agent-wiring.sh should fail when an agent's only reference is renamed away (simulated orphan)"

    cp "$backup" "$target_file"
    rm -f "$backup"

    assert_command_succeeds "bash '$PROJECT_ROOT/scripts/validate-agent-wiring.sh'" \
        "validate-agent-wiring.sh should pass again once the simulated orphan is reverted"
}

# ============================================================================
# CONFIGURATION TESTS
# ============================================================================

test_configuration() {
    log_test "Testing configuration files..."

    # Check plugin.json is valid JSON
    if command -v jq &> /dev/null; then
        if jq empty "$PROJECT_ROOT/agent-registry.json" 2>/dev/null; then
            log_pass "agent-registry.json is valid JSON"
            TESTS_RUN=$((TESTS_RUN + 1))
            TESTS_PASSED=$((TESTS_PASSED + 1))
        else
            log_fail "agent-registry.json is not valid JSON"
            TESTS_RUN=$((TESTS_RUN + 1))
            TESTS_FAILED=$((TESTS_FAILED + 1))
        fi

        # Check required fields in agent-registry.json
        local name
        name=$(jq -r '.name' "$PROJECT_ROOT/agent-registry.json")
        assert_not_empty "$name" "agent-registry.json should have a name field"

        local agent_count
        agent_count=$(jq '.agents | length' "$PROJECT_ROOT/agent-registry.json")
        if [ "$agent_count" -ge 80 ]; then
            log_pass "agent-registry.json has sufficient agents ($agent_count)"
            TESTS_RUN=$((TESTS_RUN + 1))
            TESTS_PASSED=$((TESTS_PASSED + 1))
        else
            log_fail "Expected at least 80 agents, got $agent_count"
            TESTS_RUN=$((TESTS_RUN + 1))
            TESTS_FAILED=$((TESTS_FAILED + 1))
        fi
    else
        log_skip "jq not installed, skipping JSON validation tests"
    fi
}

# ============================================================================
# MAIN TEST RUNNER
# ============================================================================

print_summary() {
    echo ""
    echo "============================================"
    echo "               TEST SUMMARY                 "
    echo "============================================"
    echo -e "Tests Run:    ${BLUE}$TESTS_RUN${NC}"
    echo -e "Passed:       ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed:       ${RED}$TESTS_FAILED${NC}"
    echo -e "Skipped:      ${YELLOW}$TESTS_SKIPPED${NC}"
    echo "============================================"

    if [ ${#FAILED_TESTS[@]} -gt 0 ]; then
        echo ""
        echo -e "${RED}Failed Tests:${NC}"
        for test in "${FAILED_TESTS[@]}"; do
            echo "  - $test"
        done
    fi

    echo ""
    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}All tests passed!${NC}"
        return 0
    else
        echo -e "${RED}Some tests failed.${NC}"
        return 1
    fi
}

run_all_tests() {
    echo "============================================"
    echo "         DevTeam Test Suite                "
    echo "============================================"
    echo ""

    test_call_hierarchy
    echo ""

    test_common_library
    echo ""

    test_validation
    echo ""

    test_state_management
    echo ""

    test_sql_injection_prevention
    echo ""

    test_event_logging
    echo ""

    test_file_structure
    echo ""

    test_agent_wiring
    echo ""

    test_configuration

    print_summary
}

# Run specific test file or all tests
if [ $# -gt 0 ]; then
    test_file="$1"
    if [ -f "$test_file" ]; then
        source "$test_file"
    else
        echo "Test file not found: $test_file"
        exit 1
    fi
else
    run_all_tests
fi
