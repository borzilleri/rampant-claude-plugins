# Bug Hunt Schema

Shared definitions for the adversarial bug-finding pipeline. The skill orchestrator injects relevant sections from this file into each agent's prompt.

## Bug ID Format

All bugs use the format `BH-NNN` (e.g., `BH-001`, `BH-002`). The Hunter assigns IDs sequentially. The Skeptic and Referee reference them.

## Severity Levels

| Level | Definition |
|-------|-----------|
| `critical` | Data loss, security vulnerability, crash in production path |
| `high` | Incorrect behavior in common code path, resource leak |
| `medium` | Edge case failure, degraded performance, error handling gap |
| `low` | Minor issue, cosmetic, unlikely to trigger in practice |

## Bug Categories

- Logic errors
- Null/undefined access
- Race conditions
- Resource leaks
- Security vulnerabilities
- Error handling gaps
- Type safety violations
- Edge cases
- API contract violations
- Performance bugs

## Context Format Adaptation

Code context arrives in one of two formats:

- **XML AST context** (via kraven or infiniloom): Includes symbol rankings, call graphs, and importance scores. Prioritize critical-ranked symbols. Use call graph relationships to trace bug impact across function boundaries.
- **Raw file contents**: Standard source code without semantic annotations. Analyze all functions equally.

The `<context-format>` tag indicates the active format.

### Analysis Enrichment

When tree-sitter context is available, an `__kraven_analysis__` block may appear in the context:

- **File Importance** — Dependency graph centrality (PageRank). Higher score = wider blast radius when that file has a bug.
- **Circular Dependencies** — Import cycles. High risk for initialization order bugs, infinite loops, and state corruption.
- **Dead Code** — Unused exports and private symbols. May indicate stale interfaces, incomplete refactors, or zombie code with side effects.
- **Complexity Hotspots** — High cyclomatic/cognitive complexity or deep nesting. Bugs cluster in complex code.

Prioritize analysis on high-importance files, circular dependency participants, and complexity hotspots.

## Common Output Fields

Every bug entry MUST include these fields:

```
- id: BH-NNN
- severity: critical | high | medium | low
- category: <one of the bug categories above>
- file: <relative file path>
- lines: <start>-<end>
- description: <one-line summary of the bug>
- evidence: <code snippet or reasoning demonstrating the bug>
```

Agents extend this base with their role-specific fields.
