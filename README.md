# DevTeam: A Whole Software Team, Made of AI Agents

DevTeam is a plugin for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that turns Claude into an entire software development team — not one assistant, but **126 specialized AI "employees,"** each with a written job description, working together to plan, build, test, and ship software.

You don't need to know anything about AI to understand this document. Read on.

---

## 1. The Simplest Explanation

Imagine a mid-size tech company's engineering department. It's not one person doing everything — it's:

- A **Product Manager** who turns a rough idea into a written spec
- **Engineers** split by specialty (backend, frontend, mobile, database...)
- **QA/Testers** who won't sign off until things actually work
- A **Security team** that audits before release
- **Code reviewers** who check every pull request
- An **Engineering Manager** who assigns work, tracks progress, and won't let anyone quietly abandon a task
- A **war room** ("Bug Council") that gets called in when a bug is nasty enough that one person can't crack it alone

**DevTeam is that department, except every "employee" is an AI agent, and the "employee handbook" for each one is a Markdown (`.md`) text file that tells it exactly what its job is, what it's allowed to touch, and how to do the work.**

There is no separate program running behind the scenes pulling the strings. **Claude Code itself is the manager** — it reads these job-description files, decides who's needed for a given task, and has them do the work, one after another or in parallel, the same way a manager reads résumés and assigns tickets.

---

## 2. What DevTeam Actually Is (Facts, Not Marketing)

- It is a **Claude Code plugin** — a folder of files that Claude Code loads and follows. It is not a separate app, server, or website.
- It ships **126 agent files** (`agents/**/*.md`), each one a job description for one kind of specialist (e.g. "Python backend developer," "security auditor," "accessibility specialist").
- It ships **20 slash commands** (`/devteam:plan`, `/devteam:implement`, `/devteam:bug`, etc.) that a human types to kick off work.
- It keeps track of everything — sessions, costs, which agent did what, pass/fail results — in a local **SQLite database** (`.devteam/devteam.db`) that lives inside your own project.
- It uses **hooks** (small scripts that run automatically at certain moments, like "when a session starts" or "when someone tries to stop early") to enforce its own rules without a human having to police it.
- **Everything runs on your machine, inside your own project.** Nothing is uploaded anywhere except the normal calls Claude Code already makes to run the AI model.

---

## 3. The Complete Workflow — Every Step and Every Agent, by Name

This section is not a simplified summary — every agent name below is a literal `subagent_type` dispatched via a real `Task()` call in this repository's own command/agent files (`commands/*.md`, `skills/*/SKILL.md`, `agents/orchestration/*.md`). Nothing here is inferred or assumed; you can grep for `subagent_type:` in this repo and find every one of these calls yourself.

### 3.1 Planning — `/devteam:plan`

```
/devteam:plan
    │
    ▼
Phase 0: Git repo check           (main session — no agent; requires a git repo to exist)
    │
    ▼
Phase 1: INTERVIEW                (main session — no agent; asks you questions one at a time;
    │                              skipped only with --skip-interview)
    ▼
Phase 2: RESEARCH        ───►  Task( research:research-agent, model: opus )
    │                          reads your actual codebase, evaluates tech choices, finds blockers
    ▼
Phase 3: Follow-up questions      (main session, based on what research found)
    │
    ▼
Phase 4: PRD GENERATED   ───►  Task( planning:prd-generator, model: sonnet )
    │                          writes docs/planning/PROJECT_PRD.json + .devteam/features.json
    ▼
Phase 5: TASKS            ───►  Task( planning:task-graph-analyzer, model: sonnet )
    │                          writes docs/planning/tasks/TASK-XXX.json (one per task),
    │                          assigns each task's suggested_agent, and — if a task is
    │                          frontend/fullstack — makes it depend on a "design" task
    ▼
Phase 6: SPRINTS          ───►  Task( planning:sprint-planner, model: sonnet )
    │                          writes docs/sprints/SPRINT-XXX.json, groups tasks into sprints/
    │                          tracks, and initializes sprint/track state in .devteam/devteam.db
    ▼
Phase 7: .devteam/devteam.db      (main session writes final project metadata via state.sh;
                                    marks phase "planning_complete")
```

### 3.2 Implementation — `/devteam:implement`

