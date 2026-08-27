# DevTeam Status Command

**Command:** `/devteam:status [options]`

Display system health, current progress, costs, and execution history.

## Usage

```bash
# Current session status
/devteam:status

# Show execution history
/devteam:status --history
/devteam:status --history 20    # Last 20 sessions

# Cost breakdown
/devteam:status --costs
/devteam:status --costs --detailed

# Agent performance metrics
/devteam:status --agents

# Check specific session
/devteam:status --session session-20260129-123456-abc123

# Show all (comprehensive report)
/devteam:status --all
```

## Options

| Option | Description |
|--------|-------------|
| `--history [n]` | Show last n sessions (default: 10) |
| `--costs` | Show cost breakdown |
| `--detailed` | Show detailed breakdown (with --costs) |
| `--agents` | Show agent performance metrics |
| `--session <id>` | Show specific session details |
| `--all` | Show comprehensive report |
| `--json` | Output as JSON |

## Your Process

### Check for Running Session

```bash
source scripts/state.sh

if is_session_running; then
    show_current_session_status
else
    show_system_overview
fi
```

### Output: Current Session

```
═══════════════════════════════════════════════════════════════════
 DevTeam Status
═══════════════════════════════════════════════════════════════════

Session: session-20260129-103045-a1b2c3
Started: 2026-01-29 10:30:45 (23 min ago)
Command: /devteam:implement --sprint 1

┌─────────────────────────────────────────────────────────────────┐
│ Progress                                                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Sprint: SPRINT-001 (Add user authentication)                   │
│  Tasks:  ████████████░░░░░░░░ 60% (3/5 complete)                │
│                                                                  │
│  Current Task: TASK-004 - Implement JWT middleware              │
│    Agent: backend:api-developer-typescript                        │
│    Model: sonnet (escalated from haiku)                         │
│    Iteration: 3 of 10                                           │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ Model Usage                                                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Model    │ Runs │ Success │ Tokens  │ Cost                     │
│  ─────────┼──────┼─────────┼─────────┼──────                    │
│  haiku    │   12 │   83%   │  45,231 │ $0.06                    │
│  sonnet   │    4 │   75%   │  28,102 │ $0.42                    │
│  opus     │    1 │  100%   │  15,883 │ $2.38                    │
│  ─────────┼──────┼─────────┼─────────┼──────                    │
│  Total    │   17 │   82%   │  89,216 │ $2.86                    │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ Quality Gates (Last Iteration)                                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ✅ Lint          passed                                        │
│  ✅ Type Check    passed                                        │
│  ❌ Tests         2 failing (AuthMiddleware.test.ts)            │
│  ⏳ Security      pending                                       │
│  ⏳ Coverage      pending                                       │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ Escalations                                                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  10:35  haiku → sonnet   2 test failures (api_developer)        │
│  10:48  sonnet → opus    Architecture issue detected            │
│                                                                  │
│  Total: 2 escalations                                           │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ Circuit Breaker                                                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  State: CLOSED (healthy)                                        │
│  Consecutive Failures: 1 of 5                                   │
│  Bug Council: Not activated                                     │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Output: No Active Session

```
═══════════════════════════════════════════════════════════════════
 DevTeam Status
═══════════════════════════════════════════════════════════════════

Status: Idle (no active session)

┌─────────────────────────────────────────────────────────────────┐
│ Recent Sessions                                                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Session                      │ Command          │ Status │ Cost │
│  ─────────────────────────────┼──────────────────┼────────┼──────│
│  session-20260129-093012-xxx  │ /devteam:bug     │ ✅     │ $1.24│
│  session-20260128-161532-xxx  │ /devteam:impl... │ ✅     │ $4.82│
│  session-20260128-142201-xxx  │ /devteam:impl... │ ❌     │ $2.11│
│  session-20260128-103045-xxx  │ /devteam:plan    │ ✅     │ $0.38│
│                                                                  │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ Active Plans                                                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  #  │ Plan                    │ Status      │ Progress           │
│  ───┼─────────────────────────┼─────────────┼────────            │
│  1  │ user-authentication     │ in_progress │ ████████░░ 80%     │
│  2  │ dark-mode-feature       │ ready       │ ░░░░░░░░░░ 0%      │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ Lifetime Statistics                                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Total Sessions: 47                                             │
│  Success Rate: 89%                                              │
│  Total Cost: $127.43                                            │
│  Avg Cost/Session: $2.71                                        │
│                                                                  │
│  Most Used Agents:                                              │
│    1. backend:api-developer-typescript (142 runs, 91% success)  │
│    2. quality:test-writer (98 runs, 87% success)                │
│    3. frontend:developer (76 runs, 88% success)        │
│                                                                  │
│  Bug Council Activations: 3                                     │
│  Avg Escalations/Session: 1.2                                   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘

Tip: Use /devteam:implement to start a new session
```

### Output: Cost Details (--costs --detailed)

```
═══════════════════════════════════════════════════════════════════
 DevTeam Cost Report
═══════════════════════════════════════════════════════════════════

Period: Last 30 days

