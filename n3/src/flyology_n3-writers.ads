with Flyology_N3.Model;

--  Notation3 serialization.
package Flyology_N3.Writers is

   --  Whether to write the shorthand forms of the well-known predicates.
   --
   --  N3 writes rdf:type as "a", log:implies as "=>", and owl:sameAs as
   --  "=". The shorthands are what the language is for; the long forms
   --  exist here because a round-trip test that reads its own shorthand
   --  proves less than one that reads both.
   --  @enum Shorthand_Verbs Write a, => and =
   --  @enum Explicit_Verbs Write every predicate as an IRI
   type Verb_Style is (Shorthand_Verbs, Explicit_Verbs);

   --  Serialize a formula as an N3 document.
   --
   --  The outermost formula is written as a document -- its statements at
   --  the top level, without enclosing braces -- because that is what
   --  parsing a document produces.
   --  @param Value Formula to serialize
   --  @param Style Whether to use the shorthand verbs
   --  @return The N3 text
   --  @exception Model.Invalid_Term Value is not a formula
   function To_N3
     (Value : Model.Term;
      Style : Verb_Style := Shorthand_Verbs) return String;

   --  Serialize a single term, as it would appear inside a statement.
   --  @param Value Term to serialize
   --  @param Style Whether to use the shorthand verbs
   --  @return The N3 text
   function Write_Term
     (Value : Model.Term;
      Style : Verb_Style := Shorthand_Verbs) return String;

end Flyology_N3.Writers;
