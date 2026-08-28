# Getting Started with DevTeam

Welcome to DevTeam, a 127-agent automated development system for Claude Code. This guide will help you get started quickly.

## Quick Start (5 minutes)

### 1. Install from Claude Code Marketplace

The easiest way to install DevTeam is directly from within Claude Code:

```bash
# Add the DevTeam marketplace
/plugin marketplace add https://github.com/Winnie-Bodhrik/devteam

# Install the plugin
/plugin install devteam@devteam-marketplace
```

All hooks, agents, skills, and rules are configured automatically. The SQLite database (`.devteam/devteam.db`) is auto-initialized on first use — no manual setup required.

#### Alternative: Install from Local Clone

For development or contributing:

```bash
git clone https://github.com/Winnie-Bodhrik/devteam.git
/plugin install /path/to/devteam
```

### 2. Verify Installation

```bash
/devteam:status
```

You should see system health information.

### 3. Your First Task

Try a simple ad-hoc task:

```bash
/devteam:implement "Add a hello world function to utils.js"
```

## Core Workflow

### Planning → Implementation

The typical DevTeam workflow:

```
1. /devteam:plan        → Create a PRD and task breakdown
2. /devteam:implement   → Execute the plan
3. /devteam:status      → Monitor progress
```

### Example: Building a Feature

```bash
# Step 1: Plan the feature
/devteam:plan --feature "Add user authentication"

# DevTeam will:
# - Interview you about requirements
# - Research your codebase
# - Generate a PRD
# - Create tasks and sprints

# Step 2: Execute the plan
/devteam:implement --sprint 1

# DevTeam will:
# - Execute tasks with appropriate agents
# - Run quality gates (tests, lint, typecheck)
# - Auto-fix issues through the Task Loop
# - Report completion

# Step 3: Check progress
/devteam:status
```

## Essential Commands

| Command | Purpose |
|---------|---------|
| `/devteam:plan` | Create plans with interview and research |
| `/devteam:implement` | Execute plans, sprints, or ad-hoc tasks |
| `/devteam:bug "desc"` | Fix a bug with diagnostic workflow |
| `/devteam:issue #123` | Fix a GitHub issue |
| `/devteam:status` | Check system health and progress |
| `/devteam:list` | List plans, sprints, and tasks |
| `/devteam:help` | Get help on any topic |

## Cost Optimization

DevTeam can be expensive if you're not careful. Use eco mode for simple tasks:

```bash
# Eco mode: uses lower-cost models for simpler tasks
/devteam:implement "Fix typo in header" --eco

# Set eco as default
/devteam:config set execution.mode eco
```

**When to use eco mode:**
- Simple bug fixes
- Documentation updates
- Code formatting
- Complexity 1-6 tasks

**When NOT to use eco mode:**
- Complex architecture
- Security-sensitive code
- Complexity 10+ tasks

## The Task Loop

DevTeam uses an iterative quality loop:

```
┌─────────────────────────────────────────────┐
│            TASK QUALITY LOOP                │
├─────────────────────────────────────────────┤
│  Execute Agent(s)                           │
│        ↓                                    │
│  Run Quality Gates (tests, lint, types)     │
│        ↓                                    │
│  PASS? → Complete                           │
│  FAIL? → Create fix tasks, retry            │
│        ↓                                    │
│  Still failing? → Escalate model            │
│        (haiku → sonnet → opus)              │
│        ↓                                    │
│  Max iterations? → Invoke Bug Council       │
└─────────────────────────────────────────────┘
```

## Specialized Agents

DevTeam has 127 specialized agents across categories:

- **Planning**: PRD generation, task breakdown, sprint planning
- **Orchestration**: Task coordination, quality loops, scope validation
- **Backend**: API development (Python, TypeScript, Java, C#, Go, Ruby, PHP)
- **Frontend**: React/Vue components, UI/UX design
- **Database**: Schema design, migrations, queries
- **Quality**: Testing, security, performance
- **DevOps**: Docker, Kubernetes, CI/CD, Terraform
- **SRE**: Site reliability, observability, platform engineering
- **Security**: Penetration testing, compliance engineering

## Project Structure

After initialization, DevTeam creates:

```
your-project/
├── .devteam/
│   ├── devteam.db        # SQLite database (state, events, metrics)
│   └── task-loop-config.yaml # Configuration
├── docs/
│   ├── planning/
│   │   ├── PROJECT_PRD.json
│   │   └── tasks/
│   │       └── TASK-XXX.json
│   └── sprints/
│       └── SPRINT-XXX.json
└── ... (your code)
```

## Common Patterns

### Bug Fixing
```bash
# Simple bug
/devteam:bug "Login button not working"

# With more context
/devteam:bug "Users can't login after password reset" --severity critical
```

### GitHub Issues
```bash
# Fix issue by number
/devteam:issue 123

# Create new issue
/devteam:issue-new "Feature request: dark mode"
```

### Parallel Development
For large projects, DevTeam uses git worktrees automatically:

```bash
# Plan with multiple tracks
/devteam:plan "E-commerce platform"

# Tracks are created automatically:
# - Track 01: Backend API
# - Track 02: Frontend
# - Track 03: Infrastructure

# Execute (worktrees managed automatically)
/devteam:implement --all

# Merging happens automatically when all tracks complete
```

## Troubleshooting

### Session Stuck
```bash
/devteam:reset
```

### High Costs
```bash
# Check costs
/devteam:status --costs

# Use eco mode
/devteam:implement --eco
```

### View Logs
```bash
/devteam:logs --level error
```

### Get Help
```bash
/devteam:help troubleshooting
```

## Next Steps

1. **Read the full documentation**: Check `docs/` for detailed guides
2. **Explore agents**: Run `/devteam:help agents` to see available capabilities
3. **Configure settings**: Run `/devteam:config` to customize behavior
4. **Join the community**: Report issues at GitHub

## Quick Reference Card

```
PLANNING
  /devteam:plan                Create new plan
  /devteam:plan --feature "X"  Plan a feature
  /devteam:list                List all plans

EXECUTION
  /devteam:implement           Execute current plan
  /devteam:implement --sprint 1 Execute sprint
  /devteam:implement --eco "X" Cost-optimized task

BUG FIXING
  /devteam:bug "description"   Fix a bug
  /devteam:issue #123          Fix GitHub issue

MONITORING
  /devteam:status              System health
  /devteam:status --costs      Cost breakdown
  /devteam:logs                View logs

UTILITIES
  /devteam:config              Configuration
  /devteam:reset               Reset state
  /devteam:help <topic>        Get help
```
