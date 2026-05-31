#!/bin/sh
set -eu
bin_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
home=$(CDPATH= cd -- "$bin_dir/.." && pwd)
cp="clojure-uber-1.12.4.jar"
if [ "${CLASSPATH:-}" ]; then
  cp="$cp:$CLASSPATH"
fi
base_opts="-XX:TieredStopAtLevel=1 -Djava.awt.headless=true"
if [ -z "${CLOJURE_NO_CDS:-}" ] && [ -f "$home/jdk/lib/server/classes.jsa" ] && [ -f "$home/lib/clojure-dynamic.jsa" ]; then
  base_opts="$base_opts -XX:SharedArchiveFile=$home/jdk/lib/server/classes.jsa:$home/lib/clojure-dynamic.jsa"
fi
cd "$home/lib"
# JAVA_OPTS is intentionally split by the shell for simple flags like: JAVA_OPTS='-Xmx64m'
# shellcheck disable=SC2086
exec "$home/jdk/bin/java" $base_opts ${JAVA_OPTS:-} -cp "$cp" clojure.main "$@"
