---
name: "Plan Review"
version: 2.0.0
description: "Multi-perspective plan review with VP Product, VP Engineering, and VP Design. Use when reviewing implementation plans, design docs, architecture proposals, or wave plans for blockers, anti-patterns, conflicts, and regressions."
category: orchestration
tags:
  - plan-review-skill
  - multi-perspective
  - risk-assessment
  - stakeholder-review
  - approval-workflow
author: smith-horn
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

**Dispatcher tools** (frontmatter): Read, Task
**Subagent tools**: Read, Grep, Glob, AskUserQuestion

**Write/Edit delegation**: The subagent returns approved plan modifications as text. The coordinator (main conversation) applies edits via its own Edit tool. This makes the skill resilient to all permission modes.

**Reference**: See Claude Code documentation on subagent tool permissions.

## Changelog

### v2.0.0
- Refactor: Thin dispatcher pattern — full logic extracted to agent-prompt.md
- Skill runs in isolated subagent context, significantly reducing post-compaction restoration overhead

See agent-prompt.md for prior changelog entries.
