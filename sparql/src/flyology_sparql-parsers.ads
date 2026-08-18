with Ada.Strings.Unbounded;

with Flyology_RDF.Chunk_Scanners;

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

   --  Parse a query given whole.
   --  @param Query_Text The SPARQL text
   --  @return The parsed query
   --  @exception Parse_Error The query is not well-formed
   --  What one query may cost to read. A caller taking input from a
   --  network must be able to say what it will accept, and the defaults
   --  are the same as the RDF parser's.
   subtype Parse_Limits is Flyology_RDF.Chunk_Scanners.Scan_Limits;

   function Parse
     (Query_Text : String;
      Limits     : Parse_Limits := (others => <>)) return Syntax.Query;

   ---------------------------------------------------------------------
   --  Chunk-fed parsing
   ---------------------------------------------------------------------

   --  A query read from input that arrives in pieces.
   --
   --  The tree is built at Finish rather than as the bytes arrive, because
   --  a query is not meaningful until it is closed and there is nothing to
   --  hand back before then. What streaming buys here is the scanner: the
   --  input may be split at any byte boundary, including inside an escape,
   --  a literal or an IRI, and the query that comes out is the one the
   --  whole text would have produced. A caller reading from a socket does
   --  not have to assemble the document first.
   type Parser is limited private;

   --  Raised when a parser is fed or finished twice.
   Parser_State_Error : exception;

   --  Start a parser.
   --  @return A parser awaiting its first chunk
   function Create (Limits : Parse_Limits := (others => <>)) return Parser;

   --  Supply the next piece of the query.
   --  @param Into The parser
   --  @param Bytes The next bytes, split at any boundary
   --  @exception Parse_Error The bytes cannot begin a token
   --  @exception Parser_State_Error The parser has already finished
   procedure Feed (Into : in out Parser; Bytes : String);

   --  Close the input and parse what arrived.
   --  @param Into The parser
   --  @return The parsed query
   --  @exception Parse_Error The query is not well-formed
   --  @exception Parser_State_Error The parser has already finished
   function Finish (Into : in out Parser) return Syntax.Query;

private

   --  Pending holds at most one partial token: everything the scanner has
   --  read is dropped, and Origin is the cursor where the remainder
   --  starts, so line and column survive a split as if there had been
   --  none.
   package Scanners renames Flyology_RDF.Chunk_Scanners;

   type Parser is limited record
      Pending  : Ada.Strings.Unbounded.Unbounded_String;
      Limits   : Parse_Limits;
      State    : Scanners.Scan_State;
      Tokens   : Scanners.Token_Vectors.Vector;
      Finished : Boolean := False;
   end record;

end Flyology_SPARQL.Parsers;
