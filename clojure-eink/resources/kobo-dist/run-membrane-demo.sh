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
