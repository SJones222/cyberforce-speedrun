#!/usr/bin/env bash
set -u
TARGET="${1:-}"
KEY="${2:-}"
[ -n "$TARGET" ] || { echo "Usage: $0 TARGET_IP [SCORING_PRIVATE_KEY]" >&2; exit 2; }

PASS=0
FAIL=0
SKIP=0
pass() { printf '[PASS] %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf '[FAIL] %s\n' "$1"; FAIL=$((FAIL + 1)); }
skip() { printf '[SKIP] %s\n' "$1"; SKIP=$((SKIP + 1)); }

need() { command -v "$1" >/dev/null 2>&1; }
check_eq() {
    local name="$1" got="$2" want="$3"
    if [ "$got" = "$want" ]; then pass "$name"; else fail "$name (got: ${got:-<empty>})"; fi
}

printf '=== Remote Scoring-Style Verification: %s ===\n' "$TARGET"

if need ping; then ping -c 1 -W 2 "$TARGET" >/dev/null 2>&1 && pass ICMP || fail ICMP; else skip 'ICMP (ping missing)'; fi

if [ -n "$KEY" ]; then
    if [ ! -r "$KEY" ]; then
        fail 'SSH private key readable'
    elif need ssh && need timeout; then
        timeout 6 ssh -i "$KEY" -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=3 "ssh-user@$TARGET" true >/dev/null 2>&1 && pass SSH || fail SSH
    else
        skip 'SSH transaction (ssh or timeout missing)'
    fi
else
    skip 'SSH transaction (no matching private key supplied)'
fi

if need curl; then
    check_eq HTTP "$(curl -fsS --max-time 5 "http://$TARGET/" 2>/dev/null || true)" 'Hello World!'
    check_eq FTP "$(curl -fsS --max-time 7 "ftp://$TARGET/iloveftp.txt" 2>/dev/null || true)" 'iloveftp'
else
    skip 'HTTP (curl missing)'
    skip 'FTP (curl missing)'
fi

if need mariadb; then
    check_eq MariaDB "$(MYSQL_PWD=password mariadb --connect-timeout=3 -N -s -h "$TARGET" -u scoring-sql -e 'SELECT data FROM cyberforce.supersecret WHERE data=7 LIMIT 1;' 2>/dev/null || true)" '7'
else
    skip 'MariaDB (mariadb client missing)'
fi

if need dig; then
    check_eq 'DNS UDP' "$(dig +short +time=2 +tries=1 @"$TARGET" test.local A 2>/dev/null || true)" '10.10.10.10'
    check_eq 'DNS TCP' "$(dig +tcp +short +time=2 +tries=1 @"$TARGET" test.local A 2>/dev/null || true)" '10.10.10.10'
else
    skip 'DNS UDP/TCP (dig missing)'
fi

printf '\nPASS=%d FAIL=%d SKIP=%d\n' "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" -eq 0 ]
