with Flyology_RDF.Quads;
with Flyology_RDF.Terms;

--  N-Triples and N-Quads serialization.
--
--  This is the crate's interchange form: it is what round-trip tests
--  compare, what a differential harness hands to another implementation,
--  and the shape canonicalization emits. It is deliberately the dullest
--  writer here -- one statement per line, no abbreviation, no prefixes.
package Flyology_RDF.NQuads_Writers is

   --  How to serialize a literal whose datatype is xsd:string.
   --  @enum Explicit_Datatype Always write ^^<...#string>
   --  @enum Implicit_Datatype Write the bare quoted form
   type String_Datatype_Style is (Explicit_Datatype, Implicit_Datatype);

   --  Serialize one term.
   --
   --  RDF 1.1 makes "abc" and "abc"^^xsd:string the same term, so both
   --  styles denote it; they differ only in bytes. Explicit is the default
   --  because it is unambiguous to read, and implicit exists because
   --  canonical forms and other implementations commonly omit it, and a
   --  byte comparison against them has to agree.
   --  @param Value Term to serialize
   --  @param Style How to render an xsd:string datatype
   --  @return The term in N-Triples syntax
   function Write_Term
     (Value : Terms.Term;
      Style : String_Datatype_Style := Explicit_Datatype) return String;

   --  Serialize one statement as a line, including the trailing " ." but
   --  not a line terminator. The graph is written only when it is not the
   --  default graph, which is what distinguishes N-Quads from N-Triples.
   --  @param Value Quad to serialize
   --  @param Style How to render an xsd:string datatype
   --  @return The statement in N-Quads syntax
   function Write_Quad
     (Value : Quads.Quad;
      Style : String_Datatype_Style := Explicit_Datatype) return String;

   --  Serialize a graph name, for callers building their own output.
   --  @param Value Graph name to serialize
   --  @return The graph name in N-Quads syntax, empty for the default graph
   function Write_Graph_Name (Value : Quads.Graph_Name) return String;

end Flyology_RDF.NQuads_Writers;
