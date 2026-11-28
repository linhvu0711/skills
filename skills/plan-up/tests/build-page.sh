# build-page.sh: the cases for this skill's build_page.py. The repo's test.sh
# sources this file after test-lib.sh and runs its cases.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# small_plan: the smallest plan .md the builder takes, as plan.md.
small_plan() {
  cat > plan.md <<'PLAN'
# Plan: #1 Lock the page
Size: size/S    Date: 2026-11-28

## Review
Change:   none
Approach: none
Blast radius:
  Touches:    plan-up
  Dependency: none
  Schema:     none
  API:        none
  Config:     none
  CI:         none
Choices:
  - none
Risks:
  - none
Works when:
  - #1 the page builds
In:  a page
Out: nothing

## Change map
None: no part or flow changes.

## File changes
| File | Change | Slices | Note |
|---|---|---|---|
| `a.sh` | edited | S1 | |

## Facts
Repo: o/r        Base: main
Test: none
UI: none

## Summary
A page.

## Proof
| # | Done-when line | Test (file, case) | UI walk | Video | Artifact |
|---|---|---|---|---|---|
| 1 | the page builds | `a.sh` "builds" | none | none | test |

## Slices
Slice 1, proves #1: a
  Change: `a.sh:1`, edit.
  Test `a.sh` "builds"
    Given:  a plan
    When:   build
    Then:   `page: plan.html`

## Gates
Slice done: its test green.
PLAN
}

t_bp_builds_twice() {
  # Given
  T="$(cd "$(mktemp -d)" && pwd -P)"; cd "$T"
  small_plan
  # When: the page is built twice
  run python3 "$here/../scripts/build_page.py" plan.md
  eq exit 0 "$code"; eq stdout "page: plan.html" "$out"
  cp plan.html first.html
  run python3 "$here/../scripts/build_page.py" plan.md
  # Then
  eq exit 0 "$code"; eq stdout "page: plan.html" "$out"
  eq "theme lines" 1 "$(grep -c -- '--bg: #f6f7f9;' plan.html)"
  lacks page '<script src="layout.js"></script>' "$(cat plan.html)"
  eq "DATA title" "Lock the page" "$(sed -n 's/^ *const DATA = \(.*\);$/\1/p' plan.html | jq -r .title)"
  [ ! -e plan.html.tmp ] || eq "temp file" none plan.html.tmp
  cmp -s first.html plan.html || eq "second page" "same bytes" "changed"
}

cases=(
  "build-page: builds the plan page with data, theme, and layout, twice|t_bp_builds_twice"
)
