#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
alr=$("$project_root/scripts/find-alr.sh")

cd "$project_root/tests"
"$alr" -n build

status=0
for program in "$project_root"/tests/bin/*; do
   [ -x "$program" ] || continue
   printf '\n== %s ==\n' "$(basename "$program")"
   if ! "$program"; then
      status=1
   fi
done

exit "$status"
