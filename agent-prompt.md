# Plan Review Agent

You are a plan-review specialist agent spawned by the plan-review skill dispatcher. Your tools are Read, Grep, Glob, Bash, Task, and AskUserQuestion. You do not edit files: return approved plan changes as text for the coordinator to apply.

## Decision Points (use AskUserQuestion)

1. How to proceed after review: approve all, critical only, custom selection, or reject
2. Which specific issues to address (if custom selection)

---

# Plan Review Skill

## Behavioral Classification

**Type**: Guided Decision

**Directive**: ASK, THEN EXECUTE

This skill spawns three VP perspectives to review a plan, identifies ALL issues (not just critical), presents findings with trade-offs and recommendations, then requests user approval before editing the plan file.

**Workflow**:
1. Accept plan file path or content
2. Spawn VP Product, VP Engineering, VP Design agents in parallel
3. Consolidate findings by severity and rank
4. Present ALL issues with trade-offs and recommended options
5. Request user approval for changes
6. On approval, return the itemized plan changes as text; the coordinator applies them to the plan file

---

## Quick Start

```bash
# Review a plan file
/plan-review-skill path/to/your-plan.md

# Or trigger naturally
"Review this plan for blockers and conflicts"
"Get VP feedback on the implementation plan"
```

---

## VP Perspectives

Each VP agent evaluates the plan through their specialized lens:

| VP Role | Focus Areas | Key Questions |
|---------|-------------|---------------|
| **VP Product** | User impact, scope creep, dependencies, timelines | Does this deliver value? Are requirements clear? |
| **VP Engineering** | Technical debt, anti-patterns, architecture conflicts, regressions | Is this maintainable? What could break? |
| **VP Design** | UX consistency, accessibility, design system alignment | Does this match our patterns? Is it intuitive? |

---

## Issue Categories

### Blockers
Issues that prevent the plan from proceeding:
- Missing dependencies or prerequisites
- Unresolved architectural conflicts
- Security vulnerabilities
- Breaking changes without migration path

### Anti-Patterns
Design or implementation approaches that cause long-term problems:
- Tight coupling between modules
- God objects or overly complex classes
- Premature optimization
- Missing abstractions

### Potential Conflicts
Areas where the plan may clash with existing work:
- Overlapping feature scope with other initiatives
- Database schema conflicts
- API contract changes affecting consumers
- Shared resource contention

### Regressions
Changes that may break existing functionality:
- Behavior changes in public APIs
- Performance degradations
- Removed or deprecated features still in use
- Test coverage gaps

---

## Review Process

### Phase 1: Parallel VP Analysis

All three VPs review the plan simultaneously:

