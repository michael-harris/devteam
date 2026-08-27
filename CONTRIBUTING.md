# Contributing to DevTeam

Thank you for your interest in contributing to DevTeam! This document provides guidelines and instructions for contributing to the project.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [Project Structure](#project-structure)
- [Contributing Guidelines](#contributing-guidelines)
- [Creating Agents](#creating-agents)
- [Adding Commands](#adding-commands)
- [Writing Tests](#writing-tests)
- [Pull Request Process](#pull-request-process)
- [Style Guide](#style-guide)

## Code of Conduct

Be respectful, inclusive, and constructive. We're all here to build something great together.

## Getting Started

### Prerequisites

- **Bash 4.0+** (macOS users: `brew install bash`)
- **SQLite3** (`brew install sqlite3` or `apt-get install sqlite3`)
- **Claude Code CLI** installed and configured
- **Git** for version control

### Fork and Clone

```bash
# Fork the repository on GitHub, then:
git clone https://github.com/YOUR_USERNAME/devteam.git
cd devteam
```

## Development Setup

### 1. Initialize the Development Environment

```bash
# Create the .devteam directory structure
mkdir -p .devteam/memory

# Initialize the database (auto-created on first use, or manually):
# Linux/macOS
./scripts/db-init.sh
# Windows
# powershell ./scripts/db-init.ps1

# Run the test suite to verify setup
./tests/run-tests.sh
```

### 2. Enable Debug Logging

```bash
# Set log level for verbose output
export DEVTEAM_LOG_LEVEL=debug
```

### 3. Verify Installation

```bash
# Source the scripts and test
source ./scripts/state.sh
generate_session_id  # Should output: session-YYYYMMDD-HHMMSS-hexchars
```

## Project Structure

```
devteam/
├── agents/                 # AI agent definitions (91 agents)
│   ├── core/              # Core orchestration agents
│   ├── specialized/       # Domain-specific agents
│   ├── quality/           # Quality assurance agents
│   └── ...
├── commands/              # Slash command implementations
├── skills/                # Capability modules
├── hooks/                 # Git and system hooks
├── scripts/               # Shell scripts for state management
│   ├── lib/              # Shared libraries
│   ├── state.sh          # Session state management
│   ├── events.sh         # Event logging
│   └── db-init.sh        # Database initialization
├── tests/                 # Test suite
├── docs/                  # Documentation
└── .devteam/             # Runtime data (gitignored)
```

## Contributing Guidelines

### What We're Looking For

1. **Bug fixes** with test coverage
2. **New agents** for specialized domains
3. **Documentation improvements**
4. **Performance optimizations**
5. **Security enhancements**

### What to Avoid

1. Breaking changes to existing APIs
2. Changes without tests
3. Large PRs without discussion
4. Commits with sensitive data

## Creating Agents

Agents are the core of DevTeam. Here's how to create a new one:

### 1. Choose the Right Category

| Category | Purpose |
|----------|---------|
| `core/` | Orchestration, planning, execution |
| `specialized/` | Domain-specific expertise |
| `quality/` | Testing, verification, review |
| `language/` | Language-specific implementations |
| `framework/` | Framework-specific knowledge |

### 2. Use the Agent Template

```bash
# Copy the template
cp agents/templates/base-agent.md agents/specialized/my-new-agent.md
```

### 3. Agent Structure

Every agent must include these sections:

```markdown
# Agent Name

## Role
Brief description of what this agent does.

## Capabilities
- Capability 1
- Capability 2

## When to Use
Describe scenarios when this agent should be selected.

## Instructions
Detailed instructions for the agent's behavior.

## Output Format
Expected output structure.

## Examples
Concrete examples of agent behavior.
```

### 4. Register the Agent

Add your agent to `agent-registry.json`:

```json
{
  "agents": [
    {
      "id": "specialized:my-new-agent",
      "name": "My New Agent",
      "description": "Brief description of what this agent does",
      "file": "agents/specialized/my-new-agent.md",
      "model": "sonnet",
      "category": "specialized"
    }
  ]
}
```

**Agent schema fields:**
| Field | Required | Description |
|-------|----------|-------------|
| `id` | Yes | Unique identifier (format: `category:name`) |
| `name` | Yes | Human-readable name |
| `description` | Yes | Brief description of capabilities |
| `file` | Yes | Path to agent markdown file |
| `model` | No | Model tier: `opus`, `sonnet`, or `haiku` (default: sonnet) |
| `category` | Yes | Agent category for organization |

### 5. Wire It Up (orchestration/planning/ux agents)

If your new agent lives in `agents/orchestration/`, `agents/planning/`, or `agents/ux/`, it must be dispatched by at least one real `Task({ subagent_type: "..." })` call from a command, a skill, or another agent — not just described in prose. A CI check (`scripts/validate-agent-wiring.sh`, wired into `.github/workflows/validate-agent-wiring.yml`) fails the build on any agent in those three directories with zero live `subagent_type:` references anywhere in the repo. This exists because that exact failure mode — a well-written orchestrator agent that nothing ever calls — has happened twice in this repo's history (see `DEVTEAM Proposal.md` §9); the check exists to make sure it can't happen silently a third time.

Before opening a PR, run it locally:

```bash
./scripts/validate-agent-wiring.sh
```

### 6. Test Your Agent

```bash
# Run agent-specific tests
./tests/test-agent.sh my-new-agent
```

## Adding Commands

Commands are user-facing slash commands.

### 1. Create the Command File

```bash
# Create in commands directory
touch commands/my-command.md
```

### 2. Command Structure

```markdown
# /devteam:my-command

## Description
What this command does.

## Usage
```
/devteam:my-command [options]
```

## Options
- `--flag`: Description

## Examples
```
/devteam:my-command --flag value
```

## Implementation
[Agent instructions for executing this command]
```

### 3. Register the Command

Add to `agent-registry.json`:

```json
{
  "commands": [
    {
      "name": "my-command",
      "description": "Brief description",
      "path": "commands/my-command.md"
    }
  ]
}
```

## Writing Tests

All contributions should include tests.

### Test File Structure

```bash
tests/
├── run-tests.sh           # Main test runner
├── test-state.sh          # State management tests
├── test-events.sh         # Event logging tests
├── test-validation.sh     # Input validation tests
└── test-agents/           # Agent-specific tests
```

### Writing a Test

```bash
#!/bin/bash
# tests/test-my-feature.sh

source "$(dirname "$0")/../scripts/lib/common.sh"
source "$(dirname "$0")/test-helpers.sh"

test_my_feature() {
    # Arrange
    local input="test value"

    # Act
    local result=$(my_function "$input")

    # Assert
    assert_equals "expected" "$result" "my_function should return expected"
}

# Run tests
run_test test_my_feature
```

### Running Tests

```bash
# Run all tests
./tests/run-tests.sh

# Run specific test file
./tests/test-state.sh

# Run with verbose output
DEVTEAM_LOG_LEVEL=debug ./tests/run-tests.sh
```

## Pull Request Process

### 1. Create a Feature Branch

```bash
git checkout -b feature/my-feature
```

### 2. Make Your Changes

- Write code
- Add tests
- Update documentation

### 3. Run Quality Checks

```bash
# Run all tests
./tests/run-tests.sh

# Confirm no orchestration/planning/ux agent was left orphaned
./scripts/validate-agent-wiring.sh

# Check shell scripts with shellcheck (if available)
shellcheck scripts/*.sh scripts/lib/*.sh
```

CI (`.github/workflows/validate-agent-wiring.yml`) runs the wiring check automatically on every PR, but running it locally first is faster than waiting on a red check. To have it run automatically before every local commit, opt in with:

```bash
./scripts/install-git-hooks.sh
```

### 4. Commit with Descriptive Messages

```bash
git commit -m "feat: Add new agent for X functionality

- Add agent definition in agents/specialized/
- Register in plugin.json
- Add tests for agent selection
- Update documentation"
```

### 5. Push and Create PR

```bash
git push -u origin feature/my-feature
# Then create PR on GitHub
```

### PR Template

```markdown
## Summary
Brief description of changes.

## Changes
- Change 1
- Change 2

## Testing
- [ ] Added unit tests
- [ ] Ran full test suite
- [ ] Tested manually

## Documentation
- [ ] Updated relevant docs
- [ ] Added inline comments where needed
```

## Style Guide

### Shell Scripts

```bash
#!/bin/bash
# Script description
# Usage: script.sh [options]

set -euo pipefail

# Constants in UPPER_SNAKE_CASE
readonly MY_CONSTANT="value"

# Functions in lower_snake_case with documentation
# Args: param1 - description
# Returns: description
my_function() {
    local param1="$1"

    # Validate inputs
    if [ -z "$param1" ]; then
        log_error "param1 required"
        return 1
    fi

    # Implementation
    echo "$param1"
}
```

### Key Principles

1. **Always use `set -euo pipefail`** for error handling
2. **Validate all inputs** before use
3. **Use `local` for function variables**
4. **Document function parameters and return values**
5. **Escape SQL values** using `sql_escape()` function
6. **Use structured logging** via `log_info()`, `log_error()`, etc.

### Agent Markdown

- Use clear, imperative language
- Include concrete examples
- Define output format precisely
- List all capabilities explicitly

### Naming Conventions

| Type | Convention | Example |
|------|------------|---------|
| Agents | kebab-case | `code-reviewer.md` |
| Commands | kebab-case | `run-tests.md` |
| Scripts | kebab-case | `db-init.sh` |
| Functions | snake_case | `get_current_session()` |
| Constants | UPPER_SNAKE | `MAX_ITERATIONS` |
| Variables | snake_case | `session_id` |

## Security Guidelines

1. **Never commit secrets** - Use environment variables
2. **Validate all user input** - Use validation functions
3. **Escape SQL values** - Use `sql_escape()` always
4. **Check file paths** - Validate before operations
5. **Use shellcheck** - Lint your shell scripts

## Getting Help

- **Issues**: Open a GitHub issue for bugs or features
- **Discussions**: Use GitHub Discussions for questions
- **Documentation**: Check `/docs` for detailed guides

## Recognition

Contributors will be recognized in:
- The CONTRIBUTORS.md file
- Release notes for significant contributions
- The project README for major features

Thank you for contributing to DevTeam!
