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

#  Measure the library a consumer gets. Without this the library builds in
#  its default checked mode, at -O1 and with assertions on, and every
#  number below would be timing the term invariants rather than the work.
FLYOLOGY_RDF_BUILD_MODE=release
export FLYOLOGY_RDF_BUILD_MODE

mkdir -p "$results"
cd "$project_root/benchmarks"
"$alr" -n build

#  Through a pipe the shell reports tee's status, not the benchmark's, so
#  a failed scaling check would leave the script reporting success. Write
#  the file first, then show it.
status=0
"$project_root/benchmarks/bin/benchmarks" "$rounds" \
   > "$results/$label.txt" 2>&1 || status=$?
cat "$results/$label.txt"

if [ -f "$results/baseline.txt" ] && [ "$label" != "baseline" ]; then
   printf '\n== against baseline ==\n'
   diff -u "$results/baseline.txt" "$results/$label.txt" || true
fi

exit "$status"