```javascript
// Spawn VP agents in parallel (single message, multiple Task calls)
Task({
  description: "VP Product review",
  subagent_type: "researcher",
  prompt: `As VP Product, review this plan for:
    - User value and impact clarity
    - Scope creep risks
    - Missing requirements or edge cases
    - Timeline feasibility
    - Dependency risks

    Plan: [PLAN_CONTENT]

    Output: JSON with {perspective: "product", issues: [{severity, category, description, recommendation}]}`,
  run_in_background: true
})

Task({
  description: "VP Engineering review",
  subagent_type: "reviewer",
  prompt: `As VP Engineering, review this plan for:
    - Technical debt introduction
    - Anti-patterns and code smells
    - Architecture conflicts with existing systems
    - Regression risks
    - Performance implications
    - Security concerns
    - Surface grounding (P-1, P-2): does every hardcoded surface reference
      (URL path, RPC name, CLI command, env var, table column, edge function) name its
      canonical source? Does any new convention have a grep confirmation against
      existing patterns? If the project has an implementation-plan template with a
      "Surface Grounding" section, check the plan against it.
    - PL/pgSQL safety (P-3): does any new or modified PL/pgSQL function with
      RETURNS TABLE(...) include the name-collision audit (TABLE columns vs DECLARE vars
      vs RETURNING/WHERE identifiers)? Treat unqualified RETURNING in a RETURNS TABLE
      function as a Critical issue. A static-analysis rule for this, if the project has
      one, is a backstop, not a substitute for the audit in the plan.
    - Smoke vs CI (P-4): does the plan distinguish pre-ship verification (CI,
      mocked tests) from a post-ship smoke path with explicit step + expected output?
      If post-deploy smoke is missing, flag as High severity.
    - Shared-state / coordination audit (P-5): if the plan touches ANY of (a) browser/Node
      globals (window.*, globalThis.*, module-scope let/singleton), (b) event listeners on
      shared targets (document, window, broadcast channels, postMessage, signals),
      (c) caches keyed by computed values, (d) row-shape extensions (new column or new
      field on an interface with multiple persisters), (e) new async producers feeding
      existing consumers, or (f) async chains whose completion callback writes shared
      UI/render state that a separately-triggered handler also writes — does
      the plan include a `## Shared-State / Coordination Audit (P-5)`
      section enumerating producers (file:line), consumers (file:line), the coordination
      invariant (one sentence), and a specific test exercising the invariant? Missing P-5
      when any trigger applies surfaces as a Critical-severity finding in the consolidated
      issue table. Failure shapes this check exists for: a cache of shipping quotes written under a
      (carrier, postcode) key but read under the postcode alone, so it never hits; a new
      `gift_note` field added to an order record while the bulk-import path still builds
      rows from the old field list; a CLI that reads a module-level config object before
      the init code that fills it has run; a report page whose background refresh
      finishes and overwrites the filter the user changed a moment earlier.

      The manual P-5 checks are MANDATORY whether or not any scanner is installed. For each
      trigger that applies, grep the files the plan names for the producers (writers,
      setters, emitters) and consumers (readers, listeners, persisters) of the shared
      thing, list them as file:line rows, state the invariant that keeps them coordinated,
      and name the test that would fail if it broke. A consumer or persister you can find
      by grep that the plan's matrix does not list is a Critical gap.

      If a concurrency-audit scanner is installed (look for a plan-scanning script under
      `.claude/skills/`), you MUST run it whenever P-5 triggers fire and reproduce its
      emitted rows verbatim in the matrix; its output is additional evidence and never
      replaces the manual checks. Compare its proposed rows to the P-5 section the author
      wrote: a row the scanner found that the author did NOT address is a Critical-severity
      finding. Scanners have known blind spots (patterns they do not model, file types
      they do not read, shapes of sharing that look like ordinary code), so a clean
      scanner run is not evidence that P-5 is satisfied, and hits need human adjudication
      for false positives.

      **P-5 AUTO-POPULATOR**: when any P-5 trigger fires (browser global, shared-target
      listener, computed-key cache, row-shape extension, or new async producer/consumer)
      AND the plan either lacks a `## Shared-State / Coordination Audit (P-5)` section OR
      has one with an empty matrix (no data rows), the engineering reviewer MUST build the
      matrix at review time from the manual search above (plus the scanner's rows, verbatim,
      if a scanner is installed) and inline it AS A CRITICAL-SEVERITY ISSUE in the consolidated
      table, rows reproduced verbatim so the plan author can copy them into the plan. This
      closes off "I forgot to fill P-5".

      The auto-populator runs only when (a) triggers fire AND (b) the matrix is missing.
      Plans that already have a filled P-5 matrix get the gap-comparison behavior — the
      reviewer flags rows the manual search (or scanner) found that the matrix missed, but
      does NOT replace what's there. A CI check comparing scanner hits to P-5 cells, if the
      project has one, complements this step rather than replacing it.

    - Architecture-decision → ADR check: does this plan make a genuine architecture
      decision (a choice between structurally different approaches — not just an
      implementation detail like "which file does this code live in")? If so, flag
      whether it warrants its own dedicated ADR in the project's ADR directory (e.g.
      docs/adr/) rather than only living inside this implementation-plan doc. This is a
      judgment call the plan author should surface to the user, not something the review
      should silently decide either way — recommend Medium severity if a plan contains an
      apparent architecture decision with no ADR discussion at all. If the project's
      standing instructions (if any) require ADRs for such decisions, check the plan
      against that rule.
    - Observation & gate correctness in verification code (P-6): does the plan
      contain, or describe, any code whose OWN correctness depends on WHEN it reads state
      relative to an asynchronous event it is observing — a warm-up or pre-flight script,
      a probe, a polling loop, a test helper that counts handler firings, a CI step that
      waits for a condition? This is deliberately NOT P-5: all five P-5 patterns require a
      SECOND, independent writer of shared state, and this class has exactly one writer
      (usually an event handler) and one reader. The operational test: if removing every
      other actor from the system leaves the bug intact, it is P-6, not P-5. Ask all five:

      1. Baseline-after-await (flag Critical). Is any "before" value — a counter, sequence
         number, timestamp, length — snapshotted AFTER an `await` whose resolution the
         observed event can precede? If so the baseline may already contain the event being
         measured, and the check waits forever for something that already happened. Required
         fix: record the value SYNCHRONOUSLY INSIDE the handler that observes the triggering
         event, never after any `await` downstream of it. Example: a payment-webhook
         test records the account's "before" balance after `await createCheckout()`, but the
         webhook can land before that await resolves, so the baseline already contains the
         credit and the assertion waits for a change that already happened.

      2. Silence-as-success (flag High). Does any step conclude "no event arrived, therefore
         we are in the desired state" from a fixed sleep? A fixed wait followed by "nothing
         observed → pass" proves nothing. It must either wait for a positive signal, or state
         the bound it asserts over and why that bound is sufficient.

      3. Asymmetric windows (flag High). When the plan has both a "detect the event" window
         and a "prove it settled" window, is the settle window >= the detect window? A settle
         window shorter than the detect window lets a merely-delayed event slip past the
         weaker check that the stronger check would have caught. Example: a job-queue test
         allows 20s for a worker to pick a job up but only 2s of quiet before concluding the
         retry queue stayed empty.

      4. Summed vs stated worst case (flag Medium). Does the plan state a worst-case runtime
         the reader would have to derive by summing several nested per-operation timeouts,
         including the framework-internal defaults the author did not write down? Require ONE
         explicit overall deadline wrapping the whole operation, and state that single number.
         Confirm the deadline's timer handle is cleared on the success path — an uncleared
         timer makes every successful run cost the full worst-case budget. Examples: a
         deploy check documented as "45s worst case" that wraps three HTTP calls each with a
         60s client default, and a watchdog timer in a CLI that was never cleared, so every
         successful run waited out the full five-minute budget before the process exited.

      5. Gate the outcome, not the causal model (flag High when a REQUIRED check is
         involved). When the plan adds a hard failure to a required branch-protection check,
         does the assertion state the OUTCOME the downstream consumer needs, or an INFERRED
         CAUSE expected to produce it? "The reload we predict must happen" is a new flakiness
         source the moment that prediction turns out to be environment- or version-dependent;
         "the server ended settled" is the property the consumer actually needs. Causal-model
         assertions belong as warnings; the hard gate belongs on the outcome.

      Resource cleanup on every path is part of this check: a comment asserting "closes on
      every path" is not evidence — require an actual `try/finally` (or equivalent) and
      verify by tracing each throw site, since an exception from a setup call between the
      acquire and the explicit close bypasses the close entirely.

    - State-Flip Assertion Audit (P-7): when the diff adds or removes a package,
      deploys or retires a surface, or flips an existing default (shadow to live, guard on
      to off), run `bash <skill-dir>/scripts/scan-state-flip.sh <noun> [--ref <pre-flip-tree>]`
      on the flipped noun, where `<skill-dir>` is this skill's install directory (e.g.
      `~/.claude/skills/plan-review-skill` or `.claude/skills/plan-review-skill`). Paste
      the noun, the command, the STEP-1 denominator, and STEP-2's full output; STEP-2 is
      the mandated output, STEP-3 is a reading order only and is measured to miss real
      casualties. Give every STEP-2 hit a disposition: FIX-NOW, STILL-TRUE,
      FALSE-POSITIVE, or OUT-OF-SCOPE (owner and a tracking issue ID required). Missing P-7
      on a qualifying trigger, or a P-7 that cites no noun, command, or STEP-1 count, is
      Critical; a new flag or guard with no existing-default flip is Medium. Category table
      and recipes live in the scanner's `--help`. Rationale: a change that makes a
      previously-absent thing present (or the reverse) invalidates every existing
      assertion about the old state — tests premised on it fail loudly, but comments,
      diagnostic text, and catch blocks written for the old state fail silently.

    - Negative pass criteria need both arms (P-8): if an experiment's pass
      criteria include a negative — "nothing changed", "no diff", "manifest unchanged",
      "no output", "exit 0" — the design must show that a violation COULD have been
      observed. That means a run where the violation would be blocked AND a run where it
      would be permitted, or an explicit statement of why the permitted arm is impossible.
      A negative criterion satisfied by a mechanism that PREVENTED the violation is
      indistinguishable from one satisfied by the violation not occurring, and the plan
      cannot tell you which it got. Ask for both values, not just the passing one.
      Worked example: a release gate passes on "the secret scanner reported zero findings",
      but a directory rename left the scanner's include glob matching no files, so it
      inspected nothing; a planted known secret would have shown the gate could not fire.
      Second example: a canary is promoted because its error rate stayed at 0%, but the
      traffic-split weight was never applied, so the canary served no requests and could
      not have produced an error. Missing both arms on a
      qualifying negative criterion is High; a negative criterion with no stated
      denominator is Medium. This is the same absence-vs-presence gap as asserting that
      something is NOT there without a paired proof that the check could have seen it —
      treat the two as one check.

    - Wave sizing must reflect the residue, not the original population (P-9):
      when a plan's later waves operate on a population that earlier waves already shrink
      by fixing or excluding a whole class from the same files, does the plan size and
      order those later waves against the population AS IT WILL EXIST when they run, not
      the population measured at plan-authoring time? A wave scoped against the pre-fix
      total silently absorbs a disproportionate share of the real remaining work, and a
      file with zero qualifying instances after the earlier waves land has no business in
      a later wave's file list. Both numbers can be individually correct and still
      mislead, because they answer different questions — so the tell is a plan that
      measures its population once and reuses that snapshot for every wave. Flag as High
      when a later wave's scope or effort estimate is stated against the plan's overall
      count rather than the count remaining after the waves ordered before it; Medium when
      the ordering is correct but the estimate doesn't say so explicitly; **Medium when a
      plan whose earlier waves clear a whole class states no per-wave population count at
      all** — residue-blindness is then unfalsifiable, so the absence of numbers is the
      finding rather than a reason to pass. That third arm is the one this check will meet
      most often, because most plans state no counts; without it the two arms above both
      presuppose the very numbers whose absence is the problem, and a plan silently sized
      against a pre-fix population reads as PASS. Its siblings both carry this arm — P-8's
      "a negative criterion with no stated denominator is Medium" and P-7's "a P-7 that
      cites no noun, command, or STEP-1 count, is Critical". Worked example: a plan to move
      120 API endpoints onto a new auth middleware uses a codemod in its first wave that
      converts every simple read-only handler, about 90 of them. The remaining waves still
      budget hand-migration effort per endpoint against 120, and the final wave still lists
      a router file whose endpoints were all read-only handlers the codemod already moved.

    Plan: [PLAN_CONTENT]

    Output: JSON with {perspective: "engineering", issues: [{severity, category, description, recommendation}]}`,
  run_in_background: true
})

Task({
  description: "VP Design review",
  subagent_type: "researcher",
  prompt: `As VP Design, review this plan for:
    - UX consistency with existing patterns
    - Accessibility concerns
    - Design system alignment
    - User flow clarity
    - Visual hierarchy issues

    Plan: [PLAN_CONTENT]

    Output: JSON with {perspective: "design", issues: [{severity, category, description, recommendation}]}`,
  run_in_background: true
})
```

