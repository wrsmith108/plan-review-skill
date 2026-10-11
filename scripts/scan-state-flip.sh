#!/usr/bin/env bash
# shellcheck disable=SC2016  # backticks in printf format strings are markdown, not command substitution
# plan-review-skill / P-7: State-Flip Assertion Audit scanner
#
# A change that makes a previously-absent thing PRESENT (or a previously-
# present thing ABSENT) invalidates every existing assertion about the old
# state: tests whose premise was the old state (fails loudly), comments and
# docs asserting the old state (silent), diagnostic text naming the old state
# as the only explanation (silent, misleads the fix), and catch blocks written
# when the old state was the only possible failure (silent, miscategorizes a
# new failure).
#
# This script finds candidate survivors of a state flip: every line matching
# the flipped noun, then narrowed to lines that also carry absence-vocabulary.
# It reports its own denominator so a reviewer cannot satisfy P-7 by pasting a
# bare number for the wrong noun. A noun with zero
# hits anywhere is the vacuous-success case, not a clean pass, and this
# script exits non-zero for it.
#
# Usage:
#   bash scan-state-flip.sh <noun> [--ref <tree>]
#
# <noun> is the thing that flipped state: a package name, a flag name, a
# binary name. [--ref <tree>] scopes the search to a git ref (a commit, a
# branch, a tag) instead of the working tree. Use the PRE-flip ref to find
# what a flip is about to invalidate, or `HEAD^` / `<sha>^` to re-run the
# counterfactual against a specific past flip.
#
# Output has three steps, all measured against the same denominator:
#   STEP 1  Every line matching the noun in the scanned paths. The
#           denominator every other count is measured against.
#   STEP 2  The STEP 1 set narrowed to lines that also carry absence-vocabulary
#           ("not installed", "by design", "isn't", "is NOT", etc).
#           THE MANDATED OUTPUT. This is what a P-7 review pastes.
#   STEP 3  A narrower vocabulary subset of STEP 2, for reading order only.
#           Misses real casualties (e.g. a test whose premise was literal
#           absence). Never treat it as a substitute for STEP 2.
#
# Categories (assign one per STEP 2 hit when reviewing):
#   1  Test whose premise is the old state:       fails loudly, cheap, already caught
#   2  Comment/doc asserting the old state:        silent, misleads the next reader
#   3  Diagnostic/error text naming the old state:  silent, wrong remediation ships
#   4  Catch block written for the old-state case:  silent, miscategorizes a new failure
#
# Dispositions (assign one per STEP 2 hit):
#   FIX-NOW        Stale; fix in this PR
#   STILL-TRUE     Assertion survives the flip unchanged
#   FALSE-POSITIVE Matched vocabulary, asserts something else
#   OUT-OF-SCOPE   Stale but owned elsewhere; requires an owner + tracking issue ID, never bare
#
# Exit codes:
#   0  STEP 1 denominator > 0 (ran to completion; STEP 2/3 may be empty, and
#      that is a real clean pass)
#   1  STEP 1 denominator is 0 (vacuous: the noun matched nothing, so check
#      the noun, not the state)
#   2  cannot proceed -- distinct causes, not one, and the stderr message names
#      which. A usage error (missing noun, extra arg, --ref without a value, a
#      noun containing a newline or carriage return); a --ref value beginning
#      with '-', which git grep would read as an option rather than a revision;
#      git grep itself failing (exit >1, e.g. 128 for an unresolvable revision)
#      -- in the STEP 1 pass THE SEARCH DID NOT RUN and there is no denominator,
#      while in the narrowing pass the denominator already stands and only STEP
#      2/3 are unusable; or STEP 2
#      exceeding STEP 1, which means STEP 2's line set stopped being a subset of
#      STEP 1's -- content changed between the two passes, or a narrowing was
#      dropped -- so the inconsistency is in this script's own output and the
#      input may be fine. Never read an exit 2 as "the noun is absent" -- that
#      is exit 1.
#
# Scanned paths (must be run inside a git repository):
#   Default: every tracked or untracked-but-not-ignored file in the repository,
#   excluding markdown, lockfiles (*.lock, package-lock.json, npm-shrinkwrap.json,
#   pnpm-lock.yaml), and vendor/build directories at any depth (node_modules,
#   vendor, dist, build).
#   STATE_FLIP_PATHS    Space-separated git pathspecs that REPLACE the default
#                       include set, e.g. STATE_FLIP_PATHS="src tests .github".
#   STATE_FLIP_EXCLUDE  Space-separated paths/globs excluded IN ADDITION to the
#                       default excludes (no pathspec magic prefix needed).
#   STATE_FLIP_NO_DEFAULT_EXCLUDES=1  Drop the built-in excludes (e.g. to scan
#                       markdown too).
#   Pathspecs containing spaces are not supported. The report prints the exact
#   scope it used.
#
# Dependency-free bash + awk + wc + tr + git grep.

