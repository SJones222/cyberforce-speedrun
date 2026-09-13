#!/usr/bin/env bash
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/lib/common.sh"
require_root

have_cmd named-checkconf || die "BIND utilities are not installed. Run ./install-packages.sh first."
MAIN=/etc/bind/named.conf.local
FRAG=/etc/bind/cyberforce-test.local.conf
ZONE=/etc/bind/db.test.local
INCLUDE='include "/etc/bind/cyberforce-test.local.conf";'

mkdir -p /etc/bind
touch "$MAIN"

# Do not silently overwrite an existing test.local zone definition in an unrelated file.
CONFLICTS="$(grep -RIlE 'zone[[:space:]]+"test\.local"' /etc/bind --include='*.conf' 2>/dev/null | grep -vF "$FRAG" || true)"
if [ -n "$CONFLICTS" ]; then
    warn "An existing test.local zone definition already exists outside this toolkit:"
    printf '%s\n' "$CONFLICTS" >&2
    die "Refusing to overwrite unrelated BIND configuration. Inspect the file above, back it up, and resolve the duplicate zone before rerunning."
fi

install_managed_file "$ROOT/configs/bind/cyberforce-test.local.conf" "$FRAG" 0644 root:bind
install_managed_file "$ROOT/configs/bind/db.test.local" "$ZONE" 0644 root:bind

if ! grep -qxF "$INCLUDE" "$MAIN"; then
    backup_file "$MAIN"
    cat >> "$MAIN" <<'EOB'

// BEGIN CYBERFORCE-SPEEDRUN MANAGED INCLUDE
include "/etc/bind/cyberforce-test.local.conf";
// END CYBERFORCE-SPEEDRUN MANAGED INCLUDE
EOB
fi

named-checkzone test.local "$ZONE" || die "test.local zone validation failed."
named-checkconf -z || die "BIND configuration/zone validation failed. No restart performed."

systemctl enable named >/dev/null 2>&1 || true
restart_checked named || die "BIND failed to restart. Check: journalctl -xeu named"

UDP="$(dig +short +time=2 +tries=1 @127.0.0.1 test.local A 2>/dev/null || true)"
TCP="$(dig +tcp +short +time=2 +tries=1 @127.0.0.1 test.local A 2>/dev/null || true)"
[ "$UDP" = '10.10.10.10' ] || die "Local DNS/UDP response is incorrect: ${UDP:-<empty>}"
[ "$TCP" = '10.10.10.10' ] || die "Local DNS/TCP response is incorrect: ${TCP:-<empty>}"
log "DNS is locally healthy on UDP/53 and TCP/53."
