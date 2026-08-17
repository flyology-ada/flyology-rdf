with Flyology_SPARQL.Syntax;

--  SPARQL query parsing.
--
--  Coverage is the query language: the prologue, all four query forms,
--  group graph patterns with OPTIONAL, UNION, MINUS, GRAPH, SERVICE,
--  FILTER, BIND and subqueries, the expression grammar with its precedence,
--  and the solution modifiers. Property paths are read as far as sequence,
--  alternative, inverse and the three cardinality operators.
--
--  Deliberately absent: SPARQL Update, federated-query specifics beyond
--  recognising SERVICE, and evaluation of any kind. A query here is a
--  document to be checked, formatted or inspected.
package Flyology_SPARQL.Parsers is

   --  Raised when a query is not well-formed. The message names the line
   --  and column.
   Parse_Error : exception;

   --  Parse a query.
   --  @param Query_Text The SPARQL text
   --  @return The parsed query
   --  @exception Parse_Error The query is not well-formed
   function Parse (Query_Text : String) return Syntax.Query;

end Flyology_SPARQL.Parsers;
