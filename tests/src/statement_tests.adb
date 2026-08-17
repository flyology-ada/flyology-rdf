--  Exercises triples, graph names, and quads.
--
--  The point of interest is that every component is reachable two ways --
--  by copying selector and by borrowing callback -- and the two must agree.
--  A borrow that returned something different from its selector would be a
--  silent correctness hole, since callers pick between them for performance
--  reasons and expect no semantic difference.

with Ada.Command_Line;
with Ada.Text_IO;
with Flyology_RDF.IRIs;
with Flyology_RDF.Quads;
with Flyology_RDF.Terms;
with Flyology_RDF.Triples;

procedure Statement_Tests is

   package IO renames Ada.Text_IO;
   package IRIs renames Flyology_RDF.IRIs;
   package Quads renames Flyology_RDF.Quads;
   package Terms renames Flyology_RDF.Terms;
   package Triples renames Flyology_RDF.Triples;

   use type IRIs.IRI;
   use type Quads.Graph_Name;
   use type Quads.Graph_Name_Kind;
   use type Quads.Quad;
   use type Terms.Term;
   use type Triples.Triple;

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

   function Alice return IRIs.IRI is
     (IRIs.From_UTF_8 ("http://example.org/alice"));
   function Bob return IRIs.IRI is
     (IRIs.From_UTF_8 ("http://example.org/bob"));
   function Knows return IRIs.IRI is
     (IRIs.From_UTF_8 ("http://xmlns.com/foaf/0.1/knows"));
   function Graph_One return IRIs.IRI is
     (IRIs.From_UTF_8 ("http://example.org/g1"));

   Borrow_Matched : Boolean := False;
   Borrow_Count   : Natural := 0;

   procedure Triple_Borrow
     (Subject   : Terms.Term;
      Predicate : IRIs.IRI;
      Object    : Terms.Term) is
   begin
      Borrow_Count := Borrow_Count + 1;
      Borrow_Matched :=
        Subject = Terms.IRI_Term (Alice)
        and then Predicate = Knows
        and then Object = Terms.IRI_Term (Bob);
   end Triple_Borrow;

   procedure Quad_Borrow
     (Graph     : Quads.Graph_Name;
      Subject   : Terms.Term;
      Predicate : IRIs.IRI;
      Object    : Terms.Term) is
   begin
      Borrow_Count := Borrow_Count + 1;
      Borrow_Matched :=
        Graph = Quads.IRI_Graph (Graph_One)
        and then Subject = Terms.IRI_Term (Alice)
        and then Predicate = Knows
        and then Object = Terms.IRI_Term (Bob);
   end Quad_Borrow;

   Name_Seen : Boolean := False;

   procedure Note_Name (Name : Terms.Term) is
   begin
      Name_Seen := Name = Terms.Blank_Node ("g");
   end Note_Name;

