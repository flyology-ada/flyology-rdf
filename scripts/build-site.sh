#!/bin/sh
set -eu

#  Assemble the published site: the authored pages, the shared browser
#  assets, and the generated API reference. The checks at the end are the
#  point -- a page that stopped being reachable is a page nobody reads.

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SITE="$ROOT/build/site"
KIT="$ROOT/vendor/website-kit"

test -f "$KIT/scripts/install-assets.mjs" || {
  echo "website-kit submodule is missing; run git submodule update --init" >&2
  exit 1
}

rm -rf "$SITE"
mkdir -p "$ROOT/build"
cp -R "$ROOT/website" "$SITE"
mkdir -p "$SITE/api"
node "$KIT/scripts/install-assets.mjs" "$SITE"
"$ROOT/scripts/docs.sh"
cp -R "$ROOT/docs/api/." "$SITE/api/"
touch "$SITE/.nojekyll"
node "$KIT/scripts/check-site.mjs" "$SITE"

test -f "$SITE/index.html"
test "$(cat "$SITE/CNAME")" = "rdf.flyology.org"
test -f "$SITE/llms.txt"
test -f "$SITE/guide/index.html"
test -f "$SITE/api/index.html"
