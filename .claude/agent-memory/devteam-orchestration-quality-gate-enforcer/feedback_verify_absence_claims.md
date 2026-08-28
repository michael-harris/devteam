---
name: verify-absence-claims
description: Never assert "field/column/function X does not exist anywhere" as a blocking violation without grepping models, migrations, and schema files first
metadata:
  type: feedback
---

Before failing a gate on the grounds that something **does not exist anywhere in the
system**, grep for it directly — models, migrations, schema files, and config — and cite
file:line. An absence claim is a much stronger assertion than a presence claim and is
easy to get wrong by reasoning only from the requirements/task JSON.

**Why:** on TASK-007 iteration 1 I raised a blocking violation stating `user.name` "is
never collected anywhere in the system." That was materially wrong: `users.name` existed
as a NOT-NULL column (`backend/app/models.py`, and the alembic
`create_users_and_tasks_tables` migration). `orchestration:task-loop` had to verify the
column itself and correct me in the iteration-2 dispatch. The true, narrower finding was
that no *user input* reaches that column because signup collects only email + password —
a different defect with a different owner and a different fix.

**How to apply:** when about to write "no upstream task produces X" or "X has no defined
source," first grep the data layer for X. Then state the precise version of the finding:
distinguish "the column does not exist" from "the column exists but nothing writes to it"
from "something writes it but the value is undefined." Only the shape you can actually
evidence goes in the violation. Also honor the reverse: if a spec cites a file:line as
evidence, open it and confirm the citation rather than taking it on faith — on TASK-007
iteration 2 the spec's two citations checked out exactly.

See [[design-task-gate-scoping]], whose "fields required by the contract that no upstream
task ever produces" clause is what I over-applied here.
