# Directory Structure Reference

This document describes the directory structure of the DevTeam plugin and the files it creates in your project.

## Plugin Structure

```
devteam/
├── agent-registry.json         # Agent and command registry (125 agents, 20 commands)
├── README.md                   # Main documentation
│
├── commands/                   # Slash command definitions
│   ├── devteam-plan.md         # /devteam:plan
│   ├── devteam-implement.md    # /devteam:implement
│   ├── devteam-bug.md          # /devteam:bug
│   ├── devteam-issue.md        # /devteam:issue
│   ├── devteam-status.md       # /devteam:status
│   ├── devteam-reset.md        # /devteam:reset
│   ├── devteam-config.md       # /devteam:config
│   ├── devteam-logs.md         # /devteam:logs
│   ├── devteam-help.md         # /devteam:help
│   ├── devteam-list.md         # /devteam:list
│   ├── devteam-select.md       # /devteam:select
│   ├── devteam-issue-new.md    # /devteam:issue-new
│   ├── devteam-design.md       # /devteam:design
│   ├── devteam-design-drift.md # /devteam:design-drift
│   ├── devteam-review.md       # /devteam:review
│   ├── devteam-test.md         # /devteam:test
│   ├── merge-tracks.md         # [Debug] /devteam:merge-tracks
│   ├── worktree-status.md      # [Debug] /devteam:worktree-status
│   ├── worktree-list.md        # [Debug] /devteam:worktree-list
│   └── worktree-cleanup.md     # [Debug] /devteam:worktree-cleanup
│
├── skills/                    # Skill definitions (20 skills)
│   ├── devteam-plan/SKILL.md
│   ├── devteam-implement/SKILL.md
│   ├── devteam-bug/SKILL.md
│   ├── ... (one directory per command, each with SKILL.md)
│   └── worktree-cleanup/SKILL.md
│
├── .claude/
│   └── rules/                 # Path-specific rule files (11)
│       └── *.md
│
├── settings.json              # Default settings, env flags, hooks config
├── .mcp.json                  # Bundled MCP server configs (GitHub, Memory)
├── .lsp.json                  # Language server configs (8 languages)
│
├── agents/                     # Agent definitions (125 agents)
│   ├── planning/               # Planning agents (3)
│   │   ├── prd-generator.md
│   │   ├── task-graph-analyzer.md
│   │   └── sprint-planner.md
│   ├── orchestration/          # Orchestration agents (9; autonomous-controller.md and sprint-loop.md deprecated to docs/deprecated/, folded into sprint-orchestrator.md)
│   │   ├── bug-council-orchestrator.md
│   │   ├── code-review-coordinator.md
│   │   ├── quality-gate-enforcer.md
│   │   ├── requirements-validator.md
│   │   ├── scope-validator.md
│   │   ├── sprint-orchestrator.md
│   │   ├── task-loop.md
│   │   ├── track-merger.md
│   │   └── workflow-compliance.md
│   ├── research/               # Research agents (1)
│   │   └── research-agent.md
│   ├── diagnosis/              # Bug Council diagnosis (5)
│   │   ├── root-cause-analyst.md
│   │   ├── code-archaeologist.md
│   │   ├── pattern-matcher.md
│   │   ├── systems-thinker.md
│   │   └── adversarial-tester.md
│   ├── backend/                # Backend agents (16)
│   │   ├── api-designer.md
│   │   ├── api-design-reviewer.md
│   │   ├── api-developer-{lang}.md  # 7 languages
│   │   └── backend-code-reviewer-{lang}.md  # 7 languages
│   ├── frontend/               # Frontend agents (3)
│   │   ├── frontend-designer.md
│   │   ├── frontend-developer.md
│   │   └── frontend-code-reviewer.md
│   ├── database/               # Database agents (12)
│   │   ├── database-designer.md
│   │   ├── database-developer-{lang}.md  # 9 languages
│   │   ├── sql-code-reviewer.md
│   │   └── nosql-code-reviewer.md
│   ├── quality/                # Quality agents (26)
│   │   ├── test-coordinator.md
│   │   ├── test-writer.md
│   │   ├── unit-test-writer-{lang}.md  # 7 languages
│   │   ├── e2e-tester.md
│   │   ├── mobile-e2e-tester.md
│   │   ├── mobile-test-writer.md
│   │   ├── performance-auditor-{lang}.md  # 9 languages
│   │   ├── refactoring-coordinator.md
│   │   ├── runtime-verifier.md
│   │   ├── security-auditor.md
│   │   ├── documentation-coordinator.md
│   │   └── visual-verification-agent.md
│   ├── devops/                 # DevOps agents (5)
│   │   ├── cicd-specialist.md
│   │   ├── docker-specialist.md
│   │   ├── kubernetes-specialist.md
│   │   ├── terraform-specialist.md
│   │   └── mobile-cicd-specialist.md
│   ├── mobile/                 # Mobile agents (8)
│   │   ├── android-developer.md
│   │   ├── ios-developer.md
│   │   ├── flutter-developer.md
│   │   ├── react-native-developer.md
│   │   ├── android-designer.md
│   │   ├── ios-designer.md
│   │   ├── android-code-reviewer.md
│   │   └── ios-code-reviewer.md
│   ├── scripting/              # Scripting agents (2)
│   │   ├── shell-developer.md
│   │   └── powershell-developer.md
│   ├── infrastructure/         # Infrastructure agents (1)
│   │   └── configuration-manager.md
│   ├── python/                 # Python generic agents (1)
│   │   └── python-developer-generic.md
│   ├── accessibility/          # Accessibility agents (2)
│   │   ├── accessibility-specialist.md
│   │   └── mobile-accessibility-specialist.md
│   ├── architecture/           # Architecture agents (1)
│   │   └── architect.md
│   ├── data-ai/                # Data & AI agents (2)
│   │   ├── data-engineer.md
│   │   └── ml-engineer.md
│   ├── devrel/                 # Developer Relations agents (1)
│   │   └── developer-advocate.md
│   ├── product/                # Product agents (1)
│   │   └── product-manager.md
│   ├── security/               # Security agents (10)
│   │   ├── penetration-tester.md
│   │   ├── compliance-engineer.md
│   │   ├── mobile-security-auditor.md
│   │   └── security-auditor-{lang}.md  # 7 languages
│   ├── specialized/            # Specialized agents (1)
│   │   └── observability-engineer.md
│   ├── sre/                    # Site Reliability agents (2)
│   │   ├── site-reliability-engineer.md
│   │   └── platform-engineer.md
│   ├── support/                # Support agents (1)
│   │   └── dependency-manager.md
│   ├── ux/                     # UX agents (12)
│   │   ├── design-system-architect.md
│   │   ├── design-system-orchestrator.md
│   │   ├── ux-system-coordinator.md
│   │   ├── ux-specialist-{platform}.md  # 3 platforms
│   │   ├── design-drift-detector.md
│   │   ├── color-palette-specialist.md
│   │   ├── typography-specialist.md
│   │   ├── data-visualization-designer.md
│   │   ├── design-compliance-validator.md
│   │   └── ui-style-curator.md
│   └── templates/              # Agent templates (1)
│       └── base-agent.md
│
├── hooks/                      # Lifecycle hooks
│   ├── stop-hook.sh / .ps1     # Stop/completion hook
│   ├── persistence-hook.sh / .ps1  # State persistence
│   ├── scope-check.sh / .ps1   # Scope validation
│   ├── pre-compact.sh / .ps1   # Pre-context-compaction
│   ├── pre-tool-use-hook.sh / .ps1  # Pre-execution validation
│   ├── post-tool-use-hook.sh / .ps1 # Post-execution logging
│   ├── session-start.sh / .ps1 # Session initialization
│   ├── session-end.sh / .ps1   # Session cleanup
│   ├── install.sh / .ps1       # Hook installation
│   ├── lib/                    # Shared hook utilities
│   │   ├── hook-common.sh
│   │   └── hook-common.ps1
│   ├── tests/                  # Hook test suite
│   │   └── test-hooks.sh
│   └── README.md
│
├── templates/                  # Templates
│   └── interview-questions.yaml  # Interview question templates
│
├── scripts/                    # Utility scripts
│   ├── schema.sql              # SQLite database schema (v1)
│   ├── schema-v2.sql           # Schema migration v2
│   ├── schema-v3.sql           # Schema migration v3
│   ├── schema-v4.sql           # Schema migration v4
│   ├── db-init.sh              # Database initialization (Linux/macOS)
│   ├── db-init.ps1             # Database initialization (Windows)
│   ├── db-maintenance.sh       # Database cleanup and optimization
│   ├── state.sh                # State management functions (Bash)
│   ├── state.ps1               # State management functions (PowerShell)
│   ├── events.sh               # Event logging functions
│   ├── baseline.sh             # Baseline commit management
│   ├── checkpoint.sh           # Full agent state snapshots
│   ├── cost-tracking.sh        # API cost monitoring
│   ├── progress.sh             # Session progress tracking
│   ├── rollback.sh             # Auto-detect and revert regressions
│   ├── validate-config.sh      # Config file validation
│   ├── init-generator.sh       # Generate init.sh for dev server
│   └── lib/                    # Shared script utilities
│       ├── common.sh
│       └── progress.sh
│
├── examples/                   # Usage examples
│   ├── complete-workflow-example.md
│   ├── parallel-tracks-example.md
│   ├── individual-agent-usage.md
│   ├── api-first-fullstack-workflow.md
│   └── multi-language-examples.md
│
└── docs/                       # Documentation
    ├── GETTING_STARTED.md      # New user guide
    ├── DIRECTORY_STRUCTURE.md  # This file
    ├── SQLITE_SCHEMA.md        # Database schema docs
    ├── TROUBLESHOOTING.md      # Problem solving guide
    ├── releases/               # Release changelogs
    │   ├── ENHANCEMENTS_V2.1.md
    │   ├── ENHANCEMENTS_V2.5.md
    │   └── ENHANCEMENTS_V3.0.md
    └── development/            # Development docs
        └── *.md
```

