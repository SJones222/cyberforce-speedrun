#!/usr/bin/env bash
set -u
ROOT="$(cd "$(dirname "$0")" && pwd)"
. "$ROOT/lib/common.sh"
require_root

STAMP="$(date +%Y%m%d-%H%M%S)"
DIR="/root/cyberforce-backups/state-$STAMP"
mkdir -p "$DIR/configs"
chmod 0700 "$DIR"
log "Saving pre-change state to $DIR"

for item in \
    /etc/ssh \
    /etc/apache2 \
    /etc/vsftpd.conf \
    /srv/ftp \
    /etc/bind \
    /etc/mysql \
    /etc/sysctl.conf \
    /etc/sysctl.d \
    /etc/nftables.conf \
    /etc/crontab \
    /etc/cron.d \
    /etc/systemd/system; do
    if [ -e "$item" ]; then
        cp -a "$item" "$DIR/configs/" 2>/dev/null || true
    fi
done

getent passwd > "$DIR/passwd.txt" 2>&1 || true
getent group > "$DIR/group.txt" 2>&1 || true
ss -lntup > "$DIR/listeners.txt" 2>&1 || true
ss -ntup > "$DIR/connections.txt" 2>&1 || true
ps auxf > "$DIR/processes.txt" 2>&1 || true
systemctl list-unit-files --no-pager > "$DIR/systemd-units.txt" 2>&1 || true
systemctl list-timers --all --no-pager > "$DIR/timers.txt" 2>&1 || true
systemctl --failed --no-pager > "$DIR/failed-units.txt" 2>&1 || true
nft list ruleset > "$DIR/nftables.txt" 2>&1 || true
who > "$DIR/who.txt" 2>&1 || true
last -n 100 > "$DIR/last.txt" 2>&1 || true

find /root /home -type f -name authorized_keys -print -exec sh -c 'echo "--- $1"; cat "$1"' _ {} \; > "$DIR/authorized_keys.txt" 2>&1 || true

if command -v mariadb-dump >/dev/null 2>&1 && mariadb -Nse 'SHOW DATABASES LIKE "cyberforce";' 2>/dev/null | grep -qx cyberforce; then
    mariadb-dump --databases cyberforce > "$DIR/cyberforce.sql" 2>/dev/null || true
fi

printf '%s\n' "$DIR"
