---
name: design-task-gate-scoping
description: For task_type "design" deliverables, report test/lint/typecheck/build/dep-audit as not_applicable (never PASS), and run design-compliance/self-review/internal-consistency/PRD-consistency instead
metadata:
  type: feedback
---

When the dispatched task has `task_type: design` (deliverable is a Markdown spec — prose,
tables, illustrative type declarations in code fences, nothing executable or importable),
report the **tests, lint, typecheck, build, and dependency-audit gates as
`not_applicable`** with an explicit reason. Do NOT report them as PASS, and do not report
them as FAIL.

`code-review` is also `not_applicable` for a Markdown-only deliverable.

The gates that actually apply are: design-compliance (acceptance-criteria coverage),
self-review report validation, documentation/internal-consistency, PRD/API-contract
consistency, security-relevant design review (for auth/permissions specs), and
markdown well-formedness (fence balance, uniform table column counts).

**Distinguish contradiction from imprecision.** A wrong section cross-reference
(`(see §7)` pointing at a section that doesn't cover the topic), an inconsistent heading
level, or an over-broad prop description are *warnings*, not blocking issues, as long as
the authoritative section states the rule unambiguously and leaves the consumer no
decision to invent. Reserve FAIL for statements that actually conflict.

**Why:** reporting a code gate as PASS on a Markdown-only deliverable is a false signal —
it tells the Task Loop that executable quality was verified when nothing executable exists.
Reporting FAIL is equally wrong since there is nothing to fix. `orchestration:task-loop`
scopes this explicitly in its dispatch when it knows the task type.

**How to apply:** check the `task_type` field in
`docs/planning/tasks/TASK-XXX.json` before choosing gates. Design specs still get a hard
FAIL for substantive defects — missing acceptance-criteria coverage, contradictions with
the PRD, or fields required by the contract that no upstream task ever produces. "It's only
a doc" is not a reason to soften a verdict.

**But scope the FAIL to what the spec itself owns.** A spec is required to resolve *its
own* contract and to flag upstream conflicts — not to fix them. Do NOT fail a design task
merely because a genuine cross-requirement planning tension exists upstream of it, or
because a sibling task's serialization/naming disagrees; if the spec states a coherent
resolution, leaves its consumers no decision to invent, and carries an explicit
conflict callout, that is a PASS with a warning. Verify absence claims before making them
one of these violations — see [[verify-absence-claims]].

See [[devteam-e2e-validation-harness]] for the shared-worktree constraints that usually
accompany these dispatches.
