#!/usr/bin/env bash
set -u
ROOT="$(cd "$(dirname "$0")" && pwd)"

showdiff() {
    local good="$1" live="$2"
    printf '\n=== %s ===\n' "$live"
    if [ ! -e "$live" ]; then
        echo 'LIVE FILE MISSING'
        return
    fi
    diff -u "$good" "$live" || true
}

showdiff "$ROOT/configs/apache/index.html" /var/www/html/index.html
showdiff "$ROOT/configs/apache/000-cyberforce.conf" /etc/apache2/sites-available/000-cyberforce.conf
showdiff "$ROOT/configs/ssh/00-00-cyberforce-scoring.conf" /etc/ssh/sshd_config.d/00-00-cyberforce-scoring.conf
showdiff "$ROOT/configs/vsftpd/vsftpd.conf" /etc/vsftpd.conf
showdiff "$ROOT/configs/mariadb/99-cyberforce.cnf" /etc/mysql/mariadb.conf.d/99-cyberforce.cnf
showdiff "$ROOT/configs/bind/cyberforce-test.local.conf" /etc/bind/cyberforce-test.local.conf
showdiff "$ROOT/configs/bind/db.test.local" /etc/bind/db.test.local

printf '\n=== BIND managed include ===\n'
grep -nF 'include "/etc/bind/cyberforce-test.local.conf";' /etc/bind/named.conf.local 2>/dev/null || echo 'MANAGED INCLUDE MISSING'
