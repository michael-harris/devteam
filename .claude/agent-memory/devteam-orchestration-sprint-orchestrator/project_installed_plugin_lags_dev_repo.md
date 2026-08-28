---
name: installed-plugin-lags-dev-repo
description: The Claude Code-loaded devteam plugin is the pre-audit upstream version, so dispatched sub-agents do NOT see the dev repo's Phase 0-7 wiring
metadata:
  type: project
---

The devteam plugin that Claude Code actually loads agent definitions from is **not** the dev repo at `/Users/winnie-work/Documents/Bodhrik/devteam/`. It is the marketplace checkout at `/Users/winnie-work/.claude/plugins/marketplaces/devteam-marketplace/` (upstream `michael-harris/devteam` @ `1af6ec2`), mirrored into the session-local runtime dir under `~/Library/Application Support/Claude/local-agent-mode-sessions/.../rpm/plugin_*/`.

Observed consequences (verified 2026-08-27):
- `orchestration:execution-ledger` does **not exist** as a dispatchable `subagent_type` — the Phase 6 agent is only in the dev repo.
- The loaded `task-loop.md` and `sprint-orchestrator.md` contain **zero** occurrences of `log_agent_started` / `invoked_by_*` — none of the Phase 3 call-hierarchy wiring.
- The loaded `scripts/events.sh` `log_agent_started()` takes only `(agent, model, task_id)` — no `invoked_by_agent` / `invoked_by_run_id` params.
- `orchestration:sprint-loop` still exists in the loaded plugin, though the dev repo deprecated it (`docs/deprecated/sprint-loop.md`) and folded sprint validation into `sprint-orchestrator.md` Step 4.

**Why:** the marketplace/runtime copy is only refreshed on plugin install/update, so unmerged or unreleased dev-repo work is invisible to dispatched sub-agents even though the dev repo is the cwd.

**How to apply:** when validating dev-repo orchestration changes end-to-end, you cannot rely on a dispatched sub-agent reading its own updated definition. Explicitly point it at the dev-repo `.md` path in the dispatch prompt, and source state/event helpers from the dev repo's `scripts/` (not the plugin's) so `invoked_by_*` is actually supported. Agents that exist only in the dev repo need a `general-purpose` shim prompted to read their dev-repo spec. See [[devteam-e2e-validation-run]].
