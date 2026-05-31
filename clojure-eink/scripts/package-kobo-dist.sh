#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
DIST="$ROOT/target/dist"
DIST_TEMPLATE="$ROOT/resources/kobo-dist"
JAR_NAME="clojure-eink-demo.jar"

cd "$ROOT"

copy_nix_runtime_libs() {
  local output=$1

  if ! command -v nix-store >/dev/null 2>&1; then
    echo "Warning: nix-store not found; cannot copy runtime closure for $output" >&2
    return 0
  fi

  if [[ ! -e "$output" ]]; then
    return 0
  fi

  while IFS= read -r store_path; do
    case "$store_path" in
      *-glibc-*)
        continue
        ;;
    esac

    while IFS= read -r lib_path; do
      rm -f "$DIST/lib/$(basename -- "$lib_path")"
      cp -L "$lib_path" "$DIST/lib/"
    done < <(find "$store_path" \( -type f -o -type l \) -name 'lib*.so*' -print 2>/dev/null)
  done < <(nix-store -qR "$output")
}

chmod -R u+w "$DIST" 2>/dev/null || true
rm -rf "$DIST"
rm -rf "$ROOT/target/classes"
clojure -T:build jar

mkdir -p "$DIST"
cp -R "$DIST_TEMPLATE"/. "$DIST/"
mkdir -p "$DIST/lib" "$DIST/lib/java" "$DIST/src"

jar_path=$(find "$ROOT/target" -maxdepth 1 -type f -name '*.jar' -print | sort | head -n 1)
if [[ -z "${jar_path:-}" ]]; then
  echo "No jar found under target/." >&2
  exit 1
fi
cp "$jar_path" "$DIST/$JAR_NAME"

if [[ -d "$ROOT/result-kobo-native/lib" ]]; then
  cp -P "$ROOT"/result-kobo-native/lib/libclojure_eink.so "$DIST/lib/"
  cp -L "$ROOT"/result-kobo-native/lib/libfbink.so* "$DIST/lib/"
  copy_nix_runtime_libs "$ROOT/result-kobo-native"
else
  cat >&2 <<'EOF'
Missing result-kobo-native/lib/libclojure_eink.so.
Build or link the Kobo native package first, for example:

  nix build .#clojure-eink-fbink-bridge-kobo -o result-kobo-native

Then rerun this script.
EOF
  exit 1
fi

if [[ -d "$ROOT/result-kobo-skia-native/lib" ]]; then
  cp -P "$ROOT"/result-kobo-skia-native/lib/libclojure_eink_skia.so "$DIST/lib/"
  cp -P "$ROOT"/result-kobo-skia-native/lib/libsk*.so* "$DIST/lib/"
  copy_nix_runtime_libs "$ROOT/result-kobo-skia-native"
else
  cat >&2 <<'EOF'
Missing result-kobo-skia-native/lib/libclojure_eink_skia.so.
Build or link the Kobo Skia native package first, for example:

  nix build .#clojure-eink-skia-bridge-kobo -o result-kobo-skia-native

Then rerun this script.
EOF
  exit 1
fi

rm -rf "$DIST/src"
mkdir -p "$DIST/src"
cp -R "$ROOT/src/clj" "$DIST/src/"

rm -rf "$DIST/lib/java"
mkdir -p "$DIST/lib/java"
while IFS= read -r cp_entry; do
  if [[ "$cp_entry" == *.jar ]]; then
    case "$cp_entry" in
      */org/clojure/clojure/*|*/org/clojure/spec.alpha/*|*/org/clojure/core.specs.alpha/*)
        continue
        ;;
    esac
    cp -P "$cp_entry" "$DIST/lib/java/"
  fi
done < <(clojure -Spath | tr ':' '\n')


rm -rf "$DIST/fonts"
mkdir -p "$DIST/fonts"
cp -P "$ROOT"/resources/fonts/* "$DIST/fonts/"
chmod +x "$DIST"/run-*.sh

(
  cd "$DIST"
  find . -type f ! -name SHA256SUMS -print | sort | xargs sha256sum > SHA256SUMS
)

printf 'Packaged Kobo dist in %s\n' "$DIST"
