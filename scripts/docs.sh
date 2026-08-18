#!/bin/sh
set -eu

#  Generate the public API reference with GNATdoc, themed by the shared
#  website kit so that every Flyology project's reference reads the same.

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
alr=$("$project_root/scripts/find-alr.sh")
kit="$project_root/vendor/website-kit"

if [ ! -f "$kit/scripts/render-gnatdoc-theme.mjs" ]; then
  printf '%s\n' \
    "website kit is unavailable; run: git submodule update --init" >&2
  exit 1
fi

if ! command -v gnatdoc >/dev/null 2>&1; then
  installed_gnatdoc=${ALIRE_INSTALL_PREFIX:-"$HOME/.alire"}/bin/gnatdoc
  if [ ! -x "$installed_gnatdoc" ]; then
    printf '%s\n' \
      "gnatdoc not found; install it with: $alr install gnatdoc_bin" >&2
    exit 1
  fi
  PATH=$(dirname "$installed_gnatdoc"):$PATH
  export PATH
fi

cd "$project_root"

#  GNATdoc reports an internal error on some declarations and then exits
#  reporting success, having omitted that declaration and everything under
#  it. Nothing downstream notices: the pages build, the link check passes,
#  and a public generic is simply absent from the reference. So collect
#  what it choked on and compare against what is already known, which
#  keeps a known upstream gap from hiding a new one.
gaps=$(mktemp)
trap 'rm -f "$gaps"' EXIT

run_gnatdoc () {
  log=$(mktemp)
  if ! "$alr" exec -- gnatdoc "$@" > "$log" 2>&1; then
    cat "$log" >&2
    rm -f "$log"
    return 1
  fi
  cat "$log"
  sed -n 's/.*raised GNATDOC\.[A-Z_]*.*\["\([^"]*\)"\].*/\1/p' "$log" \
    >> "$gaps"
  rm -f "$log"
}

node "$kit/scripts/render-gnatdoc-theme.mjs" \
  docs/gnatdoc-theme.json docs/gnatdoc/html

"$alr" build --stop-after=generation
run_gnatdoc \
  --backend=html \
  --warnings \
  --style=leading \
  -P flyology_rdf.gpr \
  -O docs/api

#  The generated pages reference these beside themselves, so they are
#  copied in rather than linked out of the site tree: the reference is
#  also published on its own.
cp website/assets/brand/flyology-mark-transparent.svg \
  docs/api/flyology-mark.svg
cp "$kit/assets/scripts/ada-highlight.js" docs/api/ada-highlight.js

node "$kit/scripts/build-api-search-index.mjs" docs/api

#  The Notation3 and SPARQL crates get their own reference. Each pulls in
#  the RDF units it depends on, so the guide keeps flyology_rdf entities
#  pointed at the reference above and sends each crate's own entities to
#  its own page.
for crate in n3 sparql; do
  case "$crate" in
    n3)     project=flyology_n3 ;;
    sparql) project=flyology_sparql ;;
  esac

  node "$kit/scripts/render-gnatdoc-theme.mjs" \
    "$crate/docs/gnatdoc-theme.json" "$crate/docs/gnatdoc/html"

  ( cd "$crate" \
    && "$alr" build --stop-after=generation \
    && run_gnatdoc \
         --backend=html \
         --style=leading \
         -P "$project.gpr" \
         -O docs/api )

  cp website/assets/brand/flyology-mark-transparent.svg \
    "$crate/docs/api/flyology-mark.svg"
  cp "$kit/assets/scripts/ada-highlight.js" \
    "$crate/docs/api/ada-highlight.js"
  node "$kit/scripts/build-api-search-index.mjs" "$crate/docs/api"

  test -f "$crate/docs/api/index.html"
done

test -f docs/api/index.html
test -f docs/api/flyology-mark.svg
test -f docs/api/ada-highlight.js

#  Each crate's reference documents the RDF units it depends on, so one
#  declaration GNATdoc cannot read is reported once per crate.
sort -u "$gaps" > "$gaps.seen"
known="$project_root/docs/gnatdoc-gaps.txt"
if ! diff -u "$known" "$gaps.seen" > "$gaps.diff"; then
  printf '%s\n' \
    "GNATdoc omitted a different set of declarations than recorded." \
    "Anything listed below with a + is absent from the API reference." \
    "" >&2
  cat "$gaps.diff" >&2
  printf '%s\n' \
    "" \
    "If the change is intended, update docs/gnatdoc-gaps.txt." >&2
  exit 1
fi

if [ -s "$known" ]; then
  printf '%s\n' "" "Absent from the API reference, GNATdoc cannot read:"
  sed 's/^/  /' "$known"
fi
