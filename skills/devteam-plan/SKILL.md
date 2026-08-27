---
name: devteam-plan
description: Conduct interactive requirements gathering, research the codebase, create a PRD, and generate a development plan with tasks and sprints.
argument-hint: ["description"] [--feature "<desc>"] [--from <path>] [--skip-research] [--skip-interview]
user-invocable: true
allowed-tools: Read, Glob, Grep, Bash, Write, Task
model: opus
---

Current session: !`source "${CLAUDE_PLUGIN_ROOT}/scripts/state.sh" && get_current_session 2>/dev/null || echo "No active session"`
Active sprint: !`source "${CLAUDE_PLUGIN_ROOT}/scripts/state.sh" && get_kv_state "active_sprint" 2>/dev/null || echo "None"`
Failure count: !`source "${CLAUDE_PLUGIN_ROOT}/scripts/state.sh" && get_kv_state "consecutive_failures" 2>/dev/null || echo "0"`

# DevTeam Plan Command

**Command:** `/devteam:plan [options]`

Conduct interactive requirements gathering, research the codebase, create a PRD, and generate a development plan with tasks and sprints.

## Usage

```bash
/devteam:plan                                # Start interactive planning
/devteam:plan "Build a task manager"         # Start with description
/devteam:plan --feature "Add dark mode"      # Plan a feature for existing project
/devteam:plan --from spec.md                 # Load from single spec file
/devteam:plan --from specs/                  # Load from folder of spec files
/devteam:plan --from existing                # Auto-detect existing docs in project
/devteam:plan --skip-research                # Skip research phase
```

## Options

| Option | Description |
|--------|-------------|
| `--feature "<desc>"` | Plan a feature for existing project |
| `--from <path>` | Load from spec file or folder |
| `--skip-research` | Skip codebase research phase |
| `--skip-interview` | Skip interview (use with --from) |
| `--tracks <N>` | Request N parallel development tracks (default: 1) |
| `--worktrees` | Use git worktrees for physical track isolation (only with `--tracks > 1`) |

## File-Based Specification Support

### Supported File Formats

| Format | Extensions | Best For |
|--------|------------|----------|
| Markdown | `.md` | Human-readable specs, PRDs |
| YAML | `.yaml`, `.yml` | Structured specs, existing PRDs |
| JSON | `.json` | API specs, structured data |
| Plain Text | `.txt` | Simple requirements lists |
| PDF | `.pdf` | Formal documents (extracted) |

### Single File Mode (`--from file.md`)

Reads a specification file and extracts:
- Project description
- Features/requirements (from headers, lists)
- Technical constraints
- User stories
- Acceptance criteria

**Example Input (`project-spec.md`):**
```markdown
# Task Manager App

## Overview
A simple task management app for teams.

## Features
- User authentication with OAuth
- Create, edit, delete tasks
- Assign tasks to team members
- Due date reminders

## Technical Requirements
- Backend: FastAPI
- Database: PostgreSQL
- Frontend: React + TypeScript
```

**Process:**
1. Read and parse file
2. Extract structured information
3. Confirm understanding with user (brief)
4. Skip redundant interview questions
5. Generate PRD from extracted data

### Folder Mode (`--from specs/`)

Reads all spec files from a folder and merges them:

```
specs/
├── overview.md           # Project overview
├── features/
│   ├── auth.md          # Authentication spec
│   ├── tasks.md         # Task management spec
│   └── notifications.md # Notification spec
├── api-design.yaml      # API specification
└── wireframes.md        # UI descriptions
```

**Process:**
1. Scan folder recursively
2. Categorize files by type/content
3. Merge into unified understanding
4. Resolve conflicts (ask user if ambiguous)
5. Generate comprehensive PRD

### Auto-Detect Mode (`--from existing`)

Searches project for existing documentation:

