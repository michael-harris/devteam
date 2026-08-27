# DevTeam Logs Command

**Command:** `/devteam:logs [options]`

View execution logs, event history, and debugging information.

## Usage

```bash
/devteam:logs                      # Show recent logs
/devteam:logs --session <id>       # Show logs for specific session
/devteam:logs --agent <name>       # Filter by agent
/devteam:logs --level error        # Filter by log level
/devteam:logs --tail 50            # Show last 50 entries
/devteam:logs --export             # Export logs to file
```

## Options

| Option | Description |
|--------|-------------|
| `--session <id>` | Filter by session ID |
| `--agent <name>` | Filter by agent name |
| `--level <level>` | Filter by level: debug, info, warn, error |
| `--tail <n>` | Show last N entries (default: 20) |
| `--since <time>` | Show logs since time (e.g., "1h", "30m") |
| `--export` | Export to logs/devteam-TIMESTAMP.log |
| `--json` | Output as JSON |
| `--verbose` | Show full log details |

## Your Process

### Step 1: Query Events Database

```javascript
async function getLogs(options) {
    let query = `
        SELECT
            e.id,
            e.timestamp,
            e.event_type,
            e.data,
            s.command as session_command,
            ar.agent
        FROM events e
        LEFT JOIN sessions s ON e.session_id = s.id
        LEFT JOIN agent_runs ar ON e.session_id = ar.session_id
        WHERE 1=1
    `

    const params = []

    if (options.session) {
        query += ` AND e.session_id = ?`
        params.push(options.session)
    }

    if (options.agent) {
        query += ` AND ar.agent LIKE ?`
        params.push(`%${options.agent}%`)
    }

    if (options.level) {
        query += ` AND json_extract(e.data, '$.level') = ?`
        params.push(options.level)
    }

    if (options.since) {
        const sinceTime = parseTimeOffset(options.since)
        query += ` AND e.timestamp > datetime('now', ?)`
        params.push(sinceTime)
    }

    query += ` ORDER BY e.timestamp DESC LIMIT ?`
    params.push(options.tail || 20)

    return await db.all(query, params)
}
```

### Step 2: Display Logs

**Default Output:**

```markdown
╔═══════════════════════════════════════════════════════════════╗
║  DevTeam Logs                                                  ║
║  Showing last 20 entries                                       ║
╚═══════════════════════════════════════════════════════════════╝

2026-01-29 10:45:23 [INFO] session_started
  Command: /devteam:implement --sprint 1
  Session: sess_abc123

2026-01-29 10:45:25 [INFO] agent_started
  Agent: backend:api-developer-typescript
  Task: TASK-001
  Model: sonnet

2026-01-29 10:46:15 [INFO] gate_passed
  Gate: tests
  Duration: 12s

2026-01-29 10:46:18 [WARN] gate_failed
  Gate: lint
  Errors: 3
  Details: src/api.ts:45 - Missing semicolon

2026-01-29 10:46:45 [INFO] fix_applied
  Issue: lint errors
  Files: ["src/api.ts"]

2026-01-29 10:47:02 [INFO] gate_passed
  Gate: lint
  Duration: 8s

2026-01-29 10:47:30 [INFO] task_completed
  Task: TASK-001
  Iterations: 2
  Model: sonnet

2026-01-29 10:47:32 [INFO] session_ended
  Status: completed
  Duration: 2m 9s
  Cost: $0.12

───────────────────────────────────────────────────────────────
Filter: /devteam:logs --level error
Export: /devteam:logs --export
```

**Error Filter:**

```bash
/devteam:logs --level error --since 24h
```

```markdown
╔═══════════════════════════════════════════════════════════════╗
║  DevTeam Logs - Errors (last 24h)                             ║
╚═══════════════════════════════════════════════════════════════╝

2026-01-29 09:15:42 [ERROR] agent_failed
  Agent: database:developer-python
  Task: TASK-003
  Error: Migration failed - column already exists
  Stack: alembic/operations.py:123
         migrations/versions/abc123.py:45

2026-01-28 16:22:18 [ERROR] gate_failed
  Gate: tests
  Failures: 2
  Details:
    - test_user_creation: AssertionError
    - test_login_flow: TimeoutError

───────────────────────────────────────────────────────────────
Total errors: 2
Sessions affected: 2
```

**Session Detail:**

```bash
/devteam:logs --session sess_abc123 --verbose
```

```markdown
╔═══════════════════════════════════════════════════════════════╗
║  Session: sess_abc123                                          ║
║  Command: /devteam:implement --sprint 1                        ║
║  Status: completed                                             ║
╚═══════════════════════════════════════════════════════════════╝

Timeline
───────────────────────────────────────────────────────────────
10:45:23.123  session_started
10:45:23.456  phase_changed → initializing
10:45:24.789  agent_started → backend:api-developer-typescript
10:45:25.012  phase_changed → executing
10:45:45.234  tool_call → Edit (src/api.ts)
10:46:02.456  tool_call → Bash (npm test)
10:46:15.678  gate_passed → tests (12s)
10:46:16.890  tool_call → Bash (npm run lint)
10:46:18.123  gate_failed → lint (3 errors)
10:46:20.456  fix_task_created → lint_errors
10:46:45.789  fix_applied → lint_errors
10:47:02.012  gate_passed → lint (8s)
10:47:30.234  task_completed → TASK-001
10:47:32.456  session_ended → completed

Agents Used
───────────────────────────────────────────────────────────────
  backend:api-developer-typescript  │ 1m 45s │ sonnet │ $0.10
  lint-fixer                   │ 25s    │ haiku  │ $0.02

Quality Gates
───────────────────────────────────────────────────────────────
  tests:     ✓ passed (12s)
  lint:      ✓ passed (retry after fix)
  typecheck: ✓ passed (5s)

Tokens
───────────────────────────────────────────────────────────────
  Input:  15,234 tokens
  Output: 3,456 tokens
  Cost:   $0.12
```

### Step 3: Export Logs

```bash
/devteam:logs --export --since 7d
```

Creates: `logs/devteam-2026-01-29T104500.log`

```
# DevTeam Execution Log
# Exported: 2026-01-29T10:45:00Z
# Filter: since 7d
# Entries: 156

[2026-01-29T10:45:23.123Z] INFO session_started session_id=sess_abc123 command="/devteam:implement --sprint 1"
[2026-01-29T10:45:25.012Z] INFO agent_started agent=backend:api-developer-typescript model=sonnet task=TASK-001
...
```

## Log Levels

| Level | Description |
|-------|-------------|
| `debug` | Detailed debugging information |
| `info` | General execution information |
| `warn` | Warnings that don't stop execution |
| `error` | Errors that may impact execution |

## See Also

- `/devteam:status` - System status and metrics
- `/devteam:status --history` - Session history
- `devteam-reports/` - A browsable, per-task/per-sprint alternative to querying logs ad hoc: `devteam-reports/tasks/TASK-XXX.md` and `devteam-reports/sprints/SPRINT-XXX.md`, rendered automatically by `orchestration:execution-ledger` as tasks and sprints complete. Use this when you want "what happened on TASK-014" as a standing document rather than a query; use `/devteam:logs` for live, ad hoc filtering.
