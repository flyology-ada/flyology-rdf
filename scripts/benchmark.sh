#!/bin/sh
set -eu

#  Run the benchmarks and keep the result, so that a change can be measured
#  against what came before it rather than described.
#
#  Numbers from a loaded machine are not comparable with numbers from an
#  idle one. Nothing here can detect that, so it is said instead: run this
#  with nothing else running, or do not compare the result.

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
alr=$("$project_root/scripts/find-alr.sh")
results="$project_root/benchmark-results"

rounds=${1:-7}
label=${2:-latest}

mkdir -p "$results"
cd "$project_root/benchmarks"
"$alr" -n build

"$project_root/benchmarks/bin/benchmarks" "$rounds" \
   | tee "$results/$label.txt"

if [ -f "$results/baseline.txt" ] && [ "$label" != "baseline" ]; then
   printf '\n== against baseline ==\n'
   diff -u "$results/baseline.txt" "$results/$label.txt" || true
fi
