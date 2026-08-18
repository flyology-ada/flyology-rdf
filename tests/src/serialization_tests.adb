--  Exercises N-Quads serialization and the dataset container.
--
--  Serialization is where the crate's identity notion lives: the dataset
--  keys statements by their written form, so an escaping bug is not merely
--  cosmetic -- it makes two distinct statements collide, or one statement
--  fail to deduplicate against itself.

with Ada.Command_Line;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Flyology_RDF.Datasets;
with Flyology_RDF.IRIs;
with Flyology_RDF.NQuads_Writers;
with Flyology_RDF.Quads;
with Flyology_RDF.Terms;

procedure Serialization_Tests is

   package IO renames Ada.Text_IO;
   package Unbounded renames Ada.Strings.Unbounded;
   package Datasets renames Flyology_RDF.Datasets;
   package IRIs renames Flyology_RDF.IRIs;
   package Quads renames Flyology_RDF.Quads;
   package Terms renames Flyology_RDF.Terms;
   package Writers renames Flyology_RDF.NQuads_Writers;

   use type Datasets.Dataset;

   Checks   : Natural := 0;
   Failures : Natural := 0;

   procedure Check (Condition : Boolean; Label : String) is
   begin
      Checks := Checks + 1;
      if not Condition then
         Failures := Failures + 1;
         IO.Put_Line ("  FAIL  " & Label);
      end if;
   end Check;

   procedure Check_Equal (Actual, Expected, Label : String) is
   begin
      Checks := Checks + 1;
      if Actual /= Expected then
         Failures := Failures + 1;
         IO.Put_Line ("  FAIL  " & Label);
         IO.Put_Line ("        got      " & Actual);
         IO.Put_Line ("        expected " & Expected);
      end if;
   end Check_Equal;

   function I (Text : String) return IRIs.IRI is (IRIs.From_UTF_8 (Text));
   function T (Text : String) return Terms.Term
   is (Terms.IRI_Term (I (Text)));

   XSD_String : constant String :=
     "http://www.w3.org/2001/XMLSchema#string";

   Alice : constant String := "http://example.org/alice";
   Bob   : constant String := "http://example.org/bob";
   Knows : constant String := "http://example.org/knows";
   Graph : constant String := "http://example.org/g";

   Seen  : Unbounded.Unbounded_String;

   procedure Note (Statement : Quads.Quad) is
   begin
      Unbounded.Append (Seen, Writers.Write_Quad (Statement));
      Unbounded.Append (Seen, ASCII.LF);
   end Note;

   Graphs_Seen : Natural := 0;

   procedure Note_Graph (Graph : Quads.Graph_Name) is
      pragma Unreferenced (Graph);
   begin
      Graphs_Seen := Graphs_Seen + 1;
   end Note_Graph;

