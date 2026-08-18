# flyology_rdf

RDF 1.2 for Ada: terms, streaming Turtle and TriG parsing, N-Triples and
N-Quads, dataset canonicalization, and a compact binary encoding.

The repository holds three crates. They are separate because their models
are, not merely because they are large:

| Crate | What it is |
| --- | --- |
| `flyology_rdf` | The RDF 1.2 model and its serializations |
| `flyology_n3` | Notation3, whose formulas and variables RDF cannot express |
| `flyology_sparql` | SPARQL 1.1 queries, which are documents rather than data |

`flyology_rdf` has no runtime dependency and no tasking. Its only concession
to a scheduler is an optional cooperative-yield callback, so it runs equally
well in a plain sequential program and inside a lightweight-task runtime.

> **Experimental.** Interfaces, diagnostics, and the binary term format are
> subject to change until `v0.1.0`, and the binary format remains explicitly
> unstable after it.

## Design

- **Invalid terms are unrepresentable.** Predicates are typed as IRIs rather
  than terms, so a literal in predicate position is a compile error rather
  than a runtime check. Terms are indefinite and immutable, constructible
  only through functions that enforce every depth, node-count, and payload
  bound.
- **Terms are a flat vector, not a pointer graph.** Nested quoted triples
  reference their children by index, so no cycle is representable and
  traversal is iterative and bounded. The N3 and SPARQL trees use the same
  shape for the same reason.
- **One scanner, three dialects.** Token boundaries are decided in exactly
  one place. Deciding them twice is what produces a family of conformance
  bugs: a scanner that recognises `PREFIX` by looking ahead misreads a
  prefixed name whose prefix is `prefix`, and one that requires whitespace
  after `a` rejects `a<http://example.org/C>`. The RDF grammars cannot see
  an N3 or SPARQL token at all.
- **Parsing is chunk-fed.** RDF input may be split at any byte boundary,
  including mid-escape and mid-literal, and produces a byte-identical event
  stream regardless. Every document in the tests is parsed twice, whole and
  one byte at a time, and the two must agree.
- **Failures are typed.** Diagnostics carry a code, the grammar production
  that failed, and a full source span with byte, line, and column at both
  ends — not a message string.

## What is here

**Reading.** Turtle, TriG, N-Triples, N-Quads, Notation3, SPARQL queries.

**Writing.** N-Quads, Turtle, TriG, Notation3, SPARQL.

**Beyond serialization.** A dataset with set semantics and deterministic
iteration; RDFC-1.0 canonicalization and the dataset isomorphism it decides;
a self-delimiting binary term encoding whose injectivity is structural.

**Not here.** SPARQL evaluation, SPARQL Update, JSON-LD, RDF/XML,
reasoning of any kind.

## Testing

`./scripts/test.sh` in each crate. The RDF suite additionally holds a
permanent IRI strictness gate, a 925-case differential establishing that the
admission rule is never more permissive than the one it replaced and that
every accepted IRI serialises back to its exact bytes.

`./scripts/provision-oracles.sh corpora` fetches the W3C suites every
harness reads. Nothing is taken from the host: every artifact is pinned,
verified, and installed under a gitignored directory, because a conformance
number produced against an unrecorded version is not evidence.

The script also provisions three independent implementations -- Jena,
oxigraph and ld-cli -- for differential checking by hand. **No test invokes
them**: the numbers below come from the W3C suites alone, and the IRI
strictness gate is a recorded table rather than a live comparison.

## Status

Conformance, measured rather than claimed. Each harness reads the W3C
manifests with this crate's own Turtle parser and reports what it examined,
not a verdict:

| Suite | Examined | Rejected valid | Accepted invalid | Wrong result |
| --- | --- | --- | --- | --- |
| RDF 1.1 and 1.2 | 1050 | **0** | **0** | **0** |
| RDFC-1.0 canonicalization | 64 | — | — | **0** |
| Notation3 syntax | 1070 | **0** | **0** | — |
| SPARQL 1.1 syntax | 488 | **0** | **0** | — |

Corpora are pinned in `scripts/provision-oracles.sh`; the runs above are
against those pins.

The N3 suite carries 123 further entries its working group withdrew,
marked `rdft:approval rdft:Rejected` in the manifest. They are read, run
and reported like any other entry and counted apart: grading against a
withdrawn test would measure agreement with a decision its own authors
reversed. Eleven of them diverge, all cwm-era notation the specification
did not keep -- `?x^^xsd:dateTime`, `?s@de`, an `id` outside a property
list. The harness prints each one, marked `[withdrawn]`. No entry in the
RDF or SPARQL suites carries that status.

The canonicalization suite grades the canonical form byte for byte, because
RDFC-1.0 fixes both the labels and their order. Twenty-one of its entries
grade the issued-identifier map, which this crate does not expose, and one
uses SHA-384, which it does not implement; both are counted as skipped.

What cannot be graded is counted as skipped, not passed: 811 SPARQL
evaluation entries need a query engine, 83 more are SPARQL Update rather
than queries, and 193 N3 entries need a reasoner. RDF evaluation entries
*are* run, and compared by RDFC-1.0 canonical form rather than by blank
node label.

SPARQL reads what it claims to: the four query forms, the pattern and
expression grammars, property paths, subqueries, VALUES, EXISTS, dataset
clauses, aggregates, and the RDF 1.2 term syntax. It also rejects what the
grammar alone admits — a projection that repeats a name, an AS that takes a
name already in scope, a variable projected past a GROUP BY that dropped
it, a blank node label spanning two basic graph patterns, a reifier or a
list where RDF 1.2 does not allow one.

## Licence

MIT OR Apache-2.0.
