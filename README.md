# Plan Review Skill

A Claude Code skill that runs multi-perspective plan review using parallel VP agents to identify blockers, anti-patterns, conflicts, and regressions before execution.

## Overview

Plan Review spawns three specialized AI agents — VP Product, VP Engineering, and VP Design — to simultaneously review implementation plans, design docs, architecture proposals, and wave plans. Each agent evaluates the plan through their domain lens. Findings are consolidated, ranked by severity, and presented for your approval before any changes are applied.

## Features

- **Parallel VP analysis** — Three perspectives reviewed simultaneously
- **Four issue categories** — Blockers, Anti-patterns, Conflicts, Regressions
- **Severity ranking** — Critical, High, Medium, Low with action guidance
- **Approval workflow** — Review all findings before plan edits are applied
- **Guided decision** — Ask, then execute: never modifies files without consent

## Usage

```bash
# Review a plan file
/plan-review-skill path/to/your-plan.md
```

Or trigger naturally:

```
"Review this plan for blockers and conflicts"
"Get VP feedback on the implementation plan"
"Run a stakeholder review on this design doc"
```

## VP Perspectives

| VP Role | Focus Areas |
|---------|-------------|
| **VP Product** | User impact, scope creep, dependencies, timelines |
| **VP Engineering** | Technical debt, anti-patterns, architecture conflicts, regressions |
| **VP Design** | UX consistency, accessibility, design system alignment |

## What's Checked

VP Engineering applies these rules in addition to the general review:

| Rule | Check |
|------|-------|
| P-1, P-2 | Surface grounding: hardcoded URLs, RPC names, CLI commands, env vars, and columns name a canonical source; new conventions are grep-confirmed |
| P-3 | PL/pgSQL safety: name-collision audit for `RETURNS TABLE` functions (unqualified `RETURNING` is Critical) |
| P-4 | Smoke vs CI: pre-ship verification is distinguished from a post-ship smoke path |
| P-5 | Shared-state / coordination audit: producers, consumers, invariant, and test; the reviewer auto-populates a missing matrix |
| P-6 | Observation and gate correctness in verification code (baseline-after-await, silence-as-success, asymmetric windows, stated worst case, gate the outcome) |
| P-7 | State-flip assertion audit: stale assertions about the old state, found with `scripts/scan-state-flip.sh` |
| P-8 | Negative pass criteria need both arms (show a violation could have been observed) |
| P-9 | Wave sizing reflects the residue left by earlier waves, not the original population |

It also flags plans that make a genuine architecture decision with no ADR discussion.

## Issue Severity Guide

| Severity | Action |
|----------|--------|
| Critical | Must address before proceeding |
| High | Should address before proceeding |
| Medium | Address in this iteration |
| Low | Address if time permits |

## Installation

```bash
skillsmith install wrsmith108/plan-review-skill
```

Or via the Skillsmith MCP server:

```
install_skill wrsmith108/plan-review-skill
```

Or manually copy this directory to `~/.claude/skills/plan-review-skill/`.

## Configuration

Optional environment variables:

| Variable | Description |
|----------|-------------|
| `PLAN_REVIEW_STRICT` | If `true`, require all Critical issues resolved before approval |
| `PLAN_REVIEW_AUTO_APPROVE` | If `true`, auto-approve Low severity changes |

Custom VP prompts via `.claude/plan-review-config.json` in your project root.

## Integration

Works with other Claude Code skills, if installed:

| Skill | Integration |
|-------|-------------|
| `wave-planner` | Review wave plans before execution |
| `launchpad` | Integrated as Stage 2 of the end-to-end pipeline |
| `governance` | Standards audit runs after plan approval |
