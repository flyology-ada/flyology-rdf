package body Flyology_RDF.Quads is

   use type Terms.Term_Kind;

   function Default_Graph return Graph_Name is
     (Variant => Default_Graph_Kind);

   function IRI_Graph (Value : IRIs.IRI) return Graph_Name is
     (Variant => IRI_Graph_Kind,
      Value   => Terms.IRI_Term (Value));

   function Blank_Node_Graph (Value : Terms.Term) return Graph_Name is
   begin
      if Terms.Kind (Value) /= Terms.Blank_Node_Kind then
         raise Terms.Invalid_Term with
           "a blank node graph name must be a blank node";
      end if;
      return
        (Variant => Blank_Node_Graph_Kind,
         Value   => Value);
   end Blank_Node_Graph;

   function Kind (Value : Graph_Name) return Graph_Name_Kind is
     (Value.Variant);

   function Name_Term (Value : Graph_Name) return Terms.Term is
   begin
      if Value.Variant = Default_Graph_Kind then
         raise Terms.Invalid_Term with
           "the default graph has no naming term";
      end if;
      return Value.Value;
   end Name_Term;

   procedure Query_Name_Term
     (Value   : Graph_Name;
      Process : not null access procedure (Name : Terms.Term)) is
   begin
      if Value.Variant = Default_Graph_Kind then
         raise Terms.Invalid_Term with
           "the default graph has no naming term";
      end if;
      Process (Value.Value);
   end Query_Name_Term;

   overriding function "=" (Left, Right : Graph_Name) return Boolean is
   begin
      if Left.Variant /= Right.Variant then
         return False;
      end if;

      case Left.Variant is
         when Default_Graph_Kind =>
            return True;
         when IRI_Graph_Kind | Blank_Node_Graph_Kind =>
            return Terms."=" (Left.Value, Right.Value);
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
   is (Graph_Data => Graph, Statement_Data => Statement);

   function Graph (Value : Quad) return Graph_Name is
     (Value.Graph_Data);

   function Statement (Value : Quad) return Triples.Triple is
     (Value.Statement_Data);

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
      procedure With_Parts
        (Subject   : Terms.Term;
         Predicate : IRIs.IRI;
         Object    : Terms.Term);

      procedure With_Parts
        (Subject   : Terms.Term;
         Predicate : IRIs.IRI;
         Object    : Terms.Term) is
      begin
         Process (Value.Graph_Data, Subject, Predicate, Object);
      end With_Parts;
   begin
      --  The graph name is held here, so only the statement's own parts
      --  have to be handed over.
      Triples.Query_Components (Value.Statement_Data, With_Parts'Access);
   end Query_Components;

   overriding function "=" (Left, Right : Quad) return Boolean is
      use type Triples.Triple;
   begin
      return Left.Graph_Data = Right.Graph_Data
        and then Left.Statement_Data = Right.Statement_Data;
   end "=";

end Flyology_RDF.Quads;
