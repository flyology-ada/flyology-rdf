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
#  so the runtime is provisioned too -- a JRE that happens to be installed is
#  a version nobody recorded, which is the thing this script exists to avoid.
#  Oxigraph is built from source, because the differential test spawns it
#  once per document and a container start per document is the difference
#  between a minute and an hour.

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
oracles="$project_root/vendor/oracles"
corpora="$project_root/tests/data"

jena_version=${FLYOLOGY_RDF_JENA_VERSION:-6.2.0}

#  downloads.apache.org carries only current releases, so a pin that is
#  still good today stops resolving the day the next one ships. The archive
#  keeps every release, and is the fallback rather than the primary because
#  the mirror is the faster of the two while it has the file.
jena_mirror=${FLYOLOGY_RDF_JENA_MIRROR:-"https://downloads.apache.org/jena/binaries"}
jena_archive_base=${FLYOLOGY_RDF_JENA_ARCHIVE:-"https://archive.apache.org/dist/jena/binaries"}

#  Temurin, for Jena. Pinned like everything else.
java_major=${FLYOLOGY_RDF_JAVA_MAJOR:-21}
java_version=${FLYOLOGY_RDF_JAVA_VERSION:-21.0.9_10}
java_release=${FLYOLOGY_RDF_JAVA_RELEASE:-jdk-21.0.9%2B10}

oxigraph_version=${FLYOLOGY_RDF_OXIGRAPH_VERSION:-0.4.11}

#  w3c/rdf-tests carries the RDF syntax suites and the SPARQL suites
#  together, so one checkout serves both harnesses.
rdf_tests_commit=${FLYOLOGY_RDF_TESTS_COMMIT:-12774b0ebb385d17651b396654b19254d0fefbfa}
rdf_canon_commit=${FLYOLOGY_RDF_CANON_COMMIT:-15619df2fda7a4ca88308733789b6774517f9638}
n3_tests_commit=${FLYOLOGY_N3_TESTS_COMMIT:-b975fc59ab5d2ad2d28e7206f1c34c716977d2ad}

usage () {
   cat <<'USAGE'
Usage: provision-oracles.sh [all|java|jena|oxigraph|corpora|verify]

  all        provision everything (default)
  java       a Temurin JRE, which Jena needs
  jena       Apache Jena, for riot -- the second parser oracle
  oxigraph   oxigraph, for convert -- the first parser oracle
  corpora    the W3C rdf-tests (RDF and SPARQL), rdf-canon, and N3 suites
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

#  Fetch from the mirror, falling back to the archive.
fetch () {
   url=$1
   fallback=$2
   target=$3
   curl -fsSL "$url" -o "$target" 2>/dev/null \
      || curl -fsSL "$fallback" -o "$target"
}

host_platform () {
   case "$(uname -s)" in
      Darwin) printf 'mac' ;;
      Linux)  printf 'linux' ;;
      *) die "no Temurin build for $(uname -s)" ;;
   esac
}

host_arch () {
   case "$(uname -m)" in
      arm64|aarch64) printf 'aarch64' ;;
      x86_64|amd64)  printf 'x64' ;;
      *) die "no Temurin build for $(uname -m)" ;;
   esac
}

#  The path to a java we provisioned, if there is one.
provisioned_java () {
   if [ -x "$oracles/java/bin/java" ]; then
      printf '%s' "$oracles/java/bin/java"
   fi
}

