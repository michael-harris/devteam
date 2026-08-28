# Dynamic Model Selection

This document describes how models are selected for tasks based on complexity.

## Complexity Scoring (0-14 scale)

Tasks are scored on these factors:

| Factor | Points | Description |
|--------|--------|-------------|
| Files affected | 0-3 | 1 file=0, 2-3=1, 4-6=2, 7+=3 |
| Estimated lines | 0-3 | <50=0, 50-150=1, 150-300=2, 300+=3 |
| New dependencies | 0-2 | 0=0, 1-2=1, 3+=2 |
| Task type | 0-3 | docs=0, test=1, impl=2, arch=3 |
| Risk flags | 0-3 | 1 point each: security, external_integration, breaking_change |

**Total: 0-14 points**

## Tier Assignment

| Score | Tier | Starting Model |
|-------|------|----------------|
| 0-4 | Simple | Haiku |
| 5-8 | Moderate | Sonnet |
| 9-14 | Complex | Opus |

## Progression on Failure

When a task fails, escalate to next tier:

```
Simple task (0-4):
  Attempt 1: haiku
  Attempt 2: haiku (retry)
  Attempt 3: sonnet (escalate)
  Attempt 4: sonnet (retry)
  Attempt 5: opus (final escalation)

Moderate task (5-8):
  Attempt 1: sonnet
  Attempt 2: sonnet (retry)
  Attempt 3: opus (escalate)
  Attempt 4: opus (final)

Complex task (9-14):
  Attempt 1: opus
  Attempt 2: opus (retry)
  Attempt 3: opus (final)
```

## Override Rules

Some task types always use specific models:

| Task Type | Override Model | Reason |
|-----------|----------------|--------|
| security_audit | opus | Security requires deep analysis |
| architecture_decision | opus | Complex trade-offs |
| documentation | haiku | Straightforward writing |
| simple_refactoring | haiku | Mechanical changes |

## Selection Algorithm

```python
def select_model(task, attempt_number=1):
    # Check for overrides
    if task.type in MODEL_OVERRIDES:
        return MODEL_OVERRIDES[task.type]

    # Calculate complexity
    score = calculate_complexity(task)

    # Determine starting tier
    if score <= 4:
        tier = 'simple'
        models = ['haiku', 'haiku', 'sonnet', 'sonnet', 'opus']
    elif score <= 8:
        tier = 'moderate'
        models = ['sonnet', 'sonnet', 'opus', 'opus']
    else:
        tier = 'complex'
        models = ['opus', 'opus', 'opus']

    # Get model for this attempt
    model_index = min(attempt_number - 1, len(models) - 1)
    return models[model_index]

def calculate_complexity(task):
    score = 0

    # Files affected
    files = task.files_affected
    if files == 1:
        score += 0
    elif files <= 3:
        score += 1
    elif files <= 6:
        score += 2
    else:
        score += 3

    # Estimated lines
    lines = task.estimated_lines
    if lines < 50:
        score += 0
    elif lines < 150:
        score += 1
    elif lines < 300:
        score += 2
    else:
        score += 3

    # New dependencies
    deps = task.new_dependencies
    if deps == 0:
        score += 0
    elif deps <= 2:
        score += 1
    else:
        score += 2

    # Task type
    type_scores = {
        'documentation': 0,
        'testing': 1,
        'design': 1,             # spec/reference work: token/component decisions, no runtime logic
        'backend': 2,
        'frontend': 2,
        'database': 2,
        'infrastructure': 2,     # config-heavy, similar risk profile to backend/database
        'python-generic': 2,     # same tier as backend -- general-purpose scripting/utilities
        'fullstack': 3,
        'architecture': 3,
        'data_architecture': 3,  # schema/data-model decisions carry the same weight as architecture
    }
    score += type_scores.get(task.task_type, 2)

    # Risk flags
    for flag in task.risk_flags:
        if flag in ['security_sensitive', 'external_integration', 'breaking_change']:
            score += 1

    return min(score, 14)
```

## Task Loop Integration

Model selection integrates with the Task Loop quality loop:

```
┌─────────────────────────────────────────────────────────────┐
│                 TASK LOOP MODEL ESCALATION                    │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Initial: Complexity-based selection                        │
│      │                                                       │
│      ▼                                                       │
│  Attempt fails                                               │
│      │                                                       │
│      ├─── 1st failure: Retry with more context (same model) │
│      │                                                       │
│      ├─── 2nd failure: Retry with alt approach (same model) │
│      │                                                       │
│      └─── 3rd failure: ESCALATE MODEL                       │
│               │                                              │
│               ├─── haiku → sonnet                           │
│               ├─── sonnet → opus                            │
│               └─── opus → Bug Council activation            │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Escalation Thresholds

Configured in `.devteam/task-loop-config.yaml`:

```yaml
model_escalation:
  consecutive_failures:
    haiku_to_sonnet: 2    # After 2 haiku failures → sonnet
    sonnet_to_opus: 2     # After 2 sonnet failures → opus
    opus_max_failures: 3  # After 3 opus failures → Bug Council
```

### Bug Council Activation

When opus-level reasoning fails repeatedly:

1. Bug Council convenes (5 specialist agents)
2. Each analyzes from their perspective
3. Solutions are synthesized
4. Implementation continues with opus

This ensures no task is abandoned - only escalated.

## Recording Model History

Track model usage in state file:

```yaml
tasks:
  TASK-005:
    status: completed
    complexity:
      score: 6
      tier: moderate
    model_history:
      - iteration: 1
        model: sonnet
        reason: "Moderate complexity (6/14)"
        result: fail
        error: "Type error in validation"
      - iteration: 2
        model: sonnet
        reason: "Retry at same tier"
        result: pass
    iterations: 2
```

## Cost Optimization

Model costs (approximate per task):

| Model | Simple Task | Moderate Task | Complex Task |
|-------|-------------|---------------|--------------|
| Haiku | $0.05 | $0.10 | $0.15 |
| Sonnet | $0.15 | $0.30 | $0.50 |
| Opus | $0.50 | $1.00 | $2.00 |

Expected distribution for typical project:
- 60% tasks: Simple (mostly Haiku)
- 30% tasks: Moderate (mostly Sonnet)
- 10% tasks: Complex (Opus)

**Estimated savings: 40-60% vs always using Opus**
