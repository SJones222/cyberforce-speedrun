#!/usr/bin/env bash
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/lib/common.sh"
require_root

CONF=/etc/sysctl.d/99-cyberforce-icmp.conf
backup_file "$CONF"
cat > "$CONF" <<'EOC'
# Managed by cyberforce-speedrun.
net.ipv4.icmp_echo_ignore_all=0
EOC
chmod 0644 "$CONF"
sysctl -w net.ipv4.icmp_echo_ignore_all=0 >/dev/null
sysctl -p "$CONF" >/dev/null
[ "$(sysctl -n net.ipv4.icmp_echo_ignore_all)" = 0 ] || die "ICMP echo replies remain disabled."
log "ICMP echo replies enabled at the kernel level. Firewall rules may still block remote ping."
