---
name: state-sh-gotchas
description: Known mismatches between orchestrator docs and scripts/state.sh reality — invalid set_phase value, DEVTEAM_DIR resolution, zsh incompatibility
metadata:
  type: project
---

Concrete gotchas hit when driving `scripts/state.sh` / `scripts/events.sh` from an orchestrator agent:

1. **`set_phase "in_progress"` always fails.** `sprint-orchestrator.md` Step 1 literally instructs `set_phase "in_progress"`, but `VALID_PHASES` in `scripts/lib/common.sh` has no `in_progress` — the valid executing-state value is `executing`. Following the doc verbatim returns exit 1 and (under `set -euo pipefail`) trips the ERR trap. This is a doc bug, not a script bug.

2. **Scripts are bash-only, and the shell here is zsh.** `state.sh` uses `BASH_SOURCE[0]` to locate `lib/common.sh`; sourcing it from zsh fails with `BASH_SOURCE[0]: parameter not set` and then resolves `lib/common.sh` relative to cwd. Always invoke via `bash -c` / a `bash` wrapper script.

3. **`DEVTEAM_DIR` is how you retarget the DB.** `common.sh` does `DEVTEAM_DIR="${DEVTEAM_DIR:-.devteam}"` then `DB_FILE="${DEVTEAM_DIR}/devteam.db"`. Exporting an absolute `DEVTEAM_DIR` before sourcing is the supported way to point plugin scripts at another project's DB. Worth asserting `DB_FILE` afterwards, since a silent fallback to the plugin repo's own `.devteam` would corrupt the wrong database.

4. **Every helper invocation is a fresh shell.** Run ids from `log_agent_started` must be echoed out and passed back in explicitly; they cannot be held in shell variables across calls.

**Why:** these cost real debugging time on the first live `/devteam:implement` run and none are discoverable from the agent docs alone.

**How to apply:** when an orchestrator agent needs to write state, wrap the dev-repo scripts in a small bash helper that exports absolute `DEVTEAM_DIR`, sources both scripts, asserts `DB_FILE`, and `eval`s the passed command. Use `executing`, not `in_progress`. See [[installed-plugin-lags-dev-repo]].
