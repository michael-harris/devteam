# DevTeam Implement Command

**Command:** `/devteam:implement [task] [options]`

Execute implementation work - plans, sprints, tasks, or ad-hoc work.

## Usage

```bash
# Execute selected/current plan
/devteam:implement

# Execute specific sprint
/devteam:implement --sprint 1
/devteam:implement --sprint SPRINT-001

# Execute all sprints
/devteam:implement --all

# Execute specific task
/devteam:implement --task TASK-001

# Ad-hoc task (will trigger interview if ambiguous)
/devteam:implement "Add pagination to user list"

# Cost-optimized execution
/devteam:implement --eco
/devteam:implement --sprint 1 --eco

# Skip interview for ad-hoc tasks
/devteam:implement "Fix typo in header" --skip-interview

# Specify task type for better agent selection
/devteam:implement "Audit auth flow" --type security
/devteam:implement "Restructure utils" --type refactor
```

## Options

| Option | Description |
|--------|-------------|
| `--sprint <id>` | Execute specific sprint |
| `--all` | Execute all sprints sequentially |
| `--task <id>` | Execute specific task |
| `--eco` | Cost-optimized execution (slower escalation, summarized context) |
| `--skip-interview` | Skip ambiguity check for ad-hoc tasks |
| `--type <type>` | Specify task type: feature, bug, security, refactor, docs |
| `--model <model>` | Force starting model: haiku, sonnet, opus |
| `--max-iterations <n>` | Override max iterations (default: 10) |
| `--show-worktrees` | Debug: Show worktree operations (normally hidden) |
| `--autonomous` | Keep looping across sprints/tasks without stopping between them (sets `orchestration:sprint-orchestrator`'s `mode: autonomous`; only applies to `--sprint`/`--all`/plan targets, ignored for `--task`/ad-hoc) |

## Your Process

This command delegates execution to the real orchestrators via `Task()` calls — it does not reimplement the task loop, quality gates, worktree management, or cost tracking inline. The main session's job is: initialize the session, determine what to execute, run the ad-hoc interview if needed, then hand off to `orchestration:task-loop` (single task) or `orchestration:sprint-orchestrator` (sprint/all-sprints/plan), which own everything downstream.

### Phase 0: Initialize Session

```bash
# Source state management
source scripts/state.sh
source scripts/events.sh

# Start session
SESSION_ID=$(start_session "/devteam:implement $*" "implement")
log_session_started "/devteam:implement $*" "implement"

# Determine execution mode
if [[ "$*" == *"--eco"* ]]; then
    set_state "execution_mode" "eco"
fi
```

Create/update session in database:

```sql
INSERT INTO sessions (
    id, command, command_type, execution_mode, status, current_phase
) VALUES (
    'session-xxx', '/devteam:implement --sprint 1', 'implement', 'normal', 'running', 'initializing'
);
```

### Phase 1: Determine Execution Target

**Priority order:**
1. `--task TASK-001` → Execute single task
2. `--sprint 1` → Execute specific sprint
3. `--all` → Execute all sprints
4. `"ad-hoc task"` → Create and execute ad-hoc task
5. (no args) → Execute current/selected plan

```javascript
function determineTarget(args) {
    if (args.task) return { type: 'task', id: args.task }
    if (args.sprint) return { type: 'sprint', id: args.sprint }
    if (args.all) return { type: 'all_sprints' }
    if (args._.length > 0) return { type: 'adhoc', description: args._.join(' ') }
    return { type: 'plan', id: getSelectedPlan() }
}
```

### Phase 2: Interview (for ad-hoc tasks)

**Skip if:**
- `--skip-interview` flag present
- Task is from a plan (already has context)
- Description is clearly unambiguous

**Trigger interview if:**
- Ad-hoc task with vague description
- Missing critical information

```javascript
// Check for ambiguity
const ambiguityIndicators = [
    description.split(' ').length < 5,           // Too short
    /fix|broken|doesn't work|issue/i.test(description) && !description.includes('when'),
    /add|create|implement/i.test(description) && !description.includes('to'),
    !description.includes(' ')                    // Single word
]

if (ambiguityIndicators.some(x => x) && !args.noInterview) {
    await runInterview('adhoc_task', description)
}
```

**Interview questions for ad-hoc tasks:**

```yaml
adhoc_task:
  triggers:
    - pattern: "fix|broken|bug"
      redirect: bug_interview
    - pattern: "add|create|implement"
      questions:
        - key: scope
          question: "What component/area should this be added to?"
        - key: requirements
          question: "What are the specific requirements?"
        - key: acceptance
          question: "How will we know when this is complete?"
```

### Phase 3: Agent Selection

For an ad-hoc task (no pre-existing TASK-XXX.json — a normal sprint/plan task's `suggested_agent` is already set by `planning:task-graph-analyzer` during `/devteam:plan` and this phase does not apply to it), determine `suggested_agent` with this precedence, in order — stop at the first match, do not blend:

1. **`--type` flag, if the user passed one** (e.g. `/devteam:implement "..." --type security`): look it up directly in `task_type_agents` below.
2. **Keyword/pattern match against the description**: if it matches one of `task_type_agents`' keys (a "security audit", "refactor X", or "fix broken Y" style description), use that entry's `primary` as `suggested_agent`, and note its `support` list in the dispatch prompt as agents the primary may itself consult.
3. **Otherwise**, infer from file types touched / language / general keywords (a normal implementation task) and pick the matching leaf implementer (e.g. `backend:api-developer-python`, `frontend:developer`) the same way `task-graph-analyzer` would for a planned task.

```yaml
# Task type overrides -- checked first per the precedence above
task_type_agents:
  security:
    primary: quality:security-auditor
    support: [security:penetration-tester, security:compliance-engineer]
  refactor:
    primary: quality:refactoring-coordinator
    support: [frontend:code-reviewer]
  bug:
    primary: diagnosis:root-cause-analyst
    support: [orchestration:bug-council-orchestrator]
```

**Concrete example — a "refactor" ad-hoc task resolves to a real dispatch, not just a config lookup.** For `/devteam:implement "Refactor the payment module for testability" --type refactor` (or an ad-hoc description that keyword-matches "refactor"), `suggested_agent` resolves to `quality:refactoring-coordinator` per the table above, and task-loop's Step 1 (`agents/orchestration/task-loop.md`) then dispatches it exactly like any other `{suggested_agent}` resolution:

```javascript
Task({
  subagent_type: "quality:refactoring-coordinator",
  model: "sonnet",  // Start here. Escalate to "opus" after 2 failures, per task-loop's normal rule.
  prompt: `Refactor the payment module for testability.

    Support agents available if needed: frontend:code-reviewer.
    Acceptance criteria: ...`
})
```

### Phase 4: Model Selection

**Normal Mode:**
```yaml
complexity_based:
  1-4: haiku
  5-8: sonnet
  9-14: opus
```

**Eco Mode:**
```yaml
eco_mode:
  default: haiku
  exceptions:
    - security: sonnet
    - architecture: sonnet
    - complexity_10_plus: sonnet
```

### Phase 5: Execute

Route to the real orchestrator based on the target determined in Phase 1. Do not reimplement the task loop, quality gates, or completion reporting here — `orchestration:task-loop` and `orchestration:sprint-orchestrator` own that (including language-aware quality gates via `quality-gate-enforcer`, not a hardcoded `npm test`/`npm run lint` that would break on non-JS projects).

**Target type `task` or `adhoc`** (a single `--task TASK-XXX`, or an ad-hoc description after Phase 2/3/4 above): delegate directly to Task Loop.

```bash
source scripts/events.sh
TL_RUN_ID=$(log_agent_started "orchestration:task-loop" "opus" "$taskId" "" "")
```
```javascript
const result = await Task({
    subagent_type: "orchestration:task-loop",
    model: "opus",
    prompt: `Execute ${taskId}: ${taskDescription}

        Your own agent_runs id for this run (use as invoked_by_run_id on
        every sub-agent you dispatch, with invoked_by_agent
        "orchestration:task-loop"): ${TL_RUN_ID}

        Acceptance criteria: ${acceptanceCriteria}
        Suggested agent: ${suggestedAgent}
        Starting model: ${startingModel} (complexity: ${complexityScore})
        Execution mode: ${ecoMode ? 'eco' : 'normal'}`
})
```
```bash
if [ "$result_status" = "COMPLETE" ]; then
    log_agent_completed "orchestration:task-loop" "opus" "$files_changed_json" "$tokens_in" "$tokens_out" "$cost_cents" "$TL_RUN_ID"
else
    log_agent_failed "orchestration:task-loop" "opus" "$result_reason" "" "$TL_RUN_ID"
fi
```

**Target type `sprint`, `all_sprints`, or `plan`**: delegate to Sprint Orchestrator, which sequences tasks (via Task Loop, per task) and runs sprint-level validation itself.

```bash
source scripts/events.sh
SO_RUN_ID=$(log_agent_started "orchestration:sprint-orchestrator" "opus" "" "" "")
```
```javascript
const result = await Task({
    subagent_type: "orchestration:sprint-orchestrator",
    model: "opus",
    prompt: `Execute ${targetType === 'all_sprints' ? 'all sprints' : `sprint ${sprintId}`} for the active plan.

        Your own agent_runs id for this run (use as own_run_id below):
        ${SO_RUN_ID}

        mode: ${autonomousFlag ? 'autonomous' : 'normal'}
        execution_mode: ${ecoMode ? 'eco' : 'normal'}`
})
```
```bash
if [ "$result_status" = "COMPLETE" ]; then
    log_agent_completed "orchestration:sprint-orchestrator" "opus" "$files_changed_json" "$tokens_in" "$tokens_out" "$cost_cents" "$SO_RUN_ID"
else
    log_agent_failed "orchestration:sprint-orchestrator" "opus" "$result_reason" "" "$SO_RUN_ID"
fi
```

**On either path returning COMPLETE:**
```bash
log_session_ended "completed" "All quality gates and workflow compliance passed"
end_session "completed" "Success"
```
Report the result using the actual fields the orchestrator returned (files changed, quality gate results, iterations, model usage, cost) — never fabricate these values:

```
╔══════════════════════════════════════════╗
║  ✅ IMPLEMENTATION COMPLETE              ║
╚══════════════════════════════════════════╝

Task: ${taskDescription}

Files Changed:
${filesChanged.map(f => `  • ${f}`).join('\n')}

Quality Gates: ${qualityGateSummary}   ← from the orchestrator's own report
Iterations: ${iterations}
Model Usage: ${modelBreakdown}
Cost: $${totalCost}

EXIT_SIGNAL: true
```

**On FAILED or HALTED:**
```bash
log_session_ended "failed" "$result_reason"
end_session "failed" "$result_reason"
```
Report what actually remains broken (from the orchestrator's own failure report):

```
╔══════════════════════════════════════════╗
║  ⚠️  EXECUTION DID NOT COMPLETE          ║
╚══════════════════════════════════════════╝

${result_reason}

Remaining Issues:
${remainingIssues.map(i => `  • ${i}`).join('\n')}

Recommendation: Review the issues above and either:
1. Run /devteam:implement again with more context
2. Break the task into smaller pieces
3. Manually address the blocking issues

EXIT_SIGNAL: true
```

## Automatic Worktree Management

**Worktrees are fully automatic.** Users never need to interact with worktrees directly. This command does not create, isolate, merge, or clean up worktrees itself — `orchestration:sprint-orchestrator` owns worktree creation and per-track isolation (its "Agent Teams Mode" section, triggered when a plan has `parallel_tracks.track_info` with multiple tracks), and `orchestration:track-merger` owns merging tracks back together once all are complete. This command's only job re: worktrees is passing `--show-worktrees` through as debug context when present, and pointing users at `/devteam:worktree status`/`/devteam:worktree list` for diagnostics if something looks wrong.

### Debug Flag

For advanced users who want to see worktree operations:

```bash
/devteam:implement --sprint 1 --show-worktrees
```

This displays:
```
═══════════════════════════════════════════════════
 Worktree Operations (debug mode)
═══════════════════════════════════════════════════

Track 01: .multi-agent/track-01 (dev-track-01)
  ✅ Worktree exists
  📍 Current commit: abc123

Track 02: .multi-agent/track-02 (dev-track-02)
  ✅ Worktree exists
  📍 Current commit: def456

Executing in: .multi-agent/track-01
```

### Important Notes

- **Users never need to run worktree commands** - everything is automatic
- Worktrees are created in `.multi-agent/` (gitignored) or `.claude/worktrees/` (native isolation)
- Branches are kept after merge for history (use `--delete-branches` in debug commands to remove)
- If something goes wrong, use `/devteam:worktree status` for diagnostics

## Sprint Execution

Sprint and all-sprints execution (`--sprint`, `--all`) is entirely owned by `orchestration:sprint-orchestrator` (task sequencing, dependency-aware parallelization, per-task delegation to Task Loop, sprint-level validation) — see Phase 5 above and `agents/orchestration/sprint-orchestrator.md`. This command does not loop over sprint tasks itself.

## User Communication

**Starting:**
```
═══════════════════════════════════════════════════
 DevTeam Implementation
═══════════════════════════════════════════════════

Target: Sprint SPRINT-001 (3 tasks)
Mode: Normal
Model: sonnet (complexity: 6)

Starting execution...
```

**Progress:**
```
═══════════════════════════════════════════════════
Task 1/3: Implement user authentication
═══════════════════════════════════════════════════

Agent: backend:api-developer-typescript
Model: sonnet
Iteration: 1

Progress:
  ✅ Created auth middleware
  ✅ Added JWT validation
  ⏳ Writing tests...

Quality Gates:
  ⏳ Pending...
```

**Escalation:**
```
⚠️  Model Escalation
────────────────────
Reason: 2 consecutive test failures
Action: sonnet → opus

Retrying with enhanced reasoning...
```

## Cost Tracking

Cost is tracked in real time by the `log_agent_started`/`log_agent_completed` calls made throughout Phase 5 (and by every sub-agent Task Loop and Sprint Orchestrator dispatch internally) — `agent_runs.cost_cents` is the single source of truth (`scripts/cost-tracking.sh` reads/formats it, it does not compute a second figure). This command does not compute cost rates itself; see `scripts/cost-tracking.sh`'s `calculate_cost()` for the authoritative per-model rates.

## Error Handling

```javascript
try {
    await executeImplementation()
} catch (error) {
    if (error.type === 'circuit_breaker') {
        log_error('Circuit breaker tripped', { failures: consecutiveFailures })
        // Wait and retry or abort
    } else if (error.type === 'rate_limit') {
        log_warning('Rate limit approaching', { usage: currentUsage })
        // Throttle execution
    } else {
        log_error(error.message, { stack: error.stack })
        end_session('failed', error.message)
    }
}
```

## See Also

- `/devteam:plan` - Create plans before implementing
- `/devteam:bug` - Fix bugs with diagnostic workflow
- `/devteam:status` - Check implementation progress
- `/devteam:list` - List available plans and sprints
