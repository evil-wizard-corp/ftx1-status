# FTX1 Status

Releases are cut automatically from commit messages, so every commit subject must be a
conventional commit: `type(scope)?!?: summary`, with type one of feat, fix, perf, refactor,
docs, test, build, ci, chore, style, revert. `feat` → minor, `fix`/`perf` → patch, `!` or a
`BREAKING CHANGE:` footer → major (minor before 1.0); other types don't release. Pick the type
by what a user of the app would notice. CI rejects PRs with non-conforming commits or titles.
See `scripts/next-version.sh` and `.github/workflows/auto-release.yml`.

Tests use Swift Testing (`swift test`), which needs Xcode, not just the Command Line Tools.
