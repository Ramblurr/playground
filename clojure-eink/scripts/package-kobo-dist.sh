#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
DIST="$ROOT/target/dist"
JAR_NAME="clojure-eink-demo.jar"

cd "$ROOT"

rm -rf "$ROOT/target/classes"
clojure -T:build jar

mkdir -p "$DIST/lib" "$DIST/lib/java" "$DIST/src"
chmod -R u+w "$DIST" 2>/dev/null || true

jar_path=$(find "$ROOT/target" -maxdepth 1 -type f -name '*.jar' -print | sort | head -n 1)
if [[ -z "${jar_path:-}" ]]; then
  echo "No jar found under target/." >&2
  exit 1
fi
cp "$jar_path" "$DIST/$JAR_NAME"

if [[ -d "$ROOT/result-kobo-native/lib" ]]; then
  cp -P "$ROOT"/result-kobo-native/lib/libclojure_eink.so "$DIST/lib/"
  cp -P "$ROOT"/result-kobo-native/lib/libfbink.so* "$DIST/lib/"
elif [[ ! -f "$DIST/lib/libclojure_eink.so" ]]; then
  cat >&2 <<'EOF'
Missing target/dist/lib/libclojure_eink.so.
Build or link the Kobo native package first, for example:

  nix build .#clojure-eink-fbink-bridge-kobo -o result-kobo-native

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

cat > "$DIST/run-demo.sh" <<'EOF'
#!/bin/sh
set -eu

APP_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
KOBO_JDK_HOME=${KOBO_JDK_HOME:-/nix/kobo-jdk25-clojure-fast-uberwarm-ffm-java2d}
JAVA_BIN=${KOBO_JAVA:-$KOBO_JDK_HOME/jdk/bin/java}
CLOJURE_JAR=${KOBO_CLOJURE_JAR:-$KOBO_JDK_HOME/lib/clojure-uber-1.12.4.jar}

if [ ! -x "$JAVA_BIN" ]; then
  echo "Cannot find executable java at: $JAVA_BIN" >&2
  echo "Set KOBO_JAVA=/path/to/java or KOBO_JDK_HOME=/path/to/kobo-jdk-image." >&2
  exit 127
fi
if [ ! -f "$CLOJURE_JAR" ]; then
  echo "Cannot find Clojure jar at: $CLOJURE_JAR" >&2
  echo "Set KOBO_CLOJURE_JAR=/path/to/clojure-uber.jar or KOBO_JDK_HOME=/path/to/kobo-jdk-image." >&2
  exit 127
fi

export EINK_NATIVE_LIB="$APP_DIR/lib/libclojure_eink.so"
export LD_LIBRARY_PATH="$APP_DIR/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# JAVA_OPTS is intentionally shell-split for simple flags like -Xmx128m.
# shellcheck disable=SC2086
exec "$JAVA_BIN" \
  --enable-native-access=ALL-UNNAMED \
  -Djava.awt.headless=true \
  ${JAVA_OPTS:-} \
  -cp "$APP_DIR/src/clj:$APP_DIR/lib/java/*:$CLOJURE_JAR:$APP_DIR/clojure-eink-demo.jar" \
  clojure.main -m ol.project --present "$@"
EOF

cat > "$DIST/run-loop.sh" <<'EOF'
#!/bin/sh
set -eu

APP_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
KOBO_JDK_HOME=${KOBO_JDK_HOME:-/nix/kobo-jdk25-clojure-fast-uberwarm-ffm-java2d}
JAVA_BIN=${KOBO_JAVA:-$KOBO_JDK_HOME/jdk/bin/java}
CLOJURE_JAR=${KOBO_CLOJURE_JAR:-$KOBO_JDK_HOME/lib/clojure-uber-1.12.4.jar}

if [ ! -x "$JAVA_BIN" ]; then
  echo "Cannot find executable java at: $JAVA_BIN" >&2
  echo "Set KOBO_JAVA=/path/to/java or KOBO_JDK_HOME=/path/to/kobo-jdk-image." >&2
  exit 127
fi
if [ ! -f "$CLOJURE_JAR" ]; then
  echo "Cannot find Clojure jar at: $CLOJURE_JAR" >&2
  echo "Set KOBO_CLOJURE_JAR=/path/to/clojure-uber.jar or KOBO_JDK_HOME=/path/to/kobo-jdk-image." >&2
  exit 127
fi

export EINK_NATIVE_LIB="$APP_DIR/lib/libclojure_eink.so"
export EINK_RELOAD_FILE="${EINK_RELOAD_FILE:-$APP_DIR/src/clj/ol/project.clj}"
export LD_LIBRARY_PATH="$APP_DIR/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# JAVA_OPTS is intentionally shell-split for simple flags like -Xmx128m.
# shellcheck disable=SC2086
exec "$JAVA_BIN" \
  --enable-native-access=ALL-UNNAMED \
  -Djava.awt.headless=true \
  ${JAVA_OPTS:-} \
  -cp "$APP_DIR/src/clj:$APP_DIR/lib/java/*:$CLOJURE_JAR:$APP_DIR/clojure-eink-demo.jar" \
  clojure.main -m ol.loop --present "$@"
EOF

cat > "$DIST/run-png-smoke.sh" <<'EOF'
#!/bin/sh
set -eu

APP_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
KOBO_JDK_HOME=${KOBO_JDK_HOME:-/nix/kobo-jdk25-clojure-fast-uberwarm-ffm-java2d}
JAVA_BIN=${KOBO_JAVA:-$KOBO_JDK_HOME/jdk/bin/java}
CLOJURE_JAR=${KOBO_CLOJURE_JAR:-$KOBO_JDK_HOME/lib/clojure-uber-1.12.4.jar}
OUT=${1:-"$APP_DIR/eink-demo.png"}

