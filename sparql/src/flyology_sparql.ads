--  SPARQL 1.1 queries.
--
--  This crate reads a query into a syntax tree and writes it back. It does
--  not evaluate: a query here is a document to be checked, formatted, or
--  inspected, not something to run against data. Evaluation is a different
--  and much larger problem, and keeping it out means the parser can be
--  useful on its own -- for validating queries, normalising their layout,
--  or finding what a query touches -- without an engine behind it.
--
--  It is a separate crate from flyology_rdf for the same reason
--  flyology_n3 is: a query is not a dataset, and its tree is not made of
--  RDF terms alone. Someone who wants to read Turtle should not link a
--  query parser.
package Flyology_SPARQL is
end Flyology_SPARQL;
