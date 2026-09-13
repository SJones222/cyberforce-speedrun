#!/usr/bin/env bash
set -u
ROOT="$(cd "$(dirname "$0")" && pwd)"
. "$ROOT/lib/common.sh"
require_root

printf '=== NETWORK ===\n'
ip -br addr
ip route

printf '\n=== SCORED LISTENERS ===\n'
ss -lntup 2>/dev/null | grep -E '(:21|:22|:53|:80|:3306)([[:space:]]|$)' || true

printf '\n=== SERVICES ===\n'
for s in apache2 ssh vsftpd mariadb named; do
    if service_exists "$s"; then
        printf '%-10s %s\n' "$s" "$(systemctl is-active "$s" 2>/dev/null || true)"
    else
        printf '%-10s %s\n' "$s" 'not-installed'
    fi
done

printf '\n=== FAILED UNITS ===\n'
systemctl --failed --no-pager || true

printf '\n=== LOCAL SCORE ===\n'
"$ROOT/verify-local.sh" || true