begin
   IO.Put_Line ("Serialization tests");

   ------------------------------------------------------------------
   --  Terms
   ------------------------------------------------------------------
   Check_Equal (Writers.Write_Term (T (Alice)), "<" & Alice & ">",
                "an IRI term");
   Check_Equal (Writers.Write_Term (Terms.Blank_Node ("b0")), "_:b0",
                "a blank node");
   Check_Equal
     (Writers.Write_Term (Terms.Literal ("text", I (XSD_String))),
      """text""^^<" & XSD_String & ">",
      "a typed literal");
   Check_Equal
     (Writers.Write_Term (Terms.Literal ("text", I (XSD_String)),
                          Writers.Implicit_Datatype),
      """text""",
      "xsd:string omitted in the implicit style");
   Check_Equal
     (Writers.Write_Term (Terms.Literal ("7", I ("http://example.org/n")),
                          Writers.Implicit_Datatype),
      """7""^^<http://example.org/n>",
      "another datatype is never omitted");
   Check_Equal
     (Writers.Write_Term (Terms.Language_Literal ("hello", "en-US")),
      """hello""@en-us",
      "a language literal");
   Check_Equal
     (Writers.Write_Term
        (Terms.Directional_Literal ("hello", "ar", Terms.Right_To_Left)),
      """hello""@ar--rtl",
      "a directional literal");

   ------------------------------------------------------------------
   --  Escaping
   ------------------------------------------------------------------
   Check_Equal
     (Writers.Write_Term (Terms.Literal ("a""b", I (XSD_String)),
                          Writers.Implicit_Datatype),
      """a\""b""",
      "a quote is escaped");
   Check_Equal
     (Writers.Write_Term (Terms.Literal ("a\b", I (XSD_String)),
                          Writers.Implicit_Datatype),
      """a\\b""",
      "a backslash is escaped");
   Check_Equal
     (Writers.Write_Term
        (Terms.Literal ("a" & ASCII.LF & "b", I (XSD_String)),
         Writers.Implicit_Datatype),
      """a\nb""",
      "a line feed is escaped");
   Check_Equal
     (Writers.Write_Term
        (Terms.Literal ("a" & ASCII.CR & "b", I (XSD_String)),
         Writers.Implicit_Datatype),
      """a\rb""",
      "a carriage return is escaped");
   Check_Equal
     (Writers.Write_Term
        (Terms.Literal ("a" & ASCII.HT & "b", I (XSD_String)),
         Writers.Implicit_Datatype),
      """a\tb""",
      "a tab takes the short escape the canonical form names");
   Check_Equal
     (Writers.Write_Term
        (Terms.Literal ("a" & Character'Val (1) & "b", I (XSD_String)),
         Writers.Implicit_Datatype),
      """a\u0001b""",
      "a control byte becomes a numeric escape");

   --  Non-ASCII passes through, so the output is UTF-8 rather than ASCII.
   Check_Equal
     (Writers.Write_Term
        (Terms.Literal ("café", I (XSD_String)),
         Writers.Implicit_Datatype),
      """café""",
      "non-ASCII is not escaped");

   ------------------------------------------------------------------
   --  Quoted triples
   ------------------------------------------------------------------
   Check_Equal
     (Writers.Write_Term
        (Terms.Triple_Term (T (Alice), I (Knows), T (Bob))),
      "<<(<" & Alice & "> <" & Knows & "> <" & Bob & ">)>>",
      "a triple term");
   Check_Equal
     (Writers.Write_Term
        (Terms.Triple_Term
           (T (Alice), I (Knows),
            Terms.Triple_Term (T (Bob), I (Knows), T (Alice)))),
      "<<(<" & Alice & "> <" & Knows & "> <<(<" & Bob & "> <" & Knows
      & "> <" & Alice & ">)>>)>>",
      "a nested triple term");

   ------------------------------------------------------------------
   --  Statements
   ------------------------------------------------------------------
   Check_Equal
     (Writers.Write_Quad
        (Quads.Create (Quads.Default_Graph, T (Alice), I (Knows), T (Bob))),
      "<" & Alice & "> <" & Knows & "> <" & Bob & "> .",
      "a default-graph statement writes no graph");
   Check_Equal
     (Writers.Write_Quad
        (Quads.Create (Quads.IRI_Graph (I (Graph)),
                       T (Alice), I (Knows), T (Bob))),
      "<" & Alice & "> <" & Knows & "> <" & Bob & "> <" & Graph & "> .",
      "a named-graph statement writes the graph last");

   ------------------------------------------------------------------
   --  Dataset semantics
   ------------------------------------------------------------------
   declare
      Data      : Datasets.Dataset := Datasets.Empty;
      Statement : constant Quads.Quad :=
        Quads.Create (Quads.Default_Graph, T (Alice), I (Knows), T (Bob));
      Added     : Boolean;
   begin
      Check (Datasets.Is_Empty (Data), "a new dataset is empty");
      Check (Datasets.Length (Data) = 0, "a new dataset has no statements");

      Datasets.Insert (Data, Statement, Added);
      Check (Added, "the first insertion is new");
      Check (Datasets.Length (Data) = 1, "one statement after insertion");
      Check (Datasets.Contains (Data, Statement), "the statement is found");

      Datasets.Insert (Data, Statement, Added);
      Check (not Added, "re-inserting reports nothing new");
      Check (Datasets.Length (Data) = 1,
             "a dataset is a set, so the duplicate collapses");

      Check (Datasets.Graph_Count (Data) = 1, "one graph is in use");

      Datasets.Insert
        (Data,
         Quads.Create (Quads.IRI_Graph (I (Graph)),
                       T (Alice), I (Knows), T (Bob)));
      Check (Datasets.Length (Data) = 2,
             "the same statement in another graph is another statement");
      Check (Datasets.Graph_Count (Data) = 2, "two graphs are in use");

      Datasets.Delete (Data, Statement);
      Check (Datasets.Length (Data) = 1, "deletion removes one statement");
      Check (Datasets.Graph_Count (Data) = 1,
             "emptying a graph removes the graph");

      Datasets.Delete (Data, Statement);
      Check (Datasets.Length (Data) = 1,
             "deleting an absent statement changes nothing");

      Graphs_Seen := 0;
      Datasets.Iterate_Graphs (Data, Note_Graph'Access);
      Check (Graphs_Seen = 1, "graph iteration visits each graph once");

      Datasets.Clear (Data);
      Check (Datasets.Is_Empty (Data), "clearing empties the dataset");
      Check (Datasets.Graph_Count (Data) = 0, "clearing removes the graphs");
   end;

   ------------------------------------------------------------------
   --  Iteration order does not depend on insertion order
   ------------------------------------------------------------------
   declare
      Forward  : Datasets.Dataset := Datasets.Empty;
      Backward : Datasets.Dataset := Datasets.Empty;

      One : constant Quads.Quad :=
        Quads.Create (Quads.Default_Graph, T (Alice), I (Knows), T (Bob));
      Two : constant Quads.Quad :=
        Quads.Create (Quads.Default_Graph, T (Bob), I (Knows), T (Alice));
      Three : constant Quads.Quad :=
        Quads.Create (Quads.IRI_Graph (I (Graph)),
                      T (Alice), I (Knows), T (Alice));
   begin
      Datasets.Insert (Forward, One);
      Datasets.Insert (Forward, Two);
      Datasets.Insert (Forward, Three);

      Datasets.Insert (Backward, Three);
      Datasets.Insert (Backward, Two);
      Datasets.Insert (Backward, One);

      Check (Forward = Backward,
             "datasets built in either order are equal");
      Check_Equal (Datasets.To_NQuads (Backward),
                   Datasets.To_NQuads (Forward),
                   "and serialize identically");

      Seen := Unbounded.Null_Unbounded_String;
      Datasets.Iterate (Forward, Note'Access);
      Check_Equal (Unbounded.To_String (Seen),
                   Datasets.To_NQuads (Forward),
                   "iteration agrees with serialization");

      Check (Datasets.Length (Forward) = 3, "three distinct statements");
      Check (Datasets.Graph_Count (Forward) = 2, "across two graphs");
   end;

   IO.Put_Line ("  checks              " & Checks'Image);
   IO.Put_Line ("  failures            " & Failures'Image);

   if Failures = 0 then
      IO.Put_Line ("PASS serialization_tests");
   else
      IO.Put_Line ("FAIL serialization_tests");
      Ada.Command_Line.Set_Exit_Status (1);
   end if;
end Serialization_Tests;
