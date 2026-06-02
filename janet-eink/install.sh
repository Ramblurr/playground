#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
TARGET_HOST=${TARGET_HOST:-root@kobo-lan}
TARGET_DIR=${TARGET_DIR:-/mnt/onboard/janet-eink-demo/janet}
OUT_LINK=$(mktemp -u -t janet-eink-kobo-bundle.XXXXXX)

trap 'rm -f "$OUT_LINK"' EXIT
rm -f "$ROOT/result"

nix build "path:$ROOT#kobo-bundle" -o "$OUT_LINK" -L
ssh "$TARGET_HOST" "mkdir -p '$TARGET_DIR'"
rsync -rtv --delete --no-owner --no-group --no-perms "$OUT_LINK/" "$TARGET_HOST:$TARGET_DIR/"