provision_java () {
   need curl
   mkdir -p "$oracles"

   if [ -x "$oracles/java/bin/java" ]; then
      note "java ready: $oracles/java/bin/java"
      return
   fi

   platform=$(host_platform)
   arch=$(host_arch)
   archive="$oracles/OpenJDK${java_major}U-jre_${arch}_${platform}_hotspot_${java_version}.tar.gz"
   base="https://github.com/adoptium/temurin${java_major}-binaries/releases/download/${java_release}"
   name=$(basename -- "$archive")

   if [ ! -f "$archive" ]; then
      note "fetching Temurin ${java_version} for ${platform}/${arch}"
      curl -fsSL "$base/$name" -o "$archive"
      #  Adoptium publishes a .sha256.txt beside every asset.
      if curl -fsSL "$base/$name.sha256.txt" -o "$archive.sha256.txt"; then
         expected=$(cut -d' ' -f1 < "$archive.sha256.txt")
         actual=$(shasum -a 256 "$archive" 2>/dev/null | cut -d' ' -f1 \
                  || sha256sum "$archive" | cut -d' ' -f1)
         [ "$expected" = "$actual" ] \
            || die "the Temurin archive does not match its published SHA-256"
         note "Temurin archive matches its published SHA-256"
      else
         die "no published SHA-256 for $name; refusing to install it"
      fi
      record_checksum "$archive"
   fi

   note "unpacking Temurin"
   rm -rf "$oracles/java.unpack"
   mkdir -p "$oracles/java.unpack"
   tar -xzf "$archive" -C "$oracles/java.unpack"

   #  macOS builds bury the runtime under Contents/Home; Linux does not.
   home=$(find "$oracles/java.unpack" -type f -name java -path '*/bin/java' \
          | head -n 1)
   [ -n "$home" ] || die "the Temurin archive held no java"
   home=$(cd "$(dirname -- "$home")/.." && pwd)
   rm -rf "$oracles/java"
   mv "$home" "$oracles/java"
   rm -rf "$oracles/java.unpack"

   [ -x "$oracles/java/bin/java" ] || die "java is not executable after unpacking"
   note "java ready: $oracles/java/bin/java"
}

provision_jena () {
   need curl

   #  Jena is a JVM application, and the JVM is provisioned rather than
   #  found: a runtime that happens to be installed is a version nobody
   #  recorded, which is the thing this script exists to avoid.
   java=$(provisioned_java)
   if [ -z "$java" ]; then
      provision_java
      java=$(provisioned_java)
   fi

   mkdir -p "$oracles"
   archive="$oracles/apache-jena-${jena_version}.tar.gz"
   name="apache-jena-${jena_version}.tar.gz"

   if [ ! -f "$archive" ]; then
      note "fetching Jena ${jena_version}"
      fetch "$jena_mirror/$name" "$jena_archive_base/$name" "$archive"
      #  Apache publishes .sha512 beside every release, on both hosts.
      if fetch "$jena_mirror/$name.sha512" \
               "$jena_archive_base/$name.sha512" "$archive.sha512"
      then
         expected=$(tr -d ' \n' < "$archive.sha512" | tr 'A-Z' 'a-z')
         expected=${expected##*=}
         actual=$(shasum -a 512 "$archive" 2>/dev/null | cut -d' ' -f1 \
                  || sha512sum "$archive" | cut -d' ' -f1)
         case "$expected" in
            *"$actual"*) note "Jena archive matches its published SHA-512" ;;
            *) die "the Jena archive does not match its published SHA-512" ;;
         esac
      else
         die "no published SHA-512 for $name; refusing to install it"
      fi
      record_checksum "$archive"
   fi

   if [ ! -d "$oracles/apache-jena-${jena_version}" ]; then
      note "unpacking Jena"
      tar -xzf "$archive" -C "$oracles"
   fi

   riot="$oracles/apache-jena-${jena_version}/bin/riot"
   [ -x "$riot" ] || die "riot not found at $riot after unpacking"

   #  Fuseki is the same parser behind an HTTP server. riot pays a JVM
   #  start per document; Fuseki pays one for the whole run, which is the
   #  difference between asking it about everything and asking it only
   #  about what the fast oracle could not answer.
   fuseki="apache-jena-fuseki-${jena_version}.tar.gz"
   fuseki_archive="$oracles/$fuseki"
   if [ ! -f "$fuseki_archive" ]; then
      note "fetching Fuseki ${jena_version}"
      fetch "$jena_mirror/$fuseki" "$jena_archive_base/$fuseki" \
            "$fuseki_archive"
      if fetch "$jena_mirror/$fuseki.sha512" \
               "$jena_archive_base/$fuseki.sha512" \
               "$fuseki_archive.sha512"
      then
         expected=$(tr -d ' \n' < "$fuseki_archive.sha512" | tr 'A-Z' 'a-z')
         expected=${expected##*=}
         actual=$(shasum -a 512 "$fuseki_archive" 2>/dev/null | cut -d' ' -f1 \
                  || sha512sum "$fuseki_archive" | cut -d' ' -f1)
         case "$expected" in
            *"$actual"*) note "Fuseki archive matches its published SHA-512" ;;
            *) die "the Fuseki archive does not match its published SHA-512" ;;
         esac
      else
         die "no published SHA-512 for $fuseki; refusing to install it"
      fi
      record_checksum "$fuseki_archive"
   fi

   if [ ! -d "$oracles/apache-jena-fuseki-${jena_version}" ]; then
      note "unpacking Fuseki"
      tar -xzf "$fuseki_archive" -C "$oracles"
   fi
   note "fuseki ready: $oracles/apache-jena-fuseki-${jena_version}"

   #  riot finds its runtime through JAVA_HOME, so record ours beside it
   #  rather than leaving the caller to guess.
   printf 'JAVA_HOME=%s\n' "$oracles/java" > "$oracles/jena.env"
   note "riot ready: $riot"
   note "  with JAVA_HOME=$oracles/java"
}

