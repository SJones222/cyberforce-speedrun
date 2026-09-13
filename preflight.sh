#!/usr/bin/env bash
set -u
ROOT="$(cd "$(dirname "$0")" && pwd)"
. "$ROOT/lib/common.sh"

printf '=== CyberForce Preflight ===\n'

printf '\n[OS / architecture]\n'
if [ -r /etc/os-release ]; then
    grep -E '^(PRETTY_NAME|VERSION_ID)=' /etc/os-release || true
    . /etc/os-release
    if [ "${ID:-}" = debian ] && [ "${VERSION_ID:-}" = 12 ]; then
        printf '[PASS] Debian 12 detected\n'
    else
        printf '[WARN] Toolkit is designed for Debian 12; detected %s %s\n' "${ID:-unknown}" "${VERSION_ID:-unknown}"
    fi
fi
printf 'Architecture: %s\n' "$(uname -m)"
case "$(uname -m)" in
    x86_64|aarch64|arm64) printf '[PASS] Supported practice architecture\n' ;;
    *) printf '[WARN] Untested architecture\n' ;;
esac

printf '\n[Identity]\n'
id
hostname

printf '\n[Addresses]\n'
ip -br addr 2>/dev/null || true
printf '\n[Routes]\n'
ip route 2>/dev/null || true

printf '\n[Listeners]\n'
ss -lntup 2>/dev/null || ss -lntu 2>/dev/null || true

printf '\n[Failed services]\n'
systemctl --failed --no-pager 2>/dev/null || true

printf '\n[Required / useful commands]\n'
for c in systemctl ss ip apt-get dpkg-query curl ssh sshd mariadb dig named-checkconf named-checkzone apache2ctl vsftpd nft tcpdump git; do
    if command -v "$c" >/dev/null 2>&1; then
        printf '[OK]   %s\n' "$c"
    else
        printf '[MISS] %s\n' "$c"
    fi
done

printf '\n[Scoring ports currently listening]\n'
for p in 21 22 53 80 3306; do
    if ss -lntuH 2>/dev/null | awk '{print $4}' | grep -Eq "(^|:)${p}$"; then
        printf '[LISTEN] %s\n' "$p"
    else
        printf '[----- ] %s\n' "$p"
    fi
done

printf '\n[HTTP / Apache runtime preflight]\n'
if ! have_cmd apache2ctl; then
    printf '[MISS] apache2ctl unavailable; Apache-specific checks skipped\n'
else
    APACHE_TEST_OUTPUT="$(apache2ctl configtest 2>&1)"
    if [ $? -eq 0 ]; then
        printf '[PASS] Apache configuration syntax valid (%s)\n' "${APACHE_TEST_OUTPUT:-Syntax OK}"
    else
        printf '[FAIL] Apache configuration syntax invalid\n%s\n' "$APACHE_TEST_OUTPUT"
    fi

    mapfile -t HTTP_LISTENS < <(apache_port80_listen_records)
    if [ "${#HTTP_LISTENS[@]}" -eq 0 ]; then
        printf '[WARN] No active-looking Apache Listen directive for TCP/80 found\n'
    else
        printf 'Apache TCP/80 Listen directives (%d):\n' "${#HTTP_LISTENS[@]}"
        printf '%s\n' "${HTTP_LISTENS[@]}" | while IFS=$'\t' read -r file line arg raw; do
            printf '  %s:%s  %s\n' "$file" "$line" "$raw"
        done

        if [ "${#HTTP_LISTENS[@]}" -gt 1 ]; then
            printf '[WARN] Multiple TCP/80 Listen directives can overlap and make Apache fail at runtime even when configtest says Syntax OK\n'
        elif IFS=$'\t' read -r _ _ arg _ <<< "${HTTP_LISTENS[0]}"; then
            case "$arg" in
                80|0.0.0.0:80) printf '[PASS] Apache TCP/80 Listen directive is externally reachable in principle (%s)\n' "$arg" ;;
                *) printf '[WARN] Apache TCP/80 Listen directive is address-specific (%s); scoring may not reach it remotely\n' "$arg" ;;
            esac
        fi
    fi

    if systemctl is-active --quiet apache2 2>/dev/null; then
        printf '[PASS] Apache service active (actual runtime start succeeded)\n'
    else
        printf '[FAIL] Apache service not active; Syntax OK alone does not prove Apache can bind/start\n'
        systemctl show apache2 -p ActiveState -p SubState -p Result --no-pager 2>/dev/null || true
    fi

    if external_tcp_listener 80; then
        printf '[PASS] TCP/80 has a non-loopback listener\n'
    else
        printf '[FAIL] TCP/80 has no non-loopback listener\n'
        ss -ltnp 2>/dev/null | grep -E '(:80)([[:space:]]|$)' || true
    fi

    if have_cmd curl; then
        HTTP_BODY="$(curl -fsS --max-time 3 http://127.0.0.1/ 2>/dev/null || true)"
        if [ "$HTTP_BODY" = 'Hello World!' ]; then
            printf '[PASS] HTTP response body exactly matches Hello World!\n'
        else
            printf '[FAIL] HTTP response body mismatch (got: %s)\n' "${HTTP_BODY:-<empty>}"
        fi
    else
        printf '[MISS] curl unavailable; HTTP content check skipped\n'
    fi
fi
