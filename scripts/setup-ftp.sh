#!/usr/bin/env bash
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/lib/common.sh"
require_root

have_cmd vsftpd || die "vsftpd is not installed. Run ./install-packages.sh first."
install_managed_file "$ROOT/configs/vsftpd/vsftpd.conf" /etc/vsftpd.conf 0644 root:root

mkdir -p /srv/ftp /var/run/vsftpd/empty
chown root:root /srv/ftp /var/run/vsftpd/empty
chmod 0755 /srv/ftp
chmod 0555 /var/run/vsftpd/empty
backup_file /srv/ftp/iloveftp.txt
printf 'iloveftp\n' > /srv/ftp/iloveftp.txt
chown root:root /srv/ftp/iloveftp.txt
chmod 0644 /srv/ftp/iloveftp.txt

systemctl enable vsftpd >/dev/null 2>&1 || true
if ! restart_checked vsftpd; then
    die "vsftpd rejected the known-good config or failed to start. Check: journalctl -xeu vsftpd"
fi

RESULT="$(curl -fsS --max-time 5 ftp://127.0.0.1/iloveftp.txt 2>/dev/null || true)"
[ "$RESULT" = 'iloveftp' ] || die "Local anonymous FTP retrieval failed."
ss -lntH | awk '{print $4}' | grep -Eq '(^|:)21$' || die "vsftpd is not listening on TCP/21."
log "FTP is locally healthy. Passive data range: TCP/30000-30010."
