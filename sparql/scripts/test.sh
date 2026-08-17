#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_root/tests"
alr -n build
status=0
for program in "$project_root"/tests/bin/*; do
   [ -x "$program" ] || continue
   printf '\n== %s ==\n' "$(basename -- "$program")"
   "$program" || status=1
done
exit "$status"