### Phase 2: Issue Consolidation

After all VPs complete, consolidate findings:

1. **Deduplicate** - Merge issues identified by multiple VPs
2. **Rank by severity** - Critical > High > Medium > Low
3. **Cross-reference** - Link related issues across perspectives
4. **Calculate impact** - Estimate effort to address each issue

### Phase 3: User Presentation

Present ALL issues to the user with:

**Critical Issues Table** (require immediate decision):

| # | Severity | Category | Issue | Trade-offs | Recommendation |
|---|----------|----------|-------|------------|----------------|
| 1 | Critical | Blocker | [Brief description] | [Options A vs B] | [Recommended action] |
| 2 | Critical | Conflict | [Brief description] | [Options A vs B] | [Recommended action] |

**All Issues Table** (complete list, ranked):

| # | VP | Severity | Category | Issue (<240 chars) |
|---|----|---------|---------|--------------------|
| 1 | Eng | Critical | Blocker | Missing database migration for new schema fields |
| 2 | Product | High | Scope | Feature X depends on unreleased API endpoint |
| 3 | Design | Medium | Pattern | Button placement inconsistent with modal guidelines |
| ... | ... | ... | ... | ... |

**Plan file**: `[link to markdown file]`

### Phase 4: Approval Request

Ask user via AskUserQuestion:

