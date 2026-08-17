# IRI strictness policy

RDF defines IRI equality as codepoint-by-codepoint comparison with no
normalisation of any kind. Two decisions follow from that, and this document
records both along with the measurements behind them.

## 1. Parse in `IRI_Syntax`, never `Web_URL_Syntax`

`Flyology_IRI.Web_URL_Syntax` deliberately lowercases the scheme and host and
inserts `/` for an empty path. Applying it to RDF terms would silently merge
distinct IRIs and corrupt every isomorphism and canonicalisation result. This
crate therefore uses `IRI_Syntax` exclusively.

**Measured:** across a 927-case differential — every ASCII byte in each of
seven position classes, plus targeted percent-escape, IPv6, case, empty-path,
non-hierarchical-scheme and non-ASCII cases — `Image (Parse (X, IRI_Syntax))`
returned `X` byte-for-byte in every accepted case. Zero inexact round trips.

## 2. Validation is RFC 3987, not a blocklist

The alternative was a permissive blocklist: accept anything after the scheme
except control bytes, `DEL`, ``<>"{}|\^` `` and malformed percent escapes. The
same differential compared that rule against `Flyology_IRI.Diagnose` in
`IRI_Syntax` plus an absoluteness check.

|                                              | count |
| -------------------------------------------- | ----- |
| examined                                      | 927   |
| agree — accept                                | 544   |
| agree — reject                                | 369   |
| blocklist accepts, RFC 3987 rejects           | 14    |
| blocklist rejects, RFC 3987 accepts           | **0** |
| inexact round trips                           | **0** |

The zero in the fourth row is the important one: the strict rule is never
*more* permissive, so adopting it cannot introduce a false accept.

The 14 disagreements fall into three classes, and two of them are defects in
the blocklist that the strict rule fixes at no cost:

- **Colon in the authority** — `http://exam:ple.org/p`. The blocklist scans
  only to the first colon to find the scheme and then never reconsiders, so a
  second colon in host position passes. `exam:ple.org` is not a valid
  host-port. Correctly rejected.
- **Repeated fragment** — `http://example.org/p#f#`. RFC 3986 excludes `#`
  from the fragment production, so only one may appear. The blocklist has no
  opinion about `#` at all. Correctly rejected.
- **Square brackets** — 12 of the 14, `[` and `]` in every position class.
  RFC 3987 permits brackets only as IPv6 host delimiters.

Only the third class is a genuine policy question, because Turtle's `IRIREF`
token production *does* admit brackets between `<` and `>`. The token grammar
and the IRI grammar are separate layers, and the RDF specification requires
the token's contents to be a valid IRI, so rejection is the conformant
behaviour. Two further observations decided it:

- The pinned W3C corpus contains **zero** IRIs with brackets inside `<...>`.
  (Files that appear to match are using blank-node `[ ]` syntax on the same
  line.) Adopting the strict rule changes no conformance result.
- The differential oracles disagree with each other here — `riot` warns and
  continues where `oxigraph` rejects — so a policy has to be stated either
  way in order to adjudicate Tier 2 divergences. Strict aligns with the
  stricter oracle and with the specification.

**Policy: RFC 3987 strict.** `Flyology_IRI.Diagnose (X, IRI_Syntax, Max)`
plus `Kind = Absolute_Reference` is the sole admission rule for a resolved
IRI. Bracket-bearing IRIs are rejected with a typed diagnostic.

## 3. What stays in the parser

Turtle's `IRIREF` production is stricter than RFC 3987 in a different
direction: bytes `<= 0x20` and ``< > " { } | ^ \ ` `` are forbidden between
the angle brackets, and `\uXXXX` / `\UXXXXXXXX` escapes are unescaped
*before* validation. That token-level work belongs to the parser;
`flyology_iri` only ever sees the unescaped result.

## 4. Length bounds

`Flyology_IRI`'s own default is 8 KiB, which is far below what an RDF
document may legitimately contain. Every call site passes an explicit
`Max_Length` derived from the active parse limits. A call that relies on the
default is a bug.

## Reproducing

`tests/src/iri_strictness_gate.adb` is the differential, retained as a
permanent guard. It fails if a round trip becomes inexact, if any new
disagreement class appears, or if the strict rule ever becomes the more
permissive of the two.
