package body Flyology_RDF.Triples is

   function Create
     (Subject   : Terms.Term;
      Predicate : IRIs.IRI;
      Object    : Terms.Term) return Triple is
     (Subject_Data   => Subject,
      Predicate_Data => Predicate,
      Object_Data    => Object);

   function Subject (Value : Triple) return Terms.Term is
     (Value.Subject_Data);

   function Predicate (Value : Triple) return IRIs.IRI is
     (Value.Predicate_Data);

   function Object (Value : Triple) return Terms.Term is
     (Value.Object_Data);

   function Subject_View
     (Value : Triple) return not null access constant Terms.Term
   is (Value.Subject_Data'Unchecked_Access);

   function Predicate_View
     (Value : Triple) return not null access constant IRIs.IRI
   is (Value.Predicate_Data'Unchecked_Access);

   function Object_View
     (Value : Triple) return not null access constant Terms.Term
   is (Value.Object_Data'Unchecked_Access);

   procedure Query_Components
     (Value   : Triple;
      Process : not null access procedure
        (Subject   : Terms.Term;
         Predicate : IRIs.IRI;
         Object    : Terms.Term)) is
   begin
      --  The components are held here rather than in holders, so handing
      --  them over is passing them, not borrowing them back out.
      Process (Value.Subject_Data, Value.Predicate_Data, Value.Object_Data);
   end Query_Components;

   overriding function "=" (Left, Right : Triple) return Boolean is
      use type Terms.Term;
      use type IRIs.IRI;
   begin
      return Left.Subject_Data = Right.Subject_Data
        and then Left.Predicate_Data = Right.Predicate_Data
        and then Left.Object_Data = Right.Object_Data;
   end "=";

end Flyology_RDF.Triples;