set -euo pipefail

NOUN=""
REF=""

while (("$#")); do
  case "$1" in
    --ref)
      if [[ -z "${2:-}" ]]; then
        echo "scan-state-flip: --ref requires a value" >&2
        exit 2
      fi
      REF="$2"
      shift 2
      ;;
    -h | --help)
      # Print the header block: skip the shebang and any shellcheck directive,
      # print contiguous comment lines, stop at the first line that is not one.
      # Both boundaries are derived, so neither can drift from the block it prints.
      awk '/^#!/ {next} /^# shellcheck/ {next} /^#/ {print; next} {exit}' "$0"
      exit 0
      ;;
    *)
      if [[ -z "$NOUN" ]]; then
        NOUN="$1"
      else
        echo "scan-state-flip: unexpected extra arg: $1" >&2
        exit 2
      fi
      shift
      ;;
  esac
done

if [[ -z "$NOUN" ]]; then
  echo "scan-state-flip: usage: $0 <noun> [--ref <tree>]" >&2
  exit 2
fi

# A noun containing a newline is not one pattern: `git grep -F` splits on newlines
# and treats each component as its OWN fixed pattern, so the denominator becomes the
# union of the parts rather than this noun's count.
if [[ "$NOUN" == *$'\n'* || "$NOUN" == *$'\r'* ]]; then
  echo "scan-state-flip: the noun contains a newline or carriage return. git grep -F would treat each line as a separate pattern and the denominator would be their union, not this noun's count. Pass a single-line noun." >&2
  exit 2
fi

# A REF is passed to `git grep` positionally, so a value that begins with
# `-` is consumed as an OPTION rather than a revision -- and git exits 0, so the
# run_grep error check cannot catch it.
#
# Scoped to the dash case ON PURPOSE: only a dash-leading value can be mistaken for
# an option. A dash-free unresolvable ref is caught one layer down, where git grep
# exits 128 and run_grep turns that into exit 2; a resolvability gate here would
# intercept it first, making that sibling check unreachable by any constructible
# input and therefore unverifiable.
if [[ -n "$REF" && "$REF" == -* ]]; then
  echo "scan-state-flip: --ref '$REF' begins with '-', so git grep would consume it as an OPTION rather than a revision and the scan would report a denominator for something other than the ref it names. Pass a branch, tag, or commit." >&2
  exit 2
fi

# Deliberately excludes *.md by default: mixing repository-wide markdown into a
# noun-scoped pass makes the denominator unreproducible. Tests are in scope because
# the FIRST casualty category this script's header names is "tests whose premise was
# the old state".
# In a git pathspec a plain `*` matches `/`, so `scripts/*.sh` covers every depth;
# `**/` instead requires at least one intervening directory, which would miss
# every top-level file.
INCLUDE_SPECS=()
if [[ -n "${STATE_FLIP_PATHS:-}" ]]; then
  read -r -a _user_specs <<<"$STATE_FLIP_PATHS"
  for _s in "${_user_specs[@]}"; do INCLUDE_SPECS+=(":(top)$_s"); done
