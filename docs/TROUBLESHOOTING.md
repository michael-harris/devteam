# Troubleshooting Guide

This guide helps you diagnose and resolve common issues with DevTeam.

## Quick Diagnostics

```bash
# Check system status
/devteam:status

# View recent errors
/devteam:logs --level error

# Get detailed help
/devteam:help troubleshooting
```

## Common Issues

### 1. Session Stuck / Commands Not Responding

**Symptoms:**
- "Session already in progress" errors
- Commands hang indefinitely
- Status shows "running" but nothing happening

**Solutions:**

```bash
# Reset current session
/devteam:reset

# Reset specific session
/devteam:reset --session <session_id>

# Full reset (clears all state)
/devteam:reset --full
```

**Prevention:**
- Don't interrupt commands mid-execution
- Wait for EXIT_SIGNAL before starting new commands

---

### 2. Database Errors

**Symptoms:**
- "Database is locked"
- "No such table" errors
- Corruption messages

**Solutions:**

The database is auto-initialized on first use. To force a reinitialize:

```bash
# Delete the database - it will be recreated automatically on next command
rm .devteam/devteam.db*
/devteam:status
```

**If corruption persists:**
```bash
# Backup and reset
mv .devteam/devteam.db .devteam/devteam.db.corrupted
# The database will be auto-recreated on next DevTeam command
/devteam:status
```

---

### 3. Tests Keep Failing (Task Loop Not Converging)

**Symptoms:**
- Same tests fail repeatedly
- Max iterations reached
- Model escalates to opus but still fails

**Diagnosis:**
```bash
# View test failures
/devteam:logs --level error --since 1h

# Check gate results
sqlite3 .devteam/devteam.db "SELECT * FROM gate_results WHERE NOT passed ORDER BY timestamp DESC LIMIT 5"
```

**Solutions:**

1. **Provide more context:**
   ```bash
   /devteam:implement "Fix the login test" --type bug
   # Add details about what the test expects
   ```

2. **Force a more capable model:**
   ```bash
   /devteam:implement --model opus  # Use opus for complex reasoning
   ```

3. **Break into smaller tasks:**
   - Instead of "Fix all tests", fix one at a time

4. **Check test environment:**
   - Ensure dependencies are installed
   - Check if tests work manually

---

### 4. High Costs / Unexpected Token Usage

**Symptoms:**
- Session costs much higher than expected
- Many model escalations
- Long-running sessions

**Diagnosis:**
```bash
# Check cost breakdown
/devteam:status --costs

# View model usage
sqlite3 .devteam/devteam.db "SELECT * FROM v_model_usage"

# Check escalations
/devteam:logs --agent escalation
```

**Solutions:**

1. **Use eco mode for simple tasks:**
   ```bash
   /devteam:implement "Fix typo" --eco
   ```

2. **Set eco as default:**
   ```bash
   /devteam:config set execution.mode eco
   ```

3. **Reduce max iterations:**
   ```bash
   /devteam:config set execution.max_iterations 5
   ```

4. **Break complex tasks:**
   - Complexity 10+ tasks should be broken down

---

### 5. Worktree Issues

**Symptoms:**
- Merge conflicts
- "Worktree not found" errors
- Branch mismatch warnings

**Diagnosis:**
```bash
# Check worktree status (debug command)
/devteam:worktree-status

# List all worktrees
git worktree list
```

**Solutions:**

1. **Clean up worktrees:**
   ```bash
   /devteam:worktree-cleanup
   ```

2. **Force cleanup:**
   ```bash
   git worktree remove --force .multi-agent/track-01
   ```

3. **Manual merge:**
   ```bash
   /devteam:merge-tracks --dry-run  # Preview
   /devteam:merge-tracks            # Execute
   ```

4. **Start fresh:**
   ```bash
   rm -rf .multi-agent/
   git worktree prune
   ```

---

### 6. Interview Not Working

**Symptoms:**
- Questions not appearing
- Interview skipped unexpectedly
- Wrong workflow triggered

**Solutions:**

1. **Force interview:**
   ```bash
   /devteam:implement "task"
   # Don't use --skip-interview
   ```

2. **Check templates:**
   ```bash
   cat templates/interview-questions.yaml
   ```