┌─────────────────────────────────────────────────────────────────┐
│ Cost by Model                                                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  haiku   ████████████████████████░░░░░░░░░░░░░░░░  $12.43 (10%) │
│  sonnet  ██████████████████████████████████░░░░░░  $68.21 (54%) │
│  opus    ████████████████████████░░░░░░░░░░░░░░░░  $46.79 (36%) │
│                                                                  │
│  Total: $127.43                                                 │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ Cost by Command Type                                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  implement  ██████████████████████████████████████  $89.21 (70%)│
│  bug        ████████████████░░░░░░░░░░░░░░░░░░░░░░  $24.33 (19%)│
│  plan       ████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  $10.12 (8%) │
│  issue      ███░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   $3.77 (3%) │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ Cost by Agent (Top 10)                                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Agent                        │ Runs │ Cost   │ Avg/Run         │
│  ─────────────────────────────┼──────┼────────┼────────         │
│  backend:api-developer-typescript │ 142 │ $34.21 │ $0.24          │
│  quality:test-writer              │  98 │ $18.43 │ $0.19          │
│  quality:security-auditor         │  23 │ $15.82 │ $0.69          │
│  frontend:developer      │  76 │ $12.11 │ $0.16          │
│  bug_council (combined)           │   3 │ $11.24 │ $3.75          │
│  ...                                                            │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ Eco Mode Savings                                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Sessions with --eco: 12                                        │
│  Estimated savings: $18.32 (23% reduction)                      │
│                                                                  │
│  Recommendation: Use --eco for routine tasks to save costs      │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Output: Agent Performance (--agents)

```
═══════════════════════════════════════════════════════════════════
 Agent Performance Report
═══════════════════════════════════════════════════════════════════

┌─────────────────────────────────────────────────────────────────┐
│ Agent Success Rates                                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Agent                        │ Runs │ Success │ Avg Time       │
│  ─────────────────────────────┼──────┼─────────┼─────────       │
│  backend:api-developer-typescript │ 142 │   91%   │ 2.3 min       │
│  backend:api-developer-python    │  67 │   89%   │ 2.1 min       │
│  frontend:developer     │  76 │   88%   │ 3.1 min       │
│  quality:test-writer             │  98 │   87%   │ 1.8 min       │
│  quality:security-auditor        │  23 │   96%   │ 4.2 min       │
│  diagnosis:root-cause-analyst    │  15 │   80%   │ 3.5 min       │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ Common Failure Reasons                                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Reason                       │ Count │ Usually Resolved By     │
│  ─────────────────────────────┼───────┼─────────────────────    │
│  Test failures                │    34 │ Model escalation        │
│  Type errors                  │    21 │ Same model retry        │
│  Lint errors                  │    12 │ Same model retry        │
│  Integration issues           │     8 │ Bug Council             │
│  Scope violation              │     5 │ Scope clarification     │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ Escalation Patterns                                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  haiku → sonnet:  67 times (avg after 1.8 failures)             │
│  sonnet → opus:   23 times (avg after 2.1 failures)             │
│  opus → council:   3 times (avg after 2.7 failures)             │
│                                                                  │
│  Most escalated tasks:                                          │
│    - Security fixes (78% escalation rate)                       │
│    - Architecture changes (65% escalation rate)                 │
│    - Complex integrations (52% escalation rate)                 │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Implementation

### Query Current Session

```sql
-- Get current session with summary
SELECT * FROM v_session_summary WHERE status = 'running';

-- Get model usage for current session
SELECT * FROM v_model_usage WHERE session_id = (
    SELECT id FROM sessions WHERE status = 'running'
);

-- Get recent events
SELECT timestamp, event_type, message
FROM events
WHERE session_id = (SELECT id FROM sessions WHERE status = 'running')
ORDER BY timestamp DESC
LIMIT 20;

-- Get gate results for current iteration
SELECT gate, passed, error_count
FROM gate_results
WHERE session_id = (SELECT id FROM sessions WHERE status = 'running')
AND iteration = (SELECT current_iteration FROM sessions WHERE status = 'running');
```

### Query History

```sql
-- Recent sessions
SELECT
    id,
    command,
    status,
    started_at,
    ended_at,
    ROUND(total_cost_cents / 100.0, 2) as cost_dollars
FROM sessions
ORDER BY started_at DESC
LIMIT 10;

-- Lifetime statistics
SELECT
    COUNT(*) as total_sessions,
    ROUND(AVG(CASE WHEN status = 'completed' THEN 1.0 ELSE 0.0 END) * 100, 1) as success_rate,
    SUM(total_cost_cents) / 100.0 as total_cost
FROM sessions;
```

### Query Agent Performance

```sql
-- Agent performance
SELECT * FROM v_agent_performance ORDER BY total_runs DESC;

-- Gate pass rates
SELECT * FROM v_gate_pass_rates;
```

## See Also

- `/devteam:list` - List plans and tasks
- `/devteam:reset` - Reset stuck state
- `/devteam:implement` - Start implementation
- `devteam-reports/` - A browsable, per-task/per-sprint alternative to these live queries: `devteam-reports/INDEX.md` is a running dashboard, with `devteam-reports/tasks/TASK-XXX.md` and `devteam-reports/sprints/SPRINT-XXX.md` per-item detail, rendered automatically by `orchestration:execution-ledger` as tasks and sprints complete. Complements this command rather than replacing it: `/devteam:status` is for the current/live session, `devteam-reports/` is the kept historical record.
