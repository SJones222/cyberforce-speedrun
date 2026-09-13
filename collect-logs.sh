#!/usr/bin/env bash
set -u

SERVICE="${1:-}"
[ -n "$SERVICE" ] || { echo "Usage: $0 {http|ssh|ftp|mariadb|dns|icmp}" >&2; exit 2; }

case "$SERVICE" in
    http|apache|apache2) UNIT=apache2; KIND=http ;;
    ssh|sshd) UNIT=ssh; KIND=ssh ;;
    ftp|vsftpd) UNIT=vsftpd; KIND=ftp ;;
    sql|mysql|mariadb) UNIT=mariadb; KIND=mariadb ;;
    dns|bind|bind9|named) UNIT=named; KIND=dns ;;
    icmp|ping) UNIT=''; KIND=icmp ;;
    *) echo "Usage: $0 {http|ssh|ftp|mariadb|dns|icmp}" >&2; exit 2 ;;
esac

STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="${TMPDIR:-/tmp}/cyberforce-${KIND}-${STAMP}.txt"

{
    echo '=== DATE ==='; date
    echo '=== HOST / NETWORK ==='; hostname; ip -br addr; ip route
    if [ -n "$UNIT" ]; then
        echo '=== SYSTEMD ==='; systemctl status "$UNIT" --no-pager 2>&1 || true
        echo '=== JOURNAL ==='; journalctl -u "$UNIT" --since '15 minutes ago' --no-pager 2>&1 || true
    fi
    echo '=== LISTENERS ==='; ss -lntup 2>&1 || true
    echo '=== CONNECTIONS ==='; ss -ntup 2>&1 || true
    echo '=== PROCESSES ==='; ps auxf

    case "$KIND" in
        http)
            echo '=== APACHE CONFIGTEST ==='; apache2ctl configtest 2>&1 || true
            echo '=== APACHE SITES ==='; apache2ctl -S 2>&1 || true
            echo '=== INDEX ==='; ls -l /var/www/html/index.html 2>&1 || true; cat /var/www/html/index.html 2>&1 || true
            ;;
        ssh)
            echo '=== SSHD TEST ==='; sshd -t 2>&1 || true
            echo '=== SSH EFFECTIVE ==='; sshd -T 2>&1 || true
            echo '=== SCORING KEYS ==='; ls -ld /home/ssh-user /home/ssh-user/.ssh 2>&1 || true; ls -l /home/ssh-user/.ssh/authorized_keys 2>&1 || true; cat /home/ssh-user/.ssh/authorized_keys 2>&1 || true
            ;;
        ftp)
            echo '=== VSFTPD CONFIG ==='; grep -Ev '^[[:space:]]*(#|$)' /etc/vsftpd.conf 2>&1 || true
            echo '=== FTP FILE ==='; ls -l /srv/ftp/iloveftp.txt 2>&1 || true; cat /srv/ftp/iloveftp.txt 2>&1 || true
            ;;
        mariadb)
            echo '=== MARIADB CONFIG ==='; grep -RniE '^[[:space:]]*(bind-address|port)[[:space:]]*=' /etc/mysql 2>&1 || true
            echo '=== MARIADB DATA ==='; mariadb -e 'SELECT User,Host FROM mysql.user WHERE User="scoring-sql"; SHOW GRANTS FOR "scoring-sql"@"%"; SELECT * FROM cyberforce.supersecret;' 2>&1 || true
            ;;
        dns)
            echo '=== NAMED-CHECKCONF ==='; named-checkconf -z 2>&1 || true
            echo '=== NAMED-CHECKZONE ==='; named-checkzone test.local /etc/bind/db.test.local 2>&1 || true
            echo '=== BIND FILES ==='; grep -nF 'cyberforce-test.local.conf' /etc/bind/named.conf.local 2>&1 || true; cat /etc/bind/cyberforce-test.local.conf 2>&1 || true; cat /etc/bind/db.test.local 2>&1 || true
            ;;
        icmp)
            echo '=== ICMP SYSCTL ==='; sysctl net.ipv4.icmp_echo_ignore_all 2>&1 || true
            echo '=== FIREWALL ==='; nft list ruleset 2>&1 || true
            ;;
    esac
} > "$OUT"

printf '%s\n' "$OUT"