```
/devteam:implement
    │
    ▼
Phase 0: New row created in .devteam/devteam.db's `sessions` table
    │
    ▼
Phase 1: Target decided — a single --task, a --sprint, --all sprints, the active plan, or an ad-hoc description
    │
    ▼
Phase 2: INTERVIEW for ad-hoc tasks only   (main session — only if the description is ambiguous)
    │
    ▼
Phase 3: WHICH AGENT IMPLEMENTS IT?
    │    • Task from a plan  → suggested_agent was already decided back in Phase 5 of planning,
    │                          by planning:task-graph-analyzer (e.g. backend:api-developer-python,
    │                          frontend:developer, database:developer-typescript — whichever
    │                          matches that task's language/type; full roster in §9)
    │    • Ad-hoc task       → resolved right now, in this order, first match wins:
    │                          1. your explicit --type flag (e.g. --type security)
    │                          2. a keyword match, e.g. "security" → quality:security-auditor,
    │                             "refactor" → quality:refactoring-coordinator,
    │                             "bug"/"fix" → diagnosis:root-cause-analyst
    │                          3. otherwise, inferred from file types/language, same as a planned task
    ▼
Phase 4: Starting AI model tier picked by task complexity score (see §12) — haiku / sonnet / opus
    │
    ▼
Phase 5: EXECUTE — routed to exactly one of:
    │    • single task/ad-hoc  → Task( orchestration:task-loop, model: opus )         → see §3.3
    │    • sprint / --all / plan → Task( orchestration:sprint-orchestrator, model: opus ) → see §3.4
```

### 3.3 Inside the Task Loop — runs once for every single task

`orchestration:task-loop` is dispatched either directly by `/devteam:implement` (a single task) or once per task by `orchestration:sprint-orchestrator` (inside a sprint). Either way, the sequence it runs is identical:

| Step | Agent dispatched | Model | What it checks / does |
|---|---|---|---|
| 1. Implementation | `{suggested_agent}` from Phase 3 above | starts at complexity-based tier, escalates one tier after 2 consecutive failures | Writes the actual code; must emit a `[TASK-XXX-COMPLETION]` self-review before finishing |
| 1.5 Scope Validation | `orchestration:scope-validator` | haiku | Has **veto power** — checks the git diff against the task's allowed/forbidden file list; on fail, out-of-scope files are reverted and the implementer re-runs before anything else proceeds |
| 2. Quality Gates | `orchestration:quality-gate-enforcer` | opus | Runs tests, type-checking, lint, security scan, and checks the self-review from Step 1 was real, not generic |
| 3. Requirements Validation | `orchestration:requirements-validator` | opus | Checks the task's actual acceptance criteria were met, not just "tests pass" |
| 3.5 Workflow Compliance | `orchestration:workflow-compliance` | opus | Only runs once Steps 2 and 3 both PASS — verifies every required agent above was actually called with real evidence, and no step was shortcut or faked |
| 4. Execution Ledger | `orchestration:execution-ledger` | haiku | Runs once the task reaches a final state (done or failed); writes `devteam-reports/tasks/TASK-XXX.md`. Best-effort only — never blocks or changes the task's real pass/fail result |

**If Step 2, 3, or 3.5 fails:** the failure count goes up, a fix context is built from the failure, and Step 1 runs again — up to **10 iterations**, escalating the AI model tier (haiku→sonnet→opus) after every 2 consecutive failures at the current tier.

**If the top-tier (opus) model fails 3 times in a row, or the loop is stuck:** `orchestration:bug-council-orchestrator` (opus) is dispatched, which runs all 5 diagnosis agents **in parallel, all at opus**: `diagnosis:root-cause-analyst`, `diagnosis:code-archaeologist`, `diagnosis:pattern-matcher`, `diagnosis:systems-thinker`, `diagnosis:adversarial-tester`. Their combined diagnosis names a `recommended_fix.suggested_agent`, which then runs a brand-new implementation attempt at opus — going through Steps 1.5, 2, 3, and 3.5 again in full; nothing is skipped just because the Bug Council was involved.

### 3.4 Sprint-Level Validation — runs once, after every task in a sprint is done

