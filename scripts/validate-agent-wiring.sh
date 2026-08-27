#!/bin/bash
# validate-agent-wiring.sh
#
# Architecture Audit Phase 7 (governance): fails if any orchestration,
# planning, or ux agent is defined but never dispatched anywhere in the
# repo -- i.e. it has zero `subagent_type: "namespace:agent-id"` references
# in commands/, skills/, or other agents.
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
# Usage: ./scripts/validate-agent-wiring.sh
# Exit code: 0 if every watched agent has at least one live reference, 1 otherwise.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Agent directories whose contents must have a live caller. Namespace is
# derived from the directory name, matching agent-registry.json's
# "namespace:agent-id" convention (e.g. agents/orchestration/task-loop.md
# -> "orchestration:task-loop").
WATCHED_DIRS=("agents/orchestration" "agents/planning" "agents/ux")

# Where a real dispatch (Task({ subagent_type: "..." })) can legally live.
SEARCH_DIRS=("commands" "skills" "agents")

orphans=()
checked=0
skipped=()

for dir in "${WATCHED_DIRS[@]}"; do
    if [ ! -d "$dir" ]; then
        echo -e "${YELLOW}WARN${NC}: watched directory '$dir' does not exist, skipping" >&2
        continue
    fi

    namespace="$(basename "$dir")"

    while IFS= read -r -d '' file; do
        # Non-agent files (e.g. agents/ux/README.md) carry no YAML
        # frontmatter -- every real agent definition starts with `---`.
        first_line="$(head -n 1 "$file")"
        if [ "$first_line" != "---" ]; then
            skipped+=("$file")
            continue
        fi

        base="$(basename "$file" .md)"
        agent_id="${namespace}:${base}"
        checked=$((checked + 1))

        # Look for a literal subagent_type reference to this agent's id,
        # in either `subagent_type: "id"` or `subagent_type="id"` form
        # (both are used across the repo), excluding the agent's own
        # definition file (a self-mention isn't a caller).
        matches="$(grep -rlE "subagent_type[:=][[:space:]]*['\"]${agent_id}['\"]" \
            "${SEARCH_DIRS[@]}" --include="*.md" 2>/dev/null | grep -vFx "$file" || true)"

        if [ -z "$matches" ]; then
            orphans+=("${agent_id} (${file})")
        fi
    done < <(find "$dir" -maxdepth 1 -name "*.md" -print0 | sort -z)
done

echo "Checked ${checked} agent(s) across: ${WATCHED_DIRS[*]}"
if [ ${#skipped[@]} -gt 0 ]; then
    echo "Skipped ${#skipped[@]} non-agent file(s) (no frontmatter): ${skipped[*]}"
fi

if [ ${#orphans[@]} -gt 0 ]; then
    echo -e "${RED}FAIL${NC}: ${#orphans[@]} orphaned agent(s) -- defined but never dispatched via a live subagent_type: reference:"
    for o in "${orphans[@]}"; do
        echo "  - $o"
    done
    echo ""
    echo "Each agent above needs a real Task({ subagent_type: \"...\" }) call from a command, skill, or another agent."
    echo "A prose/backtick mention of the agent's id does not count as wiring -- see DEVTEAM Proposal.md section 2."
    exit 1
fi

echo -e "${GREEN}PASS${NC}: every orchestration/planning/ux agent has at least one live subagent_type: reference."
exit 0
