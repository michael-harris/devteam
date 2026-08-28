---
name: devteam-e2e-validation-harness
description: Gate runs dispatched by task-loop target a throwaway sample project in the session scratchpad with concurrent tasks sharing one worktree — inspect files directly, never trust an empty git diff
metadata:
  type: project
---

End-to-end validation of the devteam agent pipeline runs against a throwaway sample
project created under the session scratchpad (e.g. `.../scratchpad/devteam-e2e-sample/`),
not against the devteam repo itself. `orchestration:task-loop` dispatches this agent per
task with a `project_root` pointing there.

**Why:** the harness exercises the real agent wiring (task-loop → implementer →
quality-gate-enforcer) on a synthetic PRD without polluting the devteam repo. Multiple
tasks run concurrently against the *same* working tree.

**How to apply:**
- Treat the sample project as read-only. No git write commands; concurrent tasks share the
  tree and a checkout/stash would corrupt their work.
- The sample repo typically has exactly one initial commit with everything else untracked,
  so `git diff` is empty and `git status` shows whole directories as `??`. **Empty
  `git diff` is not evidence that a file is unchanged** — read the files directly.
- Do not run build/lint/test commands against sibling directories (e.g. `backend/`) when
  another task is mid-build there; the result would not reflect the task under evaluation.
  Scope every command to the `changed_files` for the task.
- Implementer self-review blocks sometimes cite `git status --porcelain` as proof of "no
  regressions". In this harness that proof is weak by construction — verify the claim by
  listing the directory instead of accepting it.
- On re-validation iterations, the dispatch relays the implementer's *claimed* fixes with
  post-edit line numbers. Re-read the file and confirm each cited line actually holds the
  claimed content — stale line citations (correct fix, wrong line number after other edits
  shifted the file) have been a repeat finding worth its own advisory.

See [[design-task-gate-scoping]] for which gates to run when the deliverable is a spec.
