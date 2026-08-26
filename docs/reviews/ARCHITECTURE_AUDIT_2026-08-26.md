# DevTeam Architecture Audit & Remediation Proposal

**Subject:** Root-cause analysis of orchestration failures in the DevTeam plugin (127 agents, v4.0.0) and a sequenced plan to fix them
**Repository:** `devteam` (BODHRIK) — full read-through of every command, skill, agent, hook, schema file, and prior internal review
**Version:** v2 — corrects two factual errors from the first pass (noted in §0) and adds the execution-telemetry agent requested after v1

---

## 0. Correction from v1

The first version of this document claimed `hooks/run-hook.js`, `hooks/log-event.js`, and `scripts/schema*.sql` did not exist in the repository, based on a research mirror that — through an error in how it was assembled, not a property of your actual repo — omitted those files. On direct re-verification against the real files: **all of them exist and are functional.** `run-hook.js` correctly dispatches to the right `.sh`/`.ps1` script per platform; `log-event.js` writes to SQLite directly; `hooks/README.md` confirms hooks auto-register on plugin install with no manual step required; and `scripts/schema.sql` + `schema-v2/v3/v4.sql` define a genuinely well-designed state model (sessions, events, agent_runs, tasks, features, acceptance_criteria, escalations, gate_results, plus reporting views). Section 7 and Phase 0 below reflect the corrected, narrower finding. Everything else in v1 was independently verified across five parallel research passes and stands unchanged.

---

## 1. Executive Summary

Your specialist agents are not the problem. `frontend-designer.md`, `task-loop.md`, `prd-generator.md`, `task-graph-analyzer.md`, `sprint-planner.md`, and most of the orchestration layer are well-designed. The problem is that the commands you actually run — `/devteam:plan` and `/devteam:implement` — don't call most of them. Each command contains its own thinner, hand-written re-implementation of what the specialist agents already do, and that inline version is the only thing wired to the entry point, so it's the only thing that ever runs.

Confirmed with file:line evidence throughout this document:

- **`/devteam:plan`** calls exactly one agent (`research-agent`). `prd-generator`, `task-graph-analyzer`, and `sprint-planner` are never invoked anywhere in the repo — the command writes the PRD, tasks, and sprints itself, inline, with far less rigor than any of the three specialists define.
- **`/devteam:implement`** — the command that runs every sprint and task — calls **zero** agents via `Task()`. Not `sprint-orchestrator`, not `task-loop`, not any quality gate. It's entirely narrated pseudocode.
- **`autonomous-controller`** is invoked by nothing, anywhere — not a command, not a hook.
- **UX/design agents** only run via a separate, manual `/devteam:design` command. `frontend-developer.md` (1.9 KB, the agent that actually writes UI code) is ~9% the size of `frontend-designer.md` (21.5 KB) and never reads a design spec, because none is ever produced for it. This alone explains the "bare list instead of a real dashboard" behavior.
- **Structured quality/validation agents** (`requirements-validator`, `quality-gate-enforcer`, `workflow-compliance`) are reachable only through `task-loop`, and `task-loop` only runs for `/devteam:bug` and `/devteam:issue` — never for normal sprint/task work.
- **Self-review** — an implementer reflecting on its own work before claiming done — exists nowhere. What exists is external, mechanical checking (tests/lint pass or fail), not reasoning about correctness.
- **Execution telemetry** (cost, tokens, which agents ran, which orchestrators were involved) has solid underlying SQLite infrastructure already, but it splits across two disagreeing cost-tracking systems, has no field recording *which orchestrator dispatched which agent*, and is never rendered into a human-browsable, per-task/per-sprint form — only ad hoc query commands and one flat log export. This document adds a new agent (§9.3, Phase 6) to close that gap, per your request below.

This is not new. The repo's own history (§8) shows this exact failure mode — an orchestrator agent built and never wired up — was diagnosed and fixed once already in October 2025, at 28-agent scale, and silently regressed as the system grew to 127 agents. **Rewiring it a third time without a regression check is very likely to produce the same failure a fourth time.** Phase 7 addresses this directly.

None of this requires a rewrite. It requires connecting what's already built, reconciling the handful of places where two "correct" pieces don't yet agree with each other, and then locking the connections in place so they can't silently drop again.

---

## 2. Root Cause: The Dual-Implementation Trap

Every symptom in this document traces back to one repeated pattern:

> **A command file (`commands/*.md` / `skills/*/SKILL.md`) contains its own narrated pseudocode for what "should" happen, instead of a `Task({ subagent_type: "..." })` call to the specialist agent already built to do that job.**

A repository-wide search for every literal `subagent_type:` invocation — the only mechanism by which one agent actually launches another — produces this complete, closed call graph:

