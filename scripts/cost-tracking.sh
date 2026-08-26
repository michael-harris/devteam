#!/bin/bash
# cost-tracking.sh - Report API costs and token usage per session/task
# Based on Anthropic's "Effective Harnesses for Long-Running Agents"
#
# PHASE 0 (2026-08-26): This script is now a READ-ONLY reporting layer.
# Single source of truth for cost/token data is agent_runs.cost_cents /
# sessions.total_cost_cents, written in real time by scripts/events.sh
# (log_agent_started / log_agent_completed), which is the only layer that
# actually sees Claude Code's real token counts as each call completes.
# This script no longer writes its own competing record (the old
# `token_usage` table + `.devteam/cost-log.json` pair) -- see
# docs/reviews/ARCHITECTURE_AUDIT_2026-08-26.md §7 for why the two writers
# disagreed and record.sh `record_usage()` used to duplicate the ledger.
#
# `record` is kept as a deprecated, non-writing preview command so existing
# callers (e.g. agents/orchestration/task-loop.md's documented `record`
# invocation) do not fail; it no longer persists anything.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
DEVTEAM_DIR="${PROJECT_ROOT}/.devteam"
DB_FILE="${DEVTEAM_DIR}/devteam.db"

# Register temp file cleanup
setup_temp_cleanup

# Pricing (updated for Claude 4.5/4.6 models -- February 2026)
declare -A MODEL_PRICING
# Current Claude models
MODEL_PRICING["claude-opus-4-6"]="15.00:75.00"             # Opus 4.6 (input:output per 1M tokens)
MODEL_PRICING["claude-sonnet-4-5-20250929"]="3.00:15.00"    # Sonnet 4.5
MODEL_PRICING["claude-haiku-4-5-20251001"]="0.80:4.00"      # Haiku 4.5
# Aliases for short model names used by plugin.json
MODEL_PRICING["opus"]="15.00:75.00"
MODEL_PRICING["sonnet"]="3.00:15.00"
MODEL_PRICING["haiku"]="0.80:4.00"
# Legacy Claude models (for historical data)
MODEL_PRICING["claude-opus-4-5-20251101"]="15.00:75.00"
MODEL_PRICING["claude-sonnet-4-20250514"]="3.00:15.00"
MODEL_PRICING["claude-haiku-4-20250414"]="0.80:4.00"
MODEL_PRICING["claude-3-5-sonnet-20241022"]="3.00:15.00"
MODEL_PRICING["claude-3-5-haiku-20241022"]="0.80:4.00"

# Check for bc dependency -- required for cost calculations
_BC_AVAILABLE=true
if ! command -v bc &>/dev/null; then
    log_error "bc is not installed; cost tracking requires bc for calculations" "cost"
    log_error "  Install: apt-get install bc (Debian/Ubuntu), brew install bc (macOS)" "cost"
    _BC_AVAILABLE=false
fi

# Ensure directories
ensure_dirs() {
    mkdir -p "$DEVTEAM_DIR"
}

# Calculate cost for tokens
# NOTE: Returns cost in USD (dollars), NOT cents.
# - agent_runs.cost_cents / sessions.total_cost_cents (state.sh/events.sh) are
#   the single source of truth and store CENTS.
# - Every function in this file that reports a dollar figure derives it from
#   those cents columns with ROUND(cost_cents / 100.0, N) -- never from a
#   second, independently-accumulated total.
calculate_cost() {
    local model="$1"
    local input_tokens="$2"
    local output_tokens="$3"

    # Validate inputs are numeric
    if ! [[ "$input_tokens" =~ ^[0-9]+$ ]] || ! [[ "$output_tokens" =~ ^[0-9]+$ ]]; then
        log_error "Non-numeric token values: input=$input_tokens output=$output_tokens" "cost"
        echo "0"
        return 1
    fi

    if [ "$_BC_AVAILABLE" != "true" ]; then
        log_error "bc not available for cost calculation" "cost"
        echo "0"
        return 1
    fi

    local pricing="${MODEL_PRICING[$model]:-3.00:15.00}"
    local input_price="${pricing%%:*}"
    local output_price="${pricing##*:}"

    # Cost = (tokens / 1,000,000) * price
    local input_cost
    input_cost=$(echo "scale=6; $input_tokens / 1000000 * $input_price" | bc | sed 's/^\./0./')
    local output_cost
    output_cost=$(echo "scale=6; $output_tokens / 1000000 * $output_price" | bc | sed 's/^\./0./')
    local total_cost
    total_cost=$(echo "scale=6; $input_cost + $output_cost" | bc | sed 's/^\./0./')

    echo "$total_cost"
}

