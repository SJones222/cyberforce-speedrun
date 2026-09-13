#!/usr/bin/env bash
set -u
ROOT="$(cd "$(dirname "$0")" && pwd)"
. "$ROOT/lib/common.sh"
require_root

printf '=== CyberForce scored-service setup ===\n'

if [ "${SKIP_BACKUP:-0}" != 1 ]; then
    printf '\n>>> Capturing pre-change state\n'
    "$ROOT/backup-state.sh" || warn "Baseline backup reported an error; continuing."
fi

printf '\n>>> Ensuring packages are installed\n'
"$ROOT/install-packages.sh" || die "Package preparation failed."

FAILED=0
for s in setup-http.sh setup-ssh.sh setup-ftp.sh setup-mariadb.sh setup-dns.sh setup-icmp.sh; do
    printf '\n>>> %s\n' "$s"
    if "$ROOT/scripts/$s"; then
        printf '[PASS] %s\n' "$s"
    else
        printf '[FAIL] %s\n' "$s" >&2
        FAILED=$((FAILED + 1))
    fi
done

printf '\n>>> Local validation\n'
if ! "$ROOT/verify-local.sh"; then
    FAILED=$((FAILED + 1))
fi

printf '\nCompleted with %d failure(s).\n' "$FAILED"
[ "$FAILED" -eq 0 ]
