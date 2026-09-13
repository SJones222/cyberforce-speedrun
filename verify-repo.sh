#!/usr/bin/env bash
# verify-repo.sh - verify that this local checkout still matches the trusted
# cyberforce-speedrun GitHub repository before executing competition scripts.
#
# Usage:
#   ./verify-repo.sh
#   ./verify-repo.sh --fetch
#
# --fetch updates origin/main first. Without it, the script performs only local
# checks against the last origin/main state already fetched into this clone.

set -u

EXPECTED_ORIGIN="${EXPECTED_ORIGIN:-https://github.com/SJones222/cyberforce-speedrun.git}"
EXPECTED_BRANCH="${EXPECTED_BRANCH:-main}"
# Optional: set EXPECTED_COMMIT to a SHA you recorded somewhere off-host.
EXPECTED_COMMIT="${EXPECTED_COMMIT:-}"
FETCH=0

if [[ "${1:-}" == "--fetch" ]]; then
    FETCH=1
elif [[ -n "${1:-}" ]]; then
    printf 'Usage: %s [--fetch]\n' "$0" >&2
    exit 2
fi

PASS=0
WARN=0
FAIL=0

pass() { printf '[PASS] %s\n' "$1"; PASS=$((PASS + 1)); }
warn() { printf '[WARN] %s\n' "$1"; WARN=$((WARN + 1)); }
fail() { printf '[FAIL] %s\n' "$1"; FAIL=$((FAIL + 1)); }

normalize_url() {
    # Treat a trailing .git and trailing slash as equivalent.
    printf '%s' "$1" | sed -e 's#/*$##' -e 's#\.git$##'
}

printf '=== CyberForce Repository Verification ===\n\n'

if ! command -v git >/dev/null 2>&1; then
    fail 'git is not installed or not in PATH'
    exit 1
fi

GIT_PATH="$(command -v git)"
printf 'git binary: %s\n' "$GIT_PATH"

if ! REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    fail 'Current directory is not inside a Git repository'
    exit 1
fi

cd "$REPO_ROOT" || exit 1
printf 'repo root:  %s\n' "$REPO_ROOT"

# 1. Verify origin points to the expected repository.
if ! ACTUAL_ORIGIN="$(git remote get-url origin 2>/dev/null)"; then
    fail 'origin remote is missing'
    ACTUAL_ORIGIN=''
else
    if [[ "$(normalize_url "$ACTUAL_ORIGIN")" == "$(normalize_url "$EXPECTED_ORIGIN")" ]]; then
        pass "origin is expected repository: $ACTUAL_ORIGIN"
    else
        fail "origin mismatch: expected $EXPECTED_ORIGIN but found $ACTUAL_ORIGIN"
    fi
fi

# 2. Detect Git hook redirection and executable local hooks.
HOOKS_PATH="$(git config --get core.hooksPath 2>/dev/null || true)"
if [[ -n "$HOOKS_PATH" ]]; then
    fail "core.hooksPath is set to: $HOOKS_PATH"
else
    pass 'core.hooksPath is not overridden'
fi

