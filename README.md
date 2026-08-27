# DevTeam: Multi-Agent Autonomous Development System

A Claude Code plugin providing **125 specialized AI agents** with:
- **Interview-driven planning** - Clarify requirements before work begins
- **Codebase research** - Investigate patterns and blockers before implementation
- **SQLite state management** - Reliable session tracking and cost analytics
- **Model escalation** - Automatic haiku → sonnet → opus progression
- **Bug Council** - 5-agent diagnostic team for complex issues
- **Eco mode** - Cost-optimized execution mode for simpler tasks
- **Quality gates** - Tests, types, lint, security, coverage enforcement

---

## How This Works

This is a **Claude Code plugin** composed of:
- **Markdown agent instructions** (`agents/*.md`) — Claude Code reads these and follows them as subagent prompts via the Task tool
- **YAML configuration** (`.devteam/*.yaml`) — defines capabilities, thresholds, and agent selection triggers
- **Shell scripts** (`scripts/*.sh`, `hooks/*.sh`) — handle state persistence (SQLite), event logging, hook lifecycle, and database management
- **Slash commands** (`commands/*.md`, `skills/*/SKILL.md`) — user-facing commands that orchestrate agent workflows

There is no separate executable orchestrator. **Claude Code itself is the runtime** — it reads the agent markdown files, selects appropriate agents based on task characteristics, and executes them as subagents. The shell scripts provide supporting infrastructure (database, hooks, state tracking) but the orchestration logic lives in the agent instructions themselves.

---

## Key Features

### Autonomous Development with Task Loop

**Task Loop** is the iterative quality enforcement system that ensures every task is completed to specification:

```
┌─────────────────────────────────────────────────────────────┐
│                       TASK LOOP                              │
│                                                              │
│   Execute → Quality Gates → Pass? → Complete                 │
│      ↑           │                                           │
│      │          Fail                                         │
│      │           ↓                                           │
│      └─── Fix Tasks ← Model Escalation (if needed)          │
│                                                              │
│   Loop until: ALL QUALITY GATES PASS                        │
└─────────────────────────────────────────────────────────────┘
```

**Features:**
- Automatic model escalation (haiku → sonnet → opus) after failures
- Stuck loop detection with Bug Council activation
- Quality gates: tests, types, lint, security, coverage
- Anti-abandonment system prevents agents from giving up
- Maximum 10 iterations with human notification

### Intelligent Agent Selection

The `/devteam:implement` command automatically selects the best agents for your task:

```bash
/devteam:implement "Add user authentication with JWT tokens"
```

The `/devteam:implement` command analyzes your task description, file types involved, and project context to select appropriate agents. It considers keyword matches, file extensions, task type (feature vs. bug), and detected language/framework.

### Bug Council: Multi-Perspective Debugging

For complex bugs, the Bug Council convenes 5 specialized analysts:

```
┌─────────────────────────────────────────────────────────────┐
│                       BUG COUNCIL                            │
├─────────────────────────────────────────────────────────────┤
│  Root Cause Analyst    │ Error analysis, stack traces       │
│  Code Archaeologist    │ Git history, regression detection  │
│  Pattern Matcher       │ Similar bugs, anti-patterns        │
│  Systems Thinker       │ Dependencies, integration issues   │
│  Adversarial Tester    │ Edge cases, security vectors       │
└─────────────────────────────────────────────────────────────┘
                              ↓
                    Synthesized Solution
```

**Activation Triggers:**
- Critical/high severity bugs
- 3+ failed opus attempts
- Complexity score ≥ 10
- Explicit `bug_council: true` flag

### Scope Enforcement

Agents are strictly confined to their assigned scope:

```yaml
scope:
  allowed_files:
    - "src/auth/*.py"
  forbidden_directories:
    - "src/billing/"
  max_files_changed: 5
```

**6 Enforcement Layers:**
1. Task scope definition in YAML
2. Agent prompt constraints
3. Scope validator agent with VETO power
4. Pre-commit hook blocking
5. Runtime file access control
6. Out-of-scope observations logging

### Anti-Abandonment System

