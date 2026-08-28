---
name: cross-task-drift-is-the-high-value-finding
description: On concurrent multi-task sprints, the cross-document consistency gate catches more real defects than any single-file gate; check the full producer-consumer chain, not just the named contract pair
metadata:
  type: project
---

When gating one task in a sprint where sibling tasks are being built concurrently, the cross-document consistency gate is where the real defects live. Check the whole producer/consumer chain for a data field, not only the two documents the gate instruction names.

**Why:** on the TASK-005 run, the four named contract points (`POST /signup`, `POST /login` 401, `POST /logout`, cookie credentials) all matched cleanly — but tracing one field across four documents surfaced a genuine unsatisfiable requirement: TASK-001 gives the User model a `name` column, REQ-003 + TASK-007's dashboard spec render `user.name` verbatim in the hero card, while REQ-001's friction constraint and TASK-005's spec forbid ever collecting a name. No in-scope flow populates the field. Single-document gates cannot see this class of bug.

**How to apply:** pick the fields/statuses the spec depends on and grep every planning doc and sibling design spec for each one. When you find drift, do not reflexively FAIL the task under review — decide which document is *wrong*. A spec that correctly follows a hard product constraint should pass, with the drift routed to the orchestrator as a follow-up. Re-running the correct task often produces a worse fix (here: adding a signup field that the API does not accept).

Related: [[design-task-gate-scoping]]
