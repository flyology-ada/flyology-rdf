with Flyology_RDF.IRIs;
with Flyology_RDF.Terms;
with Flyology_RDF.Triples;

--  Immutable graph names and RDF quads.
package Flyology_RDF.Quads is

   --  What names a graph.
   --  @enum Default_Graph_Kind The unnamed default graph
   --  @enum IRI_Graph_Kind A graph named by an IRI
   --  @enum Blank_Node_Graph_Kind A graph named by a blank node
   type Graph_Name_Kind is
     (Default_Graph_Kind, IRI_Graph_Kind, Blank_Node_Graph_Kind);

   --  The name of a graph within a dataset.
   type Graph_Name is private;

   --  An RDF quad: a triple together with the graph it belongs to.
   type Quad is private;

   --  Return the name of the default graph.
   --  @return The default graph name
   function Default_Graph return Graph_Name;

   --  Name a graph by IRI.
   --  @param Value The graph IRI
   --  @return The corresponding graph name
   function IRI_Graph (Value : IRIs.IRI) return Graph_Name;

   --  Name a graph by blank node.
   --  @param Value A blank node term
   --  @return The corresponding graph name
   --  @exception Terms.Invalid_Term Value is not a blank node
   function Blank_Node_Graph (Value : Terms.Term) return Graph_Name;

   --  Report which of the three kinds this graph name is.
   --  @param Value Graph name to inspect
   --  @return The graph name's kind
   function Kind (Value : Graph_Name) return Graph_Name_Kind;

   --  Return a copy of the term naming this graph.
   --  @param Value Graph name to inspect
   --  @return The naming term
   --  @exception Terms.Invalid_Term Value is the default graph, which has
   --     no naming term
   function Name_Term (Value : Graph_Name) return Terms.Term;

   --  Borrow the naming term for the duration of Process, without copying.
   --  @param Value Graph name to borrow from
   --  @param Process Callback receiving the naming term
   --  @exception Terms.Invalid_Term Value is the default graph
   procedure Query_Name_Term
     (Value   : Graph_Name;
      Process : not null access procedure (Name : Terms.Term));

   --  Compare two graph names.
   --  @param Left First graph name
   --  @param Right Second graph name
   --  @return True when both name the same graph
   overriding function "=" (Left, Right : Graph_Name) return Boolean;

   --  Build a quad from a graph name and the three statement components.
   --  @param Graph The graph the statement belongs to
   --  @param Subject Subject term
   --  @param Predicate Predicate IRI
   --  @param Object Object term
   --  @return The corresponding quad
   function Create
     (Graph     : Graph_Name;
      Subject   : Terms.Term;
      Predicate : IRIs.IRI;
      Object    : Terms.Term) return Quad;

   --  Build a quad from a graph name and an existing triple.
   --  @param Graph The graph the statement belongs to
   --  @param Statement The triple
   --  @return The corresponding quad
   function Create
     (Graph     : Graph_Name;
      Statement : Triples.Triple) return Quad;

   --  Return a copy of the graph name.
   --  @param Value Quad to inspect
   --  @return The graph name
   function Graph (Value : Quad) return Graph_Name;

   --  Return a copy of the statement.
   --  @param Value Quad to inspect
   --  @return The triple
   function Statement (Value : Quad) return Triples.Triple;

   --  Return a copy of the subject.
   --  @param Value Quad to inspect
   --  @return The subject term
   function Subject (Value : Quad) return Terms.Term;

   --  Return a copy of the predicate.
   --  @param Value Quad to inspect
   --  @return The predicate IRI
   function Predicate (Value : Quad) return IRIs.IRI;

   --  Return a copy of the object.
   --  @param Value Quad to inspect
   --  @return The object term
   function Object (Value : Quad) return Terms.Term;

   --  Borrow all four components for the duration of Process, without
   --  copying any of them. Prefer this on any path that runs once per
   --  statement.
   --  @param Value Quad to borrow from
   --  @param Process Callback receiving the four components
   procedure Query_Components
     (Value   : Quad;
      Process : not null access procedure
        (Graph     : Graph_Name;
         Subject   : Terms.Term;
         Predicate : IRIs.IRI;
         Object    : Terms.Term));

   --  Compare two quads componentwise.
   --  @param Left First quad
   --  @param Right Second quad
   --  @return True when the graph names and statements are equal
   overriding function "=" (Left, Right : Quad) return Boolean;

private

   type Graph_Name (Variant : Graph_Name_Kind := Default_Graph_Kind) is
   record
      case Variant is
         when Default_Graph_Kind =>
            null;
         when IRI_Graph_Kind | Blank_Node_Graph_Kind =>
            Value : Terms.Term;
      end case;
   end record;

   --  Both components are definite now, so a quad is the graph name and
   --  the statement themselves rather than two allocated cells pointing
   --  at them. The terms inside still share their nodes, so this stays a
   --  handful of pointers.
   type Quad is record
      Graph_Data     : Graph_Name;
      Statement_Data : Triples.Triple;
   end record;

end Flyology_RDF.Quads;
