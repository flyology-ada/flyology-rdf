--  Exercises SPARQL parsing and serialization.
--
--  The writer normalises: keywords upper-cased, nesting indented, the
--  input's whitespace gone. That is what makes writing a query and reading
--  it back a test of the parser rather than of the formatter -- if the two
--  agree on a second pass, the tree survived the trip.

with Ada.Command_Line;
with Ada.Text_IO;
with Flyology_SPARQL.Parsers;
with Flyology_SPARQL.Syntax;
with Flyology_SPARQL.Writers;

procedure SPARQL_Tests is

   package IO renames Ada.Text_IO;
   package Parsers renames Flyology_SPARQL.Parsers;
   package Syntax renames Flyology_SPARQL.Syntax;
   package Writers renames Flyology_SPARQL.Writers;

   use type Syntax.Query_Form;
   use type Syntax.Duplicates_Kind;
   use type Syntax.Node_Reference;

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

   --  Parsing the writer's own output must give the same text again. A
   --  tree that lost something shows up as a difference on the second pass.
   procedure Check_Round_Trip (Query_Text, Label : String) is
      First  : constant String :=
        Writers.To_SPARQL (Parsers.Parse (Query_Text));
      Second : constant String :=
        Writers.To_SPARQL (Parsers.Parse (First));
   begin
      Check_Equal (Second, First, Label & " round trips");
   end Check_Round_Trip;

   procedure Check_Rejects (Query_Text, Label : String) is
      Ignored : Boolean := False;
   begin
      declare
         Result : constant Syntax.Query := Parsers.Parse (Query_Text);
      begin
         Ignored := Syntax.Form (Result) = Syntax.Select_Query;
      end;
      Check (False, Label & " must be rejected");
   exception
      when Parsers.Parse_Error =>
         Check (True, Label & " rejected");
   end Check_Rejects;

   PX : constant String :=
     "PREFIX ex: <http://example.org/>" & ASCII.LF;

