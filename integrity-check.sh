#!/usr/bin/env bash
set -u
BASE="${1:-/root/cyberforce-integrity.sha256}"
[ -r "$BASE" ] || { echo "Baseline not readable: $BASE" >&2; exit 2; }
sha256sum -c "$BASE"
