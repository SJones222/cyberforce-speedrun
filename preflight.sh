#!/usr/bin/env bash
set -u

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
