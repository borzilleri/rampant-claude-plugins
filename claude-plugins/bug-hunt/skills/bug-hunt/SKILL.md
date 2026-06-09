---
name: bug-hunt
description: >
  Use when user wants to find bugs, hunt for bugs, review code for bugs,
  check for issues, or any request to systematically analyze code for defects.
  Runs a 3-agent adversarial pipeline for high-fidelity results.
argument-hint: "[--changed | --path=<glob> | --fix | --nuclear] [paths...]"
allowed-tools:
  - Bash
  - Read
  - Grep
  - Glob
  - AskUserQuestion
---

# Bug Hunt — Adversarial 3-Agent Pipeline

Three agents with opposing biases find real bugs with high fidelity:
1. **Kraven** (Hunter) — finds aggressively (rewarded for volume)
2. **Calypso** (Skeptic) — disproves aggressively (penalized for wrong dismissals)
3. **Chameleon** (Referee) — judges accurately (scored against "ground truth")

## Step 0: Check for Kraven CLI

```bash
which kraven 2>/dev/null
```

If `kraven` is on PATH, delegate to the native binary. Kraven calls Bedrock directly — faster and cheaper than the subagent pipeline.

### Prerequisites

Kraven requires `AWS_BEARER_TOKEN_BEDROCK` in the environment. If unset, warn the user:

> "Kraven requires AWS Bedrock access. Set `AWS_BEARER_TOKEN_BEDROCK` in your environment, then retry."

### Build the kraven command from `$ARGUMENTS`:

| Skill argument | Kraven flag |
|----------------|-------------|
| `--changed` | `--changed` |
| `--path=<glob>` | `--glob <glob>` |
| Explicit paths | Positional args |
| `--fix` | `--fix` |
| `--nuclear` | `--nuclear` |
| No paths or flags | Pass current directory as positional arg |

Kraven defaults to `--format markdown`.

#### Nuclear mode

`--nuclear` runs 4 specialist hunters (security, logic, concurrency, config) per chunk plus cross-boundary analysis. Use for thorough audits. Costs ~4x more API calls.

For large repos (500+ files), add pacing to avoid Bedrock rate limits:

```bash
kraven <resolved-args> --rpm 20 --concurrency 3 --chunk-size 400000
```

#### Recommended defaults for large repos

| Repo size | Flags |
|-----------|-------|
| < 100 files | No extra flags needed |
| 100-500 files | `--concurrency 3 --rpm 30` |
| 500+ files | `--concurrency 3 --rpm 20 --chunk-size 400000` |
| 500+ files + nuclear | `--concurrency 3 --rpm 20 --chunk-size 400000 --nuclear` |

### Run it:

```bash
kraven <resolved-args>
```

### Interpret the exit code:

| Exit code | Meaning | Action |
|-----------|---------|--------|
| 0 | No confirmed bugs | Present the clean report |
| 1 | Confirmed bugs found | Present the report (this is the success case) |
| 2+ | Usage or auth error | Show the error, do NOT fall back to subagent pipeline |

Present kraven's output directly to the user and **stop** — skip Steps 1-5.

---

**If kraven is not available, continue with the subagent pipeline:**

## Step 1: Determine Scope

Parse `$ARGUMENTS` to determine what code to analyze:

| Argument | Behavior |
|----------|----------|
| `--changed` | Analyze files changed in current branch vs base (git diff) |
| `--path=<glob>` | Analyze files matching the glob pattern |
| Explicit paths (e.g., `src/auth.ts`) | Analyze those specific files |
| No arguments | Ask the user what to analyze |

Extract the `--fix` flag if present — this enables fix suggestions in the Referee's output.

Store the resolved file list for context generation.

## Step 2: Generate Code Context

Check if `infiniloom` is available:

```bash
which infiniloom 2>/dev/null
```

### If infiniloom is available

Choose the command based on scope:

- **`--changed` mode**: Run `infiniloom diff --format xml --model claude --max-tokens TOKEN_BUDGET`
- **`--path` or explicit paths**: Run `infiniloom pack --format xml --model claude --max-tokens TOKEN_BUDGET <paths>`

Where `TOKEN_BUDGET` is dynamic per agent stage (see Step 4).

Set the context format tag:
```
<context-format>xml-ast</context-format>
```

### If infiniloom is not available

Read the target files and assemble them into a `<files>` block:

```xml
<files>
  <file path="src/auth.ts">
    <content><![CDATA[
... file contents ...
    ]]></content>
  </file>
</files>
```

If total exceeds 200,000 bytes, warn the user:
> "Target files total {N}KB. For large codebases, install kraven (`cargo install --git <repo> --path cli`) for chunked analysis with tree-sitter AST context."

Set the context format tag:
```
<context-format>raw</context-format>
```

## Step 3: Load Shared Schema

Read [schema.md](schema.md) once. Inject the following sections into each agent's prompt:
- Bug categories
- Severity levels
- Context format adaptation
- Common output fields

This ensures all three agents use identical definitions.

## Step 4: Run the Pipeline

Execute agents sequentially. Each agent sees only structured output from prior agents — never their reasoning.

### Dynamic Token Budgets

When using infiniloom, re-run the command with adjusted `--max-tokens` per stage:

| Agent | Token Budget | Rationale |
|-------|-------------|-----------|
| Hunter | 100,000 | Full context, no prior reports |
| Skeptic | 80,000 | Reserves ~20K for Hunter report |
| Referee | 60,000 | Reserves ~40K for both reports + fix output |

For raw file fallback, apply proportional byte limits (400KB / 320KB / 240KB).

### 4a: Invoke bug-hunter

Spawn the **bug-hunter** agent with:
- The code context (XML AST or raw files)
- The schema sections

Present the Hunter's report:
> "**Kraven found N potential bugs** (N critical, N high, N medium, N low). Passing to Calypso for adversarial challenge."

### 4b: Invoke bug-skeptic

Spawn the **bug-skeptic** agent with:
- The Hunter's complete report
- The code context (regenerated at 80K budget if using infiniloom)
- The schema sections

Present the Skeptic's report:
> "**Calypso reviewed N findings**: N disproved, N confirmed, N partially valid. Passing to Chameleon for final judgment."

### 4c: Invoke bug-referee

Spawn the **bug-referee** agent with:
- The Hunter's complete report
- The Skeptic's complete report
- The code context (regenerated at 60K budget if using infiniloom)
- The schema sections
- Fix mode flag (if `--fix` was specified)

Present the Referee's verdict.

## Step 5: Present Final Summary

```
## Bug Hunt Results

Pipeline: Kraven -> Calypso -> Chameleon
Scope: <what was analyzed>
Context: <xml-ast | raw>

### Confirmed Bugs
<list of CONFIRMED BUG entries with severity, file, and description>

### Dismissed
<list of NOT A BUG entries with one-line reasoning>

### Pipeline Accuracy
- Hunter accuracy: N/N (N%)
- Skeptic accuracy: N/N (N%)
```

If `--fix` was enabled, include the Referee's suggested fixes for each confirmed bug.