# JAVA_OPTS is intentionally shell-split for simple flags like -Xmx128m.
# shellcheck disable=SC2086
exec "$JAVA_BIN" \
  -Djava.awt.headless=true \
  ${JAVA_OPTS:-} \
  -cp "$APP_DIR/src/clj:$APP_DIR/lib/java/*:$CLOJURE_JAR:$APP_DIR/clojure-eink-demo.jar" \
  clojure.main -m ol.project --png "$OUT"
EOF

cat > "$DIST/run-membrane-demo.sh" <<'EOF'
#!/bin/sh
set -eu

APP_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
KOBO_JDK_HOME=${KOBO_JDK_HOME:-/nix/kobo-jdk25-clojure-fast-uberwarm-ffm-java2d}
JAVA_BIN=${KOBO_JAVA:-$KOBO_JDK_HOME/jdk/bin/java}
CLOJURE_JAR=${KOBO_CLOJURE_JAR:-$KOBO_JDK_HOME/lib/clojure-uber-1.12.4.jar}

if [ ! -x "$JAVA_BIN" ]; then
  echo "Cannot find executable java at: $JAVA_BIN" >&2
  echo "Set KOBO_JAVA=/path/to/java or KOBO_JDK_HOME=/path/to/kobo-jdk-image." >&2
  exit 127
fi
if [ ! -f "$CLOJURE_JAR" ]; then
  echo "Cannot find Clojure jar at: $CLOJURE_JAR" >&2
  echo "Set KOBO_CLOJURE_JAR=/path/to/clojure-uber.jar or KOBO_JDK_HOME=/path/to/kobo-jdk-image." >&2
  exit 127
fi

export EINK_NATIVE_LIB="$APP_DIR/lib/libclojure_eink.so"
export LD_LIBRARY_PATH="$APP_DIR/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# JAVA_OPTS is intentionally shell-split for simple flags like -Xmx128m.
# shellcheck disable=SC2086
exec "$JAVA_BIN" \
  --enable-native-access=ALL-UNNAMED \
  -Djava.awt.headless=true \
  ${JAVA_OPTS:-} \
  -cp "$APP_DIR/src/clj:$APP_DIR/lib/java/*:$CLOJURE_JAR:$APP_DIR/clojure-eink-demo.jar" \
  clojure.main -m ol.membrane-demo --present "$@"
EOF

cat > "$DIST/run-membrane-loop.sh" <<'EOF'
#!/bin/sh
set -eu

APP_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
KOBO_JDK_HOME=${KOBO_JDK_HOME:-/nix/kobo-jdk25-clojure-fast-uberwarm-ffm-java2d}
JAVA_BIN=${KOBO_JAVA:-$KOBO_JDK_HOME/jdk/bin/java}
CLOJURE_JAR=${KOBO_CLOJURE_JAR:-$KOBO_JDK_HOME/lib/clojure-uber-1.12.4.jar}

if [ ! -x "$JAVA_BIN" ]; then
  echo "Cannot find executable java at: $JAVA_BIN" >&2
  echo "Set KOBO_JAVA=/path/to/java or KOBO_JDK_HOME=/path/to/kobo-jdk-image." >&2
  exit 127
fi
if [ ! -f "$CLOJURE_JAR" ]; then
  echo "Cannot find Clojure jar at: $CLOJURE_JAR" >&2
  echo "Set KOBO_CLOJURE_JAR=/path/to/clojure-uber.jar or KOBO_JDK_HOME=/path/to/kobo-jdk-image." >&2
  exit 127
fi

export EINK_NATIVE_LIB="$APP_DIR/lib/libclojure_eink.so"
export LD_LIBRARY_PATH="$APP_DIR/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# JAVA_OPTS is intentionally shell-split for simple flags like -Xmx128m.
# shellcheck disable=SC2086
exec "$JAVA_BIN" \
  --enable-native-access=ALL-UNNAMED \
  -Djava.awt.headless=true \
  ${JAVA_OPTS:-} \
  -cp "$APP_DIR/src/clj:$APP_DIR/lib/java/*:$CLOJURE_JAR:$APP_DIR/clojure-eink-demo.jar" \
  clojure.main -m ol.membrane-demo --loop --present "$@"
EOF

cat > "$DIST/README-KOBO.txt" <<'EOF'
Clojure e-ink PoC Kobo dist
===========================

Copy this directory to the Kobo onboard partition, for example:

  rsync -rtv --delete --no-owner --no-group --no-perms target/dist/ root@kobo-lan:/mnt/onboard/clojure-eink-demo/

On the Kobo:

  cd /mnt/onboard/clojure-eink-demo
  time ./run-demo.sh --renders 5 --present-last --render-mode cached-layout

Long-lived reload loop:

  ./run-loop.sh --render-mode cached-layout --reuse-image --no-wait --no-flash

Membrane FBInk render proof:

  ./run-membrane-demo.sh --no-wait --no-flash

Long-lived Membrane loop with gray8 damage tracking:

  ./run-membrane-loop.sh --no-wait --no-flash

Loop commands:

  render --renders 1 --no-present
  reload
  render --renders 1 --present-last
  quit

The demo prints elapsed timings from inside Clojure. Compare those with shell
`time` to estimate JVM/Clojure startup overhead before ol.project/-main.
EOF

chmod +x "$DIST"/run-demo.sh "$DIST"/run-loop.sh "$DIST"/run-png-smoke.sh "$DIST"/run-membrane-demo.sh "$DIST"/run-membrane-loop.sh

(
  cd "$DIST"
  find . -type f ! -name SHA256SUMS -print | sort | xargs sha256sum > SHA256SUMS
)

printf 'Packaged Kobo dist in %s\n' "$DIST"