**Search locations:**
```
docs/                    # Common docs folder
documentation/           # Alternative name
spec/                    # Spec folder
specifications/          # Alternative name
requirements/            # Requirements folder
*.md in root            # README, CONTRIBUTING, etc.
.github/                # Issue templates, etc.
```

**Process:**
1. Scan project structure
2. Find and list discovered docs
3. Ask user to confirm which to use
4. Parse and extract requirements
5. Fill gaps with brief questions

### File Parsing Examples

**From Markdown with headers:**
```markdown
# Feature: User Authentication

## Requirements
- [ ] OAuth 2.0 support (Google, GitHub)
- [ ] Session management
- [ ] Password reset flow

## Acceptance Criteria
1. User can sign in with Google
2. Session persists for 7 days
3. Password reset email sent within 1 minute
```

Extracted as:
```json
{
  "feature": {
    "name": "User Authentication",
    "requirements": [
      "OAuth 2.0 support (Google, GitHub)",
      "Session management",
      "Password reset flow"
    ],
    "acceptance_criteria": [
      "User can sign in with Google",
      "Session persists for 7 days",
      "Password reset email sent within 1 minute"
    ]
  }
}
```

**From YAML directly:**
```yaml
# Already structured - use as-is
project:
  name: Task Manager
features:
  - name: Authentication
    priority: must_have
```

**From JSON (OpenAPI):**
```json
{
  "openapi": "3.0.0",
  "paths": {
    "/tasks": { "get": {...}, "post": {...} }
  }
}
```

Extract API endpoints as features

### User Confirmation

After parsing file-based specs, always confirm:

```
Loaded specification from: project-spec.md

Extracted:
  - Project: Task Manager App
  - Features: 4 identified
  - Tech Stack: FastAPI + PostgreSQL + React
  - Constraints: None specified

Is this correct? (yes/edit/add more)
```

If `edit`: Allow user to modify extracted data
If `add more`: Continue with remaining interview questions

## Your Process

This command orchestrates PRD generation, task breakdown, and sprint planning by delegating each to its specialist agent (`planning:prd-generator`, `planning:task-graph-analyzer`, `planning:sprint-planner`) via `Task()` calls — it does not reimplement their logic inline. The main session's job is: run the git check, gather requirements and research context, then hand that context to the three planning agents in sequence, each consuming the previous one's output file from disk.

### Phase 0: Git Repository Check (REQUIRED)

Before any planning, verify git repository exists:

```bash
# Check for git repository
git rev-parse --git-dir 2>/dev/null
```

**If NOT a git repository:**

```
Git Repository Required

DevTeam requires a git repository for:
- Change tracking and rollback
- Parallel plan execution (worktrees)
- Safe merge of feature branches
- Circuit breaker recovery

Initialize a git repository now? (yes/no): _
```

If user says **yes**:
```bash
git init
git add .
git commit -m "Initial commit before DevTeam planning"
echo "Git repository initialized"
```

If user says **no**:
```
Cannot proceed without git repository.

To initialize manually:
  git init
  git add .
  git commit -m "Initial commit"

Then run /devteam:plan again.
```

**If git repo exists but has uncommitted changes:**

```
Uncommitted Changes Detected

You have uncommitted changes in your working directory.
It's recommended to commit before planning.

Options:
  1. Commit changes now (recommended)
  2. Stash changes temporarily
  3. Continue anyway (changes tracked but not snapshotted)

Select option (1/2/3): _
```

Option 1:
```bash
git add -A
git commit -m "Pre-planning snapshot"
echo "Changes committed"
```

### Phase 1: Requirements Interview

**Skip if:** `--from` flag provided with comprehensive spec and `--skip-interview` flag.

**Technology Stack Selection (FIRST):**
1. Ask: "What external services, APIs, or integrations will you need?"
2. Based on answer, recommend Python or TypeScript with reasoning:
   - Python: Better for data processing, ML, scientific computing
   - TypeScript: Better for web apps, real-time features, npm ecosystem
3. Confirm with user
4. Document choice

