#!/usr/bin/env bash
set -u
ROOT="$(cd "$(dirname "$0")" && pwd)"
. "$ROOT/lib/common.sh"
require_root

PACKAGES=(
    apache2
    openssh-server
    vsftpd
    mariadb-server
    mariadb-client
    bind9
    bind9-utils
    dnsutils
    curl
    nftables
    tcpdump
    netcat-openbsd
    iputils-ping
    procps
    psmisc
    ca-certificates
    git
)

MISSING=()
for pkg in "${PACKAGES[@]}"; do
    if ! dpkg-query -W -f='${db:Status-Abbrev}' "$pkg" 2>/dev/null | grep -q '^ii '; then
        MISSING+=("$pkg")
    fi
done

if [ "${#MISSING[@]}" -eq 0 ]; then
    log "All required packages are already installed."
    exit 0
fi

log "Missing packages: ${MISSING[*]}"
export DEBIAN_FRONTEND=noninteractive

if [ "${SKIP_APT_UPDATE:-0}" != 1 ]; then
    log "Refreshing package metadata..."
    apt-get update || die "apt-get update failed. Check Internet/DNS/repository access."
fi

log "Installing missing packages..."
apt-get install -y "${MISSING[@]}" || die "Package installation failed."
log "Package installation complete."
