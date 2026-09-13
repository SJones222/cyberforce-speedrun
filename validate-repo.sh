#!/usr/bin/env bash
set -u
ROOT="$(cd "$(dirname "$0")" && pwd)"
FAIL=0
WARN=0

pass() { printf '[PASS] %s\n' "$1"; }
fail() { printf '[FAIL] %s\n' "$1"; FAIL=$((FAIL + 1)); }
warn() { printf '[WARN] %s\n' "$1"; WARN=$((WARN + 1)); }

printf '=== Bash syntax ===\n'
while IFS= read -r -d '' f; do
    rel="${f#$ROOT/}"
    if bash -n "$f"; then pass "bash -n $rel"; else fail "bash -n $rel"; fi
done < <(find "$ROOT" -path "$ROOT/.git" -prune -o -type f -name '*.sh' -print0)

printf '\n=== Executable bits ===\n'
while IFS= read -r -d '' f; do
    rel="${f#$ROOT/}"
    if [ -x "$f" ]; then pass "executable $rel"; else fail "not executable $rel"; fi
done < <(find "$ROOT" -path "$ROOT/.git" -prune -o -type f -name '*.sh' -print0)

printf '\n=== ShellCheck ===\n'
if command -v shellcheck >/dev/null 2>&1; then
    mapfile -d '' SHELL_FILES < <(find "$ROOT" -path "$ROOT/.git" -prune -o -type f -name '*.sh' -print0)
    if shellcheck -e SC1090,SC1091 "${SHELL_FILES[@]}"; then pass 'ShellCheck'; else fail 'ShellCheck'; fi
else
    warn 'ShellCheck is not installed in this environment; bash -n and repository-specific checks still ran.'
fi

printf '\n=== Required files / scoring constants ===\n'
REQ=(
    configs/apache/index.html
    configs/apache/000-cyberforce.conf
    configs/ssh/scoring_authorized_keys
    configs/ssh/00-00-cyberforce-scoring.conf
    configs/vsftpd/vsftpd.conf
    configs/mariadb/99-cyberforce.cnf
    configs/mariadb/cyberforce.sql
    configs/bind/cyberforce-test.local.conf
    configs/bind/db.test.local
)
for f in "${REQ[@]}"; do
    [ -f "$ROOT/$f" ] && pass "exists $f" || fail "missing $f"
done

if [ "$(cat "$ROOT/configs/apache/index.html" 2>/dev/null || true)" = 'Hello World!' ] && [ "$(wc -c < "$ROOT/configs/apache/index.html")" -eq 12 ]; then
    pass 'HTTP body is exactly 12 bytes: Hello World!'
else
    fail 'HTTP body is not exact'
fi

grep -qxF 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL/cZinfkOPl5V4r1WfV7QJoziLgRY/tiqxvvRb9+sA1 ssh-user@debian12' "$ROOT/configs/ssh/scoring_authorized_keys" && pass 'scoring SSH public key' || fail 'scoring SSH public key'
grep -q '^Port 22$' "$ROOT/configs/ssh/00-00-cyberforce-scoring.conf" && pass 'SSH port 22 directive' || fail 'SSH port 22 directive'
grep -q '^PubkeyAuthentication yes$' "$ROOT/configs/ssh/00-00-cyberforce-scoring.conf" && pass 'SSH public-key directive' || fail 'SSH public-key directive'

grep -q '^anonymous_enable=YES$' "$ROOT/configs/vsftpd/vsftpd.conf" && pass 'FTP anonymous enabled' || fail 'FTP anonymous enabled'
grep -q '^local_enable=NO$' "$ROOT/configs/vsftpd/vsftpd.conf" && pass 'FTP local login disabled' || fail 'FTP local login disabled'
grep -q '^write_enable=NO$' "$ROOT/configs/vsftpd/vsftpd.conf" && pass 'FTP writes disabled' || fail 'FTP writes disabled'
DUP_FTP="$(grep -Ev '^[[:space:]]*(#|$)' "$ROOT/configs/vsftpd/vsftpd.conf" | cut -d= -f1 | sort | uniq -d || true)"
[ -z "$DUP_FTP" ] && pass 'FTP config has no duplicate directives' || fail "FTP duplicate directives: $DUP_FTP"

grep -q '^bind-address = 0.0.0.0$' "$ROOT/configs/mariadb/99-cyberforce.cnf" && pass 'MariaDB external bind' || fail 'MariaDB external bind'
grep -q '^port = 3306$' "$ROOT/configs/mariadb/99-cyberforce.cnf" && pass 'MariaDB port 3306' || fail 'MariaDB port 3306'
grep -Fq "CREATE USER 'scoring-sql'@'%' IDENTIFIED BY 'password';" "$ROOT/configs/mariadb/cyberforce.sql" && pass 'MariaDB scoring account' || fail 'MariaDB scoring account'
grep -q 'VALUES (7)' "$ROOT/configs/mariadb/cyberforce.sql" && pass 'MariaDB value 7' || fail 'MariaDB value 7'

grep -Eq 'zone[[:space:]]+"test\.local"' "$ROOT/configs/bind/cyberforce-test.local.conf" && pass 'BIND test.local zone declaration' || fail 'BIND test.local zone declaration'
grep -Eq '@[[:space:]]+IN[[:space:]]+A[[:space:]]+10\.10\.10\.10' "$ROOT/configs/bind/db.test.local" && pass 'DNS scored A record' || fail 'DNS scored A record'

if command -v named-checkzone >/dev/null 2>&1; then
    named-checkzone test.local "$ROOT/configs/bind/db.test.local" >/dev/null 2>&1 && pass 'named-checkzone zone syntax' || fail 'named-checkzone zone syntax'
else
    warn 'named-checkzone unavailable; BIND zone validated structurally only.'
fi

printf '\n=== Secret / private-key guard ===\n'
if grep -RInE --exclude-dir=.git --exclude='validate-repo.sh' 'BEGIN (RSA |OPENSSH |EC |DSA )?PRIVATE KEY|github_pat_[A-Za-z0-9_]+|ghp_[A-Za-z0-9]+' "$ROOT" >/dev/null 2>&1; then
    fail 'possible private key or GitHub token material detected'
else
    pass 'no private-key headers or GitHub token patterns detected'
fi

printf '\n=== CRLF guard ===\n'
CRLF="$(find "$ROOT" -path "$ROOT/.git" -prune -o -type f \( -name '*.sh' -o -name '*.conf' -o -name '*.sql' \) -print0 | xargs -0 grep -Il $'\r' 2>/dev/null || true)"
[ -z "$CRLF" ] && pass 'no CRLF in scripts/configs' || fail "CRLF detected: $CRLF"

printf '\nRepository validation: FAIL=%d WARN=%d\n' "$FAIL" "$WARN"
[ "$FAIL" -eq 0 ]
