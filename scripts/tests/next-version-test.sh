#!/bin/bash
# Tests for next-version.sh against throwaway repos. Run: scripts/tests/next-version-test.sh
set -euo pipefail
SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/next-version.sh"
fails=0

# expect NAME WANT [BUMP]: runs the script in the current repo.
expect() {
  local got; got="$("$SCRIPT" ${3:-})"
  if [[ "$got" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$got'"; fails=1; fi
}
repo() {
  cd "$(mktemp -d)"
  git init -q && git config user.email t@example.com && git config user.name t
  git commit -q --allow-empty -m "chore: init"
  [[ -n "${1:-}" ]] && git tag -a "$1" -m "$1"
  return 0
}
c() { git commit -q --allow-empty -m "$1"; }

repo;          expect "no tag, no release commits" ""
repo;          c "feat: x"; expect "no tag + feat" "0.1.0"
repo v0.2.0;   expect "at tag" ""
repo v0.2.0;   c "docs: a"; c "ci: b"; c "Not conventional"; expect "no release types" ""
repo v0.2.0;   c "fix(cat): a"; expect "fix" "0.2.1"
repo v0.2.0;   c "perf: a"; expect "perf" "0.2.1"
repo v0.2.0;   c "feat: a"; c "docs: b"; expect "feat older than docs" "0.3.0"
repo v0.2.0;   c "feat: a"; c "fix: b"; c "chore: c"; expect "feat buried under fix and chore" "0.3.0"
repo v0.2.0;   c "fix: a"; c "docs: b"; expect "fix older than docs" "0.2.1"
repo v0.2.0;   c "refactor!: a"; c "docs: b"; expect "breaking before 1.0 is minor" "0.3.0"
repo v1.2.3;   c "refactor!: a"; c "docs: b"; expect "breaking after 1.0" "2.0.0"
repo v1.2.3;   c "$(printf 'fix: a\n\nBREAKING CHANGE: b')"; c "docs: c"; expect "breaking footer" "2.0.0"
repo v1.2.3;   c "feature: not a type"; c "fixup: nope"; expect "lookalike types" ""
repo v0.2.0;   git tag -a v0.3.0-beta.1 -m b; c "fix: a"; expect "ignores pre-release tags" "0.2.1"
repo v0.2.0;   c "docs: a"; expect "forced patch" "0.2.1" patch
repo v0.2.0;   c "fix: a"; expect "forced minor beats fix" "0.3.0" minor
repo v0.2.0;   expect "forced major before 1.0" "1.0.0" major
repo v1.0.0
git checkout -q -b pr; c "feat: a"; c "docs: b"; git checkout -q -
git merge -q --no-ff pr -m "Merge pull request #9"
expect "feat inside a merged PR" "1.1.0"

exit $fails