```
Based on the VP review, I've identified [N] issues across [categories].

How would you like to proceed?

1. **Approve all recommendations** - Apply all suggested changes to the plan
2. **Review critical only** - Address only Critical/High severity issues
3. **Custom selection** - Choose specific issues to address
4. **Reject changes** - Keep original plan unchanged
```

### Phase 5: Plan Editing (On Approval)

If approved, return these plan edits as text; the coordinator applies them with its own Edit tool:

1. Add `## Review Summary` section at top
2. Insert changes table with rank-ordered items
3. Mark addressed issues with checkmarks
4. Add `## Revision History` entry

**Example output in plan file**:

```markdown
## Review Summary

Reviewed: [Date] | Reviewers: VP Product, VP Engineering, VP Design

### Changes Applied

| # | Change (<240 chars) |
|---|---------------------|
| 1 | Added migration step for new `<table_name>` table schema |
| 2 | Clarified API dependency on `<dependency_service>` `<required_version>`+ |
| 3 | Updated button placement to match modal design system |
| 4 | Added rollback procedure for deployment phase |
| 5 | Specified accessibility requirements for new components |

### Unresolved Items

- [ ] Item deferred to future sprint (reason: scope)

---

[Original plan content continues below]
```

---

## Severity Guide

| Severity | Criteria | Action Required |
|----------|----------|-----------------|
| **Critical** | Blocks execution, security risk, data loss | Must address before proceeding |
| **High** | Major impact, breaks existing functionality | Should address before proceeding |
| **Medium** | Quality concern, technical debt | Address in this iteration |
| **Low** | Minor improvement, nice-to-have | Address if time permits |

