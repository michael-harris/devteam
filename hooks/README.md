# DevTeam Hook Scripts

Claude Code hooks that enable autonomous execution, session persistence, and quality enforcement.

## Overview

These hooks integrate with Claude Code's hook system to provide:
- Autonomous execution until completion
- Session memory persistence
- State preservation across context compaction
- Anti-abandonment enforcement
- Scope validation and enforcement
- Dangerous command blocking
- Quality gate detection and escalation
- MCP server integration

## Quick Start

### Plugin Installation (Recommended)

When DevTeam is installed as a Claude Code plugin (via marketplace or local install), all hooks are configured automatically through `hooks/hooks.json`. No manual setup is required.

```bash
# Install from marketplace (hooks auto-configured)
/plugin marketplace add https://github.com/Winnie-Bodhrik/devteam
/plugin install devteam@devteam-marketplace
```

All hook paths use `${CLAUDE_PLUGIN_ROOT}` to resolve correctly regardless of where the plugin is cached.

### Legacy Manual Installation

If running hooks outside the plugin system, you can still install manually:

```bash
# Linux/macOS
./hooks/install.sh

# Windows PowerShell
.\hooks\install.ps1
```

The installer will:
1. Make all hooks executable
2. Install git pre-commit hook for scope checking
3. Generate Claude Code settings configuration
4. Optionally auto-install to your settings.json

## Cross-Platform Support

All hooks are available in both Bash (Linux/macOS) and PowerShell (Windows):

| Hook | Linux/macOS | Windows |
|------|-------------|---------|
| Shared Library | `lib/hook-common.sh` | `lib/hook-common.ps1` |
| Pre-Tool-Use | `pre-tool-use-hook.sh` | `pre-tool-use-hook.ps1` |
| Post-Tool-Use | `post-tool-use-hook.sh` | `post-tool-use-hook.ps1` |
| Stop Hook | `stop-hook.sh` | `stop-hook.ps1` |
| Persistence Hook | `persistence-hook.sh` | `persistence-hook.ps1` |
| Scope Check | `scope-check.sh` | `scope-check.ps1` |
| Session Start | `session-start.sh` | `session-start.ps1` |
| Session End | `session-end.sh` | `session-end.ps1` |
| Pre-Compact | `pre-compact.sh` | `pre-compact.ps1` |
| Installer | `install.sh` | `install.ps1` |

## Hook Descriptions

### pre-tool-use-hook.sh / .ps1

**Purpose**: Validates tool calls BEFORE execution.

**Behavior**:
1. Validates file operations against task scope
2. Blocks dangerous commands (rm -rf /, force push to main, etc.)
3. Injects iteration warnings when approaching limits
4. Notifies MCP server of tool usage

**Dangerous Commands Blocked**:
- `rm -rf /`, `rm -rf /*`
- `git push --force main/master`
- `DROP DATABASE`, `DROP TABLE`
- Fork bombs, disk destruction commands
- Credential exposure attempts

**Exit Codes**:
- `0`: Allow tool call
- `2`: Block tool call (with injected message)

### post-tool-use-hook.sh / .ps1

**Purpose**: Analyzes results AFTER tool execution.

**Behavior**:
1. Detects success/failure patterns in output
2. Tracks consecutive failures
3. Triggers model escalation when threshold reached
4. Detects quality gate results (tests, lint, typecheck, security)
5. Provides specific error guidance

**Quality Gates Detected**:
- Tests: pytest, jest, vitest, go test, etc.
- Type Check: tsc, mypy, pyright
- Lint: eslint, ruff, golangci-lint, rubocop
- Security: bandit, npm audit, gosec, snyk
- Coverage: coverage, --cov, nyc

