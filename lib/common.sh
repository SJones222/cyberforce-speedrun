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
    dir="${CYBERFORCE_BACKUP_DIR:-/root/cyberforce-backups/files}"
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

external_tcp_listener() {
    local port="$1" addrs
    addrs="$(ss -lntH 2>/dev/null | awk -v p=":$port" '$4 ~ p"$" {print $4}')"
    [ -n "$addrs" ] || return 1
    printf '%s\n' "$addrs" | grep -Ev '^(127\.|\[::1\]:|::1:)' >/dev/null
}

# Print the Apache configuration files that are active under Debian's normal
# include layout. DUMP_INCLUDES is preferred because it reports Apache's parsed
# include chain; the standard enabled directories are included as a fallback.
apache_active_config_files() {
    local apache_etc="${APACHE_ETC:-/etc/apache2}" dir path

    {
        [ -f "$apache_etc/apache2.conf" ] && printf '%s\n' "$apache_etc/apache2.conf"
        [ -f "$apache_etc/ports.conf" ] && printf '%s\n' "$apache_etc/ports.conf"

        if [ "$apache_etc" = /etc/apache2 ] && have_cmd apache2ctl; then
            apache2ctl -t -D DUMP_INCLUDES 2>/dev/null \
                | awk 'match($0, /\/[^[:space:]]+$/) { print substr($0, RSTART, RLENGTH) }'
        fi

        for dir in "$apache_etc/mods-enabled" "$apache_etc/conf-enabled" "$apache_etc/sites-enabled"; do
            if [ -d "$dir" ]; then
                find -L "$dir" -maxdepth 1 -type f -print 2>/dev/null
            fi
        done
    } | while IFS= read -r path; do
        [ -n "$path" ] || continue
        readlink -f "$path" 2>/dev/null || printf '%s\n' "$path"
    done | awk '!seen[$0]++'
}

# Print active-looking Apache Listen directives for TCP/80 as tab-separated:
# file, line number, Listen argument, full original line.
#
# Apache does not expose a dedicated "effective Listen directives" dump, so we
# inspect the parsed include chain and Debian's active enabled directories. This
# deliberately ignores commented directives.
apache_port80_listen_records() {
    local file
    while IFS= read -r file; do
        [ -r "$file" ] || continue
        awk '
            /^[[:space:]]*#/ { next }
            {
                raw = $0
                line = $0
                sub(/[[:space:]]*#.*/, "", line)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
                n = split(line, field, /[[:space:]]+/)
                if (n < 2 || tolower(field[1]) != "listen") next
                arg = field[2]
                if (arg == "80" || arg ~ /:80$/) {
                    printf "%s\t%d\t%s\t%s\n", FILENAME, FNR, arg, raw
                }
            }
        ' "$file"
    done < <(apache_active_config_files)
}


apache_rewrite_port80_listens_in_file() {
    local file="$1" tmp
    tmp="$(mktemp)"

    awk '
        function port80_listen(raw, line, n, field, arg) {
            line = raw
            if (line ~ /^[[:space:]]*#/) return 0
            sub(/[[:space:]]*#.*/, "", line)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
            n = split(line, field, /[[:space:]]+/)
            if (n < 2 || tolower(field[1]) != "listen") return 0
            arg = field[2]
            return (arg == "80" || arg ~ /:80$/)
        }
        {
            if (port80_listen($0)) {
                print "# cyberforce-disabled-port80-listen: " $0
            } else {
                print
            }
        }
    ' "$file" > "$tmp"

    cat "$tmp" > "$file"
    rm -f "$tmp"
}

# Normalize Apache's active-looking TCP/80 listener set to a competition-safe
# state. If there is exactly one externally reachable, non-overlapping listener
# (`Listen 80` or `Listen 0.0.0.0:80`), it is preserved. Otherwise every
# detected port-80 Listen directive is backed up and disabled, and a single
# managed `Listen 80` is enabled.
apache_normalize_port80_listeners() {
    local apache_etc="${APACHE_ETC:-/etc/apache2}"
    local listen_conf="$apache_etc/conf-available/00-cyberforce-listen.conf"
    local listen_link="$apache_etc/conf-enabled/00-cyberforce-listen.conf"
    local managed_real record file only_arg final_arg
    local normalize=1
    declare -A edited_files=()
    local -a records final_records

    mkdir -p "$apache_etc/conf-available" "$apache_etc/conf-enabled"

    mapfile -t records < <(apache_port80_listen_records)
    log "Apache TCP/80 Listen directives detected: ${#records[@]}"
    if [ "${#records[@]}" -gt 0 ]; then
        printf '%s\n' "${records[@]}" | while IFS=$'\t' read -r file line arg raw; do
            log "$file:$line -> $raw"
        done
    fi

    if [ "${#records[@]}" -eq 1 ]; then
        IFS=$'\t' read -r _ _ only_arg _ <<< "${records[0]}"
        case "$only_arg" in
            80|0.0.0.0:80)
                normalize=0
                log "Existing TCP/80 listener is already externally reachable and non-overlapping ($only_arg)."
                ;;
        esac
    fi

    if [ "$normalize" -eq 1 ]; then
        if [ "${#records[@]}" -eq 0 ]; then
            log "No active TCP/80 Listen directive found; installing one managed wildcard listener."
        else
            warn "Conflicting, duplicate, or address-specific TCP/80 Listen directives detected. Normalizing to one 'Listen 80'."
        fi

        managed_real="$(readlink -f "$listen_conf" 2>/dev/null || printf '%s' "$listen_conf")"
        for record in "${records[@]}"; do
            IFS=$'\t' read -r file _ _ _ <<< "$record"
            [ -n "$file" ] || continue
            [ "$file" = "$managed_real" ] && continue

            if [ -z "${edited_files[$file]+x}" ]; then
                backup_file "$file"
                apache_rewrite_port80_listens_in_file "$file"
                edited_files[$file]=1
                log "Disabled prior TCP/80 Listen directives in $file"
            fi
        done

        backup_file "$listen_conf"
        printf '%s\n' '# Managed by cyberforce-speedrun.' 'Listen 80' > "$listen_conf"
        chmod 0644 "$listen_conf"
        chown root:root "$listen_conf" 2>/dev/null || true

        if [ -e "$listen_link" ] || [ -L "$listen_link" ]; then
            backup_file "$listen_link"
            rm -f "$listen_link"
        fi
        ln -s ../conf-available/00-cyberforce-listen.conf "$listen_link"
    fi

    mapfile -t final_records < <(apache_port80_listen_records)
    if [ "${#final_records[@]}" -ne 1 ]; then
        printf '%s\n' "${final_records[@]}" >&2
        warn "Expected exactly one active Apache TCP/80 Listen directive after normalization; found ${#final_records[@]}."
        return 1
    fi

    IFS=$'\t' read -r _ _ final_arg _ <<< "${final_records[0]}"
    case "$final_arg" in
        80|0.0.0.0:80) return 0 ;;
        *)
            warn "Apache TCP/80 remains address-specific ($final_arg)."
            return 1
            ;;
    esac
}