else
  INCLUDE_SPECS=(':(top)*')
fi
EXCLUDE_SPECS=()
if [[ "${STATE_FLIP_NO_DEFAULT_EXCLUDES:-}" != "1" ]]; then
  EXCLUDE_SPECS+=(
    ':(top,exclude)*.md' ':(top,exclude)*.lock'
    ':(top,exclude,glob)**/package-lock.json' ':(top,exclude,glob)**/npm-shrinkwrap.json'
    ':(top,exclude,glob)**/pnpm-lock.yaml' ':(top,exclude,glob)**/yarn.lock'
    ':(top,exclude,glob)**/Cargo.lock' ':(top,exclude,glob)**/poetry.lock'
    ':(top,exclude,glob)**/Gemfile.lock'
    ':(top,exclude,glob)**/node_modules/**' ':(top,exclude,glob)**/vendor/**'
    ':(top,exclude,glob)**/dist/**' ':(top,exclude,glob)**/build/**'
  )
fi
if [[ -n "${STATE_FLIP_EXCLUDE:-}" ]]; then
  read -r -a _user_ex <<<"$STATE_FLIP_EXCLUDE"
  for _s in "${_user_ex[@]}"; do EXCLUDE_SPECS+=(":(top,exclude)$_s"); done
fi
PATHSPECS=("${INCLUDE_SPECS[@]}" ${EXCLUDE_SPECS[@]+"${EXCLUDE_SPECS[@]}"})

# -F, not -E. The noun is a package name, a flag, a binary, a workflow
# step name -- a LITERAL. As a pattern it corrupts the denominator the whole gate
# rests on, in three directions:
#   thing(alpha)  -> the group swallows it
#   widget.tool   -> over-counts, silently: `.` also matches widgetXtool
#   a|b           -> matches nearly every line, because the alternation escapes the noun
# No caller passes a pattern; all pass identifiers. If one ever needs to, add an
# explicit opt-in flag rather than restoring a silent regex default.
#
# -a, because ref-mode encrypted blobs and binaries would otherwise collapse to one
# record per file.
#
# -e, because without it a noun beginning with `-` is parsed as an OPTION rather than
# a pattern, and this script's usage names "a flag name" as a valid noun.
run_grep() {
  local rc=0
  if [[ -n "$REF" ]]; then
    git grep --full-name -aniF -e "$NOUN" "$REF" -- "${PATHSPECS[@]}" || rc=$?
  else
    # --untracked, because "working tree" has to mean the working tree. Without it
    # `git grep` searches tracked content only, so a newly written script carrying
    # the noun AND a stale assertion contributes nothing. It still excludes
    # gitignored files, so scratch files do not pollute the count. Ref mode is
    # unaffected: a ref has no working tree to be untracked in.
    git grep --full-name -aniF --untracked -e "$NOUN" -- "${PATHSPECS[@]}" || rc=$?
  fi

  # git grep exits 1 for "no match" and >1 for an ERROR -- an unresolvable
  # ref exits 128. Suppressing both would report a search that never ran as a
  # denominator of 0, a false statement about the codebase rather than a missing
  # count. Errors exit 2, the code this script already uses for "cannot proceed",
  # and git's own stderr is not suppressed so the reason is visible.
  if ((rc > 1)); then
    printf 'scan-state-flip: git grep exited %d searching for noun %s against %s. That is an ERROR, not a no-match result -- git'"'"'s own message is above. The search did not run, so there is no denominator. Do not read this as the noun being absent.\n' \
      "$rc" "'$NOUN'" "$REF_LABEL" >&2
    exit 2
  fi
}

