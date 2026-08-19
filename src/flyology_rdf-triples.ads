with Flyology_RDF.IRIs;
with Flyology_RDF.Terms;

--  Immutable RDF triples.
--
--  The predicate is typed as an IRI rather than a Term, so a literal or a
--  blank node in predicate position is a compile error rather than a runtime
--  check. Nothing here validates positions, because nothing can reach this
--  package holding an invalid one.
package Flyology_RDF.Triples is

   --  An immutable RDF triple.
   type Triple is private;

   --  Build a triple from its three components.
   --  @param Subject Subject term
   --  @param Predicate Predicate IRI
   --  @param Object Object term
   --  @return The corresponding triple
   function Create
     (Subject   : Terms.Term;
      Predicate : IRIs.IRI;
      Object    : Terms.Term) return Triple;

   --  Return a copy of the subject.
   --  @param Value Triple to inspect
   --  @return The subject term
   function Subject (Value : Triple) return Terms.Term;

   --  Return a copy of the predicate.
   --  @param Value Triple to inspect
   --  @return The predicate IRI
   function Predicate (Value : Triple) return IRIs.IRI;

   --  Return a copy of the object.
   --  @param Value Triple to inspect
   --  @return The object term
   function Object (Value : Triple) return Terms.Term;

   --  Borrow all three components for the duration of Process.
   --
   --  Unlike the selectors above, this returns nothing by copy. On any path
   --  that runs once per statement, prefer it: the selectors each copy a
   --  whole term, and a term may be an arbitrarily deep quoted triple.
   --  @param Value Triple to borrow from
   --  @param Process Callback receiving the three components
   procedure Query_Components
     (Value   : Triple;
      Process : not null access procedure
        (Subject   : Terms.Term;
         Predicate : IRIs.IRI;
         Object    : Terms.Term));

   --  Compare two triples componentwise.
   --  @param Left First triple
   --  @param Right Second triple
   --  @return True when all three components are equal
   overriding function "=" (Left, Right : Triple) return Boolean;

private

   package IRI_Holders is new Immutable_Holders
     (Element_Type => IRIs.IRI,
      "="          => IRIs."=");

   type Triple is record
      Subject_Data   : Terms.Term;
      Predicate_Data : IRIs.IRI;
      Object_Data    : Terms.Term;
   end record;

end Flyology_RDF.Triples;