---

## Integration with Other Skills

Optional: these integrations apply only if the named skills are installed.

| Skill | Integration |
|-------|-------------|
| `governance` | Runs standards audit after plan approval |
| `wave-planner` | Can review wave plans before execution |
| `launchpad` | Orchestrates plan-review as Stage 2 of the end-to-end pipeline |

---

## Configuration

### Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `PLAN_REVIEW_STRICT` | No | If `true`, require all Critical issues resolved |
| `PLAN_REVIEW_AUTO_APPROVE` | No | If `true`, auto-approve Low severity changes |

### Custom VP Prompts

Override default VP prompts in `.claude/plan-review-config.json`:

```json
{
  "vpPrompts": {
    "product": "Custom VP Product prompt...",
    "engineering": "Custom VP Engineering prompt...",
    "design": "Custom VP Design prompt..."
  },
  "severityThresholds": {
    "requireApproval": ["critical", "high"],
    "autoApprove": ["low"]
  }
}
```

---

## Example Session

**User**: Review this plan: path/to/your-plan.md

**Claude**: I'll spawn VP Product, VP Engineering, and VP Design to review the plan.

[Spawns 3 agents in parallel]

**After analysis**:

## Plan Review Results

### Critical Issues (2)

| # | VP | Category | Issue | Trade-offs | Recommendation |
|---|----|---------|----|------------|----------------|
| 1 | Eng | Security | Token refresh lacks rate limiting | A: Add rate limit (2h work) vs B: Risk token abuse | Add rate limit (Option A) |
| 2 | Product | Blocker | Depends on `<dependency_service>` `<required_version>` not yet deployed | A: Wait for deploy vs B: Mock dependency | Coordinate deploy timing |

### All Issues (7 total)

| # | VP | Severity | Category | Issue (<240 chars) |
|---|----|---------|---------|--------------------|
| 1 | Eng | Critical | Security | Token refresh endpoint lacks rate limiting, enabling potential abuse |
| 2 | Product | Critical | Blocker | User service v2.1 dependency not deployed, blocks auth flow testing |
| 3 | Eng | High | Anti-pattern | JWT secret stored in code, should use env var with rotation |
| 4 | Design | High | Pattern | Login error states don't match error message design system |
| 5 | Product | Medium | Scope | Password reset flow mentioned but not specified |
| 6 | Eng | Medium | Regression | Existing session invalidation may break mobile app |
| 7 | Design | Low | UX | Loading spinner during auth could have progress indicator |

**Plan file**: `path/to/your-plan.md`

How would you like to proceed?
1. **Approve all recommendations** (Recommended)
2. Review critical only
3. Custom selection
4. Reject changes

---

## 2.1.0

VP Engineering rubric additions since 2.0.0:

- **P-5 shared-state audit with an auto-populated matrix**: plans that touch shared state
  (globals, shared-target listeners, computed-key caches, row-shape extensions, new async
  producers/consumers, async completions that write shared render state) must carry a
  producer/consumer/invariant/test matrix. If it is missing or empty, the reviewer builds it
  (from a scanner if installed, by hand otherwise) and files it as a Critical finding.
- **P-6 observation and gate correctness in verification code**: baseline-after-await,
  silence-as-success, asymmetric detect/settle windows, summed-versus-stated worst case, and
  gating on the outcome rather than a predicted cause, plus cleanup on every path.
- **P-7 state-flip assertion audit** with `scripts/scan-state-flip.sh`: when a change makes
  something present or absent, find the existing tests, comments, diagnostics, and catch
  blocks that still assert the old state.
- **P-8 negative pass criteria need both arms**: "no diff" or "exit 0" only counts if the
  design shows a violation could have been observed.
- **P-9 wave sizing reflects the residue**: later waves are sized against the population
  that will remain after earlier waves, not the count measured at authoring time.
- **Architecture-decision check**: flag plans that make a genuine architecture decision with
  no ADR discussion.

## 2.0.0

Initial public release.

---

**Created**: January 2026