Agents cannot give up. The persistence system ensures completion:

```
Abandonment Attempt → Detected → Re-engagement Prompt
         ↓
    Still stuck?
         ↓
    Model Escalation (haiku → sonnet → opus)
         ↓
    Still stuck?
         ↓
    Bug Council Activation
         ↓
    Still stuck?
         ↓
    Human Notification (but keep trying)
```

---

## 125 Specialized Agents

### Enterprise Roles

| Category | Agents | Capabilities |
|----------|--------|--------------|
| **SRE** | Site Reliability Engineer | SLOs, incident response, chaos engineering |
| **SRE** | Platform Engineer | Internal developer platforms, golden paths |
| **SRE** | Observability Engineer | Metrics, logging, tracing, alerting |
| **Security** | Penetration Tester | OWASP testing, API security, vuln assessment |
| **Security** | Compliance Engineer | SOC2, HIPAA, GDPR, PCI-DSS |
| **Product** | Product Manager | PRDs, roadmaps, user research |
| **Quality** | Accessibility Specialist | WCAG 2.1, screen readers, inclusive design |
| **DevRel** | Developer Advocate | Technical content, community, DX |

### Orchestration Agents

| Agent | Purpose |
|-------|---------|
| **Bug Council Orchestrator** | Multi-perspective bug analysis |
| **Code Review Coordinator** | Cross-agent code review orchestration |
| **Quality Gate Enforcer** | Run and aggregate quality gate results |
| **Requirements Validator** | Validate acceptance criteria met |
| **Scope Validator** | Enforce scope boundaries |
| **Sprint Orchestrator** | Sprint execution management, task sequencing, and sprint-level validation (integration/security/performance/requirements/docs/code review/workflow compliance) after all tasks complete; runs in `mode: normal` (single invocation) or `mode: autonomous` (loops across sprints via the Stop hook until the plan is done) |
| **Task Loop** | Iterative quality loop for single task execution |
| **Track Merger** | Merge parallel worktree tracks |
| **Workflow Compliance** | Meta-validator auditing orchestration process |

### Bug Council Agents

| Agent | Specialty |
|-------|-----------|
| **Root Cause Analyst** | Error analysis, hypothesis generation |
| **Code Archaeologist** | Git history, regression detection |
| **Pattern Matcher** | Similar bugs, anti-pattern identification |
| **Systems Thinker** | Dependencies, architectural issues |
| **Adversarial Tester** | Edge cases, security vulnerabilities |

### Implementation Agents

**Backend (by language):**
- Python (FastAPI, Django, Flask)
- TypeScript (Express, NestJS, Fastify)
- Go (Gin, Echo, Fiber)
- Java (Spring Boot, Micronaut)
- C# (ASP.NET Core)
- Ruby (Rails, Sinatra)
- PHP (Laravel, Symfony)

**Frontend:**
- React, Vue, Svelte, Angular specialists
- Accessibility specialist
- Performance auditor

**Database:**
- Schema designers
- Query optimization specialists
- Migration specialists

**DevOps:**
- CI/CD Specialist (GitHub Actions, Jenkins, GitLab CI)
- Docker Specialist
- Kubernetes Specialist
- Terraform Specialist

### Quality Agents

| Agent | Focus |
|-------|-------|
| **Test Writer** | Unit, integration, e2e tests |
| **Security Auditor** | OWASP Top 10, vulnerability scanning |
| **Performance Auditor** | Profiling, optimization, load testing |
| **Accessibility Specialist** | WCAG compliance, inclusive design |
| **E2E Tester** | Playwright, Cypress, browser testing |

---

## Quick Start

### Planning + Implementation (Recommended)

```bash
# Plan a new feature (interview → research → PRD → tasks → sprints)
/devteam:plan --feature "Add user authentication with OAuth"

# Execute the plan
/devteam:implement

# Or execute specific sprint
/devteam:implement --sprint 1
```

The system will:
1. **Interview** - Clarify requirements with targeted questions
2. **Research** - Analyze codebase, identify patterns and blockers
3. **Plan** - Generate PRD, tasks, and sprints
4. **Execute** - Run with Task Loop quality loop and model escalation
5. **Verify** - Pass all quality gates before completion

