#!/usr/bin/env bash

log()  { printf '[*] %s\n' "$*"; }
warn() { printf '[!] %s\n' "$*" >&2; }
die()  { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

require_root() {
    [ "${EUID:-$(id -u)}" -eq 0 ] || die "Run this script as root (sudo)."
}

repo_root() {
    cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}

have_cmd() {
    command -v "$1" >/dev/null 2>&1
}

service_exists() {
    systemctl cat "$1" >/dev/null 2>&1
}

restart_checked() {
    local svc="$1"
    systemctl restart "$svc" || return 1
    systemctl is-active --quiet "$svc"
}

backup_file() {
    local src="$1"
    [ -e "$src" ] || return 0

    local stamp safe dir dst
    stamp="$(date +%Y%m%d-%H%M%S)"
    safe="${src#/}"
    safe="${safe//\//__}"
    dir="/root/cyberforce-backups/files"
    mkdir -p "$dir"
    dst="$dir/${safe}.${stamp}"
    cp -a "$src" "$dst"
    log "Backed up $src -> $dst"
}

install_managed_file() {
    local src="$1" dst="$2" mode="${3:-0644}" owner="${4:-root:root}"
    [ -f "$src" ] || die "Managed source missing: $src"
    backup_file "$dst"
    install -D -m "$mode" -o "${owner%%:*}" -g "${owner##*:}" "$src" "$dst"
}