begin
   IO.Put_Line ("SPARQL tests");

   ------------------------------------------------------------------
   --  Query forms
   ------------------------------------------------------------------
   declare
      Q : constant Syntax.Query :=
        Parsers.Parse ("SELECT * WHERE { ?s ?p ?o }");
   begin
      Check (Syntax.Form (Q) = Syntax.Select_Query, "SELECT is recognised");
      Check (Syntax.Selects_All (Q), "SELECT * projects everything");
      Check (Syntax.Where_Clause (Q) /= Syntax.No_Node,
             "the WHERE clause is present");
      Check (Syntax.Child_Count (Q, Syntax.Where_Clause (Q)) = 1,
             "with one pattern");
   end;

   declare
      Q : constant Syntax.Query :=
        Parsers.Parse ("ASK { ?s ?p ?o }");
   begin
      Check (Syntax.Form (Q) = Syntax.Ask_Query, "ASK is recognised");
   end;

   declare
      Q : constant Syntax.Query :=
        Parsers.Parse ("CONSTRUCT { ?s ?p ?o } WHERE { ?s ?p ?o }");
   begin
      Check (Syntax.Form (Q) = Syntax.Construct_Query,
             "CONSTRUCT is recognised");
      Check (Syntax.Template (Q) /= Syntax.No_Node,
             "and has a template");
   end;

   declare
      Q : constant Syntax.Query :=
        Parsers.Parse (PX & "DESCRIBE ex:thing");
   begin
      Check (Syntax.Form (Q) = Syntax.Describe_Query,
             "DESCRIBE is recognised");
   end;

   ------------------------------------------------------------------
   --  The prologue
   ------------------------------------------------------------------
   declare
      Q : constant Syntax.Query :=
        Parsers.Parse ("BASE <http://example.org/>" & ASCII.LF
                       & PX & "SELECT * WHERE { ?s ?p ?o }");
   begin
      Check_Equal (Syntax.Base (Q), "http://example.org/", "BASE is kept");
      Check (Syntax.Prefix_Count (Q) = 1, "one prefix is declared");
      Check_Equal (Syntax.Prefix_Name (Q, 1), "ex", "the prefix name");
      Check_Equal (Syntax.Prefix_Namespace (Q, 1), "http://example.org/",
                   "the prefix namespace");
   end;

   ------------------------------------------------------------------
   --  Keywords are not reserved
   ------------------------------------------------------------------
   Check_Round_Trip
     (PX & "SELECT ?filter WHERE { ?filter ex:p ?o }",
      "a variable named filter");
   Check_Round_Trip
     (PX & "SELECT ?select WHERE { ?select ex:graph ?o }",
      "variables and predicates named after keywords");

   --  Case-insensitivity of the keywords themselves.
   Check_Equal
     (Writers.To_SPARQL (Parsers.Parse ("select * where { ?s ?p ?o }")),
      Writers.To_SPARQL (Parsers.Parse ("SELECT * WHERE { ?s ?p ?o }")),
      "keywords are case insensitive");

   ------------------------------------------------------------------
   --  '<' is both an IRI and a comparison
   ------------------------------------------------------------------
   Check_Round_Trip
     (PX & "SELECT * WHERE { ?s ex:p ?o . FILTER (?o < 5) }",
      "less-than in a filter");
   Check_Round_Trip
     (PX & "SELECT * WHERE { ?s <http://example.org/p> ?o }",
      "an IRI in predicate position");
   Check_Round_Trip
     (PX & "SELECT * WHERE { ?s ex:p ?o . FILTER (?o <= 5 && ?o >= 1) }",
      "the comparison operators alongside an IRI");

   ------------------------------------------------------------------
   --  Patterns
   ------------------------------------------------------------------
   Check_Round_Trip
     (PX & "SELECT * WHERE { ?s ex:p ?o . OPTIONAL { ?s ex:q ?r } }",
      "OPTIONAL");
   Check_Round_Trip
     (PX & "SELECT * WHERE { { ?s ex:p ?o } UNION { ?s ex:q ?o } }",
      "UNION");
   Check_Round_Trip
     (PX & "SELECT * WHERE { ?s ex:p ?o . MINUS { ?s ex:q ?r } }",
      "MINUS");
   Check_Round_Trip
     (PX & "SELECT * WHERE { GRAPH ex:g { ?s ex:p ?o } }",
      "GRAPH");
   Check_Round_Trip
     (PX & "SELECT * WHERE { ?s ex:p ?o . BIND (?o AS ?value) }",
      "BIND");
   Check_Round_Trip
     (PX & "SELECT * WHERE { ?s ex:p ?o ; ex:q ?r , ?t }",
      "predicate and object lists");

   ------------------------------------------------------------------
   --  Expressions
   ------------------------------------------------------------------
   Check_Round_Trip
     (PX & "SELECT * WHERE { ?s ex:p ?o . FILTER (?o = 1 || ?o = 2) }",
      "disjunction");
   Check_Round_Trip
     (PX & "SELECT * WHERE { ?s ex:p ?o . FILTER (?a + ?b * ?c > 3) }",
      "arithmetic precedence");
   Check_Round_Trip
     (PX & "SELECT * WHERE { ?s ex:p ?o . FILTER (!(?o = 1)) }",
      "negation");
   Check_Round_Trip
     (PX & "SELECT * WHERE { ?s ex:p ?o . FILTER (STR(?o) = ""x"") }",
      "a built-in call");
   Check_Round_Trip
     (PX & "SELECT * WHERE { ?s ex:p ?o . FILTER (?o IN (1, 2, 3)) }",
      "IN");

   --  Precedence must be recorded, not merely accepted: multiplication
   --  binds tighter, and the written form has to show that.
   declare
      Text : constant String :=
        Writers.To_SPARQL
          (Parsers.Parse
             (PX & "SELECT * WHERE { ?s ex:p ?o . FILTER (1 + 2 * 3) }"));
   begin
      Check (Text'Length > 0, "the precedence query writes");
      Check (Writers.To_SPARQL (Parsers.Parse (Text)) = Text,
             "and reparses to the same text");
   end;

   ------------------------------------------------------------------
   --  Modifiers
   ------------------------------------------------------------------
   declare
      Q : constant Syntax.Query :=
        Parsers.Parse
          (PX & "SELECT DISTINCT ?s WHERE { ?s ex:p ?o } LIMIT 10 OFFSET 5");
   begin
      Check (Syntax.Duplicates (Q) = Syntax.Distinct_Solutions,
             "DISTINCT is recorded");
      Check (Syntax.Limit (Q) = 10, "LIMIT is recorded");
      Check (Syntax.Offset (Q) = 5, "OFFSET is recorded");
   end;

   Check_Round_Trip
     (PX & "SELECT ?s WHERE { ?s ex:p ?o } ORDER BY DESC(?o) LIMIT 5",
      "ORDER BY with a direction");
   Check_Round_Trip
     (PX & "SELECT ?s WHERE { ?s ex:p ?o } GROUP BY ?s",
      "GROUP BY");
   Check_Round_Trip
     (PX & "SELECT REDUCED ?s WHERE { ?s ex:p ?o }",
      "REDUCED");

   ------------------------------------------------------------------
   --  Property paths
   ------------------------------------------------------------------
   Check_Round_Trip
     (PX & "SELECT * WHERE { ?s ex:p/ex:q ?o }", "a sequence path");
   Check_Round_Trip
     (PX & "SELECT * WHERE { ?s ^ex:p ?o }", "an inverse path");
   Check_Round_Trip
     (PX & "SELECT * WHERE { ?s ex:p* ?o }", "a zero-or-more path");
   Check_Round_Trip
     (PX & "SELECT * WHERE { ?s ex:p+ ?o }", "a one-or-more path");

   ------------------------------------------------------------------
   --  Literals
   ------------------------------------------------------------------
   Check_Round_Trip
     (PX & "SELECT * WHERE { ?s ex:p ""text"" }", "a plain literal");
   Check_Round_Trip
     (PX & "SELECT * WHERE { ?s ex:p ""text""@en }", "a language literal");
   Check_Round_Trip
     (PX & "SELECT * WHERE { ?s ex:p ""7""^^ex:kind }", "a typed literal");
   Check_Round_Trip
     (PX & "SELECT * WHERE { ?s ex:p 42 }", "an integer literal");
   Check_Round_Trip
     (PX & "SELECT * WHERE { ?s ex:p true }", "a boolean literal");

   ------------------------------------------------------------------
   --  Rejections
   ------------------------------------------------------------------
   Check_Rejects ("", "an empty query");
   Check_Rejects ("SELECT", "SELECT with nothing after it");
   Check_Rejects ("SELECT * WHERE { ?s ?p ?o", "an unclosed group");
   Check_Rejects ("DELETE WHERE { ?s ?p ?o }",
                  "an update, which this crate does not parse");
   Check_Rejects ("SELECT * WHERE { ?s ?p ?o } EXTRA",
                  "trailing input after the query");

   IO.Put_Line ("  checks              " & Checks'Image);
   IO.Put_Line ("  failures            " & Failures'Image);

   if Failures = 0 then
      IO.Put_Line ("PASS sparql_tests");
   else
      IO.Put_Line ("FAIL sparql_tests");
      Ada.Command_Line.Set_Exit_Status (1);
   end if;
end SPARQL_Tests;
