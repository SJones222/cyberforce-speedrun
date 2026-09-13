#!/usr/bin/env bash
set -u

if [ "$(id -u)" -ne 0 ]; then
    echo 'Run with sudo/root for complete nftables and process output.' >&2
    exit 1
fi

printf '=== NFTABLES RULESET ===\n'
nft list ruleset 2>&1 || true
printf '\n=== SCORED LISTENERS ===\n'
ss -lntup 2>&1 | grep -E '(:21|:22|:53|:80|:3306)([[:space:]]|$)' || true
cat <<'TXT'

Required scoring paths to preserve:
  ICMP echo
  TCP/21       FTP control
  TCP/22       SSH
  UDP/53       DNS
  TCP/53       DNS
  TCP/80       HTTP
  TCP/3306     MariaDB
  TCP/30000-30010 if using this repo's vsftpd passive-port configuration

This script intentionally DOES NOT modify firewall rules.
Do not assume the scoring-engine source IP or competition network until it is known.
TXT
