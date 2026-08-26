# Canonical Planning Schemas

Added in Architecture Audit Phase 1 (see `docs/reviews/ARCHITECTURE_AUDIT_2026-08-26.md`, §3 and §11) to resolve the schema drift between `commands/devteam-plan.md`'s inline PRD/TASK/SPRINT generation and the actual output formats defined by `agents/planning/{prd-generator,task-graph-analyzer,sprint-planner}.md`.

| Schema | Validates | Adopted from |
|---|---|---|
| `prd.schema.json` | `docs/planning/PROJECT_PRD.json` | `agents/planning/prd-generator.md` (verbatim — explicitly the more complete of the two prior versions) |
| `features.schema.json` | `.devteam/features.json` | `agents/planning/prd-generator.md` Phase 8 |
| `task.schema.json` | `docs/planning/tasks/TASK-XXX.json` | Merged: `commands/devteam-plan.md`'s `complexity.score` + `agents/planning/task-graph-analyzer.md`'s hours-based sizing (which had no JSON schema at all before this) |
| `sprint.schema.json` | `docs/sprints/SPRINT-XXX.json` / `SPRINT-XXX-YY.json` | Merged: `commands/devteam-plan.md`'s `dependencies.sprints[]` shape + `agents/planning/sprint-planner.md`'s track/worktree fields |

## Status as of Phase 1

These schemas are the **documented target shape**. Nothing parses or validates against them yet — that wiring is Phase 2 (`commands/devteam-plan.md` calling the planning agents directly) and beyond. `commands/devteam-plan.md`'s own inline schema examples do **not** yet match these files; that's expected, since Phase 2 deletes that inline code path rather than reconciling it in place.

## The track / track_key convention

`sprint.schema.json` introduces `track_key` (zero-padded 2-digit string, e.g. `"01"`) alongside `track` (bare integer, e.g. `1`) to close a real ambiguity: `agents/planning/sprint-planner.md` creates worktrees as `.multi-agent/track-01` but records state under the bare key `parallel_tracks.track_info.1.*`, with no documented rule connecting the two. `commands/devteam-implement.md`'s inline worktree-path interpolation (`` `.multi-agent/track-${trackId}` ``, using the bare state key as `trackId`) would silently resolve to the wrong, nonexistent directory as a result. Use `track` for JSON fields and SQLite state keys; use `track_key` for filenames, branch names, and CLI arguments.

## Validating a document

No schema-validation dependency is part of the shipped project (nothing in `scripts/` currently requires `jsonschema`/`ajv`). To check a document by hand:

```bash
python3 -m venv /tmp/schema-venv && /tmp/schema-venv/bin/pip install jsonschema
/tmp/schema-venv/bin/python -c "
import json, jsonschema
schema = json.load(open('.devteam/schemas/task.schema.json'))
doc = json.load(open('docs/planning/tasks/TASK-001.json'))
jsonschema.validate(doc, schema)
"
```