**Requirements Gathering (ONE question at a time):**
1. "What problem are you solving?"
2. "Who are the primary users?"
3. "What are the must-have features?"
4. "What are the nice-to-have features?"
5. "What scale do you expect? (users, data volume)"
6. "Any specific constraints? (timeline, budget, compliance)"
7. "How will you measure success?"

**Be efficient:** If user provides comprehensive initial description, skip questions already answered.

### Phase 2: Research Phase

**Skip if:** `--skip-research` flag provided.

**Purpose:** Investigate the codebase and technologies before planning to:
- Identify existing patterns to follow
- Find potential blockers early
- Make informed technology recommendations
- Prevent "discover problems during implementation" scenarios

**Research Agent Tasks:**

```javascript
// Spawn Research Agent
const researchResults = await Task({
    subagent_type: "research:research-agent",
    model: "opus",
    prompt: `Research for: ${projectDescription}

        Investigate:
        1. CODEBASE ANALYSIS
           - Existing project structure
           - Current tech stack in use
           - Coding patterns and conventions
           - Related existing features

        2. TECHNOLOGY EVALUATION
           - Recommended libraries/frameworks
           - Compatibility with existing stack
           - Community support and maintenance status
           - Security considerations

        3. IMPLEMENTATION PATTERNS
           - Similar features in codebase
           - Patterns to follow
           - Anti-patterns to avoid

        4. POTENTIAL BLOCKERS
           - Technical debt that might interfere
           - Missing dependencies
           - Breaking changes required
           - Integration challenges

        5. RECOMMENDATIONS
           - Suggested approach
           - Alternative approaches considered
           - Risk assessment

        Output structured findings with evidence.`
})
```

**Research Output Format:**

```yaml
research_findings:
  codebase_analysis:
    project_structure: "monorepo with packages/"
    existing_stack:
      backend: "FastAPI"
      frontend: "React + TypeScript"
      database: "PostgreSQL with SQLAlchemy"
    patterns_identified:
      - "Repository pattern for data access"
      - "React Query for server state"
      - "Tailwind for styling"

  technology_evaluation:
    recommended:
      - name: "Zod"
        reason: "Schema validation, already used in 3 places"
        confidence: high
    alternatives_considered:
      - name: "Yup"
        reason: "More verbose, different pattern than existing"
        rejected: true

  implementation_patterns:
    follow:
      - pattern: "Use existing AuthContext for user state"
        location: "src/contexts/AuthContext.tsx"
      - pattern: "API routes follow RESTful conventions"
        location: "src/api/routes/"
    avoid:
      - pattern: "Direct database access in components"
        reason: "Violates existing architecture"

  potential_blockers:
    - blocker: "User table lacks 'preferences' column"
      severity: medium
      resolution: "Migration required before feature"
    - blocker: "Current auth doesn't support OAuth"
      severity: high
      resolution: "Auth refactor needed first"

  recommendations:
    primary_approach: "Extend existing UserService with preferences"
    estimated_complexity: 7
    risks:
      - "OAuth integration more complex than expected"
    prerequisites:
      - "Database migration for user preferences"
```

**Display Research Progress:**

```
Research Phase

Analyzing codebase and technologies...

  Project structure analyzed
  Existing patterns identified (5 found)
  Technology compatibility checked
  2 potential blockers identified
  Recommendations generated

Research Summary:
  - Existing stack: FastAPI + React + PostgreSQL
  - Patterns to follow: Repository pattern, React Query
  - Blockers found: 2 (1 high, 1 medium severity)
  - Recommended approach: Extend existing UserService

Proceeding to follow-up questions...
```

### Phase 3: Follow-up Questions (Research-Informed)

Based on research findings, ask clarifying questions:

