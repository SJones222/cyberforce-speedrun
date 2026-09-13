#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/lib/common.sh"

TOTAL=0

run_case() {
    local name="$1" content="$2" expect_original="$3"
    local d arg
    local -a records records_again

    d="$(mktemp -d)"
    mkdir -p "$d"/{conf-available,conf-enabled,sites-enabled,mods-enabled,backups}
    printf '%b\n' "$content" > "$d/apache2.conf"
    : > "$d/ports.conf"

    APACHE_ETC="$d"
    CYBERFORCE_BACKUP_DIR="$d/backups"
    export APACHE_ETC CYBERFORCE_BACKUP_DIR

    apache_normalize_port80_listeners >/dev/null 2>&1
    mapfile -t records < <(apache_port80_listen_records)
    [ "${#records[@]}" -eq 1 ] || { echo "FAIL $name: expected 1 listener, got ${#records[@]}" >&2; exit 1; }
    IFS=$'\t' read -r _ _ arg _ <<< "${records[0]}"
    case "$arg" in
        80|0.0.0.0:80) ;;
        *) echo "FAIL $name: unsafe final listener $arg" >&2; exit 1 ;;
    esac

    if [ "$expect_original" = disabled ]; then
        grep -q '^# cyberforce-disabled-port80-listen:' "$d/apache2.conf" || {
            echo "FAIL $name: original port-80 Listen was not disabled" >&2
            exit 1
        }
    fi

    # Idempotency: a second pass must leave one and only one safe listener.
    apache_normalize_port80_listeners >/dev/null 2>&1
    mapfile -t records_again < <(apache_port80_listen_records)
    [ "${#records_again[@]}" -eq 1 ] || { echo "FAIL $name: second run changed listener count" >&2; exit 1; }

    rm -rf "$d"
    TOTAL=$((TOTAL + 1))
    printf '[PASS] HTTP listener regression: %s\n' "$name"
}

run_case loopback-only 'Listen 127.0.0.1:80' disabled
run_case already-good 'Listen 80' preserved
run_case ipv4-wildcard 'Listen 0.0.0.0:80' preserved
run_case ipv6-only 'Listen [::]:80' disabled
run_case overlapping $'Listen 127.0.0.1:80\nListen 80' disabled
run_case missing '# no TCP/80 listener' preserved

printf '[PASS] %d HTTP listener regression cases\n' "$TOTAL"
