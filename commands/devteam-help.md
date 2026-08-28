# DevTeam Help Command

**Command:** `/devteam:help [topic]`

Get help on DevTeam commands, concepts, and troubleshooting.

## Usage

```bash
/devteam:help                    # Show command overview
/devteam:help implement          # Help for specific command
/devteam:help eco                # Help on eco mode
/devteam:help agents             # Help on agent system
/devteam:help troubleshooting    # Troubleshooting guide
```

## Available Topics

### Commands
| Topic | Description |
|-------|-------------|
| `plan` | Planning and PRD generation |
| `implement` | Implementation execution |
| `bug` | Bug fixing workflow |
| `issue` | GitHub issue handling |
| `status` | System status and metrics |
| `reset` | Reset and recovery |
| `config` | Configuration management |
| `logs` | Log viewing |

### Concepts
| Topic | Description |
|-------|-------------|
| `eco` | Eco mode for cost optimization |
| `task-loop` | Task Loop quality loop |
| `interview` | Interview system |
| `research` | Research phase |
| `escalation` | Model escalation |
| `gates` | Quality gates |
| `council` | Bug Council |
| `agents` | Agent system |
| `worktrees` | Git worktree automation |

### Guides
| Topic | Description |
|-------|-------------|
| `getting-started` | New user guide |
| `troubleshooting` | Problem solving |
| `best-practices` | Recommended practices |
| `migration` | Migrating from v2.x |

## Your Process

### Step 1: Resolve Topic

```javascript
function resolveTopic(input) {
    // Exact match
    if (topics[input]) return topics[input]

    // Command alias
    if (commandAliases[input]) return topics[commandAliases[input]]

    // Fuzzy match
    const matches = findSimilar(input, Object.keys(topics))
    if (matches.length) {
        return { type: 'suggestion', matches }
    }

    return { type: 'not_found' }
}
```

### Step 2: Display Help

**No Topic (Overview):**

```markdown
╔═══════════════════════════════════════════════════════════════╗
║  DevTeam v3.4 Help                                             ║
╚═══════════════════════════════════════════════════════════════╝

Quick Start
───────────────────────────────────────────────────────────────
  /devteam:plan              Create a project plan
  /devteam:implement         Execute implementation
  /devteam:bug "issue"       Fix a bug
  /devteam:status            Check system status

Common Commands
───────────────────────────────────────────────────────────────
  Plan & Execute
    /devteam:plan            Interactive planning with research
    /devteam:implement       Execute plans, sprints, or tasks
    /devteam:implement --eco Cost-optimized execution

  Bug Fixing
    /devteam:bug             Fix local bugs
    /devteam:issue #123      Fix GitHub issues

  Management
    /devteam:status          System health and costs
    /devteam:list            List plans and tasks
    /devteam:reset           Reset stuck sessions

Get Help on Specific Topics
───────────────────────────────────────────────────────────────
  /devteam:help <command>    Help for a command
  /devteam:help eco          Eco mode explanation
  /devteam:help task-loop    Quality loop details
  /devteam:help troubleshooting  Problem solving

Documentation: https://github.com/Winnie-Bodhrik/devteam
```

**Command Help:**

```bash
/devteam:help implement
```

```markdown
╔═══════════════════════════════════════════════════════════════╗
║  /devteam:implement                                            ║
║  Execute implementation work                                   ║
╚═══════════════════════════════════════════════════════════════╝

Usage
───────────────────────────────────────────────────────────────
  /devteam:implement                    Execute current plan
  /devteam:implement --sprint 1         Execute specific sprint
  /devteam:implement --all              Execute all sprints
  /devteam:implement "task"             Ad-hoc task
  /devteam:implement --eco              Cost-optimized mode

Options
───────────────────────────────────────────────────────────────
  --sprint <id>      Execute specific sprint
  --all              Execute all sprints
  --task <id>        Execute specific task
  --eco              Cost-optimized execution
  --skip-interview     Skip ambiguity check
  --type <type>      Task type: feature, bug, security
  --model <model>    Force model: haiku, sonnet, opus

Examples
───────────────────────────────────────────────────────────────
  # Execute first sprint
  /devteam:implement --sprint 1

  # Quick bug fix with eco mode
  /devteam:implement "Fix login button" --eco --type bug

  # Execute with specific model
  /devteam:implement --task TASK-001 --model opus

See Also
───────────────────────────────────────────────────────────────
  /devteam:plan      Create plans first
  /devteam:status    Check progress
  /devteam:help eco  Cost optimization details
```

**Concept Help:**

```bash
/devteam:help eco
```

```markdown
╔═══════════════════════════════════════════════════════════════╗
║  Eco Mode                                                      ║
║  Cost-optimized execution                                      ║
╚═══════════════════════════════════════════════════════════════╝

Overview
───────────────────────────────────────────────────────────────
Eco mode reduces costs by 30-50% through:
  • Starting with Haiku for most tasks
  • Slower model escalation (4 failures vs 2)
  • Summarized context to reduce tokens
  • Sequential quality gates

When to Use
───────────────────────────────────────────────────────────────
  ✓ Simple tasks (complexity 1-6)
  ✓ Bug fixes with clear reproduction
  ✓ Documentation updates
  ✓ Code formatting/linting
  ✓ Test writing for existing code

When NOT to Use
───────────────────────────────────────────────────────────────
  ✗ Complex architecture decisions
  ✗ Security-sensitive code
  ✗ Tasks requiring deep reasoning
  ✗ Complexity 10+ tasks

Comparison
───────────────────────────────────────────────────────────────
                    Normal          Eco
  Initial Model     Complexity-based Haiku
  Escalation        2 failures      4 failures
  Context           Full            Summarized
  Quality Gates     Parallel        Sequential
  Avg Cost          $0.15/task      $0.06/task

Usage
───────────────────────────────────────────────────────────────
  /devteam:implement --eco "task"
  /devteam:bug "issue" --eco
  /devteam:config set execution.mode eco  # Set as default

See Also
───────────────────────────────────────────────────────────────
  /devteam:help escalation  Model escalation details
  /devteam:status --costs   Cost breakdown
```

**Troubleshooting:**

```bash
/devteam:help troubleshooting
```

```markdown
╔═══════════════════════════════════════════════════════════════╗
║  Troubleshooting Guide                                         ║
╚═══════════════════════════════════════════════════════════════╝

Common Issues
───────────────────────────────────────────────────────────────

1. Session Stuck
   Symptoms: Commands not responding, "session in progress"
   Solution:
     /devteam:reset
     /devteam:reset --session <id>

2. Tests Keep Failing
   Symptoms: Task Loop not converging
   Solutions:
     - Check test output: /devteam:logs --level error
     - Force model upgrade: --model opus
     - Break into smaller tasks

3. High Costs
   Symptoms: Unexpected token usage
   Solutions:
     - Use eco mode: --eco
     - Check costs: /devteam:status --costs
     - Review model usage in logs

4. Database Errors
   Symptoms: "Database locked" or corruption
   Solution:
     bash scripts/db-init.sh  # Reinitialize

5. Worktree Issues
   Symptoms: Merge conflicts, missing worktrees
   Solutions:
     /devteam:worktree-status  # Debug command
     /devteam:worktree-cleanup # Manual cleanup

Getting Help
───────────────────────────────────────────────────────────────
  Logs:   /devteam:logs --level error
  Status: /devteam:status --all
  GitHub: https://github.com/Winnie-Bodhrik/devteam/issues
```

## See Also

- `/devteam:status` - System status
- `/devteam:logs` - Execution logs
- `docs/GETTING_STARTED.md` - Full documentation