```
/devteam:plan          ──Task──▶ research:research-agent                              (ONLY call)
/devteam:implement      (zero Task calls — fully inline)
/devteam:design         ──Task──▶ ux:ux-system-coordinator
/devteam:design-drift   ──Task──▶ ux:design-drift-detector
/devteam:review         ──Task──▶ orchestration:code-review-coordinator
/devteam:test           ──Task──▶ quality:test-coordinator
/devteam:bug, /devteam:issue ─▶ diagnosis:{5 Bug Council agents} ─▶ orchestration:task-loop
/merge-tracks           ──Task──▶ orchestration:track-merger        (manual/debug command)

orchestration:autonomous-controller ──▶ sprint-orchestrator, task-loop, sprint-loop   (nothing ever calls IT)
orchestration:sprint-orchestrator   ──▶ task-loop, sprint-loop        (reachable only via autonomous-controller — dead)
orchestration:sprint-loop           ──▶ runtime-verifier, e2e-tester, security-auditor, visual-verification,
                                         performance-auditor, requirements-validator, documentation-coordinator,
                                         code-review-coordinator, workflow-compliance  (reachable only via sprint-orchestrator — dead)
orchestration:task-loop              ──▶ {suggested_agent}, scope-validator, quality-gate-enforcer,
                                          requirements-validator, bug-council-orchestrator
                                          (reachable ONLY from /devteam:bug, /devteam:issue)
```

Of the eleven files in `agents/orchestration/`, only three have *any* live execution path (`task-loop`, `code-review-coordinator`, `track-merger`), and **none is reachable from `/devteam:implement`**. `sprint-orchestrator`, `sprint-loop`, `autonomous-controller`, and `workflow-compliance` are fully orphaned: registered in `agent-registry.json` with the correct `opus` model, syntactically valid, well-written — and invoked by nothing.

The same pattern repeats in planning: `prd-generator`, `task-graph-analyzer`, `sprint-planner` are richly specified and appear nowhere as a `Task()` target. `commands/devteam-plan.md` states its own intent at line 198: *"This command combines PRD generation and sprint planning into a single workflow"* — a deliberate inlining, not an oversight.

**Why this matters more than "some agents are unused":** in an LLM-orchestrated system, a `Task()` call is the only reliable way to get a specialist's actual behavior — its dedicated prompt, checklists, schema, escalation logic. A comment that narrates "Execute with Task Loop" and reproduces a simplified diagram of what the loop does is a paraphrase competing for the main session's attention, not a delegation. The paraphrase runs; the real thing doesn't.

---

## 3. Gap Inventory — Planning Phase

**Commands:** `commands/devteam-plan.md`, `skills/devteam-plan/SKILL.md`
**Orphaned agents:** `agents/planning/{prd-generator,task-graph-analyzer,sprint-planner}.md`

| Orphaned agent | What it adds that the inline version lacks |
|---|---|
| `prd-generator.md` (458 lines) | An 8-phase gated interview (lines 68–203) vs. 7 unordered questions inline. The **"200+ Feature Approach"** (155–203): every requirement decomposed into 5–20 granular, independently-testable features across 10 categories, with explicit "too broad" vs. "appropriate" guidance — entirely absent inline. A separate `.devteam/features.json` output (365–406) that mirrors the real `features` table already defined in `schema-v2.sql` — currently populated by neither. |
| `task-graph-analyzer.md` (132 lines) | A formal **critical-path algorithm** (39–67, worked example) computing max viable parallel tracks — absent inline. Two mandated artifacts the inline version never produces: `TASK_SUMMARY.md` and `task-dependency-graph.md` (77–121). An explicit circular-dependency check (128). |
| `sprint-planner.md` (350 lines) | A full **bin-packing / balanced track-assignment algorithm** (50–75) with a request-vs-maximum clamp rule (34–38) — the inline version only asserts worktrees are "configured automatically." Concrete `git worktree add` provisioning with conflict handling (119–160) — the actual git mechanics live only here. Three distinct output templates with computed time-savings (222–336) vs. one generic template inline. |

**Reconnecting these is not a one-line fix — their schemas disagree with each other and with what `/devteam:implement` consumes:**

- `prd-generator.md` writes `requirements: {must_have, should_have, out_of_scope}`; the inline PRD writes `features: {must_have, nice_to_have}` — different key, different ID prefix (`REQ-` vs `F`), no `out_of_scope`. `task-graph-analyzer.md:22` ("Extract from must-have and should-have requirements") uses `prd-generator`'s vocabulary, not the inline schema's — it would silently misparse today's PRD output.
- `task-graph-analyzer.md` defines **no TASK-XXX.json schema at all** and is entirely hours-based (task sizing "1–2 days," critical path in hours). The inline schema's `complexity: {score, factors}` (0–14) is what `.devteam/model-selection.md:88–125` reads to pick haiku/sonnet/opus per task. Reconnecting `task-graph-analyzer` as-is would silently break model selection for every task.
- `sprint-planner.md`'s balancing algorithm sums **hours** (line 217: "40–80 hours per sprint per track") from a field `task-graph-analyzer` never defines — the same score-vs-hours split, one level up.
- **Registration is split two ways**: `agent-registry.json` registers `planning:sprint-planner` as `model_strategy: fixed`; `.devteam/agent-capabilities.yaml:653–664` separately registers the same agent under a different id (`sprint_planner`, no namespace) with a different strategy (`complexity_range: [3,8]`). `prd-generator`/`task-graph-analyzer` don't appear in `agent-capabilities.yaml` at all.

**The "two-phase architecture" you asked about is a disconnected fourth state model, not a badly-run one.** `.devteam/two-phase-architecture.yaml` defines a separate Ralph-style scheme (`features.json`, `progress.txt`, `init.sh`, first-run vs. resume detection) and its own integration section (373–379) says `/devteam:plan` should trigger it after the PRD step. Direct inspection confirms `devteam-plan.md` never references any of those three files. The mechanism is implemented on the consumer side — `task-loop.md:194–260,640–668` has real detection logic for it, and `scripts/init-generator.sh`/`progress.sh`/`checkpoint.sh` genuinely support it — but since `task-loop` is unreachable from `/devteam:implement` and `devteam-plan.md` never produces the files, **it has never fired in the live flow.** It isn't doing a bad job; it isn't running at all.

