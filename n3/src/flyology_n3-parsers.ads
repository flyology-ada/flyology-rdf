with Flyology_N3.Model;

--  Notation3 parsing.
--
--  Unlike the RDF parsers, this one takes the whole document at once. That
--  is a deliberate difference rather than an omission: an N3 formula is a
--  term, and a term is not meaningful until it is closed, so a document
--  whose outermost construct is a formula offers no useful boundary to
--  stream at. Feeding N3 in chunks would buy a smaller buffer and nothing
--  else, and would cost the recursive descent that makes the nesting
--  readable.
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

end Flyology_N3.Parsers;
