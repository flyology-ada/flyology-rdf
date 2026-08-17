package body Flyology_RDF.Triples is

   function Create
     (Subject   : Terms.Term;
      Predicate : IRIs.IRI;
      Object    : Terms.Term) return Triple is
     (Initialized    => True,
      Subject_Data   => Term_Holders.To_Holder (Subject),
      Predicate_Data => IRI_Holders.To_Holder (Predicate),
      Object_Data    => Term_Holders.To_Holder (Object));

   function Subject (Value : Triple) return Terms.Term is
     (Term_Holders.Element (Value.Subject_Data));

   function Predicate (Value : Triple) return IRIs.IRI is
     (IRI_Holders.Element (Value.Predicate_Data));

   function Object (Value : Triple) return Terms.Term is
     (Term_Holders.Element (Value.Object_Data));

   procedure Query_Components
     (Value   : Triple;
      Process : not null access procedure
        (Subject   : Terms.Term;
         Predicate : IRIs.IRI;
         Object    : Terms.Term))
   is
      --  Nested borrows rather than three copies. Each Query_Element hands
      --  over the holder-owned value for the duration of its callback, so
      --  the innermost body sees all three without any of them being
      --  duplicated.
      procedure With_Subject (Subject : Terms.Term);

      procedure With_Subject (Subject : Terms.Term) is
         procedure With_Predicate (Predicate : IRIs.IRI);

         procedure With_Predicate (Predicate : IRIs.IRI) is
            procedure With_Object (Object : Terms.Term);

            procedure With_Object (Object : Terms.Term) is
            begin
               Process (Subject, Predicate, Object);
            end With_Object;
         begin
            Term_Holders.Query_Element
              (Value.Object_Data, With_Object'Access);
         end With_Predicate;
      begin
         IRI_Holders.Query_Element
           (Value.Predicate_Data, With_Predicate'Access);
      end With_Subject;
   begin
      Term_Holders.Query_Element (Value.Subject_Data, With_Subject'Access);
   end Query_Components;

   overriding function "=" (Left, Right : Triple) return Boolean is
      use type Term_Holders.Holder;
      use type IRI_Holders.Holder;
   begin
      return Left.Subject_Data = Right.Subject_Data
        and then Left.Predicate_Data = Right.Predicate_Data
        and then Left.Object_Data = Right.Object_Data;
   end "=";

end Flyology_RDF.Triples;