`orchestration:sprint-orchestrator` dispatches `orchestration:task-loop` once per task in the sprint (§3.3, in dependency order, parallelizing tasks that don't depend on each other). Once **every** task in the sprint has reached a final state, it runs 8 sprint-wide sub-checks, in this exact order, before the sprint can close:

| Step | Agent dispatched | Model |
|---|---|---|
| 4.1 Integration | `quality:runtime-verifier` | sonnet |
| 4.2 Security | `quality:security-auditor` (+ the matching `security:security-auditor-{language}`) | opus |
| 4.3 Hybrid testing *(only if the sprint touched frontend files)* | `quality:e2e-tester`, then `quality:visual-verification` | sonnet, opus |
| 4.4 Performance | `quality:performance-auditor-{language}` | sonnet |
| 4.5 Requirements (sprint-wide) | `orchestration:requirements-validator` | opus |
| 4.6 Documentation | `quality:documentation-coordinator` | haiku |
| 4.7 Code review | `orchestration:code-review-coordinator` | opus |
| 4.8 Workflow compliance | `orchestration:workflow-compliance` | opus |

If any sub-check fails, a fix task is created and sent back through `orchestration:task-loop` (§3.3), then that specific sub-check is re-run — the sprint does not close until all 8 pass. Once they do, `orchestration:execution-ledger` (haiku) renders `devteam-reports/sprints/SPRINT-XXX.md`.

### 3.5 The One-Line Version

```
/devteam:plan → interview → research-agent → prd-generator → task-graph-analyzer → sprint-planner
    → .devteam/devteam.db (plan + sprint state saved)
    → /devteam:implement → agent selection ({suggested_agent}) → task-loop
        → implementer → scope-validator → quality-gate-enforcer → requirements-validator
        → workflow-compliance → execution-ledger
    → (once every task in the sprint is done) → sprint-orchestrator's 8-step sprint validation
        → execution-ledger → devteam-reports/
```

**Every single arrow above writes to `.devteam/devteam.db`** — every agent dispatch, pass, fail, and retry is logged there the moment it happens (`scripts/events.sh`'s `log_agent_started`/`log_agent_completed`/`log_agent_failed`), which is what `/devteam:status` reads from and what `execution-ledger` turns into the reports in `devteam-reports/`.

---

## 4. The Quality Loop ("Task Loop") — Explained Like a Performance Review

Real engineering teams don't accept work on the first draft. DevTeam enforces the same discipline mechanically:

```
Do the work  →  Run the checks (tests, types, lint, security)
    ↑                        │
    │                     Failed?
    │                        ↓
    └──── Try again, with a smarter/more careful model if it keeps failing
```

- If the same AI model fails a task **twice in a row**, DevTeam automatically "promotes" the work to a more capable model — the equivalent of handing a stuck ticket to a senior engineer instead of a junior one.
- The tiers, cheapest to most capable, are **Haiku → Sonnet → Opus**. Simple tasks (typo fixes, docs) stay on the cheap tier; complex or security-sensitive work is *always* sent straight to the top tier.
- There's a hard cap of **10 attempts** per task. If it's still failing after that, a human gets notified — but the agents keep trying rather than silently giving up (see the anti-abandonment system below).
- A task cannot be marked "complete" unless it passes **every** required check: tests, type-checking, lint, security, and staying within its assigned scope of files.

---

## 5. When a Bug Is Too Hard for One Agent: The "Bug Council"

For everyday bugs, one specialist agent handles it. But for a genuinely hard bug — the kind where one engineer keeps guessing wrong — real teams pull people into a room together. DevTeam's version is the **Bug Council**: five specialist agents look at the *same* bug from five different angles at once, then a synthesized fix is produced from all five perspectives.

| Council Member | What they look for (real-world equivalent) |
|---|---|
| **Root Cause Analyst** | Reads the error/stack trace like a debugger would |
| **Code Archaeologist** | Checks git history — "did a recent change cause this?" |
| **Pattern Matcher** | "Have we seen this exact bug shape somewhere else in the codebase?" |
| **Systems Thinker** | Looks at how components/services depend on each other |
| **Adversarial Tester** | Tries to break it — edge cases, malicious input, security angles |

**The Council is automatically called in when:** the bug is marked critical/high severity, the top-tier AI model has already failed 3+ times, the task is unusually complex, or a human explicitly asks for it (`--council`).

---

## 6. Guardrails: Keeping Agents Honest

A real company doesn't let a new hire touch the production database or the billing system on day one. DevTeam enforces the same kind of boundaries automatically, in **six layers** so that no single failure lets an agent go off-script:

1. Every task is given a written **scope** — an explicit allow-list of files/folders it may touch, a forbidden list, and a max number of files it may change.
2. That scope is baked directly into the instructions the agent receives.
3. A dedicated **Scope Validator** agent has **veto power** — it can reject a change even if the work is otherwise correct.
4. A pre-commit hook physically blocks a commit that touches forbidden files.
5. Runtime file-access checks catch violations as they happen, not just at commit time.
6. Anything an agent *noticed* was out of scope (but didn't touch) gets logged for a human to review later, instead of being silently ignored.

**Anti-abandonment:** Agents are also not allowed to just say "this is too hard, I give up." That kind of language is detected and blocked; the agent is re-prompted to keep working, then escalated to a stronger model, then to the Bug Council, and only after all of that does a human get pinged — and even then, the system keeps trying rather than stopping.

---

## 7. The Paper Trail: Reports and Cost Tracking

Every AI model call costs real money and takes real time — DevTeam treats that like a contractor's timesheet, not a mystery bill:

- Every agent run is logged to the local SQLite database: which agent, which AI model tier, how long it took, tokens used, and cost.
- A dedicated reporting agent (**Execution Ledger**) turns that raw data into readable Markdown reports under `devteam-reports/` — one file per task, one per sprint, plus a running `INDEX.md` dashboard. These reports are meant to be kept and reviewed later (they're checked into your project, unlike the raw database).
- `/devteam:status` shows you system health, current progress, and cost at any time, from your terminal.

---

## 8. Keeping the Org Chart Honest: Agent-Wiring Governance

One risk in a system this large: an agent's job description could exist on paper but never actually get assigned any work — like an employee who was hired, given a desk, and then forgotten. DevTeam has an automated check (`scripts/validate-agent-wiring.sh`, run in CI) that scans the entire repository and fails the build if any agent capable of delegating work to others has **zero real callers**. This isn't hypothetical: a live audit of this project using that exact check found and fixed a real orphaned agent (`quality:refactoring-coordinator`) that looked wired up in documentation but was never actually reachable — proof the check does real work, not just theater.

---

## 9. Meet the Team: What the 126 Agents Actually Cover

Every category below maps to a real job function you'd find on an engineering org chart:

| Category | Real-world equivalent | What they do here |
|---|---|---|
| **Orchestration** (10 agents) | Engineering managers, tech leads | Assign work, run the quality loop, enforce scope, merge parallel work, generate reports |
| **Planning** (3 agents) | Product managers, program managers | Turn ideas into PRDs, tasks, and sprints |
| **Research** (1 agent) | Tech lead doing discovery | Reads your codebase before anyone writes new code |
| **Diagnosis / Bug Council** (5 agents) | Senior incident-response engineers | Multi-angle bug diagnosis (see §5) |
| **Backend** (16 agents) | Backend engineers, one per language/stack | Python, TypeScript, Go, Java, C#, Ruby, PHP APIs |
| **Frontend** (3 agents) | Frontend/UI engineers | React/Vue components, UI review |
| **Database** (12 agents) | DBAs, data engineers | Schema design, migrations, query review (SQL + NoSQL) |
| **Quality** (26 agents) | QA engineers, test engineers, SRE | Unit/integration/E2E tests, performance audits, security scans, accessibility, documentation |
| **DevOps** (5 agents) | Platform/DevOps engineers | Docker, Kubernetes, CI/CD, Terraform, mobile CI/CD |
| **Mobile** (8 agents) | iOS/Android engineers | Native iOS, Android, Flutter, React Native |
| **Security** (10 agents) | Security engineers | Penetration testing, compliance (SOC2/HIPAA/GDPR/PCI-DSS), per-language security auditing |
| **SRE** (2 agents) | Site reliability engineers | Incident response, observability, internal platform tooling |
| **UX / Design** (12 agents) | Product designers | Design systems, typography, color, data visualization, drift detection |
| **Accessibility** (2 agents) | Accessibility specialists | WCAG compliance, screen-reader support |
| **Architecture** (1 agent) | Staff/principal engineer | High-level system design decisions |
| **Data & AI** (2 agents) | Data/ML engineers | Data pipelines, ML model integration |
| **Product** (1 agent) | Product manager | Requirements and stakeholder-style communication |
| **DevRel** (1 agent) | Developer advocate | Docs and developer-facing content |
| **Support / Infra / Scripting** (5 agents) | Tooling/support engineers | Dependency updates, configuration, shell/PowerShell scripting |

*(Full breakdown by file: see [docs/DIRECTORY_STRUCTURE.md](docs/DIRECTORY_STRUCTURE.md).)*

---

## 10. Working on Multiple Things at Once (Parallel Tracks)

For a large plan, DevTeam can split work into independent **tracks** (e.g. "Track 1: Backend API," "Track 2: Frontend," "Track 3: Infrastructure") that run in isolated git **worktrees** — think of it as three engineers each working on their own branch/checkout of the repo at the same time, with a dedicated **Track Merger** agent responsible for combining everyone's work back together at the end, the way a lead engineer resolves merge conflicts when several people's branches land at once.

```bash
/devteam:plan "E-commerce platform" --tracks 3 --worktrees
/devteam:implement --all       # runs all tracks, merges automatically when done
```

---

## 11. Quick Start

### Install

```bash
# From the Claude Code marketplace
/plugin marketplace add https://github.com/Winnie-Bodhrik/devteam
/plugin install devteam@devteam-marketplace

# Verify it's installed
/devteam:status
```

Nothing else to set up — the local database, hooks, agents, and skills are configured automatically on first use.

### Plan and build a feature

```bash
/devteam:plan --feature "Add user authentication with OAuth"
/devteam:implement
```

### Fix a bug

```bash
/devteam:bug "Login fails for guest users"
/devteam:issue 123                      # fix a GitHub issue by number
/devteam:bug "Memory leak" --council    # force the 5-agent Bug Council
```

### Watch costs

```bash
/devteam:implement --eco   # use cheaper models for simple work
/devteam:status --costs    # see what's been spent so far
```

---

## 12. Cost & Model Tiers, in Plain Terms

Not every task deserves your most expensive engineer. DevTeam scores each task's complexity (0–14) and picks a starting AI model tier accordingly:

| Complexity | Model | Think of it as | Good for |
|---|---|---|---|
| 1–4 | Haiku | A junior engineer, fast and cheap | Typo fixes, small docs edits, boilerplate |
| 5–8 | Sonnet | A mid-level engineer | Regular features, most day-to-day work |
| 9–14 | Opus | A senior/staff engineer, expensive but thorough | Complex architecture, security-critical code |

Security and architecture tasks are **always** routed to the top tier, regardless of complexity score — the same way a real company wouldn't let a junior hire push directly to the payments system. `--eco` mode simply caps things toward the cheaper tiers for low-stakes work.

---

## 13. What Gets Created in Your Project

```
your-project/
├── .devteam/                # DevTeam's own state (database, config) — not your app code
│   └── devteam.db           # local SQLite database: sessions, costs, results
├── docs/planning/           # PRDs and task definitions, as JSON files you can read
├── docs/sprints/            # Sprint definitions
└── devteam-reports/         # Human-readable reports (kept in git, unlike .devteam/)
```

Full details, including recommended `.gitignore` entries: [docs/DIRECTORY_STRUCTURE.md](docs/DIRECTORY_STRUCTURE.md).

---

## 14. Commands Reference

| Command | What it does (plain English) |
|---|---|
| `/devteam:plan` | Interview you, research your codebase, produce a plan (PRD + tasks + sprints) |
| `/devteam:implement` | Actually build the plan (or a sprint, a single task, or an ad-hoc request) |
| `/devteam:bug "<desc>"` | Diagnose and fix a bug, escalating to the Bug Council if it's hard |
| `/devteam:issue <#>` | Fix a specific GitHub issue by number |
| `/devteam:issue-new "<desc>"` | File a new, well-formatted GitHub issue |
| `/devteam:review` | Run a full cross-specialty code review |
| `/devteam:test` | Coordinate writing/running tests |
| `/devteam:design` / `/devteam:design-drift` | Generate or audit UI/design-system consistency |
| `/devteam:status` | Show health, progress, and cost |
| `/devteam:list` | List all plans, sprints, and tasks |
| `/devteam:select <plan>` | Choose which plan is "active" |
| `/devteam:config` | View/change DevTeam's own settings |
| `/devteam:logs` | View the raw event history |
| `/devteam:reset` | Un-stick a session that's gone wrong |
| `/devteam:help` | Ask DevTeam questions about itself |
| `/devteam:worktree-status`, `worktree-list`, `worktree-cleanup`, `merge-tracks` | Manage parallel-track worktrees (debug/expert use) |

See [commands/README.md](commands/README.md) for full option flags on every command.

---

## 15. Quality Standards — Nothing Ships Without These

| Gate | Requirement |
|---|---|
| Tests | 100% passing |
| Type checking | Zero type errors |
| Lint | Zero lint errors |
| Security | No high/critical findings |
| Coverage | ≥80% |
| Scope | All changes stayed inside their assigned file boundaries |

---

## 16. Frequently Asked Questions

**Q: Is this a chatbot I talk to, or something else?**
A: You still interact through Claude Code's normal chat interface, using slash commands (`/devteam:plan`, etc.). What's different is what happens *behind* that command: instead of one general-purpose assistant, a whole roster of specialist agents gets assigned, checked, and re-checked automatically.

**Q: What stops an agent from just giving up on a hard task?**
A: The persistence system detects "giving up" language and blocks it, forcing continued effort with escalating re-engagement prompts, model upgrades, and eventually the Bug Council — a human is only notified after all of that, and even then the system keeps trying.

**Q: Can an agent touch files outside what it was assigned?**
A: No. A dedicated Scope Validator agent has veto power and blocks out-of-scope changes; anything it can't block outright gets caught by a pre-commit hook.

**Q: What actually triggers the Bug Council?**
A: A critical/high-severity bug, 3+ failed attempts at the top AI model tier, a complexity score of 10+, or you explicitly asking for it with `--council`.

**Q: How do I make it pick different specialists for my project?**
A: Edit `.devteam/agent-capabilities.yaml` — it's a plain YAML file listing keyword/file-pattern triggers per agent.

**Q: Does any of my code or data leave my machine?**
A: DevTeam's own state (database, reports, configs) is stored locally in your project. The only outbound traffic is the normal AI model calls Claude Code already makes to do the work you asked for.

---

## 17. Installation Details

### Prerequisites
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code)
- SQLite3
- Bash 4.0+ (Linux/macOS) or PowerShell 5.1+ (Windows)
- Git

### From the marketplace (recommended)
```bash
/plugin marketplace add https://github.com/Winnie-Bodhrik/devteam
/plugin install devteam@devteam-marketplace
/devteam:status
```

### From a local clone (for contributing)
```bash
git clone https://github.com/Winnie-Bodhrik/devteam.git
/plugin install /path/to/devteam
/devteam:status
```

### Optional: parallel Agent Teams
```bash
export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
```
Enables true concurrent multi-agent execution (used for the parallel tracks described in §10).

---

## 18. Contributing

Contributions welcome — see [CONTRIBUTING.md](CONTRIBUTING.md). Areas of particular interest:
- Additional language/framework support
- New enterprise agent roles
- Improved agent-selection logic
- Integrations with more external tools

---

## 19. Credits & Acknowledgments

This project draws inspiration from several projects in the AI-assisted development space, while every implementation in this repository is original code.

| Project | What we learned from it |
|---|---|
| [ralph-claude-code](https://github.com/frankbria/ralph-claude-code) | The autonomous-loop concept, exit-signal pattern, circuit breaker for stagnation |
| [everything-claude-code](https://github.com/affaan-m/everything-claude-code) | Specialized agent delegation, cross-platform hook architecture |
| [awesome-claude-skills](https://github.com/ComposioHQ/awesome-claude-skills) | Skill organization and YAML frontmatter conventions |
| [wshobson/agents](https://github.com/wshobson/agents) | Tiered model assignment, plugin architecture, token-efficiency patterns |
| [ui-ux-pro-max-skill](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill) | Design-system generation patterns |

Broader ecosystem inspirations: Aider, AutoGPT, MetaGPT, GPT-Engineer, Sweep AI, OpenHands, and SWE-agent. Standards referenced: OWASP Top 10, WCAG 2.1, SOC2/HIPAA/GDPR/PCI-DSS, Google SRE practices, and The Twelve-Factor App.

Task Loop, Model Escalation, Bug Council, Scope Enforcement, Anti-Abandonment, and the Execution Ledger/agent-wiring governance system are original systems built for this project — see the git history for the full design record.

---

## License

MIT License — see [LICENSE](LICENSE).

---

**Built for Claude Code.**
