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
