private with Ada.Containers.Indefinite_Ordered_Maps;

with Flyology_RDF.Datasets;

--  Turtle and TriG serialization.
--
--  Where the N-Quads writer optimises for being trivially comparable, this
--  one optimises for being read: statements are grouped by graph and then by
--  subject, repeated predicates collapse into an object list, and bound
--  prefixes shorten IRIs.
--
--  It deliberately does not abbreviate blank nodes into bracket form or
--  collections into parentheses. Both are pleasant to read and neither is
--  free: they require knowing that a blank node is referenced exactly once,
--  in the right position, and that a chain really is well formed. Writing
--  them out costs some elegance and no correctness, and the round trip is
--  what matters here.
package Flyology_RDF.Turtle_Writers is

   --  A set of prefix bindings to abbreviate with.
   type Prefix_Map is private;

   --  No bindings; every IRI is written in full.
   --  @return An empty prefix map
   function No_Prefixes return Prefix_Map;

   --  Bind a prefix to a namespace, replacing any existing binding.
   --
   --  A binding is used only where it produces a legal prefixed name, so
   --  binding a namespace that would require escaping in the local part
   --  simply leaves those IRIs written in full rather than producing
   --  something that does not parse back.
   --  @param Into Map to extend
   --  @param Prefix Prefix without its colon, possibly empty
   --  @param Namespace IRI the prefix stands for
   procedure Bind
     (Into      : in out Prefix_Map;
      Prefix    : String;
      Namespace : String);

   --  Serialize a dataset as TriG.
   --
   --  Statements in the default graph are written at the top level, and each
   --  named graph in its own block.
   --  @param Value Dataset to serialize
   --  @param Prefixes Bindings to abbreviate with
   --  @return The dataset in TriG syntax
   function To_TriG
     (Value    : Datasets.Dataset;
      Prefixes : Prefix_Map := No_Prefixes) return String;

   --  Serialize a dataset as Turtle.
   --  @param Value Dataset to serialize, holding only the default graph
   --  @param Prefixes Bindings to abbreviate with
   --  @return The dataset in Turtle syntax
   --  @exception Constraint_Error Value holds a named graph, which Turtle
   --     cannot express
   function To_Turtle
     (Value    : Datasets.Dataset;
      Prefixes : Prefix_Map := No_Prefixes) return String;

private

   package Namespace_Maps is new Ada.Containers.Indefinite_Ordered_Maps
     (Key_Type     => String,
      Element_Type => String);

   type Prefix_Map is record
      --  Keyed by namespace so that lookup during writing is by the part of
      --  an IRI that is known: its leading text.
      By_Namespace : Namespace_Maps.Map;
   end record;

end Flyology_RDF.Turtle_Writers;
