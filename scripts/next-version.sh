#!/bin/bash
# Prints the next version (no "v") implied by conventional commits since the last stable tag,
# or nothing if no commit calls for a release.
#   feat                          -> minor
#   fix, perf                     -> patch
#   type!: or "BREAKING CHANGE:"  -> major (minor while the version is 0.x)
#   anything else (docs, ci, ...) -> no release
# Usage: scripts/next-version.sh [patch|minor|major]   (optional: force at least this bump)
set -euo pipefail

FORCE="${1:-}"
LAST="$(git describe --tags --abbrev=0 --match 'v[0-9]*.[0-9]*.[0-9]*' --exclude '*-*' 2>/dev/null || true)"
RANGE="${LAST:+$LAST..}HEAD"
IFS=. read -r MAJOR MINOR PATCH <<<"${LAST#v}"
MAJOR="${MAJOR:-0}" MINOR="${MINOR:-0}" PATCH="${PATCH:-0}"

git rev-parse --verify -q HEAD >/dev/null || { echo "no commits" >&2; exit 2; }

# 0 none, 1 patch, 2 minor, 3 major
level=0
bump() { (( $1 > level )) && level=$1 || true; }

while IFS= read -r -d $'\0' commit; do
  subject="${commit%%$'\n'*}"
  if [[ "$subject" =~ ^[a-z]+(\([^\)]*\))?!: ]] || grep -qE '^BREAKING[ -]CHANGE:' <<<"$commit"; then
    bump 3
  elif [[ "$subject" =~ ^feat(\([^\)]*\))?: ]]; then
    bump 2
  elif [[ "$subject" =~ ^(fix|perf)(\([^\)]*\))?: ]]; then
    bump 1
  fi
done < <(git log -z --no-merges --format='%B' "$RANGE")  # -z: NUL between commits, no stray newline

case "$FORCE" in
  patch) bump 1 ;; minor) bump 2 ;; major) bump 3 ;; "") ;;
  *) echo "unknown bump: $FORCE" >&2; exit 2 ;;
esac

# Before 1.0, a breaking change bumps the minor version.
if (( level == 3 && MAJOR == 0 )) && [[ "$FORCE" != major ]]; then level=2; fi

case $level in
  0) exit 0 ;;
  1) echo "$MAJOR.$MINOR.$((PATCH + 1))" ;;
  2) echo "$MAJOR.$((MINOR + 1)).0" ;;
  3) echo "$((MAJOR + 1)).0.0" ;;
esac