# Deprecated: this used to write to token_usage + cost-log.json (a second,
# independently-accumulated ledger that could disagree with agent_runs).
# It is kept only so existing callers don't fail; it now just previews the
# cost of the given token counts and points at where the real numbers live.
# Recording real usage happens exclusively through scripts/events.sh
# (log_agent_started/log_agent_completed), called from the hook layer, which
# is the only place that actually observes Claude Code's real token counts.
record_usage() {
    local session_id="${1:-$(date +%Y%m%d)}"
    local task_id="${2:-none}"
    local model="${3:-claude-3-5-sonnet}"
    local input_tokens="${4:-0}"
    local output_tokens="${5:-0}"
    local operation="${6:-unknown}"

    ensure_dirs

    local cost
    cost=$(calculate_cost "$model" "$input_tokens" "$output_tokens")

    log_warn "cost-tracking.sh 'record' no longer persists data (Phase 0: single cost source)." "cost"
    log_warn "Use scripts/events.sh log_agent_started/log_agent_completed to record real usage against agent_runs." "cost"
    log_info "Preview only (not saved): ${input_tokens} in + ${output_tokens} out = \$${cost} (${model}, session=${session_id}, task=${task_id}, op=${operation})"
    log_info "For real recorded costs: $0 session <session_id> | $0 total"
}

# Get session summary
# Args: session_id (required -- costs are now keyed by the real sessions.id,
# not by an arbitrary date string)
session_summary() {
    local session_id="${1:-}"

    ensure_dirs

    if [[ -z "$session_id" ]]; then
        echo "Usage: $0 session <session_id>"
        log_error "session_id is required" "cost"
        return 1
    fi

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo " Session Cost Summary: ${session_id}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    if [[ ! -f "$DB_FILE" ]]; then
        echo "No database found."
        echo ""
        return 0
    fi

    local sql_sid
    sql_sid=$(sql_escape "$session_id")

    local summary_row
    summary_row=$(sql_exec "SELECT status, total_tokens, total_cost_dollars, agent_runs FROM v_session_summary WHERE id='${sql_sid}';" 2>/dev/null || echo "")

    if [[ -z "$summary_row" ]]; then
        echo "  No session found with id: ${session_id}"
        echo ""
        return 0
    fi

    IFS='|' read -r s_status s_tokens s_cost s_runs <<< "$summary_row"

    printf "  %-25s %s\n" "Session ID:" "$session_id"
    printf "  %-25s %s\n" "Status:" "${s_status:-unknown}"
    printf "  %-25s %s\n" "Agent Runs:" "${s_runs:-0}"
    printf "  %-25s %s\n" "Total Tokens:" "$(format_number "${s_tokens:-0}")"
    printf "  %-25s \$%.4f\n" "Total Cost:" "${s_cost:-0}"

    echo ""
    echo "By Model:"
    echo "─────────────────────────────────────────────────────────────"
    sql_exec_table "SELECT model, runs, tokens_input, tokens_output, printf('%.4f', cost_cents / 100.0) as cost_usd FROM v_model_usage WHERE session_id='${sql_sid}' ORDER BY cost_cents DESC;"

    echo ""
    echo "By Agent:"
    echo "─────────────────────────────────────────────────────────────"
    sql_exec_table "SELECT agent, COUNT(*) as runs, SUM(tokens_input) as input_tokens, SUM(tokens_output) as output_tokens, printf('%.4f', COALESCE(SUM(cost_cents), 0) / 100.0) as cost_usd FROM agent_runs WHERE session_id='${sql_sid}' GROUP BY agent ORDER BY SUM(cost_cents) DESC LIMIT 10;"
    echo ""
}

# Get daily summary (grouped by session, for agent activity on a given day)
daily_summary() {
    local date="${1:-$(date +%Y-%m-%d)}"

    ensure_dirs

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo " Daily Cost Summary: ${date}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    if [[ ! -f "$DB_FILE" ]]; then
        echo "No database found."
        echo ""
        return 0
    fi

    local sql_date
    sql_date=$(sql_escape "$date")

    sql_exec_table "SELECT session_id, COUNT(*) as agent_runs, SUM(tokens_input) as input_tokens, SUM(tokens_output) as output_tokens, printf('\$%.4f', COALESCE(SUM(cost_cents), 0) / 100.0) as total_cost FROM agent_runs WHERE date(started_at) = '${sql_date}' GROUP BY session_id ORDER BY SUM(cost_cents) DESC;"

    echo ""
    echo "─────────────────────────────────────────────────────────────"
    local day_total
    day_total=$(sql_exec "SELECT printf('\$%.4f', COALESCE(SUM(cost_cents), 0) / 100.0) FROM agent_runs WHERE date(started_at)='${sql_date}';")
    echo "Daily Total: ${day_total}"
    echo ""
}