```yaml
follow_up_triggers:
  - condition: blocker_found
    question: "Research found {blocker}. Should we address this first, or work around it?"

  - condition: multiple_approaches
    question: "There are two ways to implement this: {approach_a} or {approach_b}. Which do you prefer?"

  - condition: prerequisites_needed
    question: "This feature requires {prerequisite} first. Should we include that in the plan?"

  - condition: technology_choice
    question: "Research suggests using {recommended} because {reason}. Does that work for you?"
```

**Example Follow-up:**

```
Follow-up Questions (from Research)

Research identified some items that need your input:

Q1: A database migration is needed to add user preferences.
    Should we include this in Sprint 1? (yes/no/skip feature)

Q2: Two implementation approaches are possible:
    A) Extend existing UserService (recommended, lower risk)
    B) Create new PreferencesService (cleaner, more work)
    Which approach do you prefer? (a/b)

Q3: OAuth integration is more complex than a simple feature.
    Should we:
    A) Include OAuth in this plan (adds ~2 sprints)
    B) Use existing auth, add OAuth later
    C) Descope to just username/password
    Select option (a/b/c):
```

### Phase 4: Generate PRD

Delegate PRD generation to the PRD Generator agent — it owns the canonical schema (`.devteam/schemas/prd.schema.json`, `.devteam/schemas/features.schema.json`) and the 200+-feature enumeration methodology. Do not write the PRD inline; pass everything gathered in Phases 1-3 so the agent doesn't re-ask what's already known.

```javascript
const prdResult = await Task({
    subagent_type: "planning:prd-generator",
    model: "sonnet",
    prompt: `Generate the Project PRD for: ${projectDescription}

        The following has already been gathered in this session -- do NOT
        re-ask these questions, use them directly. Only ask a follow-up
        question if something critical is still missing or ambiguous.

        TECHNOLOGY STACK (confirmed): ${confirmedStack}

        INTERVIEW ANSWERS:
        - Problem: ${problemAnswer}
        - Primary users: ${usersAnswer}
        - Must-have features: ${mustHaveAnswer}
        - Nice-to-have features: ${niceToHaveAnswer}
        - Scale: ${scaleAnswer}
        - Constraints: ${constraintsAnswer}
        - Success metrics: ${successMetricsAnswer}

        RESEARCH FINDINGS (from research-agent; omit if --skip-research):
        ${researchFindings}

        FOLLOW-UP ANSWERS (research-informed, if any were asked):
        ${followUpAnswers}

        Produce, matching your canonical schemas exactly:
        1. docs/planning/PROJECT_PRD.json
        2. .devteam/features.json (Phase 8 feature enumeration)

        Fold the research findings' recommended_approach, blockers, and
        patterns_identified into the PRD's technical/requirements sections
        rather than discarding them.`
})
```

**If `prdResult` surfaces a missing-information question**, ask the user that specific question, then re-invoke the agent with the answer appended. Never fabricate an answer on the agent's behalf.

### Phase 5: Task Breakdown

Delegate task decomposition to the Task Graph Analyzer agent — it owns the critical-path algorithm, the two-metric (`complexity.score` + `estimated_hours`) sizing, and the design-task emission rule (see `agents/planning/task-graph-analyzer.md`).

```javascript
const taskResult = await Task({
    subagent_type: "planning:task-graph-analyzer",
    model: "sonnet",
    prompt: `Read docs/planning/PROJECT_PRD.json (just generated) and break
        it into tasks.

        Produce, matching .devteam/schemas/task.schema.json exactly:
        1. docs/planning/tasks/TASK-XXX.json -- one file per task
        2. docs/planning/TASK_SUMMARY.md -- task list, dependency chains,
           max parallel tracks, critical path
        3. docs/planning/task-dependency-graph.md -- visual dependency graph

        Apply your design-task emission rule: every task_type "frontend" or
        "fullstack" task must depend on a "design" task covering the same
        feature_ref.`
})
```

### Phase 6: Sprint Planning

Delegate sprint organization to the Sprint Planner agent — it owns the balanced track-assignment algorithm, worktree provisioning, and SQLite state initialization for sprints/tracks/statistics (see `agents/planning/sprint-planner.md`).