# ABSENCE_VOCAB below is a genuine ERE alternation that INTERPOLATES
# the noun, so -F cannot fix it -- the noun must be escaped before it is embedded.
# Unescaped, a noun of `a|b` turns "no a|b|without a|b" into the alternatives `no a`,
# `b`, `without a`, `b`, and the bare `b` then matches almost everything.
escape_ere() {
  local s=$1 out='' i c
  for ((i = 0; i < ${#s}; i++)); do
    c=${s:i:1}
    case $c in
      '.' | '^' | '$' | '*' | '+' | '?' | '(' | ')' | '[' | ']' | '{' | '}' | '|' | [\\]) out+="\\$c" ;;
      *) out+=$c ;;
    esac
  done
  printf '%s' "$out"
}

count_lines() {
  if [[ -z "$1" ]]; then
    echo 0
  else
    printf '%s\n' "$1" | wc -l | tr -d ' '
  fi
}

REF_LABEL="${REF:-working tree}"

STEP1_OUT=$(run_grep)
STEP1_COUNT=$(count_lines "$STEP1_OUT")

printf '## State-Flip Assertion Audit (P-7) for `%s`\n\n' "$NOUN"
printf 'Noun: `%s`\n' "$NOUN"
printf 'Ref: `%s`\n' "$REF_LABEL"
# A denominator for the right noun over the wrong paths is the same defect
# as one for the wrong noun, so the report states its scope too. Printed from
# PATHSPECS itself rather than restated.
printf 'Scanned paths: `%s`\n' "${PATHSPECS[*]}"

# A ref-mode scan reads blobs from the object database, where a transparent-encryption
# filter stores them ENCRYPTED, and a genuine binary in scope is equally invisible to a text
# noun. The question is not "is this encrypted" but "is there content in scope this
# TEXT search cannot read", and git answers it directly: `git grep -l -a` lists every
# blob, `git grep -lI` lists only those git considers text, and the difference is the
# complete unreadable set. No sampling, no ordering dependence, no magic bytes. It
# runs in BOTH modes, since a binary blob is just as unreadable in a working tree.
UNREADABLE_SPECS=()
INDETERMINATE_SPECS=()
for _spec in "${INCLUDE_SPECS[@]}"; do
  _all_rc=0
  _txt_rc=0
  if [[ -n "$REF" ]]; then
    _all=$(git grep -l -a -e '' "$REF" -- "$_spec" ${EXCLUDE_SPECS[@]+"${EXCLUDE_SPECS[@]}"} 2>/dev/null) || _all_rc=$?
    _txt=$(git grep -lI -e '' "$REF" -- "$_spec" ${EXCLUDE_SPECS[@]+"${EXCLUDE_SPECS[@]}"} 2>/dev/null) || _txt_rc=$?
  else
    _all=$(git grep -l -a --untracked -e '' -- "$_spec" ${EXCLUDE_SPECS[@]+"${EXCLUDE_SPECS[@]}"} 2>/dev/null) || _all_rc=$?
    _txt=$(git grep -lI --untracked -e '' -- "$_spec" ${EXCLUDE_SPECS[@]+"${EXCLUDE_SPECS[@]}"} 2>/dev/null) || _txt_rc=$?
  fi
  # git grep exits 1 for "no match" -- an empty pathspec, entirely normal. Anything
  # above that is an ERROR, and scoring it as "nothing unreadable" would be the same
  # collapse this block exists to prevent.
  if ((_all_rc > 1 || _txt_rc > 1)); then
    INDETERMINATE_SPECS+=("$_spec")
    continue
  fi
  _n_all=$(count_lines "$_all")
  _n_txt=$(count_lines "$_txt")
  if ((_n_all > _n_txt)); then
    UNREADABLE_SPECS+=("$_spec ($((_n_all - _n_txt)) of $_n_all)")
  fi
done
if ((${#INDETERMINATE_SPECS[@]} > 0)); then
  printf '\n> **Scope warning.** These pathspecs could not be examined for unreadable content -- the check itself failed, so whether the counts below cover them is UNKNOWN, which is not the same as covered: `%s`.\n' \
    "${INDETERMINATE_SPECS[*]}"
fi
if ((${#UNREADABLE_SPECS[@]} > 0)); then
  printf '\n> **Scope warning.** These pathspecs hold blobs that are not text -- encrypted blobs in `--ref` mode (transparent-encryption filters), or genuine binaries: `%s`. Their bytes ARE searched (this scan passes `-a`) and so they DO contribute to the counts below, but any hit in them is a byte coincidence rather than a source reference, and a miss is not evidence about whatever the bytes encode. Treat the counts as unreliable over these paths in both directions. For encrypted paths, re-run WITHOUT `--ref` to search their decrypted working-tree contents.\n' \
    "${UNREADABLE_SPECS[*]}"
fi

printf 'STEP 1 (denominator): %s\n\n' "$STEP1_COUNT"

if [[ "$STEP1_COUNT" -eq 0 ]]; then
  # Pathspecs anchor to the top of the repository git resolves from the process
  # cwd; inside a submodule that is the submodule.
  _root=$(git rev-parse --show-toplevel 2>/dev/null) || _root=""
  echo "scan-state-flip: STEP 1 denominator is 0 for noun '$NOUN' against ref '$REF_LABEL', searched from repository root '${_root:-UNKNOWN}'. The noun does not appear anywhere in the scanned paths. This is the vacuous-success case, not a clean pass. Either the wrong noun was grepped, the scanned pathspecs genuinely don't cover this state, or that root is not the repository you meant. A zero denominator is never pasteable as a P-7 result on its own." >&2
  exit 1
fi

NOUN_ERE=$(escape_ere "$NOUN")
ABSENCE_VOCAB="not installed|not present|not available|not on path|absent|does not exist|unavailable|no $NOUN_ERE|without $NOUN_ERE|by design|isn't|is NOT"
TRIAGE_VOCAB="by design|isn't installed|is NOT inside|not installed"

# Post-filtering STEP1_OUT with a plain grep sees the WHOLE record --
# "path:line:content" in working-tree mode, "ref:path:line:content" in ref mode -- so
# absence vocabulary in the ref or the PATH matches lines whose CONTENT carries none,
# inflating the mandated output with false casualties. `git grep --and` applies both
# patterns to file CONTENT only and never to the path. -E rather than -F because
# ABSENCE_VOCAB is a genuine alternation; NOUN_ERE is escape_ere()'s output and is
# exactly equivalent to the -F noun, which is that function's whole contract.
run_grep_and() {
  local vocab="$1" rc=0
  if [[ -n "$REF" ]]; then
    git grep --full-name -aniE -e "$NOUN_ERE" --and -e "$vocab" "$REF" -- "${PATHSPECS[@]}" || rc=$?
  else
    git grep --full-name -aniE --untracked -e "$NOUN_ERE" --and -e "$vocab" -- "${PATHSPECS[@]}" || rc=$?
  fi
  if ((rc > 1)); then
    printf 'scan-state-flip: git grep exited %d narrowing to absence-vocabulary against %s. That is an ERROR, not a no-match result -- git'"'"'s own message is above. Do not read the resulting count as a real STEP 2/3 result.\n' \
      "$rc" "$REF_LABEL" >&2
    exit 2
  fi
}

STEP2_OUT=$(run_grep_and "$ABSENCE_VOCAB")
STEP2_COUNT=$(count_lines "$STEP2_OUT")

STEP3_OUT=$(run_grep_and "$TRIAGE_VOCAB")
STEP3_COUNT=$(count_lines "$STEP3_OUT")

# STEP 2 narrows STEP 1, so it cannot exceed it. They are separate git grep
# passes, so ANYTHING that stops STEP 2's line set being a subset of STEP 1's
# reaches this guard -- a working-tree write landing between the passes needs no
# edit to this file at all; a source edit that drops the narrowing, or an escape
# that stops matching the -F noun, gets there too. The list is examples, not a
# closed set. Without the guard the report names files the scope line says were
# never searched, at exit 0.
if ((STEP2_COUNT > STEP1_COUNT)); then
  printf 'scan-state-flip: STEP 2 reported %s hit(s) against a STEP 1 denominator of %s. STEP 2 narrows STEP 1 and cannot exceed it, so STEP 2'"'"'s line set stopped being a subset of STEP 1'"'"'s. A write landing between the passes is one cause of that and not the only one, so do not stop at checking for a concurrent write. Neither count describes the other. Do not paste either as a P-7 result.\n' \
    "$STEP2_COUNT" "$STEP1_COUNT" >&2
  exit 2
fi

printf '### STEP 2: noun x absence-vocabulary (%s hit(s)), MANDATED OUTPUT\n\n' "$STEP2_COUNT"
if [[ "$STEP2_COUNT" -gt 0 ]]; then
  printf '%s\n' "$STEP2_OUT"
else
  printf '_None. STEP 1 found the noun %s time(s) but none carried absence-vocabulary._\n' "$STEP1_COUNT"
fi
printf '\n'

printf '### STEP 3: high-yield triage subset (%s hit(s)), reading order only, NOT a filter\n\n' "$STEP3_COUNT"
printf '_Read STEP 3 first for triage, but STEP 2 is the check. STEP 3 is measured to miss real casualties; do not stop at STEP 3._\n\n'
if [[ "$STEP3_COUNT" -gt 0 ]]; then
  printf '%s\n' "$STEP3_OUT"
else
  printf '_None._\n'
fi
printf '\n'

printf '### Suggested P-7 matrix (scaffold)\n\n'
printf 'Copy this into the plan'\''s `## State-Flip Assertion Audit (P-7)` section, or into the corresponding pull-request review finding. One row per STEP 2 hit. Category is one of: 1 (test), 2 (comment/doc), 3 (diagnostic/error text), 4 (catch block). Disposition is one of: FIX-NOW, STILL-TRUE, FALSE-POSITIVE, OUT-OF-SCOPE (requires an owner + tracking issue ID).\n\n'
printf '| Hit (file:line) | Category | Disposition | Notes |\n'
printf '|------------------|----------|--------------|-------|\n'
if [[ "$STEP2_COUNT" -gt 0 ]]; then
  printf '%s\n' "$STEP2_OUT" | while IFS= read -r hit; do
    # git grep prefixes each line with "<ref>:" only when --ref was passed;
    # strip that prefix before splitting the remaining "path:line:content"
    # so a ref containing no colons of its own (a branch, tag, or SHA) is
    # not mistaken for the path field.
    if [[ -n "$REF" ]]; then
      hit_no_ref="${hit#"$REF":}"
    else
      hit_no_ref="$hit"
    fi
    # Splitting at the FIRST colon assumes the path has none. For
    # scripts/a:b.sh:1:content that yields loc=scripts/a and lineno=b.sh, which reads
    # like a correct path while the line number is silently gone. Walk to the first
    # ":<digits>:" boundary instead.
    loc="$hit_no_ref"
    lineno=""
    scan_rest="$hit_no_ref"
    scan_path=""
    while [[ "$scan_rest" == *:* ]]; do
      scan_head="${scan_rest%%:*}"
      scan_tail="${scan_rest#*:}"
      scan_path="${scan_path:+$scan_path:}$scan_head"
      if [[ "$scan_tail" =~ ^[0-9]+: ]]; then
        loc="$scan_path"
        lineno="${scan_tail%%:*}"
        break
      fi
      scan_rest="$scan_tail"
    done
    printf '| `%s:%s` | _<1-4>_ | _<disposition>_ | _<one sentence>_ |\n' "$loc" "$lineno"
  done
else
  printf '| _<none, STEP 2 was empty>_ | | | |\n'
fi

exit 0
