#!/usr/bin/env bash
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/lib/common.sh"
require_root

have_cmd mariadb || die "MariaDB client/server is not installed. Run ./install-packages.sh first."
CONF=/etc/mysql/mariadb.conf.d/99-cyberforce.cnf
install_managed_file "$ROOT/configs/mariadb/99-cyberforce.cnf" "$CONF" 0644 root:root

# Parse all configured server options before touching the running daemon where possible.
if have_cmd mariadbd; then
    mariadbd --verbose --help >/dev/null 2>&1 || die "MariaDB configuration parsing failed after installing $CONF."
fi

systemctl enable mariadb >/dev/null 2>&1 || true
systemctl start mariadb || die "MariaDB could not be started. Check: journalctl -xeu mariadb"

STAMP="$(date +%Y%m%d-%H%M%S)"
if mariadb -Nse 'SHOW DATABASES LIKE "cyberforce";' 2>/dev/null | grep -qx cyberforce; then
    mkdir -p /root/cyberforce-backups
    mariadb-dump --databases cyberforce > "/root/cyberforce-backups/cyberforce-before-setup-$STAMP.sql" 2>/dev/null || warn "Could not dump existing cyberforce database."
fi

log "Rebuilding the explicitly scored cyberforce.supersecret table and scoring-sql@% account..."
mariadb < "$ROOT/configs/mariadb/cyberforce.sql" || die "SQL bootstrap failed."
restart_checked mariadb || die "MariaDB failed to restart. Check: journalctl -xeu mariadb"

LISTENERS="$(ss -lntH | awk '$4 ~ /:3306$/ {print $4}')"
[ -n "$LISTENERS" ] || die "MariaDB is not listening on TCP/3306."
if ! printf '%s\n' "$LISTENERS" | grep -Ev '^(127\.|\[::1\]:|::1:)' >/dev/null; then
    die "MariaDB appears bound only to loopback. Inspect effective bind-address."
fi

VALUE="$(mariadb --protocol=TCP -N -s -u scoring-sql -ppassword -h 127.0.0.1 -e 'SELECT data FROM cyberforce.supersecret WHERE data=7 LIMIT 1;' 2>/dev/null || true)"
[ "$VALUE" = '7' ] || die "Local TCP scoring query failed."

GRANTS="$(mariadb -N -s -e "SHOW GRANTS FOR 'scoring-sql'@'%';" 2>/dev/null || true)"
printf '%s\n' "$GRANTS" | grep -Fq 'cyberforce' || die "scoring-sql@% does not have the expected cyberforce grant."
OTHER_HOSTS="$(mariadb -N -s -e "SELECT Host FROM mysql.user WHERE User='scoring-sql' AND Host <> '%';" 2>/dev/null || true)"
if [ -n "$OTHER_HOSTS" ]; then
    warn "Additional scoring-sql host-specific accounts exist and can take precedence over scoring-sql@% for matching clients:"
    printf '%s\n' "$OTHER_HOSTS" >&2
    warn "Review them manually before deleting; this script does not remove unrelated host-specific accounts automatically."
fi
log "MariaDB is locally healthy and exposed on TCP/3306."