```javascript
const sprintResult = await Task({
    subagent_type: "planning:sprint-planner",
    model: "sonnet",
    prompt: `Read all task files from docs/planning/tasks/ and organize
        them into sprints.

        Requested parallel tracks: ${tracksOption || 1}
        Use git worktrees: ${worktreesOption || false}

        Produce, matching .devteam/schemas/sprint.schema.json exactly:
        1. docs/sprints/SPRINT-XXX.json (or SPRINT-XXX-YY.json per track)
        2. docs/sprints/SPRINT_OVERVIEW.md
        3. SQLite state initialized per your own Step 7 (sprints, tracks,
           statistics)`
})
```

### Phase 7: Finalize Project Metadata

Sprint planning above already initializes sprint/track/statistics state. Set the remaining project-level metadata that no planning agent owns:

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/state.sh"

set_kv_state "metadata.project_name" "<project.name from docs/planning/PROJECT_PRD.json>"
set_kv_state "metadata.project_type" "project"   # "feature" when run with --feature
set_kv_state "metadata.created_at" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
set_phase "planning_complete"
```

## Output Summary

After completion, display (populate every bracketed value below by reading the actual PROJECT_PRD.json / TASK-*.json / SPRINT-*.json files the agents above just generated -- never fabricate counts):

```
PROJECT PLAN COMPLETE

Project: [Name]

Technology Stack:
  - Backend: [Language + Framework]
  - Frontend: [Framework]
  - Database: [Database + ORM]

Planning Summary:
  - Requirements: [X] must-have, [Y] should-have
  - Features enumerated: [Z] (.devteam/features.json)
  - Tasks: [N] total tasks
  - Sprints: [M] sprints planned
  - Estimated complexity: [sum of estimated_complexity across sprints]

Files created:
  - docs/planning/PROJECT_PRD.json
  - .devteam/features.json
  - docs/planning/tasks/TASK-*.json ([N] files)
  - docs/planning/TASK_SUMMARY.md
  - docs/planning/task-dependency-graph.md
  - docs/sprints/SPRINT-*.json ([M] files)
  - docs/sprints/SPRINT_OVERVIEW.md
  - .devteam/devteam.db (state initialized)

Research Findings:
  - Patterns to follow: [N] identified
  - Blockers addressed: [N]
  - Approach: [Recommended approach]

Next steps:
  1. Review the PRD and tasks
  2. Run /devteam:implement to start implementation
  3. Or run /devteam:implement --sprint 1 for first sprint only
```

## Parallel Track Planning

When `--tracks <N>` (N > 1) is passed, Phase 6 above hands the track count and `--worktrees` flag straight to `planning:sprint-planner`, which owns the balanced track-assignment algorithm, worktree creation, and the SQLite track-state initialization (`parallel_tracks.*`, `track_info.*`) end to end — see `agents/planning/sprint-planner.md` steps 3, 4, 6.5, and 7. This command does not duplicate that logic inline.

**Note:** Users never need to interact with worktrees directly. The system handles:
- Creation of worktrees when execution begins
- Isolation of track work in separate directories
- Automatic merging when all tracks complete
- Cleanup of worktrees after merge

For debugging worktree issues, advanced users can use:
- `/devteam:worktree status` - View worktree state
- `/devteam:worktree list` - List all worktrees
- `/devteam:implement --show-worktrees` - See worktree operations during execution

## Important Notes

- Ask ONE question at a time
- Be conversational but efficient
- Provide technology recommendations with reasoning
- Don't generate files until you have all required information
- Initialize state in SQLite database (.devteam/devteam.db) for progress tracking
- Research phase prevents costly discoveries during implementation
- Parallel tracks are automatically managed with git worktrees (hidden from users)

## See Also

- `/devteam:implement` - Execute the plan
- `/devteam:list` - List available plans
- `/devteam:status` - Check planning status
