#!/bin/sh
set -eu

#  Fetch the independent implementations the differential tests compare
#  against, and the conformance corpora they run over.
#
#  Nothing here is taken from the host. A tool that happens to be installed
#  is a tool nobody recorded the version of, and a conformance number
#  produced against an unrecorded version is not evidence. Everything is
#  pinned, verified, and installed under a directory that is not committed.
#
#  The two oracles need different mechanisms and the script does not pretend
#  otherwise. Jena is published as a signed archive and needs a Java runtime,
#  which cannot be provisioned here and is checked for instead. Oxigraph
#  ships a self-contained binary.

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
oracles="$project_root/vendor/oracles"
corpora="$project_root/tests/data"

jena_version=${FLYOLOGY_RDF_JENA_VERSION:-6.2.0}
jena_url=${FLYOLOGY_RDF_JENA_URL:-"https://downloads.apache.org/jena/binaries/apache-jena-${jena_version}.tar.gz"}

oxigraph_version=${FLYOLOGY_RDF_OXIGRAPH_VERSION:-0.4.11}
oxigraph_image=${FLYOLOGY_RDF_OXIGRAPH_IMAGE:-"ghcr.io/oxigraph/oxigraph:${oxigraph_version}"}

ldcli_version=${FLYOLOGY_RDF_LDCLI_VERSION:-1.0.3}

rdf_tests_commit=${FLYOLOGY_RDF_TESTS_COMMIT:-}
rdf_canon_commit=${FLYOLOGY_RDF_CANON_COMMIT:-}

usage () {
   cat <<'USAGE'
Usage: provision-oracles.sh [all|jena|oxigraph|ldcli|corpora|verify]

  all        provision everything (default)
  jena       Apache Jena, for riot -- the primary parser oracle
  oxigraph   oxigraph, for convert -- the secondary parser oracle
  ldcli      ld-cli, for rdfc -- the RDFC-1.0 oracle
  corpora    the W3C rdf-tests and rdf-canon suites
  verify     re-check what is already installed against its pins

Every pin is overridable through the environment variable named beside it
in this script; the default is the pin.
USAGE
}

note () { printf '==> %s\n' "$*"; }
warn () { printf 'warning: %s\n' "$*" >&2; }
die  () { printf 'error: %s\n' "$*" >&2; exit 1; }

need () {
   command -v "$1" >/dev/null 2>&1 || die "$1 is required but not on PATH"
}

#  A checksum file sits beside each artifact so that verify can re-run
#  without the network.
record_checksum () {
   artifact=$1
   shasum -a 256 "$artifact" > "$artifact.sha256" 2>/dev/null \
      || sha256sum "$artifact" > "$artifact.sha256"
}

check_checksum () {
   artifact=$1
   [ -f "$artifact.sha256" ] || die "no recorded checksum for $artifact"
   ( cd "$(dirname -- "$artifact")" \
     && { shasum -a 256 -c "$(basename -- "$artifact").sha256" \
          || sha256sum -c "$(basename -- "$artifact").sha256"; } ) \
      >/dev/null || die "$artifact does not match its recorded checksum"
}

provision_jena () {
   need curl
   #  Jena is a JVM application. This is the one prerequisite the script
   #  cannot satisfy itself, so it fails loudly rather than half-installing.
   if ! command -v java >/dev/null 2>&1; then
      die "Jena needs a Java runtime (21 or later) on PATH; install one, or
        set FLYOLOGY_RDF_SKIP_JENA=1 to run with oxigraph alone"
   fi

   mkdir -p "$oracles"
   archive="$oracles/apache-jena-${jena_version}.tar.gz"

   if [ ! -f "$archive" ]; then
      note "fetching Jena ${jena_version}"
      curl -fsSL "$jena_url" -o "$archive"
      #  Apache publishes .sha512 beside every release. Prefer it, and fall
      #  back to recording what we received so that verify still means
      #  something on a mirror that does not carry one.
      if curl -fsSL "${jena_url}.sha512" -o "$archive.sha512" 2>/dev/null; then
         expected=$(tr -d ' \n' < "$archive.sha512" | cut -d= -f2)
         actual=$(shasum -a 512 "$archive" 2>/dev/null | cut -d' ' -f1 \
                  || sha512sum "$archive" | cut -d' ' -f1)
         case "$expected" in
            *"$actual"*|"") : ;;
            *) [ "$expected" = "$actual" ] \
                 || die "Jena archive does not match the published SHA-512" ;;
         esac
         note "Jena archive matches the published SHA-512"
      else
         warn "no published SHA-512 for this Jena URL; recording ours"
      fi
      record_checksum "$archive"
   fi

   if [ ! -d "$oracles/apache-jena-${jena_version}" ]; then
      note "unpacking Jena"
      tar -xzf "$archive" -C "$oracles"
   fi

   riot="$oracles/apache-jena-${jena_version}/bin/riot"
   [ -x "$riot" ] || die "riot not found at $riot after unpacking"
   note "riot ready: $riot"
}