### Bug Fixing

```bash
# Fix a local bug (interview → diagnose → fix → verify)
/devteam:bug "Login fails for guest users"

# Fix a GitHub issue
/devteam:issue 123

# Force Bug Council for complex issues
/devteam:bug "Memory leak in image processor" --council
```

### Cost-Optimized Mode

```bash
# Use eco mode (lower-cost models for simpler tasks)
/devteam:implement --eco
/devteam:bug "Minor CSS issue" --eco
```

### Monitoring

```bash
# Check status, costs, progress
/devteam:status

# List plans and tasks
/devteam:list

# Reset stuck sessions
/devteam:reset
```

---

## Configuration

### Task Loop Configuration (`.devteam/task-loop-config.yaml`)

```yaml
loop_settings:
  max_iterations: 10

model_escalation:
  enabled: true
  consecutive_failures:
    haiku_to_sonnet: 2
    sonnet_to_opus: 2
    opus_max_failures: 3  # Then Bug Council

quality_gates:
  required:
    tests_passing: true
    type_check: true
    lint: true
  security:
    on_finding: create_fix_task
```

### Scope Definition (per task)

```yaml
# In task definition
scope:
  allowed_files:
    - "src/auth/*.py"
  allowed_patterns:
    - "tests/auth/**/*.py"
  forbidden_directories:
    - "src/billing/"
    - "src/admin/"
  max_files_changed: 10
```

### Agent Selection (`.devteam/agent-capabilities.yaml`)

```yaml
categories:
  security:
    agents:
      - id: penetration_tester
        triggers:
          keywords: [pentest, security testing, vulnerability]
          task_types: [security_testing]
```

---

## Hooks System

The system uses Claude Code hooks for autonomous execution. **All hooks support both Linux/macOS (Bash) and Windows (PowerShell).**

| Hook | Linux/macOS | Windows | Purpose |
|------|-------------|---------|---------|
| Stop Hook | `stop-hook.sh` | `stop-hook.ps1` | Blocks exit without `EXIT_SIGNAL: true` |
| Persistence Hook | `persistence-hook.sh` | `persistence-hook.ps1` | Detects and prevents abandonment |
| Scope Check | `scope-check.sh` | `scope-check.ps1` | Validates commits stay in scope |
| Pre-Compact | `pre-compact.sh` | `pre-compact.ps1` | Preserves state before context compaction |
| Pre-Tool-Use | `pre-tool-use-hook.sh` | `pre-tool-use-hook.ps1` | Pre-execution validation |
| Post-Tool-Use | `post-tool-use-hook.sh` | `post-tool-use-hook.ps1` | Post-execution logging |
| Session Start | `session-start.sh` | `session-start.ps1` | Session initialization |
| Session End | `session-end.sh` | `session-end.ps1` | Session cleanup |
| Install | `install.sh` | `install.ps1` | Hook installation script |

When installed via the marketplace or as a plugin, all hooks are configured automatically through `hooks/hooks.json`. No manual settings.json editing is required.

See [hooks/README.md](hooks/README.md) for hook details and troubleshooting.

---

## Model Tiers & Cost Optimization

### Automatic Model Selection

| Complexity | Model | Characteristics | Use Case |
|------------|-------|------------------|----------|
| 1-4 | Haiku | Fast, lowest cost | Simple fixes, docs |
| 5-8 | Sonnet | Balanced | Standard features |
| 9-14 | Opus | Most capable, highest cost | Complex architecture |

### Escalation Flow

```
Task starts at complexity-appropriate tier
           │
           ▼
       Attempt #1
           │
       FAIL? ──────────────────┐
           │                   │
           ▼                   ▼
       Attempt #2          Same tier
           │              + more context
       FAIL? ──────────────────┐
           │                   │
           ▼                   ▼
       Attempt #3          Same tier
           │              + alt approach
       FAIL? ──────────────────┐
           │                   │
           ▼                   ▼
       ESCALATE           Upgrade tier
           │              (haiku→sonnet→opus)
           ▼
    Continue with higher tier
```

