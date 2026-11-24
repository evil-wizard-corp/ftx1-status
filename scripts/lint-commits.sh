#!/bin/bash
# Fails if any non-merge commit in BASE..HEAD has a subject that isn't a conventional commit.
# Usage: scripts/lint-commits.sh BASE [HEAD]
#        scripts/lint-commits.sh --subject "feat: some text"
set -euo pipefail

TYPES='feat|fix|perf|refactor|docs|test|build|ci|chore|style|revert'
PATTERN="^($TYPES)(\([a-z0-9._/-]+\))?!?: .+"

# check LABEL SUBJECT
check() {
  [[ "$2" =~ $PATTERN ]] && return 0
  echo "::error::$1 \"$2\" isn't a conventional commit. Use type(scope)!: summary, with type one of ${TYPES//|/, }."
  return 1
}

if [[ "${1:-}" == "--subject" ]]; then
  check "PR title" "${2:-}"
  exit
fi

for rev in "$1" "${2:-HEAD}"; do
  git rev-parse --verify -q "$rev^{commit}" >/dev/null || { echo "::error::unknown revision $rev"; exit 2; }
done
bad=0
while IFS= read -r line; do
  check "${line:0:7}" "${line#* }" || bad=1
done < <(git log --no-merges --format='%H %s' "$1..${2:-HEAD}")
exit $bad
