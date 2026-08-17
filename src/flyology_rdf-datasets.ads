private with Ada.Containers.Indefinite_Ordered_Maps;

with Flyology_RDF.Quads;

--  A set of RDF statements across one or more graphs.
--
--  An RDF dataset is a set, so inserting the same statement twice leaves
--  one. Identity is the statement's N-Quads serialization, which makes two
--  statements the same exactly when they denote the same RDF statement --
--  including blank node labels, which are part of a statement's identity
--  within a dataset even though they carry no meaning outside it.
--
--  Iteration is in serialization order rather than insertion order. That
--  costs nothing here and buys a property worth having: two datasets built
--  by different routes iterate identically, so comparing them, printing
--  them, or hashing them needs no separate sort.
package Flyology_RDF.Datasets is

   --  A collection of statements.
   type Dataset is private;

   --  An empty dataset.
   --  @return A dataset containing no statements
   function Empty return Dataset;

   --  Add a statement, ignoring one that is already present.
   --  @param Into Dataset to extend
   --  @param Value Statement to add
   procedure Insert (Into : in out Dataset; Value : Quads.Quad);

   --  Add a statement and report whether it was new.
   --  @param Into Dataset to extend
   --  @param Value Statement to add
   --  @param Inserted True when Value was not already present
   procedure Insert
     (Into     : in out Dataset;
      Value    : Quads.Quad;
      Inserted : out Boolean);

   --  Remove a statement, ignoring one that is absent.
   --  @param From Dataset to reduce
   --  @param Value Statement to remove
   procedure Delete (From : in out Dataset; Value : Quads.Quad);

   --  Discard every statement.
   --  @param Value Dataset to empty
   procedure Clear (Value : in out Dataset);

   --  Report whether a statement is present.
   --  @param Value Dataset to search
   --  @param Statement Statement to look for
   --  @return True when Statement is present
   function Contains
     (Value : Dataset; Statement : Quads.Quad) return Boolean;

   --  Report the number of distinct statements.
   --  @param Value Dataset to measure
   --  @return Statement count
   function Length (Value : Dataset) return Natural;

   --  Report whether the dataset holds no statements.
   --  @param Value Dataset to test
   --  @return True when Length is zero
   function Is_Empty (Value : Dataset) return Boolean;

   --  Visit every statement in serialization order.
   --  @param Value Dataset to traverse
   --  @param Process Callback receiving each statement
   procedure Iterate
     (Value   : Dataset;
      Process : not null access procedure (Statement : Quads.Quad));

   --  Report the number of distinct graphs holding at least one statement,
   --  counting the default graph when it is used.
   --  @param Value Dataset to measure
   --  @return Graph count
   function Graph_Count (Value : Dataset) return Natural;

   --  Visit each graph that holds at least one statement, in serialization
   --  order, with the default graph first when present.
   --  @param Value Dataset to traverse
   --  @param Process Callback receiving each graph name
   procedure Iterate_Graphs
     (Value   : Dataset;
      Process : not null access procedure (Graph : Quads.Graph_Name));

   --  Visit every statement of one graph, in serialization order.
   --  @param Value Dataset to traverse
   --  @param Graph Graph to restrict to
   --  @param Process Callback receiving each statement
   procedure Iterate_Graph
     (Value   : Dataset;
      Graph   : Quads.Graph_Name;
      Process : not null access procedure (Statement : Quads.Quad));

   --  Serialize the whole dataset as N-Quads, one statement per line, each
   --  terminated by a line feed. Statements appear in serialization order,
   --  so the result is a deterministic function of the dataset's contents.
   --  @param Value Dataset to serialize
   --  @return The dataset in N-Quads syntax
   function To_NQuads (Value : Dataset) return String;

   --  Compare two datasets as sets of statements.
   --
   --  This is equality of labelled statements, not isomorphism: two
   --  datasets that differ only in their blank node labels are not equal
   --  here. Deciding that requires canonicalization.
   --  @param Left First dataset
   --  @param Right Second dataset
   --  @return True when both hold the same statements
   overriding function "=" (Left, Right : Dataset) return Boolean;

private

   package Statement_Maps is new Ada.Containers.Indefinite_Ordered_Maps
     (Key_Type     => String,
      Element_Type => Quads.Quad,
      "="          => Quads."=");

   package Graph_Maps is new Ada.Containers.Indefinite_Ordered_Maps
     (Key_Type     => String,
      Element_Type => Quads.Graph_Name,
      "="          => Quads."=");

   package Count_Maps is new Ada.Containers.Indefinite_Ordered_Maps
     (Key_Type     => String,
      Element_Type => Natural);

   type Dataset is record
      Statements : Statement_Maps.Map;
      Graphs     : Graph_Maps.Map;
      --  Statements per graph key, so that removing the last statement of
      --  a graph also removes the graph. The default graph's key is the
      --  empty string, which sorts first, so it leads the iteration order
      --  for free.
      Counts     : Count_Maps.Map;
   end record;

end Flyology_RDF.Datasets;
