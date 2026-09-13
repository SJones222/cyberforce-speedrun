#!/usr/bin/env bash
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/lib/common.sh"
require_root

have_cmd apache2ctl || die "apache2 is not installed. Run ./install-packages.sh first."
have_cmd curl || die "curl is not installed. Run ./install-packages.sh first."
have_cmd ss || die "ss is not installed. Run ./install-packages.sh first."

APACHE_ETC=/etc/apache2
mkdir -p /var/www/html \
    "$APACHE_ETC/sites-available" \
    "$APACHE_ETC/sites-enabled" \
    "$APACHE_ETC/conf-available" \
    "$APACHE_ETC/conf-enabled"

install_managed_file "$ROOT/configs/apache/index.html" /var/www/html/index.html 0644 root:root
install_managed_file "$ROOT/configs/apache/000-cyberforce.conf" "$APACHE_ETC/sites-available/000-cyberforce.conf" 0644 root:root
ln -sfn ../sites-available/000-cyberforce.conf "$APACHE_ETC/sites-enabled/000-cyberforce.conf"

# Syntax validation is intentionally separate from runtime validation: Apache
# can report "Syntax OK" and still fail to start because Listen directives
# overlap or another process owns TCP/80.
apache2ctl configtest || die "Apache configuration syntax is invalid. Inspect: apache2ctl configtest"

apache_normalize_port80_listeners || die "Could not produce one safe, non-overlapping Apache TCP/80 Listen directive."

apache2ctl configtest || die "Apache configuration syntax failed after listener normalization."
systemctl enable apache2 >/dev/null 2>&1 || true

if ! systemctl restart apache2; then
    warn "Apache restart failed even though configtest passed. Runtime bind conflicts are possible."
    ss -ltnp 2>/dev/null | grep -E '(:80)([[:space:]]|$)' >&2 || true
    systemctl status apache2 --no-pager -l >&2 || true
    journalctl -u apache2 -n 50 --no-pager >&2 || true
    die "Apache failed to restart."
fi

systemctl is-active --quiet apache2 || die "Apache restart returned but apache2.service is not active."

if ! external_tcp_listener 80; then
    ss -ltnp 2>/dev/null | grep -E '(:80)([[:space:]]|$)' >&2 || true
    die "Apache is not externally listening on TCP/80 after restart."
fi

RESULT="$(curl -fsS --max-time 3 http://127.0.0.1/ 2>/dev/null || true)"
[ "$RESULT" = 'Hello World!' ] || die "Local HTTP body is not exactly 'Hello World!' (got: ${RESULT:-<empty>})."

log "HTTP is healthy: apache2 active, TCP/80 externally bound, body exactly 'Hello World!'."