## Project Files Created

When you use DevTeam, it creates files in your project:

```
your-project/
├── .devteam/                   # DevTeam data directory
│   ├── devteam.db              # SQLite database
│   │   ├── sessions            # Execution sessions
│   │   ├── events              # Event history
│   │   ├── agent_runs          # Agent performance
│   │   ├── gate_results        # Quality gate results
│   │   ├── interviews          # Interview responses
│   │   ├── research_findings   # Research results
│   │   ├── bugs                # Bug tracking
│   │   └── escalations         # Model escalations
│   ├── task-loop-config.yaml   # Configuration file
│   ├── sprint-loop-config.yaml # Sprint-level validation settings (read by sprint-orchestrator.md)
│   ├── task-loop-config.yaml   # Task loop settings
│   ├── test-config.yaml        # Test execution config
│   ├── testing-config.yaml     # Testing strategy config
│   ├── code-review-config.yaml # Code review settings
│   ├── database-config.yaml    # Database preferences
│   ├── frontend-config.yaml    # Frontend settings
│   ├── performance-config.yaml # Performance thresholds
│   ├── refactoring-config.yaml # Refactoring rules
│   ├── ux-config.yaml          # UX design settings
│   └── validation-config.yaml  # Validation rules
│
├── docs/
│   ├── planning/               # Planning artifacts
│   │   ├── PROJECT_PRD.json    # Product Requirements Document
│   │   └── tasks/              # Task definitions
│   │       ├── TASK-001.json
│   │       ├── TASK-002.json
│   │       └── ...
│   └── sprints/                # Sprint definitions
│       ├── SPRINT-001.json
│       ├── SPRINT-002.json
│       └── ...
│
└── .multi-agent/               # Worktrees (temporary, auto-managed)
    ├── track-01/               # Track 1 worktree
    ├── track-02/               # Track 2 worktree
    └── ...
```

