#!/usr/bin/env bash
set -u
ROOT="$(cd "$(dirname "$0")" && pwd)"
. "$ROOT/lib/common.sh"
require_root

STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="${1:-/root/cyberforce-audit-$STAMP.txt}"

{
    echo '=== DATE / HOST ==='; date; hostname; uname -a
    echo '=== NETWORK ==='; ip -br addr; ip route
    echo '=== LOGGED IN ==='; who; w
    echo '=== RECENT LOGINS ==='; last -n 100
    echo '=== UID 0 ACCOUNTS ==='; awk -F: '$3==0 {print}' /etc/passwd
    echo '=== UID >=1000 ACCOUNTS ==='; awk -F: '$3>=1000 {print}' /etc/passwd
    echo '=== SUDO GROUP ==='; getent group sudo || true
    echo '=== SUDOERS ==='; grep -RniEv '^[[:space:]]*(#|$)' /etc/sudoers /etc/sudoers.d 2>/dev/null || true
    echo '=== AUTHORIZED KEYS ==='; find /root /home -type f -name authorized_keys -print -exec sh -c 'echo "--- $1"; cat "$1"' _ {} \; 2>/dev/null || true
    echo '=== SSH EFFECTIVE SECURITY-RELEVANT SETTINGS ==='; sshd -T 2>/dev/null | grep -E '^(port|permitrootlogin|passwordauthentication|pubkeyauthentication|authorizedkeysfile|allowusers|denyusers|allowgroups|denygroups) ' || true
    echo '=== LISTENERS ==='; ss -lntup 2>&1 || true
    echo '=== ESTABLISHED CONNECTIONS ==='; ss -ntup 2>&1 || true
    echo '=== PROCESS TREE ==='; ps auxf
    echo '=== RUNNING SERVICES ==='; systemctl --type=service --state=running --no-pager 2>&1 || true
    echo '=== ENABLED SERVICES ==='; systemctl list-unit-files --type=service --state=enabled --no-pager 2>&1 || true
    echo '=== FAILED SERVICES ==='; systemctl --failed --no-pager 2>&1 || true
    echo '=== LOCAL SYSTEMD UNITS ==='; find /etc/systemd/system -maxdepth 4 \( -type f -o -type l \) -print 2>/dev/null || true
    echo '=== LOCAL SYSTEMD EXECSTART LINES ==='; grep -RniE '^[[:space:]]*Exec(Start|StartPre|StartPost)=' /etc/systemd/system 2>/dev/null || true
    echo '=== TIMERS ==='; systemctl list-timers --all --no-pager 2>&1 || true
    echo '=== SYSTEM CRONTAB ==='; cat /etc/crontab 2>&1 || true
    echo '=== CRON.D ==='; find /etc/cron.d -maxdepth 1 -type f -print -exec sh -c 'echo "--- $1"; cat "$1"' _ {} \; 2>/dev/null || true
    echo '=== USER CRONTABS ==='
    if [ -d /var/spool/cron/crontabs ]; then
        find /var/spool/cron/crontabs -maxdepth 1 -type f -print -exec sh -c 'echo "--- $1"; cat "$1"' _ {} \; 2>/dev/null || true
    fi
    echo '=== SHELL STARTUP SUSPICIOUS STRINGS ==='; grep -RniE 'curl|wget|nc[[:space:]]|bash[[:space:]]+-c|python|/tmp/|/dev/shm/' /etc/profile /etc/profile.d /root /home 2>/dev/null || true
    echo '=== LD.SO.PRELOAD ==='; cat /etc/ld.so.preload 2>&1 || true
    echo '=== TMP EXECUTABLES ==='; find /tmp /var/tmp /dev/shm -xdev -type f -executable -ls 2>/dev/null || true
    echo '=== RECENT ETC FILES (2 DAYS) ==='; find /etc -xdev -type f -mtime -2 -ls 2>/dev/null || true
    echo '=== RECENT ROOT/HOME FILES (2 DAYS) ==='; find /root /home -xdev -type f -mtime -2 -ls 2>/dev/null || true
    echo '=== SUID FILES ==='; find / -xdev -type f -perm -4000 -ls 2>/dev/null || true
    echo '=== NFTABLES ==='; nft list ruleset 2>&1 || true
} > "$OUT"

chmod 0600 "$OUT"
printf '%s\n' "$OUT"
