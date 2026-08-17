package body Flyology_RDF.Quads is

   use type Terms.Term_Kind;

   function Default_Graph return Graph_Name is
     (Variant => Default_Graph_Kind);

   function IRI_Graph (Value : IRIs.IRI) return Graph_Name is
     (Variant => IRI_Graph_Kind,
      Value   => Term_Holders.To_Holder (Terms.IRI_Term (Value)));

   function Blank_Node_Graph (Value : Terms.Term) return Graph_Name is
   begin
      if Terms.Kind (Value) /= Terms.Blank_Node_Kind then
         raise Terms.Invalid_Term with
           "a blank node graph name must be a blank node";
      end if;
      return
        (Variant => Blank_Node_Graph_Kind,
         Value   => Term_Holders.To_Holder (Value));
   end Blank_Node_Graph;

   function Kind (Value : Graph_Name) return Graph_Name_Kind is
     (Value.Variant);

   function Name_Term (Value : Graph_Name) return Terms.Term is
   begin
      if Value.Variant = Default_Graph_Kind then
         raise Terms.Invalid_Term with
           "the default graph has no naming term";
      end if;
      return Term_Holders.Element (Value.Value);
   end Name_Term;

   procedure Query_Name_Term
     (Value   : Graph_Name;
      Process : not null access procedure (Name : Terms.Term)) is
   begin
      if Value.Variant = Default_Graph_Kind then
         raise Terms.Invalid_Term with
           "the default graph has no naming term";
      end if;
      Term_Holders.Query_Element (Value.Value, Process);
   end Query_Name_Term;

   overriding function "=" (Left, Right : Graph_Name) return Boolean is
      use type Term_Holders.Holder;
   begin
      if Left.Variant /= Right.Variant then
         return False;
      end if;

      case Left.Variant is
         when Default_Graph_Kind =>
            return True;
         when IRI_Graph_Kind | Blank_Node_Graph_Kind =>
            return Left.Value = Right.Value;
      end case;
   end "=";

   function Create
     (Graph     : Graph_Name;
      Subject   : Terms.Term;
      Predicate : IRIs.IRI;
      Object    : Terms.Term) return Quad
   is (Create (Graph, Triples.Create (Subject, Predicate, Object)));

   function Create
     (Graph     : Graph_Name;
      Statement : Triples.Triple) return Quad
   is (Initialized    => True,
       Graph_Data     => Graph_Name_Holders.To_Holder (Graph),
       Statement_Data => Triple_Holders.To_Holder (Statement));

   function Graph (Value : Quad) return Graph_Name is
     (Graph_Name_Holders.Element (Value.Graph_Data));

   function Statement (Value : Quad) return Triples.Triple is
     (Triple_Holders.Element (Value.Statement_Data));

   function Subject (Value : Quad) return Terms.Term is
     (Triples.Subject (Statement (Value)));

   function Predicate (Value : Quad) return IRIs.IRI is
     (Triples.Predicate (Statement (Value)));

   function Object (Value : Quad) return Terms.Term is
     (Triples.Object (Statement (Value)));

   procedure Query_Components
     (Value   : Quad;
      Process : not null access procedure
        (Graph     : Graph_Name;
         Subject   : Terms.Term;
         Predicate : IRIs.IRI;
         Object    : Terms.Term))
   is
      procedure With_Graph (Graph : Graph_Name);

      procedure With_Graph (Graph : Graph_Name) is
         procedure With_Statement (Statement : Triples.Triple);

         procedure With_Statement (Statement : Triples.Triple) is
            procedure With_Parts
              (Subject   : Terms.Term;
               Predicate : IRIs.IRI;
               Object    : Terms.Term);

            procedure With_Parts
              (Subject   : Terms.Term;
               Predicate : IRIs.IRI;
               Object    : Terms.Term) is
            begin
               Process (Graph, Subject, Predicate, Object);
            end With_Parts;
         begin
            Triples.Query_Components (Statement, With_Parts'Access);
         end With_Statement;
      begin
         Triple_Holders.Query_Element
           (Value.Statement_Data, With_Statement'Access);
      end With_Graph;
   begin
      Graph_Name_Holders.Query_Element
        (Value.Graph_Data, With_Graph'Access);
   end Query_Components;

   overriding function "=" (Left, Right : Quad) return Boolean is
      use type Graph_Name_Holders.Holder;
      use type Triple_Holders.Holder;
   begin
      return Left.Graph_Data = Right.Graph_Data
        and then Left.Statement_Data = Right.Statement_Data;
   end "=";

end Flyology_RDF.Quads;
