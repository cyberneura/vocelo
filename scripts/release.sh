#!/bin/bash
# Picks the next version, puts it on main, and watches the release it starts.
#
#   scripts/release.sh            # patch
#   scripts/release.sh minor
#   scripts/release.sh major
#
# What starts a release is the push, not this script: the workflow runs on any push
# to main and decides by asking whether the version in VERSION is already released.
# A failure here does not stop the build, and pushing an already released version
# does nothing at all -- which is the reason the number is picked here rather than
# typed: a reused one looks like a release that ran and published nothing.
set -euo pipefail
cd "$(dirname "$0")/.."
bump="${1:-patch}"
# Anything past the first argument is rejected rather than ignored: this one pushes
# to main, so a typo must not be read as a bare `release.sh`.
if [[ $# -gt 1 ]] || ! [[ "$bump" =~ ^(patch|minor|major)$ ]]; then
    echo "Usage: scripts/release.sh [patch|minor|major]  (default: patch)" >&2
    exit 1
fi
if ! command -v gh > /dev/null 2>&1; then
    echo "gh CLI not found; install it and run 'gh auth login'" >&2
    exit 1
fi
if ! gh auth status > /dev/null 2>&1; then
    echo "gh is not authenticated; run 'gh auth login'" >&2
    exit 1
fi
# The build runs on what is on origin/main, so releasing from anything else would
# publish something never seen.
if [[ "$(git branch --show-current)" != main ]]; then
    echo "not on main" >&2
    exit 1
fi
if [[ -n "$(git status --porcelain)" ]]; then
    echo "working tree is not clean; commit or stash first" >&2
    exit 1
fi
git fetch origin +main:refs/remotes/origin/main
if [[ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]]; then
    echo "local HEAD does not match origin/main; push or pull first" >&2
    exit 1
fi
current=$(tr -d '[:space:]' < VERSION)
if ! [[ "$current" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    echo "VERSION is not X.Y.Z: $current" >&2
    exit 1
fi
IFS=. read -r major minor patch <<< "$current"
case "$bump" in
    major) version="$((major + 1)).0.0" ;;
    minor) version="$major.$((minor + 1)).0" ;;
    patch) version="$major.$minor.$((patch + 1))" ;;
esac
printf 'Bumping version: %s -> %s (%s)\n' "$current" "$version" "$bump"
echo "$version" > VERSION
git add VERSION
git commit -m "Release v$version"
if ! git push origin HEAD:main; then
    echo "push failed; the local release commit remains" >&2
    echo "  undo it:  git reset --hard origin/main" >&2
    exit 1
fi
printf 'Waiting for the release build of v%s ...\n' "$version"
# Polled for by commit rather than taking the newest run, so a push that lands in
# between is not the one watched. `|| true` because a momentary API error means
# "not there yet", not "give up" (set -e exits on a failing command substitution).
release_sha=$(git rev-parse HEAD)
run_id=""
for _ in $(seq 1 60); do
    sleep 2
    run_id=$(gh run list --workflow=release.yml --branch main --limit 20 \
        --json databaseId,headSha \
        --jq "[.[] | select(.headSha == \"$release_sha\")] | .[0].databaseId // \"\"" \
        2> /dev/null || true)
    [[ -n "$run_id" ]] && break
done
if [[ -z "$run_id" ]]; then
    echo "could not find the workflow run within 2 minutes; it may still be running:" >&2
    echo "  gh run list --workflow=release.yml" >&2
    exit 1
fi
printf 'Watching run %s ...\n' "$run_id"
gh run watch "$run_id" --exit-status
printf 'Done: https://github.com/cyberneura/vocelo/releases/tag/v%s\n' "$version"
