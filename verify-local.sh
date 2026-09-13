#!/usr/bin/env bash
set -u
ROOT="$(cd "$(dirname "$0")" && pwd)"
. "$ROOT/lib/common.sh"
require_root

PASS=0
FAIL=0
WARNINGS=0

pass() { printf '[PASS] %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf '[FAIL] %s\n' "$1"; FAIL=$((FAIL + 1)); }
warncheck() { printf '[WARN] %s\n' "$1"; WARNINGS=$((WARNINGS + 1)); }

check_service() {
    local svc="$1" label="$2"
    systemctl is-active --quiet "$svc" 2>/dev/null && pass "$label service active" || fail "$label service active"
}

listener_udp() {
    local port="$1"
    ss -lnuH 2>/dev/null | awk '{print $4}' | grep -Eq "(^|:)${port}$"
}

printf '=== Local CyberForce Validation ===\n'

# ICMP
[ "$(sysctl -n net.ipv4.icmp_echo_ignore_all 2>/dev/null || echo 1)" = 0 ] && pass 'ICMP kernel echo replies enabled' || fail 'ICMP kernel echo replies enabled'

# SSH
check_service ssh SSH
if sshd -t >/dev/null 2>&1; then pass 'SSH configuration syntax'; else fail 'SSH configuration syntax'; fi
if external_tcp_listener 22; then pass 'SSH TCP/22 externally bound'; else fail 'SSH TCP/22 externally bound'; fi
if id ssh-user >/dev/null 2>&1; then
    pass 'ssh-user exists'
    HOME_DIR="$(getent passwd ssh-user | cut -d: -f6)"
    KEY_EXPECTED="$(cat "$ROOT/configs/ssh/scoring_authorized_keys")"
    if grep -qxF "$KEY_EXPECTED" "$HOME_DIR/.ssh/authorized_keys" 2>/dev/null; then pass 'SSH scoring public key present'; else fail 'SSH scoring public key present'; fi
    [ "$(stat -c '%U:%G' "$HOME_DIR/.ssh" 2>/dev/null || true)" = 'ssh-user:ssh-user' ] && pass 'SSH .ssh ownership' || fail 'SSH .ssh ownership'
    [ "$(stat -c '%a' "$HOME_DIR/.ssh" 2>/dev/null || true)" = 700 ] && pass 'SSH .ssh mode 700' || fail 'SSH .ssh mode 700'
    [ "$(stat -c '%a' "$HOME_DIR/.ssh/authorized_keys" 2>/dev/null || true)" = 600 ] && pass 'SSH authorized_keys mode 600' || fail 'SSH authorized_keys mode 600'
else
    fail 'ssh-user exists'
fi
EFFECTIVE="$(sshd -T 2>/dev/null || true)"
printf '%s\n' "$EFFECTIVE" | grep -qx 'port 22' && pass 'SSH effective port 22' || fail 'SSH effective port 22'
printf '%s\n' "$EFFECTIVE" | grep -qx 'pubkeyauthentication yes' && pass 'SSH public-key authentication enabled' || fail 'SSH public-key authentication enabled'

# HTTP
if apache2ctl configtest >/dev/null 2>&1; then pass 'HTTP Apache configuration syntax'; else fail 'HTTP Apache configuration syntax'; fi
check_service apache2 HTTP
external_tcp_listener 80 && pass 'HTTP TCP/80 externally bound' || fail 'HTTP TCP/80 externally bound'
HTTP_BODY="$(curl -fsS --max-time 3 http://127.0.0.1/ 2>/dev/null || true)"
[ "$HTTP_BODY" = 'Hello World!' ] && pass 'HTTP exact body' || fail "HTTP exact body (got: ${HTTP_BODY:-<empty>})"

# FTP
check_service vsftpd FTP
FTP_BODY="$(curl -fsS --max-time 5 ftp://127.0.0.1/iloveftp.txt 2>/dev/null || true)"
[ "$FTP_BODY" = 'iloveftp' ] && pass 'FTP anonymous scored file' || fail "FTP anonymous scored file (got: ${FTP_BODY:-<empty>})"
external_tcp_listener 21 && pass 'FTP TCP/21 externally bound' || fail 'FTP TCP/21 externally bound'

# MariaDB
check_service mariadb MariaDB
SQL_BODY="$(MYSQL_PWD=password mariadb --protocol=TCP --connect-timeout=3 -N -s -h 127.0.0.1 -u scoring-sql -e 'SELECT data FROM cyberforce.supersecret WHERE data=7 LIMIT 1;' 2>/dev/null || true)"
[ "$SQL_BODY" = 7 ] && pass 'MariaDB scored query' || fail "MariaDB scored query (got: ${SQL_BODY:-<empty>})"
external_tcp_listener 3306 && pass 'MariaDB TCP/3306 externally bound' || fail 'MariaDB TCP/3306 externally bound'
GRANTS="$(mariadb -N -s -e "SHOW GRANTS FOR 'scoring-sql'@'%';" 2>/dev/null || true)"
printf '%s\n' "$GRANTS" | grep -Fq 'cyberforce' && pass 'MariaDB scoring-sql@% grant present' || fail 'MariaDB scoring-sql@% grant present'

# DNS
check_service named DNS
DNS_UDP="$(dig +short +time=2 +tries=1 @127.0.0.1 test.local A 2>/dev/null || true)"
DNS_TCP="$(dig +tcp +short +time=2 +tries=1 @127.0.0.1 test.local A 2>/dev/null || true)"
[ "$DNS_UDP" = '10.10.10.10' ] && pass 'DNS UDP answer' || fail "DNS UDP answer (got: ${DNS_UDP:-<empty>})"
[ "$DNS_TCP" = '10.10.10.10' ] && pass 'DNS TCP answer' || fail "DNS TCP answer (got: ${DNS_TCP:-<empty>})"
external_tcp_listener 53 && pass 'DNS TCP/53 externally bound' || fail 'DNS TCP/53 externally bound'
listener_udp 53 && pass 'DNS UDP/53 listening' || fail 'DNS UDP/53 listening'

if command -v nft >/dev/null 2>&1 && nft list ruleset 2>/dev/null | grep -qE 'drop|reject'; then
    warncheck 'Firewall contains drop/reject rules. Local checks cannot prove remote scoring reachability; run verify-remote.sh from another host.'
fi

printf '\nPASS=%d FAIL=%d WARN=%d\n' "$PASS" "$FAIL" "$WARNINGS"
[ "$FAIL" -eq 0 ]
