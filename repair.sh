#!/usr/bin/env bash
set -u
ROOT="$(cd "$(dirname "$0")" && pwd)"
. "$ROOT/lib/common.sh"
require_root

SERVICE="${1:-}"
case "$SERVICE" in
    http|apache|apache2) SCRIPT=setup-http.sh ;;
    ssh|sshd) SCRIPT=setup-ssh.sh ;;
    ftp|vsftpd) SCRIPT=setup-ftp.sh ;;
    sql|mysql|mariadb) SCRIPT=setup-mariadb.sh ;;
    dns|bind|bind9|named) SCRIPT=setup-dns.sh ;;
    icmp|ping) SCRIPT=setup-icmp.sh ;;
    *) echo "Usage: sudo $0 {http|ssh|ftp|mariadb|dns|icmp}" >&2; exit 2 ;;
esac

"$ROOT/install-packages.sh" || die "Required package preparation failed."
exec "$ROOT/scripts/$SCRIPT"