# Get overall totals
total_summary() {
    ensure_dirs

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo " All-Time Cost Summary"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    if [[ ! -f "$DB_FILE" ]]; then
        echo "No database found."
        echo ""
        return 0
    fi

    local total_input
    total_input=$(sql_exec "SELECT COALESCE(SUM(tokens_input), 0) FROM agent_runs;" 2>/dev/null || echo 0)
    local total_output
    total_output=$(sql_exec "SELECT COALESCE(SUM(tokens_output), 0) FROM agent_runs;" 2>/dev/null || echo 0)
    local total_cost
    total_cost=$(sql_exec "SELECT ROUND(COALESCE(SUM(cost_cents), 0) / 100.0, 4) FROM agent_runs;" 2>/dev/null || echo 0)
    local request_count
    request_count=$(sql_exec "SELECT COUNT(*) FROM agent_runs;" 2>/dev/null || echo 0)
    local session_count
    session_count=$(sql_exec "SELECT COUNT(DISTINCT session_id) FROM agent_runs;" 2>/dev/null || echo 0)

    printf "  %-25s %s\n" "Total Sessions:" "$session_count"
    printf "  %-25s %s\n" "Total Agent Runs:" "$(format_number "$request_count")"
    printf "  %-25s %s\n" "Total Input Tokens:" "$(format_number "$total_input")"
    printf "  %-25s %s\n" "Total Output Tokens:" "$(format_number "$total_output")"
    printf "  %-25s %s\n" "Total Tokens:" "$(format_number "$((total_input + total_output))")"
    printf "  %-25s \$%.4f\n" "Total Cost:" "$total_cost"

    echo ""
    echo "By Day (Last 7 Days):"
    echo "─────────────────────────────────────────────────────────────"
    sql_exec_table "SELECT date(started_at) as date, COUNT(*) as agent_runs, SUM(tokens_input + tokens_output) as tokens, printf('\$%.4f', COALESCE(SUM(cost_cents), 0) / 100.0) as cost FROM agent_runs WHERE started_at >= date('now', '-7 days') GROUP BY date(started_at) ORDER BY date(started_at) DESC;"

    echo ""
    echo "By Model (All Time):"
    echo "─────────────────────────────────────────────────────────────"
    sql_exec_table "SELECT model, COUNT(*) as runs, SUM(tokens_input + tokens_output) as tokens, printf('\$%.4f', COALESCE(SUM(cost_cents), 0) / 100.0) as cost FROM agent_runs GROUP BY model ORDER BY SUM(cost_cents) DESC;"
    echo ""
}