---

## 4. Gap Inventory — Implementation / Orchestration Phase

**Commands:** `commands/devteam-implement.md`, `skills/devteam-implement/SKILL.md`
**Orphaned:** `sprint-orchestrator`, `sprint-loop`, `autonomous-controller`, `workflow-compliance`
**Reachable from the wrong commands only:** `task-loop`, `scope-validator`, `quality-gate-enforcer`, `requirements-validator`

`commands/devteam-implement.md` — the single most-used command — contains **zero** `Task()` calls (confirmed: zero hits for `subagent_type`, `Task(`, or any orchestrator name). Its "Phase 5: Execute with Task Loop" is a simplified ASCII diagram plus JS function stubs, narration for the main session, not a delegation. Capabilities that exist in `task-loop.md` and are simply absent from what runs:

| Capability | Where specified | What runs instead |
|---|---|---|
| Stuck-loop detection (3× same files/tests/error) | `task-loop.md:169–190` | Nothing |
| Budget-aware escalation halt (<20% budget) | `task-loop.md:135–151` | Failure-count table only (`devteam-implement.md:217–223`) |
| Scope validation before quality gates | `task-loop.md:272–285` (calls `scope-validator`) | Nothing |
| Language-aware quality gates (pytest/mypy/ruff, go test/vet, etc.) | via `quality-gate-enforcer.md` | **Hardcoded `npm test`/`npm run lint`** (`:229–235`) — breaks on non-JS projects |
| Bug Council auto-activation (3× opus failure / stuck loop) | `task-loop.md:332–363` | Only listed as a "support agent" for `task_type=="bug"` |
| Automated regression rollback | `task-loop.md:593–628` | Absent |
| Two-phase startup/resume detection | `task-loop.md:194–247` | Absent |
| Structured per-iteration reports | `task-loop.md:396–460` | One final banner only |

`quality-gate-enforcer.md`, `requirements-validator.md`, `workflow-compliance.md` have no `Task` tool in their own frontmatter, and `quality-gate-enforcer.md`'s body describes `delegate_to: quality:e2e-tester` (lines 200, 206, 216) as if it could call that itself — it structurally can't. They only run as sub-steps inside `task-loop`, which only runs for `/devteam:bug`/`/devteam:issue`.

One further internal inconsistency: **`task-loop.md` never calls `workflow-compliance`**, even though `workflow-compliance.md:402–403` documents itself as inserted "before marking task complete" *inside* the Task Loop. So even in the one flow where `task-loop` does run, the closest existing analog to a structured completion report (§6) still never fires — it's only reachable from the also-orphaned `sprint-loop.md`.

**Net effect:** the designed stack is `autonomous-controller → sprint-orchestrator → {task-loop, sprint-loop} → sub-gates`. The one command a normal user hits reaches none of it.

---

## 5. Gap Inventory — UX / Design Pipeline

**Orphaned:** `ux-system-coordinator` (reachable only from manual `/devteam:design`), `design-system-architect`, `design-system-orchestrator`, `frontend-designer`, `ios-designer`, `android-designer` — zero `Task()` references anywhere for the latter four.

**Design is structurally excluded from the task graph, not just poorly triggered.** `devteam-plan.md:550`'s task schema enumerates `task_type: "backend | frontend | database | fullstack | testing | infrastructure"` — no `"design"` category exists. `task-loop.md` (679 lines, the dispatch engine) contains the words "design" or "frontend" **zero times**. Its only dispatch call (`:265`) is `Task({subagent_type: "{suggested_agent}"})` — whatever `/devteam:plan` wrote, never a design agent by construction.

**The one agent that does run is too thin to compensate and can't ask for help.** `frontend-developer.md` (1,928 bytes vs. `frontend-designer.md`'s 21,496) is a capability checklist — "Implement UI components," "Style with CSS/Tailwind" — with a quality-check item `[ ] Components match design` that has nothing to match against. It never references `tokens.json`, `design-system/`, or any component spec, and has **no `Task` tool**, so it cannot request design input even if it wanted to.

**The handoff mechanism exists only on paper.** `.devteam/design-integration.md:239–270` and `design-enforcement.md:103–201` describe a detailed token-injection protocol, but `design-enforcement.yaml` — the config file that spec says must exist — **does not exist anywhere in the repo**. The one gate that would enforce it (`task-loop-config.yaml:196`, `design_compliance`) only fires `when design_system_exists`, and nothing ever creates `design-system/`, so it's a permanent no-op.

**The design agents' own claimed data doesn't exist either** — independently confirmed in your own `docs/deprecated/CODEBASE_REVIEW_2026-02-01.md` §2.7: the "67 UI styles / 96 palettes / 57 typography pairings" are referenced, not implemented as data.

**Mobile has the same gap, plus a misdirected reference:** `ios-developer.md`/`android-developer.md`'s "Collaborates With" sections point at `frontend:designer` (the wrong platform) rather than their own `ios-designer`/`android-designer` — and that reference is moot anyway since it's also never invoked.

