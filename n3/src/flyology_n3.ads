--  Notation3.
--
--  N3 is often described as a superset of Turtle, and at the syntactic
--  level it is. At the level that matters here it is something else: N3
--  adds variables and formulas, and neither exists in RDF's abstract
--  syntax. A formula is a quoted graph -- a term that happens to be a set
--  of statements -- and RDF has no such term.
--
--  That is why this is a separate crate rather than more packages inside
--  flyology_rdf. Its model is a strict superset of the RDF one and reuses
--  it wherever the term really is an RDF term, but a consumer that only
--  wants to read Turtle should not be carrying term kinds that RDF cannot
--  express.
package Flyology_N3 is
end Flyology_N3;