---

## Architecture

### Complete Flow

```
User Request
     │
     ▼
┌─────────────────┐
│  /devteam:implement  │ ← Automatic agent selection
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   Task Loop     │ ← Iterative quality loop per task
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   TASK LOOP     │ ← Quality loop wrapper
│  ┌───────────┐  │
│  │  Execute  │  │ ← Selected agents work
│  │  Agents   │  │
│  └─────┬─────┘  │
│        │        │
│        ▼        │
│  ┌───────────┐  │
│  │  Quality  │  │ ← Tests, lint, security
│  │   Gates   │  │
│  └─────┬─────┘  │
│        │        │
│    PASS│ FAIL   │
│        │   │    │
│        │   ▼    │
│        │ ┌────┐ │
│        │ │Fix │ │ ← Create fix tasks
│        │ └──┬─┘ │
│        │    │   │
│        │    ▼   │
│        │ Escalate? → Model upgrade if needed
│        │    │   │
│        └────┴───┘
│             │
└─────────────┘
         │
         ▼
   EXIT_SIGNAL: true
```

### Directory Structure

```
.devteam/
├── config.yaml              # Main project configuration
├── task-loop-config.yaml    # Task Loop quality loop config
├── agent-capabilities.yaml  # Agent registry with triggers
├── agent-selection.md       # Selection algorithm docs
├── persistence-config.yaml  # Anti-abandonment rules
├── scope-enforcement.md     # Scope system docs
├── model-selection.md       # Dynamic model assignment
├── parallel-execution.md    # Concurrent task handling
├── plan-management.md       # Plan lifecycle tracking
├── sprint-loop-config.yaml  # Sprint-level validation settings (read by sprint-orchestrator.md, folded in from the deprecated sprint-loop agent)
├── task-loop-config.yaml    # Task execution settings
├── code-review-config.yaml  # Code review standards
├── database-config.yaml     # Database setup
├── frontend-config.yaml     # Frontend-specific settings
├── performance-config.yaml  # Performance audit thresholds
├── test-config.yaml         # Test framework configuration
├── testing-config.yaml      # Test execution config
├── ux-config.yaml           # UX validation rules
├── validation-config.yaml   # Requirements validation rules
├── refactoring-config.yaml  # Refactoring guidelines
├── devteam.db               # SQLite execution state + circuit breaker tracking (runtime)
└── plans/                   # Multi-plan storage (runtime)

agents/
├── orchestration/           # 9 orchestration agents (autonomous-controller.md and sprint-loop.md were deprecated to docs/deprecated/ -- folded into sprint-orchestrator.md)
│   ├── bug-council-orchestrator.md
│   ├── code-review-coordinator.md
│   ├── quality-gate-enforcer.md
│   ├── requirements-validator.md
│   ├── scope-validator.md
│   ├── sprint-orchestrator.md
│   ├── task-loop.md
│   ├── track-merger.md
│   └── workflow-compliance.md
├── planning/                # PRD & sprint planning (3)
├── research/                # Codebase research (1)
├── diagnosis/               # Bug Council agents (5)
├── backend/                 # Backend API developers (16)
├── frontend/                # Frontend developers (3)
├── database/                # Database specialists (12)
├── quality/                 # Testing & QA (26)
├── devops/                  # CI/CD, Docker, K8s (5)
├── mobile/                  # iOS, Android, Flutter, RN (8)
├── security/                # Security & Compliance (10)
├── sre/                     # Site Reliability Engineering (2)
├── ux/                      # Design system agents (12)
├── accessibility/           # A11y specialists (2)
├── architecture/            # System architecture (1)
├── data-ai/                 # Data & ML engineering (2)
├── devrel/                  # Developer advocacy (1)
├── product/                 # Product management (1)
├── specialized/             # Observability (1)
├── support/                 # Dependency management (1)
├── infrastructure/          # Configuration management (1)
├── python/                  # Python utilities (1)
├── scripting/               # Shell & PowerShell (2)
└── templates/
    └── base-agent.md

commands/                    # 20 slash commands
├── devteam-plan.md
├── devteam-implement.md
├── devteam-bug.md
├── devteam-issue.md
├── devteam-issue-new.md
├── devteam-status.md
├── devteam-reset.md
├── devteam-config.md
├── devteam-logs.md
├── devteam-help.md
├── devteam-list.md
├── devteam-select.md
├── devteam-design.md
├── devteam-design-drift.md
├── devteam-review.md
├── devteam-test.md
├── merge-tracks.md
├── worktree-status.md
├── worktree-list.md
└── worktree-cleanup.md

skills/                      # 20 skill definitions (SKILL.md per directory)
├── devteam-plan/
├── devteam-implement/
├── devteam-bug/
├── ... (one directory per command)
└── worktree-cleanup/

.claude/
└── rules/                   # 11 path-specific rule files
    └── *.md

agent-registry.json          # Agent and command registry (125 agents, 20 commands)
settings.json                # Plugin default settings
.mcp.json                    # Bundled MCP server configs (GitHub, Memory)
.lsp.json                    # Language server configs (8 languages)

hooks/                       # Cross-platform hooks
├── stop-hook.sh / .ps1      # Exit control
├── persistence-hook.sh / .ps1
├── scope-check.sh / .ps1
├── pre-compact.sh / .ps1
├── pre-tool-use-hook.sh / .ps1
├── post-tool-use-hook.sh / .ps1
├── session-start.sh / .ps1
├── session-end.sh / .ps1
├── install.sh / .ps1
├── lib/                     # Shared hook utilities
├── tests/                   # Hook test suite
└── README.md

mcp-configs/                 # MCP server configurations
├── required.json
├── recommended.json
├── optional.json
├── lsp-servers.json
└── README.md
```

