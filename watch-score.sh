#!/usr/bin/env bash
set -u
ROOT="$(cd "$(dirname "$0")" && pwd)"
MODE="${1:-local}"
INTERVAL="${INTERVAL:-60}"

case "$INTERVAL" in
    ''|*[!0-9]*) echo 'INTERVAL must be an integer number of seconds.' >&2; exit 2 ;;
esac

while true; do
    clear 2>/dev/null || true
    date
    if [ "$MODE" = local ]; then
        if [ "$(id -u)" -ne 0 ]; then
            echo 'Local verification requires root: sudo ./watch-score.sh local' >&2
            exit 1
        fi
        "$ROOT/verify-local.sh" || true
    elif [ "$MODE" = remote ]; then
        TARGET="${2:-}"
        KEY="${3:-}"
        [ -n "$TARGET" ] || { echo "Usage: $0 remote TARGET_IP [KEY]" >&2; exit 2; }
        "$ROOT/verify-remote.sh" "$TARGET" "$KEY" || true
    else
        echo "Usage: $0 {local|remote [TARGET_IP] [KEY]}" >&2
        exit 2
    fi
    sleep "$INTERVAL"
done
