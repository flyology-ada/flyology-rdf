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
- **Parsing is chunk-fed.** Input to any of the three may be split at any
  byte boundary, including mid-escape and mid-literal, and the result is
  the one the whole text would have given. Every document in the tests is
  parsed twice, whole and one byte at a time, and the two must agree --
  1,161 N3 documents, 317 SPARQL queries and the RDF suite besides. RDF
  emits statements as they close; N3 and SPARQL build their tree at the
  end, because a formula and a query are terms and a term means nothing
  until it is closed.
- **Failures are typed.** Diagnostics carry a code, the grammar production
  that failed, and a full source span with byte, line, and column at both
  ends — not a message string.

## What is here

**Reading.** Turtle, TriG, N-Triples, N-Quads, Notation3, SPARQL queries.

**Writing.** N-Quads, Turtle, TriG, Notation3, SPARQL.

**Beyond serialization.** A dataset with set semantics and deterministic
iteration; RDFC-1.0 canonicalization with either digest it admits, the
issued-identifier map, and the dataset isomorphism it decides;
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

`./scripts/provision-oracles.sh` also provisions two independent
implementations, oxigraph and Jena, and a pinned JRE for Jena to run on --
because a runtime that happens to be installed is a version nobody
recorded, which is the thing the script exists to avoid. The differential
below runs against them; without them it skips and says so.

## Status

Conformance, measured rather than claimed. Each harness reads the W3C
manifests with this crate's own Turtle parser and reports what it examined,
not a verdict:

| Suite | Examined | Rejected valid | Accepted invalid | Wrong result |
| --- | --- | --- | --- | --- |
| RDF 1.1 and 1.2 | 1050 | **0** | **0** | **0** |
| RDFC-1.0 canonicalization | 86 | — | — | **0** |
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
grade the issued-identifier map instead, and two ask for SHA-384; all of
them are run. Nothing in that suite is skipped.

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

## Differential testing

The W3C suites are finite, curated, and graded against our own reading of
them. The differential grades us against somebody else's code, and asks two
questions of every corpus document this crate accepts.

*Does the oracle read the document the way we do?* Its N-Quads are read back
with our own reader and canonicalized, so blank node labels -- the one thing
two conforming parsers may disagree about -- never enter the comparison.

*Does the oracle read our serialization the way we wrote it?* That is the
question the suites cannot ask. A writer bug that our own parser reads back
symmetrically survives every round-trip test there is, because both halves
share the misunderstanding. A foreign parser does not share it. The one
serialization bug found so far -- tab, backspace and form feed written as
numeric escapes where the canonical form names short ones -- was of exactly
that shape, and it survived 23 hand-written checks.

The two oracles are asked in order rather than both of everything. oxigraph
is native and answers in milliseconds, but 0.4 implements RDF-star, the
draft that preceded RDF 1.2, and reads `<< >>` as a quoted triple where RDF
1.2 reads a reified triple; its answer there describes the older
specification rather than either implementation, so it is not compared.
Jena implements RDF 1.2 and costs half a second a document, which is too
much for every document and right for the ones oxigraph could not answer.

One oracle disagreeing is a lead, not a verdict. When one does, the other
is asked, and if it agrees with us then the two oracles disagree with each
other -- a fact about them, reported as contested rather than counted
against us. Only a disagreement with no second opinion, or two oracles
disagreeing together, fails the run. There is one contested case today:
oxigraph 0.4 does not remove dot segments from an absolute IRI reference,
where RFC 3986 §5.2.2 applies `remove_dot_segments` whether or not the
reference carries its own scheme. Jena reads it as we do.

Coverage: 2,443 documents seen, 2,081 accepted, and 2,049 of those had
their serialization read back by a foreign parser. No writer divergence.

## Licence

MIT OR Apache-2.0.