HOOK_DIR="$(git rev-parse --git-path hooks 2>/dev/null || true)"
if [[ -n "$HOOK_DIR" && -d "$HOOK_DIR" ]]; then
    mapfile -t ACTIVE_HOOKS < <(find "$HOOK_DIR" -maxdepth 1 -type f -perm -u+x ! -name '*.sample' -print 2>/dev/null)
    if (( ${#ACTIVE_HOOKS[@]} > 0 )); then
        fail "Executable Git hook(s) present: ${ACTIVE_HOOKS[*]}"
    else
        pass 'No executable local Git hooks found'
    fi
fi

# fsmonitor can execute an external hook/command on some Git versions.
FSMONITOR="$(git config --get core.fsmonitor 2>/dev/null || true)"
if [[ -n "$FSMONITOR" && "$FSMONITOR" != "false" ]]; then
    fail "core.fsmonitor is enabled/set: $FSMONITOR"
else
    pass 'core.fsmonitor is not configured to run an external helper'
fi

# 3. Optionally fetch the trusted remote state.
if (( FETCH )); then
    if [[ -z "$ACTUAL_ORIGIN" ]] || [[ "$(normalize_url "$ACTUAL_ORIGIN")" != "$(normalize_url "$EXPECTED_ORIGIN")" ]]; then
        fail 'Refusing to fetch because origin did not match the expected repository'
    elif git fetch --quiet --prune origin "$EXPECTED_BRANCH"; then
        pass "Fetched origin/$EXPECTED_BRANCH"
    else
        fail "Could not fetch origin/$EXPECTED_BRANCH"
    fi
else
    warn 'Remote was not fetched; use --fetch when network access is available'
fi

# 4. Verify expected remote-tracking branch exists.
REMOTE_REF="origin/$EXPECTED_BRANCH"
if git rev-parse --verify --quiet "$REMOTE_REF" >/dev/null; then
    pass "$REMOTE_REF exists"
else
    fail "$REMOTE_REF does not exist locally"
fi

# 5. Check branch/commit relationship.
CURRENT_BRANCH="$(git branch --show-current 2>/dev/null || true)"
if [[ "$CURRENT_BRANCH" == "$EXPECTED_BRANCH" ]]; then
    pass "Current branch is $EXPECTED_BRANCH"
else
    warn "Current branch is '${CURRENT_BRANCH:-detached HEAD}', expected '$EXPECTED_BRANCH'"
fi

HEAD_SHA="$(git rev-parse HEAD 2>/dev/null || true)"
REMOTE_SHA="$(git rev-parse "$REMOTE_REF" 2>/dev/null || true)"
printf 'HEAD:        %s\n' "${HEAD_SHA:-unknown}"
printf 'origin/main: %s\n' "${REMOTE_SHA:-unknown}"

if [[ -n "$HEAD_SHA" && -n "$REMOTE_SHA" ]]; then
    if [[ "$HEAD_SHA" == "$REMOTE_SHA" ]]; then
        pass 'HEAD exactly matches origin/main'
    else
        fail 'HEAD does not match origin/main'
    fi
fi

if [[ -n "$EXPECTED_COMMIT" ]]; then
    if [[ "$HEAD_SHA" == "$EXPECTED_COMMIT" && "$REMOTE_SHA" == "$EXPECTED_COMMIT" ]]; then
        pass "HEAD and origin/main match externally recorded commit $EXPECTED_COMMIT"
    else
        fail "Externally recorded commit mismatch: expected $EXPECTED_COMMIT"
    fi
else
    warn 'EXPECTED_COMMIT not set; remote compromise would not be detected by commit comparison alone'
fi

# 6. Check tracked and untracked working-tree changes.
STATUS="$(git status --porcelain=v1 --untracked-files=all)"
if [[ -z "$STATUS" ]]; then
    pass 'Working tree is clean'
else
    fail 'Working tree contains local changes or untracked files'
    printf '%s\n' "$STATUS" | sed 's/^/       /'
fi

# Explicitly compare both index and worktree against the trusted remote tree.
if git rev-parse --verify --quiet "$REMOTE_REF" >/dev/null; then
    if git diff --quiet "$REMOTE_REF" -- && git diff --cached --quiet "$REMOTE_REF" --; then
        pass 'Tracked files match origin/main'
    else
        fail 'Tracked files differ from origin/main'
    fi
fi

# 7. Check repository object integrity.
if git fsck --full --no-dangling >/dev/null 2>&1; then
    pass 'Git object database passed fsck'
else
    fail 'git fsck reported repository integrity problems'
fi

# 8. Flag unexpected symbolic links among tracked files. The competition repo
# should not need tracked symlinks; a symlink can redirect a script/config read.
SYMLINKS="$(git ls-files -s | awk '$1 == "120000" {print $4}')"
if [[ -z "$SYMLINKS" ]]; then
    pass 'No tracked symbolic links found'
else
    warn 'Tracked symbolic link(s) found; review them:'
    printf '%s\n' "$SYMLINKS" | sed 's/^/       /'
fi

printf '\n=== Result ===\n'
printf 'PASS: %d  WARN: %d  FAIL: %d\n' "$PASS" "$WARN" "$FAIL"

if (( FAIL > 0 )); then
    printf '\nDO NOT run repository scripts until the failures are understood or the checkout is refreshed.\n' >&2
    exit 1
fi

printf '\nRepository checks passed.\n'
exit 0