---

## Commands Reference

### Core Commands

| Command | Description |
|---------|-------------|
| `/devteam:plan` | Interactive planning with interview, research, and sprint generation |
| `/devteam:implement` | Execute plans, sprints, tasks, or ad-hoc work |
| `/devteam:bug "<desc>"` | Fix bugs with diagnostic workflow and Bug Council |
| `/devteam:issue <#>` | Fix GitHub issues with interview if needed |
| `/devteam:status` | Display system health, progress, and costs |
| `/devteam:reset` | Reset stuck sessions and recover from errors |

### Planning Options

```bash
/devteam:plan                      # Interactive planning
/devteam:plan --feature "desc"     # Plan specific feature
/devteam:plan --from spec.md       # Plan from spec file
/devteam:plan --skip-research      # Skip research phase
```

### Implementation Options

```bash
/devteam:implement                 # Execute current plan
/devteam:implement --sprint 1      # Execute specific sprint
/devteam:implement --all           # Execute all sprints
/devteam:implement --task TASK-001 # Execute specific task
/devteam:implement "ad-hoc task"   # One-off task with interview
/devteam:implement --eco           # Cost-optimized mode
```

### Bug Fixing Options

```bash
/devteam:bug "description"         # Fix with interview
/devteam:bug "desc" --council      # Force Bug Council
/devteam:bug "desc" --severity critical
/devteam:bug "desc" --eco          # Cost-optimized
```

### Quality & Review Commands

| Command | Description |
|---------|-------------|
| `/devteam:review` | Run cross-agent code review |
| `/devteam:test` | Run test coordination and execution |
| `/devteam:design` | Design system generation and validation |
| `/devteam:design-drift` | Detect design system drift |

### Management Commands

| Command | Description |
|---------|-------------|
| `/devteam:list` | List plans, sprints, and tasks |
| `/devteam:select <plan>` | Select active plan |
| `/devteam:issue-new "<desc>"` | Create new GitHub issue |
| `/devteam:config` | View and modify configuration |
| `/devteam:logs` | View execution logs |
| `/devteam:help` | Get help on any topic |

### Worktree Commands

| Command | Description |
|---------|-------------|
| `/devteam:worktree-status` | Show worktree status |
| `/devteam:worktree-list` | List all worktrees |
| `/devteam:worktree-cleanup` | Clean up worktrees |
| `/devteam:merge-tracks` | Merge parallel tracks |