**The exact trace for "Create the student dashboard":** `/devteam:plan` writes `task_type: "frontend"`, `suggested_agent: "frontend:developer"` — no design task exists to precede it → `/devteam:implement` dispatches `frontend:developer` with only acceptance criteria as context, no tokens, no spec → its entire guidance is the generic checklist above, with nothing telling it to build a hero card, progress bars, or an "Upcoming" section — those are exactly the decisions `frontend-designer.md`'s atomic-design workflow exists to make, and it's never consulted. With no design input, the model defaults to the literal minimum: email, course list. **This is a wiring defect, not a prompt-quality defect.**

---

## 6. Gap Inventory — Quality Gates & Self-Review

**What you asked for:** before marking a task done, an agent asks itself *"Did I implement the requested behavior? Did I break existing behavior? Did I account for edge cases?"* and emits a structured completion report.

**What partially exists, all externally administered (checker-side, not implementer-side):**
- `requirements-validator.md:170–265` — PASS/FAIL per acceptance criterion with evidence.
- `workflow-compliance.md:67–95` — requires `docs/tasks/TASK-XXX-summary.md` with mandatory sections (`## Requirements`, `## Implementation`, `## Code Review`, `## Testing`, `## Requirements Validation`) — the closest existing shape to what you asked for, but it's an auditor checking the document exists, not the implementer reasoning about its own work.
- `agents/templates/base-agent.md:97–116` — every agent's shared completion gate: tests/types/lint/security/commit, all mechanical tool-output checks, before `EXIT_SIGNAL: true` may be emitted.

**Confirmed absent, by repository-wide search for "self-review," "did I," "before marking complete":** no implementer agent is ever asked to reason about whether it fulfilled the request, regressed anything, or missed an edge case. Four sampled implementer agents (`api-developer-python`, `frontend-developer`, `android-developer`, `python-developer-generic`) confirm this — their "Output" sections list file paths, nothing more.

**And even the checker-side version never runs in the normal flow**, for the same reason as everything else here: `requirements-validator`/`quality-gate-enforcer`/`workflow-compliance` are reachable only through `task-loop`, which only runs for `/devteam:bug`/`/devteam:issue`.

---

## 7. Gap Inventory — Autonomous Controller & the Hook/State Substrate

**Your question:** *"the autonomous controller isn't active when the project is running."*

**Confirmed, precisely: it is never active, under any circumstance.** A repo-wide search for `autonomous-controller` outside its own file turns up only `README.md`, `agent-registry.json` (a metadata entry, not an invocation), and design-history docs. Every hook script (`stop-hook.sh`, `pre-tool-use-hook.sh`, etc.) was read in full and grepped for `autonomous-controller`/`sprint-orchestrator`/`sprint-loop`/`task-loop`: **zero matches in any of them.** No command, skill, or hook ever reaches it.

