# flyology_rdf

RDF 1.2 terms, streaming Turtle and TriG parsing, and dataset
canonicalization for Ada.

The crate has no runtime dependency and no tasking. Its only concession to a
scheduler is an optional cooperative-yield callback, so it runs equally well
in a plain sequential program and inside a lightweight-task runtime.

> **Experimental.** Interfaces, diagnostics, and the binary term format are
> all subject to change until `v0.1.0`, and the binary format remains
> explicitly unstable after it.

## Design

- **Invalid terms are unrepresentable.** Predicates are typed as IRIs rather
  than terms, so a literal in predicate position is a compile error rather
  than a runtime check. Terms are indefinite and immutable, constructible
  only through functions that enforce every depth, node-count, and payload
  bound.
- **Terms are a flat vector, not a pointer graph.** Nested triple terms
  reference their children by index, so no cycle is representable and
  traversal is iterative and bounded.
- **Parsing is chunk-fed.** Input may be split at any byte boundary,
  including mid-escape and mid-literal, and produces a byte-identical event
  stream regardless of how it was split.
- **Failures are typed.** Diagnostics carry a code, the grammar production
  that failed, and a full source span with byte, line, and column at both
  ends — not a message string.

## Status

Under construction. This section will carry conformance evidence — corpus
counts and oracle provenance — once the harness produces it, and not before.

## Licence

MIT OR Apache-2.0.