**Exit Codes**:
- `0`: Continue normally (post hooks don't block)

### persistence-hook.sh / .ps1

**Purpose**: Detects and prevents premature task abandonment.

**Behavior**:
1. Analyzes Claude's output for "give up" patterns
2. Detects direct abandonment: "I give up", "I cannot complete"
3. Detects passive abandonment: "Let me know if you need"
4. Detects permission-seeking: "Should I proceed?"
5. Blocks abandonment and injects re-engagement prompts
6. Escalates model tier after repeated attempts
7. Activates Bug Council if agent remains stuck

**Abandonment Patterns Detected**:
- Direct: "I give up", "I'm stuck", "I cannot determine"
- Passive: "Let me know if", "Feel free to", "Hope that helps"
- Permission-seeking: "Should I proceed", "Would you like me to"

**Escalation Sequence**:
| Attempt | Response |
|---------|----------|
| 1st | Gentle redirect - try different approach |
| 2nd | Forceful redirect - list 3 alternatives |
| 3rd | Model upgrade to Opus + Bug Council |
| 4th+ | Human notification (keep trying) |

**Exit Codes**:
- `0`: Allow (output acceptable)
- `2`: Block and re-engage (abandonment detected)

### stop-hook.sh / .ps1

**Purpose**: Implements autonomous execution loop control.

**Behavior**:
1. Checks for valid exit signals in Claude's output
2. If autonomous mode active and no signal, blocks exit
3. Monitors circuit breaker for consecutive failures
4. Tracks iteration count against maximum
5. Saves checkpoint before authorized exits
6. Cleans up session on authorized exit

**Valid Exit Signals**:
- `EXIT_SIGNAL: true`
- `All quality gates passed`
- `Task completed successfully`
- `Implementation complete`
- `/devteam:end`

**Exit Codes**:
- `0`: Allow exit (work complete or not autonomous)
- `2`: Block exit and continue

### scope-check.sh / .ps1

**Purpose**: Enforce strict scope compliance at commit time.

**Behavior**:
1. Reads current task ID from `.devteam/current-task.txt`
2. Loads task scope from database or task JSON file
3. Validates all staged files against allowed/forbidden lists
4. Detects potentially sensitive files (.env, *.key, credentials)
5. Blocks commit if any file is out of scope

**Exit Codes**:
- `0`: All changes within scope
- `1`: Scope violation (commit blocked)

**Scope Definition**:
```json
// docs/planning/tasks/TASK-XXX.json
{
  "scope": {
    "allowed_files": ["src/auth/session.ts"],
    "allowed_patterns": ["tests/auth/**/*.test.ts"],
    "forbidden_files": ["src/auth/oauth.ts"],
    "forbidden_directories": ["src/api/"]
  }
}
```

## Shared Library (hook-common.sh / .ps1)

The shared library provides common functions for all hooks:

### Configuration
- `DEVTEAM_ROOT` - Project root directory
- `DEVTEAM_DIR` - .devteam directory path
- `DEVTEAM_DB` - SQLite database path
- `MAX_ITERATIONS` - Maximum iteration count (default: 100)
- `MAX_FAILURES` - Circuit breaker threshold (default: 5)

### Logging Functions
- `log_debug/info/warn/error(hook, message)` - Structured logging
- Logs to `.devteam/hooks.log`

### Database Functions
- `db_exists()` - Check if database exists
- `db_query(sql)` - Execute SQL query
- `get_current_session()` - Get running session ID
- `get_current_task()` - Get in-progress task ID
- `get_current_iteration()` - Get iteration count
- `get_current_model()` - Get current model tier
- `get_consecutive_failures()` - Get failure count
- `increment_failures()` / `reset_failures()`
- `log_event_to_db(type, category, message, data)`

### MCP Communication
- `mcp_available()` - Check if MCP server is running
- `mcp_notify(event_type, data)` - Send event to MCP

### Scope Validation
- `file_in_scope(file)` - Check if file is in allowed scope
- `get_scope_files()` - Get scope patterns for current task

### Context & Injection
- `get_claude_context()` - Extract current context as JSON
- `inject_system_message(tag, message)` - Create system message

### Utilities
- `is_autonomous_mode()` - Check if autonomous mode active
- `is_circuit_breaker_open()` - Check if too many failures
- `is_max_iterations_reached()` - Check iteration limit
- `trigger_escalation(reason)` - Trigger model upgrade
- `save_checkpoint(message)` - Save progress checkpoint

## Environment Variables

Hooks use these environment variables from Claude Code:

| Variable | Description |
|----------|-------------|
| `CLAUDE_TOOL_NAME` | Name of tool being called |
| `CLAUDE_TOOL_INPUT` | Tool input parameters (JSON) |
| `CLAUDE_TOOL_RESULT` | Tool execution result |
| `CLAUDE_OUTPUT` | Claude's text output |
| `STOP_HOOK_MESSAGE` | Message for stop hook |

Configuration via environment:
| Variable | Description | Default |
|----------|-------------|---------|
| `DEVTEAM_MAX_ITERATIONS` | Max iterations before stop | 100 |
| `DEVTEAM_MAX_FAILURES` | Circuit breaker threshold | 5 |
| `DEVTEAM_ECO_MODE` | Use higher escalation thresholds | false |
| `DEVTEAM_DEBUG` | Enable debug logging | false |

## State Files

The hooks read/write these files in `.devteam/`:

| File | Purpose |
|------|---------|
| `devteam.db` | SQLite database for state |
| `autonomous-mode` | Autonomous mode marker |
| `circuit-breaker.json` | Failure tracking |
| `current-task.txt` | Active task ID |
| `consecutive-failures.txt` | Failure counter |
| `hooks.log` | Hook execution log |
| `abandonment-attempts.log` | Abandonment tracking |
| `escalation-trigger` | Model escalation signals |
| `last-errors.txt` | Recent error summary |
| `human-attention-needed.log` | Human notification log |
| `memory/*.md` | Session memory files |

## MCP Server Integration

Hooks integrate with the MCP server when available:

- **Socket**: `.devteam/mcp.sock` (Unix socket)
- **HTTP**: `MCP_SERVER_URL` environment variable

Events sent to MCP:
- `pre_tool_use` - Before tool execution
- `post_tool_use` - After tool execution
- `abandonment_detected` - When abandonment blocked
- `exit_blocked` - When exit prevented
- `session_exit` - When session ends
- `scope_violation` - When scope check fails
- `commit_validated` - When commit passes scope

## Testing

Run the hook test suite:

```bash
./hooks/tests/test-hooks.sh
```

Tests verify:
- Hook library loads correctly
- Persistence hook detects abandonment patterns
- Stop hook respects EXIT_SIGNAL
- Pre-tool-use hook blocks dangerous commands
- Post-tool-use hook detects failures
- All hook files exist

## Troubleshooting

### Hooks not executing (Linux/macOS)

```bash
# Verify hooks are executable
chmod +x hooks/*.sh hooks/lib/*.sh

# Check paths are absolute in settings.json
# Verify Claude Code version supports hooks
```

### Hooks not executing (Windows)

```powershell
# Check execution policy
Get-ExecutionPolicy
# Hooks should use -ExecutionPolicy Bypass flag

# Verify PowerShell version (5.1+ or 7+)
$PSVersionTable.PSVersion
```

### Autonomous mode not working

```bash
# Check marker file exists
ls -la .devteam/autonomous-mode

# Check circuit breaker state
cat .devteam/circuit-breaker.json

# Check hook log for errors
tail -50 .devteam/hooks.log
```

### Scope check issues

```bash
# Verify task file exists
cat .devteam/current-task.txt

# Check task scope definition
cat docs/planning/tasks/TASK-XXX.json

# Run scope check manually
./hooks/scope-check.sh
```

### Database issues

The database is auto-initialized on first use. To force reinitialize:

```bash
# Delete and let auto-init recreate it
rm -f .devteam/devteam.db*
/devteam:status

# Or manually (local development only):
# Linux/macOS
./scripts/db-init.sh
# Windows
# powershell ./scripts/db-init.ps1

# Check database exists
ls -la .devteam/devteam.db

# Query database
sqlite3 .devteam/devteam.db "SELECT * FROM sessions;"
```

## Dependencies

### Linux/macOS
- `bash` (4.0+)
- `sqlite3` (for database access)
- `jq` (optional, for JSON parsing)
- Standard Unix tools: date, mkdir, cat, grep

### Windows
- PowerShell 5.1+ or PowerShell Core 7+
- No additional dependencies (uses built-in cmdlets)

## Security Notes

- Hooks run with user permissions
- State files may contain project details
- Add `.devteam/` to `.gitignore` for sensitive projects
- Dangerous commands are blocked by pre-tool-use hook
- Sensitive files (.env, *.key) trigger warnings in scope check
- On Windows, `-ExecutionPolicy Bypass` only affects specific script execution
