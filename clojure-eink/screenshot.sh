#!/usr/bin/env bash
set -euo pipefail

KOBO=${KOBO:-kobo-lan}
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
OUT_DIR="$SCRIPT_DIR/screenshots"
OUT="$OUT_DIR/kobo-screen-$(date +%Y%m%d-%H%M%S).png"

mkdir -p "$OUT_DIR"

ssh "$KOBO" 'fbgrab - 2>/dev/null' > "$OUT"

file "$OUT"
printf 'Saved screenshot: %s\n' "$OUT"