begin
   IO.Put_Line ("Statement tests");

   ------------------------------------------------------------------
   --  Triples
   ------------------------------------------------------------------
   declare
      Statement : constant Triples.Triple :=
        Triples.Create (Terms.IRI_Term (Alice), Knows, Terms.IRI_Term (Bob));
   begin
      Check (Triples.Subject (Statement) = Terms.IRI_Term (Alice),
             "triple subject");
      Check (Triples.Predicate (Statement) = Knows, "triple predicate");
      Check (Triples.Object (Statement) = Terms.IRI_Term (Bob),
             "triple object");

      Borrow_Matched := False;
      Borrow_Count := 0;
      Triples.Query_Components (Statement, Triple_Borrow'Access);
      Check (Borrow_Count = 1, "triple borrow runs exactly once");
      Check (Borrow_Matched, "triple borrow agrees with the selectors");

      Check (Statement = Triples.Create
               (Terms.IRI_Term (Alice), Knows, Terms.IRI_Term (Bob)),
             "triple equality");
      Check (Statement /= Triples.Create
               (Terms.IRI_Term (Bob), Knows, Terms.IRI_Term (Alice)),
             "triple inequality when subject and object swap");
   end;

   --  A quoted triple in object position is an ordinary term here.
   declare
      Quoted : constant Terms.Term :=
        Terms.Triple_Term (Terms.IRI_Term (Alice), Knows,
                           Terms.IRI_Term (Bob));
      Statement : constant Triples.Triple :=
        Triples.Create
          (Terms.Blank_Node ("witness"),
           IRIs.From_UTF_8 ("http://example.org/said"),
           Quoted);
   begin
      Check (Triples.Object (Statement) = Quoted,
             "quoted triple survives as an object");
   end;

   ------------------------------------------------------------------
   --  Graph names
   ------------------------------------------------------------------
   Check (Quads.Kind (Quads.Default_Graph) = Quads.Default_Graph_Kind,
          "default graph kind");
   Check (Quads.Kind (Quads.IRI_Graph (Graph_One)) = Quads.IRI_Graph_Kind,
          "IRI graph kind");
   Check (Quads.Kind (Quads.Blank_Node_Graph (Terms.Blank_Node ("g")))
            = Quads.Blank_Node_Graph_Kind,
          "blank node graph kind");

   Check (Quads.Default_Graph = Quads.Default_Graph,
          "default graph equals itself");
   Check (Quads.Default_Graph /= Quads.IRI_Graph (Graph_One),
          "default graph differs from a named graph");
   Check (Quads.IRI_Graph (Graph_One) = Quads.IRI_Graph (Graph_One),
          "IRI graph equality");

   Check (Quads.Name_Term (Quads.IRI_Graph (Graph_One))
            = Terms.IRI_Term (Graph_One),
          "IRI graph naming term");

   Name_Seen := False;
   Quads.Query_Name_Term
     (Quads.Blank_Node_Graph (Terms.Blank_Node ("g")), Note_Name'Access);
   Check (Name_Seen, "graph name borrow agrees with the selector");

   declare
      Ignored : Quads.Graph_Name := Quads.Default_Graph;
   begin
      Ignored := Quads.Blank_Node_Graph (Terms.IRI_Term (Alice));
      Check (False, "an IRI term must not name a blank node graph");
      pragma Unreferenced (Ignored);
   exception
      when Terms.Invalid_Term =>
         Check (True, "an IRI term rejected as a blank node graph name");
   end;

   declare
      Ignored : Terms.Term := Terms.IRI_Term (Alice);
   begin
      Ignored := Quads.Name_Term (Quads.Default_Graph);
      Check (False, "the default graph must have no naming term");
      pragma Unreferenced (Ignored);
   exception
      when Terms.Invalid_Term =>
         Check (True, "the default graph has no naming term");
   end;

   ------------------------------------------------------------------
   --  Quads
   ------------------------------------------------------------------
   declare
      Statement : constant Triples.Triple :=
        Triples.Create (Terms.IRI_Term (Alice), Knows, Terms.IRI_Term (Bob));
      From_Parts : constant Quads.Quad :=
        Quads.Create (Quads.IRI_Graph (Graph_One),
                      Terms.IRI_Term (Alice), Knows, Terms.IRI_Term (Bob));
      From_Triple : constant Quads.Quad :=
        Quads.Create (Quads.IRI_Graph (Graph_One), Statement);
   begin
      Check (From_Parts = From_Triple,
             "both constructors build the same quad");
      Check (Quads.Graph (From_Parts) = Quads.IRI_Graph (Graph_One),
             "quad graph");
      Check (Quads.Statement (From_Parts) = Statement, "quad statement");
      Check (Quads.Subject (From_Parts) = Terms.IRI_Term (Alice),
             "quad subject");
      Check (Quads.Predicate (From_Parts) = Knows, "quad predicate");
      Check (Quads.Object (From_Parts) = Terms.IRI_Term (Bob),
             "quad object");

      Borrow_Matched := False;
      Borrow_Count := 0;
      Quads.Query_Components (From_Parts, Quad_Borrow'Access);
      Check (Borrow_Count = 1, "quad borrow runs exactly once");
      Check (Borrow_Matched, "quad borrow agrees with the selectors");

      --  The graph is part of a quad's identity: the same statement in two
      --  graphs is two quads.
      Check (From_Parts /= Quads.Create (Quads.Default_Graph, Statement),
             "the graph participates in quad equality");
   end;

   IO.Put_Line ("  checks              " & Checks'Image);
   IO.Put_Line ("  failures            " & Failures'Image);

   if Failures = 0 then
      IO.Put_Line ("PASS statement_tests");
   else
      IO.Put_Line ("FAIL statement_tests");
      Ada.Command_Line.Set_Exit_Status (1);
   end if;
end Statement_Tests;
