#!/bin/sh
set -eu
bin_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
home=$(CDPATH= cd -- "$bin_dir/.." && pwd)
exec "$home/jdk/bin/java" -Djava.awt.headless=true "$@"
