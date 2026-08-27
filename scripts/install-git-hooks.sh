#!/bin/bash
# install-git-hooks.sh
#
# Opt-in local git pre-commit hook for the Architecture Audit Phase 7
# governance check (scripts/validate-agent-wiring.sh). Git hooks live in
# .git/hooks/, which is never tracked or shared by git itself, so each
# contributor who wants the check to run before every local commit runs
# this once after cloning. CI (.github/workflows/validate-agent-wiring.yml)
# is the check that's always enforced regardless of whether this is
# installed -- this script is a convenience to catch orphaned agents
# before pushing, not a substitute for CI.
#
# Usage: ./scripts/install-git-hooks.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOKS_DIR="$PROJECT_ROOT/.git/hooks"

if [ ! -d "$PROJECT_ROOT/.git" ]; then
    echo "ERROR: $PROJECT_ROOT is not a git repository root (no .git directory found)."
    exit 1
fi

mkdir -p "$HOOKS_DIR"

HOOK_FILE="$HOOKS_DIR/pre-commit"

if [ -f "$HOOK_FILE" ] && ! grep -q "validate-agent-wiring.sh" "$HOOK_FILE" 2>/dev/null; then
    echo "ERROR: $HOOK_FILE already exists and doesn't look like it was installed by this script."
    echo "Add the following line to it manually instead of overwriting it:"
    echo "  \"\$(git rev-parse --show-toplevel)/scripts/validate-agent-wiring.sh\""
    exit 1
fi

cat > "$HOOK_FILE" <<'EOF'
#!/bin/bash
# Installed by scripts/install-git-hooks.sh -- Architecture Audit Phase 7.
# Blocks a commit if any orchestration/planning/ux agent is left orphaned
# (defined but never dispatched via a live subagent_type: reference).
# Bypass for a single commit with: git commit --no-verify
REPO_ROOT="$(git rev-parse --show-toplevel)"
"$REPO_ROOT/scripts/validate-agent-wiring.sh"
EOF

chmod +x "$HOOK_FILE"

echo "Installed pre-commit hook at $HOOK_FILE"
echo "It runs scripts/validate-agent-wiring.sh before every commit (skip once with: git commit --no-verify)."
