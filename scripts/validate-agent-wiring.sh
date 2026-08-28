#!/bin/bash
# validate-agent-wiring.sh
#
# Architecture Audit Phase 7 (governance): fails if any agent that can
# itself dispatch other agents (declares `Task` in its frontmatter `tools:`
# list) is defined but never dispatched anywhere in the repo -- i.e. it has
# zero `subagent_type: "namespace:agent-id"` references in commands/,
# skills/, or other agents.
#
# This is the "no agent ships without a caller" check (DEVTEAM Proposal.md
# §10.1 principle 6, §11 Phase 7): a repository-wide search for the literal
# `subagent_type:`/`subagent_type=` call is the only reliable signal that an
# agent is actually reachable, since a command can narrate what an agent
# "should" do (or mention its id in prose) without ever delegating to it via
# Task(). Prose mentions and comments deliberately do NOT count -- that gap
# between narration and delegation is exactly the defect this check exists
# to catch (see §2 "The Dual-Implementation Trap").
#
# Scope: the union of two criteria, not just three hardcoded directories.
# 1. Every agent under the three original watched directories
#    (agents/orchestration, agents/planning, agents/ux) -- unconditionally,
#    same as before, since that's where the non-dispatcher orchestration
#    layer lives too (scope-validator, requirements-validator,
#    quality-gate-enforcer, workflow-compliance -- none declare `Task`
#    themselves, but all are load-bearing orchestration-layer agents that
#    must stay reachable).
# 2. Any agent ANYWHERE ELSE whose own `tools:` list includes `Task` --
#    i.e. every agent designed to dispatch others, regardless of which
#    directory it lives in. A leaf implementer/specialist agent (no `Task`
#    tool, outside the three dirs) is out of scope: those are reached
#    dynamically via task-loop's `{suggested_agent}` placeholder, resolved
#    per-task at planning time, which this static check cannot verify for
#    any agent that way. But a Task-capable *coordinator* living outside
#    the three dirs is exactly the class of bug this check exists to catch
#    and previously missed: `quality:refactoring-coordinator` (a genuine
#    dispatcher in agents/quality/) was a real, live, currently-unwired
#    orphan the original three-directory scope could never have caught.
#
# Two further hardening fixes over the original version:
# - Agent id is derived from the frontmatter `name:` field, not the
#   filename. They diverge for 23+ agents in this repo (e.g.
#   agents/quality/visual-verification-agent.md has name: visual-verification)
#   -- every real caller and agent-registry.json use the name: value, so a
#   filename-derived id could silently check wiring against an id nothing
#   actually calls. A missing/empty name: field is itself a failure.
# - HTML comments are stripped before searching (in check-subagent-reference.py),
#   so a subagent_type literal quoted inside an explicit "anti-pattern, do
#   NOT do this" example cannot be miscounted as a live caller.
#
# The frontmatter-parsing and reference-search logic live in small,
# standalone scripts/lib/*.py helpers rather than inline awk/sed/python
# here -- past attempts at inlining a quote-heavy regex directly into this
# bash script were fragile to nested-quoting bugs; a separate file sidesteps
# that entirely.
#
# Usage: ./scripts/validate-agent-wiring.sh
# Exit code: 0 if every watched agent has at least one live reference and
# every frontmatter'd agent file has a real name: field; 1 otherwise.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

READ_FRONTMATTER="$SCRIPT_DIR/lib/read-agent-frontmatter.py"
CHECK_REFERENCE="$SCRIPT_DIR/lib/check-subagent-reference.py"

# Always-watched directories (criterion 1 above) -- namespace matches the
# directory basename, per agent-registry.json's "namespace:agent-id" convention.
WATCHED_DIRS=(agents/orchestration agents/planning agents/ux)

# Where a real dispatch (Task({ subagent_type: "..." })) can legally live.
SEARCH_DIRS=(commands skills agents)

orphans=()
malformed=()
checked=0
skipped=()

while IFS= read -r -d '' file; do
    first_line="$(head -n 1 "$file" | tr -d '\r')"
    if [ "$first_line" != "---" ]; then
        skipped+=("$file")
        continue
    fi

    frontmatter="$(python3 "$READ_FRONTMATTER" "$file")"
    name_value="${frontmatter%%$'\t'*}"
    tools_line="${frontmatter#*$'\t'}"

    if [ -z "$name_value" ]; then
        malformed+=("$file (missing or empty frontmatter name: field -- cannot determine its agent id, so wiring cannot be checked)")
        continue
    fi

    namespace="$(basename "$(dirname "$file")")"

    is_watched_dir=0
    for d in "${WATCHED_DIRS[@]}"; do
        [ "$namespace" = "$(basename "$d")" ] && is_watched_dir=1
    done

    is_dispatcher=0
    printf '%s' "$tools_line" | grep -qE '(^|[, ])Task([, ]|$)' && is_dispatcher=1

    if [ "$is_watched_dir" -eq 0 ] && [ "$is_dispatcher" -eq 0 ]; then
        # Neither in the always-watched orchestration/planning/ux dirs, nor
        # itself a dispatcher elsewhere -- out of scope for this check.
        continue
    fi

    agent_id="${namespace}:${name_value}"
    checked=$((checked + 1))

    matches="$(python3 "$CHECK_REFERENCE" "$agent_id" "$file" "${SEARCH_DIRS[@]}")"

    if [ -z "$matches" ]; then
        orphans+=("${agent_id} (${file})")
    fi
done < <(find agents -name "*.md" -print0 | sort -z)

echo "Checked ${checked} agent(s): all of agents/{orchestration,planning,ux} plus any dispatcher (Task-capable) agent elsewhere"
if [ ${#skipped[@]} -gt 0 ]; then
    echo "Skipped ${#skipped[@]} non-agent file(s) (no frontmatter): ${skipped[*]}"
fi

fail=0

if [ ${#malformed[@]} -gt 0 ]; then
    echo -e "${RED}FAIL${NC}: ${#malformed[@]} agent file(s) with missing/empty frontmatter name::"
    for m in "${malformed[@]}"; do
        echo "  - $m"
    done
    fail=1
fi

if [ ${#orphans[@]} -gt 0 ]; then
    echo -e "${RED}FAIL${NC}: ${#orphans[@]} orphaned dispatcher agent(s) -- defined but never dispatched via a live subagent_type: reference:"
    for o in "${orphans[@]}"; do
        echo "  - $o"
    done
    echo ""
    echo "Each agent above needs a real Task({ subagent_type: \"...\" }) call from a command, skill, or another agent."
    echo "A prose/backtick mention of the agent's id does not count as wiring -- see DEVTEAM Proposal.md section 2."
    fail=1
fi

if [ "$fail" -ne 0 ]; then
    exit 1
fi

echo -e "${GREEN}PASS${NC}: every dispatcher agent has at least one live subagent_type: reference, and every agent file has a real name."
exit 0
