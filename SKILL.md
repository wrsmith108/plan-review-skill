---
name: "Plan Review"
version: 2.1.0
description: "Multi-perspective plan review with VP Product, VP Engineering, and VP Design. Use when reviewing implementation plans, design docs, architecture proposals, or wave plans for blockers, anti-patterns, conflicts, and regressions."
category: orchestration
tags:
  - plan-review-skill
  - multi-perspective
  - risk-assessment
  - stakeholder-review
  - approval-workflow
author: wrsmith108
triggers:
  keywords:
    - review this plan
    - check the plan
    - plan review
    - review my plan
    - assess this plan
    - evaluate the plan
    - stakeholder review
    - VP review
    - executive review
  explicit:
    - /plan-review-skill
tools:
  - Read
  - Task
  - Bash
---

# Plan Review

Multi-perspective plan review with VP Product, VP Engineering, and VP Design to identify blockers, anti-patterns, conflicts, and regressions.

## Execution

When triggered, **immediately**:

1. Read `agent-prompt.md` from this skill's directory:
   - User install: `~/.claude/skills/plan-review-skill/agent-prompt.md`
   - Project install: `.claude/skills/plan-review-skill/agent-prompt.md`
2. Spawn a single Task with `subagent_type: "general-purpose"` passing the agent-prompt content as the prompt
3. Include in the prompt: the user's request, the plan file path or content, and current working directory
4. Wait for the agent to complete
5. Present the agent's summary to the user

Do NOT execute the review workflow in this session. The subagent handles VP agent spawning, issue consolidation, and user interaction (AskUserQuestion). **Plan edits are returned as recommendations** for the coordinator to apply — the subagent should not edit files directly, as background execution auto-denies Write/Edit tools.

## Execution Context Requirements

This skill spawns a general-purpose subagent that coordinates VP review agents and consolidates findings.

**Foreground execution required**: Yes for interactive AskUserQuestion prompts. Background execution auto-denies clarifying questions.

**Dispatcher tools** (frontmatter): Read, Task, Bash (Bash is needed for the P-7 scanner fallback)
**Subagent tools**: Read, Grep, Glob, Bash, Task, AskUserQuestion (Task to spawn the three VP agents; Bash to run the P-7 scanner). No Write/Edit.

**Write/Edit delegation**: The subagent returns approved plan modifications as text. The coordinator (main conversation) applies edits via its own Edit tool. This makes the skill resilient to all permission modes.

**Reference**: See Claude Code documentation on subagent tool permissions.

## Bundled Scripts

`scripts/scan-state-flip.sh` is the scanner behind the P-7 State-Flip Assertion Audit. The review subagent runs it (via Bash) against the noun a change flips, e.g. `bash <skill-dir>/scripts/scan-state-flip.sh <noun> [--ref <pre-flip-tree>]`; run `--help` for scope options. It needs `git` and must run inside a git repository. If the subagent has no Bash access, the coordinator (which has Bash) runs the script and passes the output back.

The P-5 shared-state audit is always performed by hand; it does not depend on any extra tooling. If a concurrency-audit scanner (a separate skill) is installed, the reviewer must run it whenever P-5 triggers and reproduce its rows verbatim. Its output adds evidence and never replaces the manual checks.

## Changelog

### v2.1.0
- Rubric additions: P-5 shared-state audit with auto-populated matrix, P-6 observation/gate correctness, P-7 state-flip audit (`scripts/scan-state-flip.sh`), P-8 negative pass criteria need both arms, P-9 wave sizing reflects the residue, ADR-worthiness check
- P-5 manual checks are mandatory; a concurrency-audit scanner, if installed, is supplemental evidence only

### v2.0.0
- Refactor: Thin dispatcher pattern — full logic extracted to agent-prompt.md
- Skill runs in isolated subagent context, significantly reducing post-compaction restoration overhead

See agent-prompt.md for the full changelog.