3. **Specify task type:**
   ```bash
   /devteam:implement "description" --type bug
   /devteam:implement "description" --type feature
   ```

---

### 7. Research Phase Issues

**Symptoms:**
- Research takes too long
- "Research timeout" errors
- Research findings empty

**Solutions:**

1. **Skip research for simple tasks:**
   ```bash
   /devteam:plan --skip-research
   ```

2. **Increase timeout:**
   ```bash
   /devteam:config set research.timeout_minutes 10
   ```

3. **Check codebase accessibility:**
   - Ensure files are readable
   - Check for large binary files that might slow scanning

---

### 8. Agent Selection Wrong

**Symptoms:**
- Wrong language agent selected
- Frontend agent for backend task
- More expensive model used when a cheaper one would suffice

**Solutions:**

1. **Specify task type:**
   ```bash
   /devteam:implement --type backend
   /devteam:implement --type frontend
   ```

2. **Force a specific model:**
   ```bash
   /devteam:implement --model haiku   # Cost-optimized for simple tasks
   /devteam:implement --model sonnet  # Default for most operations
   /devteam:implement --model opus    # Complex reasoning and architecture
   ```

3. **Check project detection:**
   - Ensure package.json/pyproject.toml exists
   - Verify language-specific config files

**Note:** Each agent has an explicit model assignment (haiku, sonnet, or opus) in its YAML frontmatter and agent-registry.json. Orchestrators handle escalation automatically (sonnet -> opus after 2 failures, opus -> Bug Council after 3 failures).

---

### 9. Quality Gates Not Running

**Symptoms:**
- Tests skipped
- Lint not running
- No type checking

**Diagnosis:**
```bash
# Check gate configuration
/devteam:config show
```

**Solutions:**

1. **Verify gate commands:**
   ```bash
   # Test manually
   npm test
   npm run lint
   npm run typecheck
   ```

2. **Configure gates:**
   ```bash
   /devteam:config set gates.tests.command "npm test"
   /devteam:config set gates.lint.enabled true
   ```

3. **Check auto-detection:**
   - DevTeam auto-detects from package.json
   - Manual config overrides auto-detection

---

### 10. GitHub Integration Issues

**Symptoms:**
- "gh: command not found"
- Authentication errors
- Can't fetch issues

**Solutions:**

1. **Install GitHub CLI:**
   ```bash
   # macOS
   brew install gh

   # Ubuntu
   sudo apt install gh

   # Windows
   winget install GitHub.cli
   ```

2. **Authenticate:**
   ```bash
   gh auth login
   ```

3. **Verify:**
   ```bash
   gh auth status
   gh issue list
   ```

---

## Diagnostic Commands

### View System State
```bash
# Full status
/devteam:status --all

# Database health
sqlite3 .devteam/devteam.db "PRAGMA integrity_check"

# View recent sessions
sqlite3 .devteam/devteam.db "SELECT * FROM v_session_summary LIMIT 5"
```

### View Logs
```bash
# All recent logs
/devteam:logs --tail 50

# Errors only
/devteam:logs --level error

# Specific session
/devteam:logs --session <id> --verbose

# Export for sharing
/devteam:logs --export
```

### Reset Options
```bash
# Abort current session
/devteam:reset

# Clear specific session
/devteam:reset --session <id>

# Clear all history
/devteam:reset --clear-history

# Full factory reset
/devteam:reset --full
```

## Getting Help

### In-Tool Help
```bash
/devteam:help                # Overview
/devteam:help <command>      # Command help
/devteam:help troubleshooting # This guide
```

### Community
- GitHub Issues: [Report bugs](https://github.com/Winnie-Bodhrik/devteam/issues)
- Discussions: Ask questions and share tips

### Logs for Bug Reports

When reporting issues, include:

```bash
# Export logs
/devteam:logs --export --since 24h

# System info
/devteam:status --all --json > status.json
```

## Prevention Best Practices

1. **Use eco mode for simple tasks** - Saves costs and reduces errors
2. **Let commands complete** - Don't interrupt mid-execution
3. **Break complex tasks** - Complexity > 10 should be split
4. **Commit frequently** - DevTeam works best with clean git state
5. **Review plans first** - Check PRD before implementing
6. **Monitor costs** - Check `/devteam:status --costs` regularly
