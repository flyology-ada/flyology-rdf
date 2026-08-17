with Flyology_SPARQL.Syntax;

--  SPARQL query serialization.
--
--  The output is a normalised form of the query that was read: the same
--  query, laid out one way. Keywords are upper case, nesting is indented,
--  and whatever the input did about whitespace is gone. That normalisation
--  is the point -- it is what makes writing a query and reading it back a
--  test of the parser rather than a test of the formatter.
package Flyology_SPARQL.Writers is

   --  Serialize a query.
   --  @param Value Query to serialize
   --  @return The SPARQL text
   function To_SPARQL (Value : Syntax.Query) return String;

end Flyology_SPARQL.Writers;