**The hook/state substrate underneath it, corrected from v1, is largely real and reasonably well-built:**
- `hooks/hooks.json` dispatches to `run-hook.js`, which correctly shells out to the matching `.sh`/`.ps1` script per platform. `log-event.js` writes events directly via the `sqlite3` CLI. Both exist and are functional, if minimal (both fail silently by design — "never block Claude Code" — which is a reasonable default but means a broken hook degrades invisibly rather than surfacing an error).
- `hooks/README.md:21` confirms hooks are auto-registered on plugin install ("via marketplace or local install... no manual setup required") — the manual `install.sh --auto` path is for a separate, non-plugin install mode, not a required step for the packaged plugin.
- `scripts/schema.sql` + `schema-v2/v3/v4.sql` define a genuinely solid model: `sessions`, `events`, `agent_runs` (with `task_id`, `agent`, `model`, `tokens_input/output`, `cost_cents`, `files_changed`), `tasks` (with `sprint_id`, `depends_on`, `scope_files`), `features`/`acceptance_criteria` (schema-v2, matching `prd-generator`'s 200+-feature model), `escalations`, `gate_results`, plus reporting views (`v_agent_performance`, `v_model_usage`, `v_sprint_progress`, `v_gate_pass_rates`). This is a real, usable foundation — see §8 for what's still missing from it.

**Two real, narrower gaps remain in this layer** (replacing v1's incorrect "hooks are broken" claim). Both are plain mechanical bugs — not agent-judgment problems — so both are fixed with deterministic script changes, not a new agent. Concrete fix for each:

**1. Two cost-tracking systems disagree, and nothing owns producing the readable log from either of them.**

*What's happening:* `scripts/state.sh`/`events.sh` write cost into `agent_runs.cost_cents` and `sessions.total_cost_cents` — in **cents** — every time a hook or orchestrator logs an agent run. Separately, `scripts/cost-tracking.sh` (an independent script, called from a different place) writes its *own* record of the same kind of event into a different table, `token_usage`, and a flat file, `.devteam/cost-log.json` — in **dollars**. Nothing reconciles the two; the script's own comment admits *"callers bridging between the two systems must convert."* Right now, two different numbers can each claim to be "the cost of Task-014," and there is no page that turns either of them into something you'd actually want to read.

*Fix:* Two, sequenced changes, both in Phase 0/6:
- **Pick one writer.** Keep `agent_runs.cost_cents`/`sessions.total_cost_cents` (the cents-based, hook-driven path in `state.sh`/`events.sh`) as the single source of truth — it's the one already linked to `tasks.id` and `sessions.id` by foreign key, and it's the one written in real time by the hook layer, which is the only layer that actually has Claude Code's real token counts as each call completes (an agent cannot introspect its own token usage — only the harness/hook system can, so this recording step has to stay at the script/hook level, not become an agent's job). Retire `cost-tracking.sh`'s separate `token_usage` table and `.devteam/cost-log.json` as a second writer — either delete `record_usage()`'s independent insert, or turn it into a thin, read-only helper that queries `agent_runs` and converts cents→dollars for display, so it can no longer drift from the real numbers.
- **Then the human-readable log is owned by the `execution-ledger` agent (§10.3), not by either script.** Once there's one canonical, cents-based table, the scripts' job stops at recording raw rows in real time; turning those raw rows into the `devteam-reports/tasks/TASK-XXX.md` / `sprints/SPRINT-XXX.md` files you actually read is entirely the `execution-ledger` agent's responsibility — it is the one place in the system that produces the logs you review, reading from the now-single source instead of guessing between two.

**2. `.devteam/config.yaml`'s `autonomous:` block is decorative — changing it does nothing.**

*What's happening, in plain terms:* `.devteam/config.yaml` has a section that reads like real settings — "stop after 5 failures in a row" (`max_consecutive_failures: 5`), "stop after 50 loops" (`max_iterations: 50`), and so on. It looks like the file you'd edit to change that behavior. It isn't. The actual code that enforces those limits (`scripts/state.sh`) has its own separate, hardcoded copies of similar numbers baked directly into the script. A search for `config.yaml` across every script in the repo returns zero hits — nothing ever opens the file and reads it. `hooks/session-start.sh:9` even declares a variable, `CONFIG_FILE=".devteam/config.yaml"`, pointing at it, and then never uses that variable again anywhere in the file. So today, if you edited `config.yaml` to raise `max_iterations` to 200, the system would still stop at 50 — the number in the file and the number actually enforced are two unrelated things that happen to currently match.

*Fix:* Make `hooks/session-start.sh` actually read the file at the start of every session and turn its values into the session's real limits, with the current hardcoded numbers kept only as a fallback if the file is missing or unreadable. The `autonomous:` block is flat, simple key/value pairs (`enabled`, `max_iterations`, `circuit_breaker.max_consecutive_failures`, `circuit_breaker.cooldown_minutes`) — it doesn't need a full YAML parser or a new dependency like `yq`; a few targeted `grep`/`sed` lines scoped to those specific keys are enough, consistent with how the rest of the script already does lightweight parsing. `session-start.sh` then writes the parsed values into `session_state` (or new columns on `sessions`) at session start, and `state.sh`'s `should_trip_circuit_breaker()` / `is_max_iterations_reached()` read from there instead of their hardcoded constants. After this, editing `config.yaml` is the actual way to change autonomous-mode behavior, which is what the file already implies it should be.

---

## 8. Gap Inventory — Execution Telemetry (Cost, Tokens, Agent Calls, Orchestrator Involvement)

This section grounds the new agent you asked for.

**What already exists and is genuinely solid:** the schema in §7 supports exactly the reporting you want at the data-model level. `agent_runs` records agent + model + tokens + cost + files-changed per attempt, linked to `tasks.id`; `tasks.sprint_id` links tasks to sprints; `escalations` records model-tier changes with reasons; `gate_results` records quality-gate pass/fail. `commands/devteam-logs.md` already queries this into readable session timelines, and `commands/devteam-status.md` reports summary metrics. `scripts/cost-tracking.sh` has a real, correct `calculate_cost()` against current model pricing.

**What's missing, confirmed by direct inspection:**
1. **No call-hierarchy field.** `agent_runs` has no column recording *which orchestrator or parent agent dispatched this run*. You cannot currently query "which orchestrators were involved in Sprint 3" — the schema has no way to distinguish "sprint-orchestrator ran" from "task-loop ran" from "frontend:developer ran" as a chain; they're all just rows in `agent_runs` with no parent link.
2. **The dual cost-tracking split** from §7 means a per-task cost figure pulled from `agent_runs.cost_cents` and one pulled from `.devteam/cost-log.json` can disagree.
3. **Nothing renders this to a human-browsable, per-task/per-sprint artifact.** `/devteam:logs --export` writes one flat chronological log file; there is no per-task or per-sprint document, and nothing runs automatically — a user has to remember to run a query command rather than being able to open a folder and read what happened.
4. **None of this is currently populated anyway**, for the same root cause as everything else — the inline `/devteam:implement` path only partially calls the logging functions, and `task-loop.md` (which calls them properly) doesn't run in the normal flow.

Phase 6 below adds the agent you asked for on top of this real foundation, rather than building a fifth, competing tracking system.

---

## 9. This Is a Recurring Defect — History

Ten internal review documents, October 2025 → February 2026, already cover most of this ground:

| Date | Document | Finding |
|---|---|---|
| 2025-10-30 | `docs/development/agent-review-findings.md` | **First diagnosis of this exact pattern**, at 28-agent scale: *"`sprint-orchestrator.md` EXISTS but is NOT launched."* Recommends wiring it up. |
| 2025-10-30 | `docs/development/plugin-conversion.md` | Carries the same finding into a pre-conversion checklist. |
| 2025-10-30 | `docs/development/PLUGIN_BUILD_COMPLETE.md` | **Claims the fix was made** at 27-agent scale, with a before/after diagram. |
| undated | `docs/development/RALPH_INTEGRATION_OPTIONS.md` | Proposes `autonomous-controller` as one of four options for continuous execution, but **recommends starting with a plain shell stop-hook instead** — the likely origin of why the agent exists but was never promoted to load-bearing. |
| undated | `docs/development/IMPLEMENTATION_PLAN.md` | ~1900-line redesign; even here, planning/orchestration delegation is specified only in prose, while the Bug Council section shows literal `Task()` calls — a plausible seed of the whole pattern. Targeted consolidating 76→~55 agents; the project grew to 126–129 instead. |
| Jan 2026 | `docs/reviews/PROJECT_REVIEW_2026-01.md` | 7.4/10 review, 89+ agents. Scored "Architecture & Design" 8.0/10 without checking invocation wiring at all. |
| 2026-01-30 | `docs/reviews/ISSUE_VALIDATION_REPORT_2026-01-30.md` | Purely mechanical bug list — no mention of orchestrator wiring. |
| 2026-01-30 | `docs/reviews/FINAL_VALIDATION_REPORT_2026-01-30.md` | Confirms 126 agents *registered* with correct models — never checks *invocation*. |
| 2026-02-01 | `docs/deprecated/CODEBASE_REVIEW_2026-02-01.md` | **Independently re-diagnoses the same root cause**, in stronger terms: *"the system is fundamentally a specification/framework that cannot execute autonomously."* Also independently found the UX/design gap and the "hooks require manual configuration" belief (§7 shows that belief was itself outdated for the packaged-plugin path). Carries a header claiming resolution *"in subsequent audits... see MEMORY.md"* — **no document available substantiates that claim**, and this audit's own fresh findings show the same defects still present. |

**What this means:** the orphaned-orchestrator problem was fixed once (Oct 2025) at small scale and regressed as the system scaled 4.5x. Rewiring it a third time without a regression check (Phase 7) will very likely regress a fourth time. The self-review/completion-report gap (§6) and the telemetry-attribution gap (§8) are not rediscoveries — no prior document names either.

---

## 10. Target Architecture

### 10.1 Principles

1. **One execution engine.** Every implementation command routes through the same `task-loop` — no bespoke inline copies.
2. **Three orchestration layers, not four.** Retire `autonomous-controller` as a separate agent; make "autonomous mode" a flag `sprint-orchestrator` honors directly, governed by the Stop hook. Fold `sprint-loop`'s sprint-level gates into `sprint-orchestrator`'s completion phase. Result: `sprint-orchestrator → task-loop → specialist agent`.
3. **Design is a task type, not an optional side command.** `task-graph-analyzer` emits `task_type: "design"` with a dependency edge into every UI-bearing task, structurally, not by convention.
4. **Self-review and external validation are both kept, and connected.** A reasoning step in `base-agent.md` for every implementer; `requirements-validator`/`quality-gate-enforcer` remain the independent check on top of it.
5. **The execution ledger is a reporting layer over one source of truth**, not a new competing state store — it reconciles the existing cent/dollar split and adds the one real missing field (call hierarchy).
6. **No agent ships without a caller.** An automated check fails the build if an orchestration/planning agent has zero `Task()` references anywhere — this is what stops the Oct-2025-style regression from happening a third time.

### 10.2 Target call graph

```
/devteam:plan  ──▶ research:research-agent
               ──▶ planning:prd-generator        ──▶ PROJECT_PRD.json + features.json (canonical schema, Phase 1)
               ──▶ planning:task-graph-analyzer   ──▶ TASK-*.json (incl. task_type:"design") + dependency graph
               ──▶ planning:sprint-planner        ──▶ SPRINT-*.json + worktree provisioning

/devteam:implement, /devteam:bug, /devteam:issue
               ──▶ orchestration:sprint-orchestrator      (mode: normal | autonomous)
                       │
                       ├─ design task pending? ──▶ ux:ux-system-coordinator
                       │      (writes design-system/tokens.json + component specs BEFORE
                       │       any dependent frontend/mobile task is dispatched)
                       │
                       ├─ per task ──▶ orchestration:task-loop
                       │                  ├─▶ scope-validator
                       │                  ├─▶ {suggested_agent}  (reads design-system/ first if UI-bearing;
                       │                  │    emits self-review + completion report before returning)
                       │                  ├─▶ quality-gate-enforcer (language-aware)
                       │                  ├─▶ requirements-validator
                       │                  ├─▶ bug-council-orchestrator (on stuck-loop / 3x opus failure)
                       │                  └─▶ orchestration:execution-ledger  (NEW — records the task report)
                       │
                       └─ sprint completion: e2e-tester, security-auditor, visual-verification,
                          performance-auditor, documentation-coordinator, code-review-coordinator,
                          workflow-compliance, orchestration:execution-ledger (NEW — sprint roll-up)

Hook layer (real, already largely correct — §7): SessionStart / PreToolUse / PostToolUse / Stop / PreCompact / SessionEnd
  enforce scope, circuit breaker, autonomous-mode looping, anti-abandonment.
```

### 10.3 New agent: `orchestration:execution-ledger`

**What you asked for:** an agent that logs cost per task, tokens per task, agents called per task, and orchestrators involved per sprint, into a separate folder you can review any time.

| | |
|---|---|
| **File** | `agents/orchestration/execution-ledger.md` |
| **Tools** | `Read, Glob, Grep, Bash, Write` (no `Task` — it's a leaf reporter, not a dispatcher) |
| **Model** | `haiku` (mechanical rendering, not reasoning — consistent with the system's own cost-tier philosophy) |
| **Triggers** | Called by `task-loop.md` immediately after a task reaches a terminal state (completed/failed); called by `sprint-orchestrator.md` at sprint completion. Both calls are best-effort/non-blocking, matching `log-event.js`'s existing "never block on logging failure" convention. |
| **Reads** | `agent_runs`, `events`, `escalations`, `gate_results`, `tasks`, `sessions`, `features`, `acceptance_criteria`, plus the existing views (`v_agent_performance`, `v_model_usage`, `v_sprint_progress`, `v_gate_pass_rates`) |
| **Writes to** | `devteam-reports/` at the project root — a plain, visible, git-tracked folder (not under `.devteam/`, which stays the system's internal state; not gitignored, since this is meant to be a kept project record) |

**Output structure:**

```
devteam-reports/
├── INDEX.md                      # running dashboard: all sprints, cumulative cost/tokens, links
├── sprints/
│   └── SPRINT-003.md             # sprint roll-up (see below)
└── tasks/
    └── TASK-014.md               # per-task report (see below)
```

**`tasks/TASK-XXX.md` contains:** task metadata (id, title, sprint, status, priority, complexity, duration); reconciled cost and tokens (input/output/total, USD — single authoritative number, see below); a table of every agent called (agent, model, iteration/attempt, status, duration, files changed); the **orchestrator chain** that dispatched it (e.g. `sprint-orchestrator → task-loop → scope-validator → frontend:developer → quality-gate-enforcer → requirements-validator`), using the new call-hierarchy field described below; quality gate results; escalation history; and — once Phase 5 ships — the implementer's self-review/completion report, embedded or linked.

**`sprints/SPRINT-XXX.md` contains:** sprint metadata and goal; aggregate cost/tokens across all its tasks; **every orchestrator invoked during the sprint, with counts** (e.g. `sprint-orchestrator: 1, task-loop: 7, bug-council-orchestrator: 1, code-review-coordinator: 1`); a per-task summary table linking to each task report; gate pass rates; model usage breakdown.

**This agent is the single owner of the readable logs.** The scripts (`state.sh`/`events.sh`, called from hooks) stay as the real-time, low-level recorder — they have to, since only the hook layer sees Claude Code's actual token counts as each call completes. `execution-ledger` never records raw usage itself; its only job is to read the now-single-source ledger (Phase 0's fix) and render it into the files in `devteam-reports/`. Two prerequisites, both already scoped to earlier phases, not new work:
- **The cost split is already reconciled by Phase 0** (§7.1) before this agent is built, so it reads one number, not two.
- **Add the call-hierarchy field.** A new `schema-v5.sql` (Phase 1) adds `invoked_by_agent TEXT` and `invoked_by_run_id INTEGER REFERENCES agent_runs(id)` to `agent_runs`. `task-loop.md` and `sprint-orchestrator.md` (rewritten in Phase 3) populate it on every dispatch — this is what makes "orchestrators involved in the sprint" a query this agent can run, instead of a guess.

**Discoverability:** add a one-line cross-reference from `commands/devteam-logs.md` and `commands/devteam-status.md`'s "See Also" sections pointing at `devteam-reports/`, so the existing query commands and the new browsable folder are presented as complementary, not competing.

---

## 11. Implementation Roadmap

Nine phases (0–8), ordered so each phase's output is a precondition for the next. No phase can be reordered without breaking a downstream step — this is the dependency order the evidence above actually requires, and it's built so adding the telemetry agent (Phase 6) does not disturb any other phase's scope.

| Phase | Objective | Depends on | Key files |
|---|---|---|---|
| **0** | Reconcile the execution substrate (§7, concrete fixes): make `agent_runs.cost_cents`/`sessions.total_cost_cents` the single cost source and reduce `cost-tracking.sh` to a read-only cents→dollars formatter over it; make `hooks/session-start.sh` actually parse `config.yaml`'s `autonomous:` block into session state so `state.sh`'s circuit-breaker/iteration checks read it instead of their hardcoded duplicates. *(No hook rewrite needed — §0 correction; this is a script fix, not a new agent.)* | — | `scripts/state.sh`, `scripts/cost-tracking.sh`, `hooks/session-start.sh` |
| **1** | Unify schemas: one canonical PRD schema (adopt `prd-generator.md`'s, since it's strictly more complete); one canonical TASK schema keeping `complexity.score` *and* adding `estimated_hours`; one canonical SPRINT schema; reconcile the `01` vs `1` track-key format; merge `agent-registry.json`/`agent-capabilities.yaml`'s conflicting `sprint-planner` registrations; add `task_type: "design"`/`"data_architecture"` to the TASK enum; add the `invoked_by_*` columns via `schema-v5.sql` (needed by Phase 6). | 0 | `agent-registry.json`, `.devteam/agent-capabilities.yaml`, `agents/planning/task-graph-analyzer.md`, new `.devteam/schemas/*.json`, `scripts/schema-v5.sql` |
| **2** | Reconnect planning: delete `devteam-plan.md`'s inline Phase 4/5/6 pseudocode; replace with chained `Task()` calls `prd-generator → task-graph-analyzer → sprint-planner`; feed `research-agent`'s findings into the `prd-generator` prompt; add the design-task emission rule. | 1 | `commands/devteam-plan.md`, `skills/devteam-plan/SKILL.md`, `agents/planning/*.md` |
| **3** | Reconnect execution: extend `sprint-orchestrator.md` with a `mode: normal\|autonomous` flag and folded-in sprint-completion gates (formerly `sprint-loop`); deprecate `autonomous-controller.md` and `sprint-loop.md` to `docs/deprecated/`; delete `devteam-implement.md`'s inline Phase 5/6/7; replace with one `Task()` call to `sprint-orchestrator`; add the missing `workflow-compliance` call inside `task-loop.md`; make every dispatch populate the Phase-1 `invoked_by_*` columns. | 1, 0 | `agents/orchestration/{sprint-orchestrator,task-loop}.md`, `commands/devteam-implement.md`, `skills/devteam-implement/SKILL.md` |
| **4** | Wire the design pipeline: `sprint-orchestrator` dispatches `ux:ux-system-coordinator` (or platform designer) before any UI-bearing task with a pending design dependency; rewrite `frontend-developer.md` to require reading `design-system/tokens.json` first and add real layout guidance; fix `ios-developer.md`/`android-developer.md`'s misdirected designer references; create the missing `design-enforcement.yaml`; seed real (or honestly rescoped) style/palette/typography data. | 2, 3 | `agents/orchestration/sprint-orchestrator.md`, `agents/frontend/frontend-developer.md`, `agents/mobile/{ios,android}-developer.md`, `.devteam/design-enforcement.yaml` |
| **5** | Self-review: extend `base-agent.md`'s completion gate with a reasoning step (requested behavior / regressions / edge cases) and a required `[TASK-XXX-COMPLETION]` report; have `requirements-validator`/`quality-gate-enforcer` check the report is present and non-trivial, reusing `workflow-compliance`'s section-presence pattern. | 3 | `agents/templates/base-agent.md`, `agents/orchestration/{requirements-validator,quality-gate-enforcer}.md` |
| **6** | **Build `orchestration:execution-ledger`** (§10.3): new agent file; wire its call from `task-loop.md` (per task) and `sprint-orchestrator.md` (per sprint); create `devteam-reports/{tasks,sprints}/` + `INDEX.md` rendering logic; cross-link from `devteam-logs`/`devteam-status`. | 1 (schema), 3 (calls to attach to), 5 (embeds self-review reports) | new `agents/orchestration/execution-ledger.md`, `agents/orchestration/{task-loop,sprint-orchestrator}.md`, `commands/{devteam-logs,devteam-status}.md` |
| **7** | Governance: new `scripts/validate-agent-wiring.sh` — fails if any `agents/orchestration/*.md`, `agents/planning/*.md`, or `agents/ux/*.md` file has zero `subagent_type:` references anywhere in `commands/`, `skills/`, or other agents; wire into pre-commit/CI. | 2–6 (needs a correct wired state to lock in) | new `scripts/validate-agent-wiring.sh`, CI config |
| **8** | End-to-end validation: run `/devteam:plan "Build a task manager with a student-style dashboard"` → confirm PRD/task/sprint artifacts match the Phase-1 schema with a `design` task present → `/devteam:implement --all` → confirm the design pipeline fires before frontend work, gates are language-aware and scope-checked, every task carries a real completion report, and `devteam-reports/` is populated with a correct sprint roll-up and per-task cost/agent/orchestrator breakdown. | all | none (validation only) |

**Acceptance check per phase**, in brief: Phase 0 — one cost figure, sourced from one place; circuit-breaker default changed in `config.yaml` visibly changes behavior. Phase 1 — a hand-written sample PRD flows through the three planning agents with no field-name mismatch. Phase 2 — `/devteam:plan` produces `TASK_SUMMARY.md` + `task-dependency-graph.md` + a `design` task. Phase 3 — `/devteam:implement --sprint 1` on a non-JS project runs language-correct gates, scope-validator observably rejects an out-of-scope file. Phase 4 — the dashboard regression test from §5 produces card-based layout, not a bare list. Phase 5 — a completed task's output contains a specific, non-boilerplate completion report. Phase 6 — after one sprint, `devteam-reports/sprints/SPRINT-001.md` lists every orchestrator invoked with correct counts and one cost figure that matches `agent_runs`. Phase 7 — renaming a `subagent_type:` reference to simulate a new orphan is caught and fails the check. Phase 8 — the full lifecycle runs clean, end to end.

---

## 12. What Not To Do

**Don't rewrite from scratch.** The specialist agents are good — `prd-generator`'s 200+-feature methodology, `task-graph-analyzer`'s critical-path algorithm, `frontend-designer`'s atomic-design spec, `task-loop`'s escalation logic, and now the SQLite telemetry schema in §7–8 are all solid work. The defect is the wiring between the command layer and these agents, plus schema drift between agents that were designed to work together. A rewrite would discard work that doesn't need discarding and reintroduce the exact risk (a thin, hastily-written command layer) that caused this in the first place.

**Don't skip Phase 7.** This is the second time this defect has been found in this codebase (§9), and the first fix didn't survive scaling from 28 to 127 agents. Skipping the automated wiring check means this document — or one very like it — gets written again once the agent count grows further.