provision_oxigraph () {
   #  A native binary, not a container: the differential test spawns this
   #  once per document, and a container start per document is the
   #  difference between a minute and an hour.
   need cargo
   if [ -x "$oracles/oxigraph/bin/oxigraph" ]; then
      note "oxigraph ready: $oracles/oxigraph/bin/oxigraph"
      return
   fi
   note "building oxigraph-cli ${oxigraph_version}"
   cargo install oxigraph-cli \
      --version "$oxigraph_version" \
      --root "$oracles/oxigraph" --locked
   printf 'oxigraph-cli %s\n' "$oxigraph_version" > "$oracles/oxigraph.pin"
   note "oxigraph ready: $oracles/oxigraph/bin/oxigraph"
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

   #  Notation3 is specified outside the RDF suites and carries its own.
   provision_corpus w3c-n3 \
      https://github.com/w3c/N3.git "$n3_tests_commit"

   #  The SPARQL harness reads from the rdf-tests checkout rather than a
   #  second clone; a symlink keeps that visible instead of implied.
   if [ -d "$corpora/w3c-rdf-tests/sparql" ] \
      && [ ! -e "$corpora/w3c-sparql-tests" ]; then
      ln -s w3c-rdf-tests/sparql "$corpora/w3c-sparql-tests"
      note "sparql suites linked from the rdf-tests checkout"
   fi

   #  Same for N3, whose suites sit under tests/ in its specification repo.
   if [ -d "$corpora/w3c-n3/tests" ] \
      && [ ! -e "$corpora/w3c-n3-tests" ]; then
      ln -s w3c-n3/tests "$corpora/w3c-n3-tests"
      note "n3 suites linked from the N3 checkout"
   fi
}

verify () {
   status=0
   for archive in "$oracles"/*.tar.gz "$oracles"/*.zip; do
      [ -f "$archive" ] || continue
      check_checksum "$archive" && note "verified $(basename -- "$archive")"
   done
   [ -f "$oracles/oxigraph.pin" ] \
      && note "oxigraph pin: $(cat "$oracles/oxigraph.pin")"
   [ -x "$oracles/java/bin/java" ] \
      && note "java: $("$oracles/java/bin/java" -version 2>&1 | head -n 1)"
   for corpus in "$corpora"/w3c-*; do
      [ -d "$corpus/.git" ] || continue
      note "$(basename -- "$corpus") at $(git -C "$corpus" rev-parse HEAD)"
   done
   return $status
}

case "${1:-all}" in
   all)
      provision_oxigraph
      [ "${FLYOLOGY_RDF_SKIP_JENA:-0}" = "1" ] || provision_jena
      provision_corpora
      ;;
   java)     provision_java ;;
   jena)     provision_jena ;;
   oxigraph) provision_oxigraph ;;
   corpora)  provision_corpora ;;
   verify)   verify ;;
   -h|--help|help) usage ;;
   *) usage; exit 2 ;;
esac