## File Descriptions

### `.devteam/devteam.db`
SQLite database containing all runtime state. See [SQLITE_SCHEMA.md](SQLITE_SCHEMA.md) for details.

### `.devteam/task-loop-config.yaml`
Configuration file for DevTeam behavior:

```yaml
version: "3.0"

execution:
  mode: normal          # normal | eco
  max_iterations: 10
  parallel_gates: true

models:
  default_tier: auto
  escalation_threshold: 2
  eco_threshold: 4

gates:
  tests:
    enabled: true
    command: auto
  lint:
    enabled: true
  typecheck:
    enabled: true
  security:
    enabled: false
```

### `docs/planning/PROJECT_PRD.json`
Product Requirements Document generated during planning:

```json
{
  "version": "1.0",
  "project_name": "My Project",
  "created": "2026-01-29",
  "technology_stack": {
    "primary_language": "typescript",
    "backend_framework": "express",
    "frontend_framework": "react",
    "database": "postgresql"
  },
  "problem_statement": "Description of the problem being solved",
  "features": {
    "must_have": [
      {
        "id": "F001",
        "name": "Feature name",
        "acceptance_criteria": [
          "Criterion 1"
        ]
      }
    ]
  }
}
```

### `docs/planning/tasks/TASK-XXX.json`
Individual task definitions:

```json
{
  "id": "TASK-001",
  "title": "Implement user authentication",
  "description": "Create login and registration endpoints",
  "feature_ref": "F001",
  "task_type": "backend",
  "complexity": {
    "score": 6,
    "tier": "moderate"
  },
  "dependencies": [],
  "acceptance_criteria": [
    "Users can register",
    "Users can login"
  ]
}
```

### `docs/sprints/SPRINT-XXX.json`
Sprint definitions grouping tasks:

```json
{
  "id": "SPRINT-001",
  "name": "Foundation",
  "goal": "Set up core infrastructure",
  "tasks": [
    "TASK-001",
    "TASK-002"
  ],
  "estimated_complexity": 12,
  "quality_gates": [
    "All tests pass",
    "No type errors"
  ]
}
```

## Temporary Files

### `.multi-agent/`
Contains git worktrees for parallel track execution. This directory is:
- Created automatically when executing multi-track plans
- Managed entirely by DevTeam (users don't interact with it)
- Cleaned up automatically after merge
- Safe to delete if empty

## Gitignore Recommendations

Add to your `.gitignore`:

```gitignore
# DevTeam
.devteam/devteam.db
.devteam/devteam.db-journal
.devteam/devteam.db-wal
.multi-agent/

# Keep config in version control
!.devteam/task-loop-config.yaml
```

## Cleaning Up

To remove all DevTeam files:

```bash
# Remove state (keeps config)
rm .devteam/devteam.db*

# Full removal
rm -rf .devteam/
rm -rf .multi-agent/
rm -rf docs/planning/
rm -rf docs/sprints/
```

To reinitialize, simply delete the database and run any DevTeam command — the database is auto-created on first use:

```bash
rm .devteam/devteam.db*
/devteam:status
```