See [commands/README.md](commands/README.md) for detailed documentation.

---

## Quality Standards

Every task must pass:

| Gate | Requirement |
|------|-------------|
| **Tests** | 100% of tests passing |
| **Types** | No type errors (mypy, tsc) |
| **Lint** | No lint errors |
| **Security** | No high/critical findings |
| **Coverage** | ≥80% code coverage |
| **Scope** | All changes within scope |

**No task completes without all gates passing.**

---

## Examples

### Example 1: Add Feature

```bash
/devteam:implement "Add user profile page with avatar upload"
```

System automatically:
1. Detects React frontend + FastAPI backend
2. Selects: frontend_developer, api_developer_python, test_writer
3. Creates scoped subtasks for each
4. Executes with Task Loop
5. Security audit on file upload
6. Completes when all tests pass

### Example 2: Fix Bug

```bash
/devteam:implement "Fix: Users can't login after password reset"
```

System automatically:
1. Detects bug-type task
2. Assigns root_cause_analyst first
3. If initial fix fails, activates Bug Council
4. 5 perspectives analyze the issue
5. Synthesized solution implemented
6. Regression tests added

### Example 3: Security Audit

```bash
/devteam:implement "Audit authentication system"
```

System automatically:
1. Selects: security_auditor, penetration_tester, compliance_engineer
2. Runs OWASP Top 10 checks
3. Creates fix tasks for findings
4. Verifies fixes
5. Generates compliance report

---

## Installation

### Install from Claude Code Marketplace (Recommended)

The easiest way to install DevTeam is directly from within Claude Code:

```bash
# 1. Add the DevTeam marketplace
/plugin marketplace add https://github.com/michael-harris/devteam

# 2. Install the plugin
/plugin install devteam@devteam-marketplace

# 3. Verify installation
/devteam:status
```

That's it. The database is auto-initialized on first use. Hooks, agents, skills, and rules are all configured automatically.

### Install from Local Clone (Development)

For contributing or local development:

```bash
# 1. Clone the repository
git clone https://github.com/michael-harris/devteam.git

# 2. Install as a local plugin
/plugin install /path/to/devteam

# 3. Verify installation
/devteam:status
```

### Prerequisites

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code)
- SQLite3
- Bash 4.0+ (Linux/macOS) or PowerShell 5.1+ (Windows)
- Git

### Environment Variable (Agent Teams)

To enable Agent Teams (parallel multi-agent execution), set this environment variable before starting Claude Code:

```bash
export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
```

---

## FAQ

**Q: What stops agents from giving up?**

A: The persistence system detects "give up" language and blocks it, forcing continued effort with escalating re-engagement prompts, model upgrades, and Bug Council activation.

**Q: How does model escalation work?**

A: After 2 consecutive failures at a tier, the model upgrades (haiku→sonnet→opus). After 3 opus failures, Bug Council activates.

**Q: Can agents modify files outside their scope?**

A: No. The scope validator has VETO power and blocks all out-of-scope changes. Agents log observations for out-of-scope issues instead.

**Q: What triggers the Bug Council?**

A: Critical bugs, 3+ failed opus attempts, complexity ≥10, or explicit flag.

**Q: How do I customize agent selection?**

A: Edit `.devteam/agent-capabilities.yaml` to add triggers, keywords, and file patterns.

---

## Contributing

Contributions welcome! Areas of interest:
- Additional language support
- New enterprise agent roles
- Improved selection algorithms
- Integration with more tools

---

## Credits & Acknowledgments

This project draws inspiration from and builds upon several pioneering projects in the AI-assisted development space.

### Direct Inspirations (Claude Code Ecosystem)

These projects directly influenced our design and implementation:

