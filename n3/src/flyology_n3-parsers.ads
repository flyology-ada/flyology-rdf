with Ada.Containers.Indefinite_Vectors;
with Ada.Strings.Unbounded;

with Flyology_RDF.Lexers;
with Flyology_RDF.Parser_Cursors;

with Flyology_N3.Model;

--  Notation3 parsing.
--
--  The document may arrive whole or in chunks. Unlike the RDF parsers it
--  emits nothing as it reads, and that is a difference in the grammar
--  rather than an omission: an N3 formula is a term, a term is not
--  meaningful until it is closed, and a document whose outermost construct
--  is a formula offers no boundary to hand anything back at. What chunks
--  buy is the scanner, which is where splitting hurts -- input may be cut
--  at any byte, including inside an escape, a literal or an IRI, and the
--  formula that comes out is the one the whole text would have given.
package Flyology_N3.Parsers is

   --  Raised when a document is not well-formed N3. The message names the
   --  line and column.
   Parse_Error : exception;

   --  Parse a document into the formula it denotes.
   --
   --  The result is a formula whose statements are the document's
   --  top-level statements, which is what N3 means by the document itself.
   --  @param Document The N3 text
   --  @param Base_IRI Absolute IRI relative references resolve against
   --  @return The document as a formula
   --  @exception Parse_Error The document is not well-formed
   function Parse
     (Document : String;
      Base_IRI : String := "") return Model.Term;

   ---------------------------------------------------------------------
   --  Chunk-fed parsing
   ---------------------------------------------------------------------

   --  A document read from input that arrives in pieces.
   type Parser is limited private;

   --  Raised when a parser is fed or finished twice.
   Parser_State_Error : exception;

   --  Start a parser.
   --  @param Base_IRI Absolute IRI relative references resolve against
   --  @return A parser awaiting its first chunk
   function Create (Base_IRI : String := "") return Parser;

   --  Supply the next piece of the document.
   --  @param Into The parser
   --  @param Bytes The next bytes, split at any boundary
   --  @exception Parse_Error The bytes cannot begin a token
   --  @exception Parser_State_Error The parser has already finished
   procedure Feed (Into : in out Parser; Bytes : String);

   --  Close the input and parse what arrived.
   --  @param Into The parser
   --  @return The document as a formula
   --  @exception Parse_Error The document is not well-formed
   --  @exception Parser_State_Error The parser has already finished
   function Finish (Into : in out Parser) return Model.Term;

private

   package Token_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Flyology_RDF.Lexers.Token,
      "="          => Flyology_RDF.Lexers."=");

   --  Pending holds at most one partial token: everything the scanner has
   --  read is dropped, and Origin is the cursor where the remainder
   --  starts, so line and column survive a split as if there had been
   --  none.
   type Parser is limited record
      Pending  : Ada.Strings.Unbounded.Unbounded_String;
      Base     : Ada.Strings.Unbounded.Unbounded_String;
      Origin   : Flyology_RDF.Parser_Cursors.Cursor_State :=
        Flyology_RDF.Parser_Cursors.Initial_State;
      Tokens   : Token_Vectors.Vector;
      Finished : Boolean := False;
   end record;

end Flyology_N3.Parsers;
