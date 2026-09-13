#!/usr/bin/env bash
set -u
OUT="${1:-/root/cyberforce-integrity.sha256}"
[ "$(id -u)" -eq 0 ] || { echo 'Run with sudo/root.' >&2; exit 1; }

FILES=(
    /etc/ssh/sshd_config
    /etc/ssh/sshd_config.d/00-00-cyberforce-scoring.conf
    /home/ssh-user/.ssh/authorized_keys
    /etc/vsftpd.conf
    /srv/ftp/iloveftp.txt
    /etc/mysql/mariadb.conf.d/99-cyberforce.cnf
    /etc/bind/named.conf.local
    /etc/bind/cyberforce-test.local.conf
    /etc/bind/db.test.local
    /var/www/html/index.html
    /etc/apache2/sites-available/000-cyberforce.conf
    /etc/sysctl.d/99-cyberforce-icmp.conf
    /etc/crontab
)

: > "$OUT"
for f in "${FILES[@]}"; do
    [ -f "$f" ] && sha256sum "$f" >> "$OUT"
done
chmod 0600 "$OUT"
printf '%s\n' "$OUT"