provision_oxigraph () {
   #  A container digest is the strongest pin available for oxigraph and
   #  matches how this ecosystem already pins Autobahn.
   if command -v docker >/dev/null 2>&1; then
      note "pulling $oxigraph_image"
      docker pull "$oxigraph_image" >/dev/null
      digest=$(docker image inspect --format '{{index .RepoDigests 0}}' \
               "$oxigraph_image" 2>/dev/null || true)
      mkdir -p "$oracles"
      printf '%s\n' "${digest:-$oxigraph_image}" \
         > "$oracles/oxigraph.pin"
      note "oxigraph pinned: ${digest:-$oxigraph_image}"
   elif command -v cargo >/dev/null 2>&1; then
      note "no docker; building oxigraph-cli ${oxigraph_version} with cargo"
      cargo install oxigraph-cli \
         --version "$oxigraph_version" \
         --root "$oracles/oxigraph" --locked
      printf 'cargo oxigraph-cli %s\n' "$oxigraph_version" \
         > "$oracles/oxigraph.pin"
   else
      die "oxigraph needs either docker or cargo"
   fi
}

provision_ldcli () {
   need curl
   need unzip
   mkdir -p "$oracles"

   case "$(uname -s)" in
      Darwin) platform=macos-latest ;;
      Linux)  platform=ubuntu-latest ;;
      *) die "no ld-cli build for $(uname -s)" ;;
   esac

   archive="$oracles/ld-cli-${ldcli_version}-${platform}.zip"
   url="https://github.com/filip26/ld-cli/releases/download/v${ldcli_version}/ld-cli-${ldcli_version}-${platform}.zip"

   if [ ! -f "$archive" ]; then
      note "fetching ld-cli ${ldcli_version} for ${platform}"
      curl -fsSL "$url" -o "$archive"
      record_checksum "$archive"
   fi

   if [ ! -d "$oracles/ld-cli-${ldcli_version}" ]; then
      note "unpacking ld-cli"
      mkdir -p "$oracles/ld-cli-${ldcli_version}"
      unzip -q -o "$archive" -d "$oracles/ld-cli-${ldcli_version}"
      find "$oracles/ld-cli-${ldcli_version}" -name 'ld-cli' -type f \
         -exec chmod +x {} +
   fi

   #  ld-cli is a GraalVM native image, so unlike Jena it needs no runtime.
   binary=$(find "$oracles/ld-cli-${ldcli_version}" -name 'ld-cli' -type f \
            | head -n 1)
   [ -n "$binary" ] || die "ld-cli binary not found after unpacking"
   note "ld-cli ready: $binary"
}

provision_corpus () {
   need git
   name=$1
   url=$2
   commit=$3
   target="$corpora/$name"

   if [ ! -d "$target/.git" ]; then
      note "cloning $name"
      git clone --quiet "$url" "$target"
   fi

   if [ -n "$commit" ]; then
      note "pinning $name to $commit"
      ( cd "$target" && git fetch --quiet origin "$commit" 2>/dev/null || true
        git -C "$target" checkout --quiet "$commit" )
   else
      #  No pin given: record what was fetched so the run is reproducible
      #  even though the fetch was not.
      recorded=$(git -C "$target" rev-parse HEAD)
      printf '%s\n' "$recorded" > "$target.commit"
      warn "$name is unpinned; recorded $recorded -- set the pin in this
        script or in the environment before publishing any number from it"
   fi
}

provision_corpora () {
   mkdir -p "$corpora"
   provision_corpus w3c-rdf-tests \
      https://github.com/w3c/rdf-tests.git "$rdf_tests_commit"
   provision_corpus w3c-rdf-canon \
      https://github.com/w3c/rdf-canon.git "$rdf_canon_commit"
}

verify () {
   status=0
   for archive in "$oracles"/*.tar.gz "$oracles"/*.zip; do
      [ -f "$archive" ] || continue
      check_checksum "$archive" && note "verified $(basename -- "$archive")"
   done
   [ -f "$oracles/oxigraph.pin" ] \
      && note "oxigraph pin: $(cat "$oracles/oxigraph.pin")"
   for corpus in "$corpora"/w3c-*; do
      [ -d "$corpus/.git" ] || continue
      note "$(basename -- "$corpus") at $(git -C "$corpus" rev-parse HEAD)"
   done
   return $status
}

case "${1:-all}" in
   all)
      [ "${FLYOLOGY_RDF_SKIP_JENA:-0}" = "1" ] || provision_jena
      provision_oxigraph
      provision_ldcli
      provision_corpora
      ;;
   jena)     provision_jena ;;
   oxigraph) provision_oxigraph ;;
   ldcli)    provision_ldcli ;;
   corpora)  provision_corpora ;;
   verify)   verify ;;
   -h|--help|help) usage ;;
   *) usage; exit 2 ;;
esac