# Set budget alert
set_budget() {
    local budget_type="$1"  # session, daily, monthly
    local amount="$2"

    # Validate inputs
    budget_type=$(sanitize_input "$budget_type" 32)
    if ! [[ "$amount" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        log_error "Invalid budget amount: $amount" "cost"
        return 1
    fi

    ensure_dirs

    local budget_file="${DEVTEAM_DIR}/budgets.json"

    if [[ ! -f "$budget_file" ]]; then
        echo "{}" > "$budget_file"
    fi

    # Update budget
    local tmp_file
    tmp_file=$(safe_mktemp)
    if command -v jq &> /dev/null; then
        jq ".${budget_type} = ${amount}" "$budget_file" > "$tmp_file" && mv "$tmp_file" "$budget_file"
    else
        echo "{\"${budget_type}\": ${amount}}" > "$budget_file"
    fi

    log_info "Set ${budget_type} budget to \$${amount}"
}

# Check budget
# Args: [session_id]
check_budget() {
    local session_id="${1:-}"

    ensure_dirs

    local budget_file="${DEVTEAM_DIR}/budgets.json"

    if [[ ! -f "$budget_file" ]]; then
        log_info "No budgets configured"
        return 0
    fi

    if [[ ! -f "$DB_FILE" ]]; then
        log_info "No database found"
        return 0
    fi

    local session_cost="0"
    if [[ -n "$session_id" ]]; then
        local sql_sid
        sql_sid=$(sql_escape "$session_id")
        session_cost=$(sql_exec "SELECT COALESCE(ROUND(total_cost_cents / 100.0, 4), 0) FROM sessions WHERE id='${sql_sid}';" 2>/dev/null || echo 0)
        session_cost="${session_cost:-0}"
    fi
    local daily_cost
    daily_cost=$(sql_exec "SELECT COALESCE(ROUND(SUM(cost_cents) / 100.0, 4), 0) FROM agent_runs WHERE date(started_at) = date('now');" 2>/dev/null || echo 0)
    daily_cost="${daily_cost:-0}"

    if command -v jq &> /dev/null; then
        local session_budget
        session_budget=$(jq -r ".session // 0" "$budget_file")
        local daily_budget
        daily_budget=$(jq -r ".daily // 0" "$budget_file")

        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo " Budget Status"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""

        if [[ -n "$session_id" ]] && [[ "$session_budget" != "0" ]]; then
            local session_pct
            session_pct=$(echo "scale=1; $session_cost / $session_budget * 100" | bc)
            printf "  Session: \$%.4f / \$%.2f (%s%%)\n" "$session_cost" "$session_budget" "$session_pct"
            if (( $(echo "$session_cost > $session_budget" | bc -l) )); then
                log_warn "⚠️  SESSION BUDGET EXCEEDED!"
            elif (( $(echo "$session_cost > $session_budget * 0.8" | bc -l) )); then
                log_warn "Session at 80%+ of budget"
            fi
        fi

        if [[ "$daily_budget" != "0" ]]; then
            local daily_pct
            daily_pct=$(echo "scale=1; $daily_cost / $daily_budget * 100" | bc)
            printf "  Daily:   \$%.4f / \$%.2f (%s%%)\n" "$daily_cost" "$daily_budget" "$daily_pct"
            if (( $(echo "$daily_cost > $daily_budget" | bc -l) )); then
                log_warn "⚠️  DAILY BUDGET EXCEEDED!"
            elif (( $(echo "$daily_cost > $daily_budget * 0.8" | bc -l) )); then
                log_warn "Daily at 80%+ of budget"
            fi
        fi
        echo ""
    fi
}

# Export to CSV
export_csv() {
    local output="${1:-${DEVTEAM_DIR}/cost-export.csv}"

    ensure_dirs

    if [[ -f "$DB_FILE" ]]; then
        sqlite3 -csv -header "$DB_FILE" "PRAGMA foreign_keys = ON; SELECT ar.id, ar.session_id, ar.task_id, ar.agent, ar.model, ar.tokens_input, ar.tokens_output, ROUND(COALESCE(ar.cost_cents, 0) / 100.0, 4) as cost_usd, ar.status, ar.started_at, ar.ended_at FROM agent_runs ar ORDER BY ar.started_at DESC;" > "$output"
        log_info "Exported to ${output}"
    else
        log_error "No database found"
    fi
}

# Main
case "${1:-help}" in
    record)
        record_usage "${2:-}" "${3:-}" "${4:-sonnet}" "${5:-0}" "${6:-0}" "${7:-unknown}"
        ;;
    session)
        session_summary "${2:-}"
        ;;
    daily)
        daily_summary "${2:-$(date +%Y-%m-%d)}"
        ;;
    total|all)
        total_summary
        ;;
    budget)
        case "${2:-check}" in
            set)
                set_budget "${3:-daily}" "${4:-10}"
                ;;
            check)
                check_budget "${3:-}"
                ;;
            *)
                echo "Usage: $0 budget [set|check] [type] [amount]"
                ;;
        esac
        ;;
    export)
        export_csv "${2:-}"
        ;;
    help|*)
        echo "Usage: $0 <command> [args]"
        echo ""
        echo "Commands (all reporting is read-only over agent_runs/sessions):"
        echo "  record <session> <task> <model> <in> <out> [op]"
        echo "                             DEPRECATED: previews cost, does not persist."
        echo "                             Real usage is recorded by scripts/events.sh."
        echo "  session <session_id>       Show session summary"
        echo "  daily [date]               Show daily summary"
        echo "  total                      Show all-time totals"
        echo "  budget set <type> <amt>    Set budget (session/daily)"
        echo "  budget check [session_id]  Check budget status"
        echo "  export [file]              Export agent_runs to CSV"
        echo ""
        echo "Examples:"
        echo "  $0 session session-20260826-101500-abc123"
        echo "  $0 daily 2026-08-26"
        echo "  $0 budget set daily 25.00"
        echo "  $0 budget check session-20260826-101500-abc123"
        ;;
esac
