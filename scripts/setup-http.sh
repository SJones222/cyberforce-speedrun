#!/usr/bin/env bash
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/lib/common.sh"
require_root

have_cmd apache2ctl || die "apache2 is not installed. Run ./install-packages.sh first."
mkdir -p /var/www/html /etc/apache2/sites-available /etc/apache2/sites-enabled /etc/apache2/conf-available /etc/apache2/conf-enabled
install_managed_file "$ROOT/configs/apache/index.html" /var/www/html/index.html 0644 root:root
install_managed_file "$ROOT/configs/apache/000-cyberforce.conf" /etc/apache2/sites-available/000-cyberforce.conf 0644 root:root
ln -sfn ../sites-available/000-cyberforce.conf /etc/apache2/sites-enabled/000-cyberforce.conf

# Fresh Debian already listens on 80. If it no longer does, add a small managed
# Listen directive instead of replacing ports.conf.
if ! grep -RhsE '^[[:space:]]*Listen[[:space:]]+([^#[:space:]]*:)?80([[:space:]]|$)' /etc/apache2/ports.conf /etc/apache2/conf-enabled 2>/dev/null | grep -q .; then
    LISTEN_CONF=/etc/apache2/conf-available/00-cyberforce-listen.conf
    backup_file "$LISTEN_CONF"
    printf '%s\n' 'Listen 80' > "$LISTEN_CONF"
    chmod 0644 "$LISTEN_CONF"
    ln -sfn ../conf-available/00-cyberforce-listen.conf /etc/apache2/conf-enabled/00-cyberforce-listen.conf
fi

apache2ctl configtest || die "Apache configuration validation failed. Inspect: apache2ctl configtest"
systemctl enable apache2 >/dev/null 2>&1 || true
restart_checked apache2 || die "Apache failed to restart. Check: journalctl -xeu apache2"

RESULT="$(curl -fsS --max-time 3 http://127.0.0.1/ 2>/dev/null || true)"
[ "$RESULT" = 'Hello World!' ] || die "Local HTTP body is not exactly 'Hello World!'."
ss -lntH | awk '{print $4}' | grep -Eq '(^|:)80$' || die "Apache is not listening on TCP/80."
log "HTTP is locally healthy on TCP/80."
