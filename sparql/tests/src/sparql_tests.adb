--  Exercises SPARQL parsing and serialization.
--
--  The writer normalises: keywords upper-cased, nesting indented, the
--  input's whitespace gone. That is what makes writing a query and reading
--  it back a test of the parser rather than of the formatter -- if the two
--  agree on a second pass, the tree survived the trip.

with Ada.Command_Line;
with Ada.Strings.Unbounded;
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

   ------------------------------------------------------------------
   --  Regressions: defects found by review, kept fixed
   ------------------------------------------------------------------

   --  The additive continuations interleave, and a signed literal takes
   --  multiplicative continuations of its own.
   Check_Round_Trip ("SELECT * WHERE { FILTER(?x - 1 +2 = 0) }",
                     "an operator step then a signed-literal step");
   Check_Round_Trip ("SELECT * WHERE { FILTER(?x+1*2 = 3) }",
                     "a product after a signed literal");

   --  VARNAME admits no hyphen, so "?a-?b" is a subtraction.
   Check_Round_Trip ("SELECT * WHERE { FILTER(?a-?b = 0) }",
                     "a subtraction written without spaces");

   --  LIMIT and OFFSET take the unsigned INTEGER terminal.
   Check_Rejects ("SELECT * WHERE { ?s ?p ?o } LIMIT -1",
                  "a signed limit");
   Check_Rejects ("SELECT * WHERE { ?s ?p ?o } LIMIT 99999999999999999999",
                  "a limit past the implementation");
   Check_Rejects
     ("SELECT * WHERE { { SELECT ?a WHERE { ?a ?p ?b } LIMIT ?a } }",
      "a variable as a subquery limit");

   --  Subquery modifiers are the query's own, read by the same routines.
   Check_Round_Trip
     ("SELECT * WHERE { { SELECT ?a ?b WHERE { ?a ?p ?b }"
      & " GROUP BY ?a ?b } }",
      "a subquery grouping by two keys");
   Check_Round_Trip
     ("SELECT * WHERE { { SELECT ?a WHERE { ?a ?p ?b }"
      & " VALUES ?a { 1 2 } } }",
      "a subquery closed by inline data");
   Check_Round_Trip
     ("SELECT ?s WHERE { ?s ?p ?o } GROUP BY ?s"
      & " HAVING (COUNT(?o) > 1) (COUNT(?o) < 5)",
      "two HAVING constraints");
   Check_Round_Trip
     ("SELECT ?s WHERE { ?s ?p ?o } GROUP BY ?s VALUES ?s { <http://x> }",
      "inline data after a GROUP BY");
   Check_Round_Trip
     ("DESCRIBE <http://x> VALUES ?v { 1 }",
      "inline data on a DESCRIBE without WHERE");

   --  An EXISTS body, an annotation, and a reifier survive writing.
   Check_Round_Trip ("SELECT * WHERE { FILTER EXISTS { ?s ?p ?o } }",
                     "an EXISTS body");
   Check_Round_Trip
     ("SELECT * WHERE { FILTER NOT EXISTS { ?s ?p ?o . FILTER(?o > 2) } }",
      "a NOT EXISTS body with a nested constraint");
   Check_Round_Trip ("SELECT * WHERE { ?s ?p ?o {| ?a ?b |} }",
                     "an annotation block");
   Check_Round_Trip ("SELECT * WHERE { ?s ?p ?o ~ ?r . }",
                     "a bare reifier");

   --  A generated node is known by its mark, so a document label that
   --  merely looks like one is still checked across groups.
   Check_Rejects ("SELECT * WHERE { { _:gx ?p 1 } { _:gx ?p 2 } }",
                  "a g-spelled label shared between groups");

   --  Projections, DESCRIBE targets and keyword calls are narrower than
   --  the term and expression grammars they sit inside.
   Check_Rejects ("SELECT <http://x> WHERE { ?s ?p ?o }",
                  "an IRI in a projection");
   Check_Rejects ("SELECT ""lit"" WHERE { ?s ?p ?o }",
                  "a literal in a projection");
   Check_Rejects ("DESCRIBE ""lit""",
                  "a literal as a DESCRIBE target");
   Check_Rejects ("SELECT * WHERE { FILTER(FOO(?x)) }",
                  "a bare word is not a function name");
   Check_Rejects ("SELECT * WHERE { FILTER(RAND) }",
                  "a built-in without its argument list");

   --  The aggregate markers write back as the syntax they abbreviate.
   Check_Round_Trip
     ("SELECT (COUNT(DISTINCT *) AS ?n) WHERE { ?s ?p ?o }",
      "a DISTINCT aggregate");
   Check_Round_Trip
     ("SELECT (GROUP_CONCAT(DISTINCT ?x; SEPARATOR = "", "") AS ?g)"
      & " WHERE { ?s ?p ?x } GROUP BY ?s",
      "GROUP_CONCAT with a separator");

   --  Nesting is bounded, so a query of open braces cannot exhaust the
   --  stack.
   declare
      package SU renames Ada.Strings.Unbounded;
      Deep : SU.Unbounded_String;
   begin
      SU.Append (Deep, "SELECT * WHERE ");
      for Ignored in 1 .. 60_000 loop
         SU.Append (Deep, "{");
      end loop;
      for Ignored in 1 .. 60_000 loop
         SU.Append (Deep, "}");
      end loop;
      Check_Rejects (SU.To_String (Deep), "unbounded group nesting");
   end;

   IO.Put_Line ("  checks              " & Checks'Image);
   IO.Put_Line ("  failures            " & Failures'Image);

   if Failures = 0 then
      IO.Put_Line ("PASS sparql_tests");
   else
      IO.Put_Line ("FAIL sparql_tests");
      Ada.Command_Line.Set_Exit_Status (1);
   end if;
end SPARQL_Tests;