| Project | What We Learned | Link |
|---------|-----------------|------|
| **ralph-claude-code** | The Ralph autonomous loop concept, EXIT_SIGNAL pattern, circuit breaker for stagnation detection, dual-condition exit gates, `.ralph/` directory structure pattern | [github.com/frankbria/ralph-claude-code](https://github.com/frankbria/ralph-claude-code) |
| **everything-claude-code** | Specialized agent delegation pattern, cross-platform hook architecture, subagent orchestration strategies, skill/agent separation | [github.com/affaan-m/everything-claude-code](https://github.com/affaan-m/everything-claude-code) |
| **awesome-claude-skills** | Skill organization patterns, YAML frontmatter structure, category-based skill taxonomy | [github.com/ComposioHQ/awesome-claude-skills](https://github.com/ComposioHQ/awesome-claude-skills) |
| **wshobson/agents** | Tiered model assignment (Opus/Sonnet/Haiku), plugin architecture patterns, token efficiency strategies, 72-plugin modular design | [github.com/wshobson/agents](https://github.com/wshobson/agents) |
| **ui-ux-pro-max-skill** | Design system generation patterns, industry-specific rule sets, Master+Overrides architecture concept | [github.com/nextlevelbuilder/ui-ux-pro-max-skill](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill) |

### What We Built Upon (Our Additions)

While inspired by these projects, we developed original implementations:

| Feature | Inspiration Source | Our Original Addition |
|---------|-------------------|----------------------|
| **Task Loop** | ralph-claude-code's autonomous loop | Added model escalation (haiku→sonnet→opus), Bug Council activation, quality gates integration |
| **Model Escalation** | wshobson/agents tier concept | Automatic escalation after consecutive failures, complexity-based initial selection, de-escalation after success |
| **Bug Council** | Original concept | 5-agent multi-perspective debugging system with synthesized solutions |
| **Scope Enforcement** | Original concept | 6-layer enforcement with VETO power, out-of-scope observations logging |
| **Anti-Abandonment** | Original concept | Persistence hooks detecting "give up" patterns, escalating re-engagement prompts |
| **Agent Selection** | everything-claude-code delegation | Task-aware agent selection based on keywords, file types, task type, and language |
| **Enterprise Agents** | wshobson/agents categories | SRE, Platform Engineer, Compliance Engineer, Penetration Tester, and 8 other enterprise roles |

### Broader Ecosystem Inspirations

| Project | Inspiration | Link |
|---------|-------------|------|
| **Aider** | Iterative code refinement and "linting loops" | [github.com/paul-gauthier/aider](https://github.com/paul-gauthier/aider) |
| **AutoGPT** | Multi-agent orchestration patterns | [github.com/Significant-Gravitas/AutoGPT](https://github.com/Significant-Gravitas/AutoGPT) |
| **MetaGPT** | Role-based agents, "committee of experts" | [github.com/geekan/MetaGPT](https://github.com/geekan/MetaGPT) |
| **GPT-Engineer** | PRD-to-code workflows | [github.com/gpt-engineer-org/gpt-engineer](https://github.com/gpt-engineer-org/gpt-engineer) |
| **Sweep AI** | Automated bug fixing patterns | [github.com/sweepai/sweep](https://github.com/sweepai/sweep) |
| **OpenHands** | Agent-computer interfaces | [github.com/All-Hands-AI/OpenHands](https://github.com/All-Hands-AI/OpenHands) |
| **SWE-agent** | Software engineering agent design | [github.com/princeton-nlp/SWE-agent](https://github.com/princeton-nlp/SWE-agent) |

### Standards & Frameworks Referenced

- **OWASP Top 10** - Security testing methodology
- **WCAG 2.1** - Accessibility compliance standards
- **SOC2/HIPAA/GDPR/PCI-DSS** - Compliance frameworks
- **Google SRE** - Site Reliability Engineering practices
- **The Twelve-Factor App** - Modern application design principles

### Originality Statement

All code in this repository was written from scratch. While we adopted concepts and patterns from the above projects (particularly the Ralph loop concept from frankbria/ralph-claude-code), our implementations are original:

- Our hooks use different file structures (`.devteam/` vs `.ralph/`)
- Our config uses YAML with model escalation (original uses INI without escalation)
- Our agent definitions follow a different structure
- Bug Council, scope enforcement, and anti-abandonment are entirely original systems

---

## License

MIT License - See LICENSE file.

---

**Built for Claude Code**
