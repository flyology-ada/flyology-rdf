--  Exercises Notation3 parsing and serialization.
--
--  The interesting cases are the ones N3 has and RDF does not: variables,
--  formulas as terms, implication in both directions, and paths -- which
--  are the odd one out, because reading a path produces statements as a
--  side effect of naming a term.

with Ada.Command_Line;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Flyology_N3.Model;
with Flyology_N3.Parsers;
with Flyology_N3.Writers;

procedure N3_Tests is

   package IO renames Ada.Text_IO;
   package Model renames Flyology_N3.Model;
   package Parsers renames Flyology_N3.Parsers;
   package Writers renames Flyology_N3.Writers;

   use type Model.Term;
   use type Model.Term_Kind;

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

   function Written (Document : String) return String
   is (Writers.To_N3 (Parsers.Parse (Document)));

   procedure Check_N3 (Document, Expected, Label : String) is
   begin
      Check_Equal (Written (Document), Expected, Label);
   end Check_N3;

   --  Writing and reading again must reach the same term, which is the
   --  strongest thing that can be said without a canonical form for
   --  formulas.
   procedure Check_Round_Trip (Document, Label : String) is
      First  : constant Model.Term := Parsers.Parse (Document);
      Second : constant Model.Term :=
        Parsers.Parse (Writers.To_N3 (First));
      Third  : constant Model.Term :=
        Parsers.Parse (Writers.To_N3 (Second));
   begin
      Check (Second = Third, Label & " reaches a fixed point");
      Check_Equal (Writers.To_N3 (Third), Writers.To_N3 (Second),
                   Label & " is byte-stable");

      --  The long forms of the verbs must read back to the same term as
      --  the shorthands, or the shorthand is not a shorthand.
      Check (Parsers.Parse (Writers.To_N3 (First, Writers.Explicit_Verbs))
             = Second,
             Label & " agrees between verb styles");
   end Check_Round_Trip;

   procedure Check_Rejects (Document, Label : String) is
      Ignored : Model.Term := Model.Empty_Formula;
   begin
      Ignored := Parsers.Parse (Document);
      Check (False, Label & " must be rejected");
      pragma Unreferenced (Ignored);
   exception
      when Parsers.Parse_Error =>
         Check (True, Label & " rejected");
   end Check_Rejects;

   EX : constant String :=
     "@prefix ex: <http://example.org/> ." & ASCII.LF;

begin
   IO.Put_Line ("N3 tests");

   ------------------------------------------------------------------
   --  What N3 shares with Turtle
   ------------------------------------------------------------------
   Check_N3 (EX & "ex:s ex:p ex:o .",
             "<http://example.org/s> <http://example.org/p> "
             & "<http://example.org/o> ." & ASCII.LF,
             "a plain statement");

   Check_N3 (EX & "ex:s a ex:Thing .",
             "<http://example.org/s> a <http://example.org/Thing> ."
             & ASCII.LF,
             "the a shorthand survives");

   Check_N3 (EX & "ex:s ex:p ""text"" .",
             "<http://example.org/s> <http://example.org/p> ""text"" ."
             & ASCII.LF,
             "a literal");

   ------------------------------------------------------------------
   --  Variables
   ------------------------------------------------------------------
   Check_N3 (EX & "?x ex:p ?y .",
             "?x <http://example.org/p> ?y ." & ASCII.LF,
             "variables in subject and object");

   declare
      Document : constant Model.Term := Parsers.Parse (EX & "?x ex:p ?y .");
      Statement : constant Model.Statement :=
        Model.Statement_At (Document, 1);
   begin
      Check (Model.Kind (Model.Subject (Statement)) = Model.Variable_Kind,
             "a variable parses as a variable");
      Check_Equal (Model.Name (Model.Subject (Statement)), "x",
                   "a variable keeps its name without the marker");
   end;

   ------------------------------------------------------------------
   --  Formulas
   ------------------------------------------------------------------
   Check_N3 (EX & "{ ex:a ex:b ex:c } ex:p ex:o .",
             "{" & ASCII.LF
             & "    <http://example.org/a> <http://example.org/b> "
             & "<http://example.org/c> ." & ASCII.LF
             & "} <http://example.org/p> <http://example.org/o> ."
             & ASCII.LF,
             "a formula as a subject");

   Check_N3 (EX & "ex:s ex:p {} .",
             "<http://example.org/s> <http://example.org/p> {} ."
             & ASCII.LF,
             "the empty formula");

   declare
      Document : constant Model.Term :=
        Parsers.Parse (EX & "{ ex:a ex:b ex:c . ex:d ex:e ex:f } ex:p ex:o .");
      Statement : constant Model.Statement :=
        Model.Statement_At (Document, 1);
      Subject   : constant Model.Term := Model.Subject (Statement);
   begin
      Check (Model.Kind (Subject) = Model.Formula_Kind,
             "a formula parses as a formula");
      Check (Model.Statement_Count (Subject) = 2,
             "and holds both of its statements");
   end;

   ------------------------------------------------------------------
   --  Implication, in both directions
   ------------------------------------------------------------------
   Check_N3 (EX & "{ ex:a ex:b ex:c } => { ex:d ex:e ex:f } .",
             "{" & ASCII.LF
             & "    <http://example.org/a> <http://example.org/b> "
             & "<http://example.org/c> ." & ASCII.LF
             & "} => {" & ASCII.LF
             & "    <http://example.org/d> <http://example.org/e> "
             & "<http://example.org/f> ." & ASCII.LF
             & "} ." & ASCII.LF,
             "forward implication");

   --  "A <= B" and "B => A" state the same thing, so they must produce the
   --  same term rather than two predicates that happen to look alike.
   Check_Equal
     (Written (EX & "{ ex:a ex:b ex:c } <= { ex:d ex:e ex:f } ."),
      Written (EX & "{ ex:d ex:e ex:f } => { ex:a ex:b ex:c } ."),
      "reverse implication is forward implication with the sides swapped");

   Check_N3 (EX & "ex:a = ex:b .",
             "<http://example.org/a> = <http://example.org/b> ." & ASCII.LF,
             "equality");

   ------------------------------------------------------------------
   --  Lists are terms, not chains
   ------------------------------------------------------------------
   Check_N3 (EX & "ex:s ex:p ( ex:a ex:b ) .",
             "<http://example.org/s> <http://example.org/p> "
             & "( <http://example.org/a> <http://example.org/b> ) ."
             & ASCII.LF,
             "a list stays a list");

   declare
      Document : constant Model.Term :=
        Parsers.Parse (EX & "ex:s ex:p ( ex:a ex:b ) .");
      Object : constant Model.Term :=
        Model.Object (Model.Statement_At (Document, 1));
   begin
      Check (Model.Kind (Object) = Model.List_Kind,
             "a list parses as a list rather than an rdf:List chain");
      Check (Model.Length (Object) = 2, "with both of its elements");
   end;

   ------------------------------------------------------------------
   --  Paths, which produce statements while naming a term
   ------------------------------------------------------------------
   declare
      Document : constant Model.Term :=
        Parsers.Parse (EX & "ex:a!ex:b ex:p ex:o .");
   begin
      --  ":a!:b :p :o" says two things: something is the :b of :a, and
      --  that something has :p of :o.
      Check (Model.Statement_Count (Document) = 2,
             "a forward path adds a statement");
   end;

   declare
      Document : constant Model.Term :=
        Parsers.Parse (EX & "ex:a^ex:b ex:p ex:o .");
   begin
      Check (Model.Statement_Count (Document) = 2,
             "a backward path adds a statement");
   end;

   ------------------------------------------------------------------
   --  Round trips
   ------------------------------------------------------------------
   Check_Round_Trip (EX & "ex:s ex:p ex:o .", "a plain statement");
   Check_Round_Trip (EX & "?x ex:p ?y .", "variables");
   Check_Round_Trip (EX & "{ ex:a ex:b ?x } => { ex:c ex:d ?x } .",
                     "an implication over a variable");
   Check_Round_Trip (EX & "ex:s ex:p ( ex:a ( ex:b ex:c ) ) .",
                     "a nested list");
   Check_Round_Trip (EX & "ex:s ex:p { ex:a ex:b { ex:c ex:d ex:e } } .",
                     "a nested formula");
   Check_Round_Trip (EX & "ex:s ex:p ex:o ; ex:q ex:r .",
                     "a predicate-object list");
   Check_Round_Trip (EX & "ex:s ex:p [ ex:q ex:r ] .",
                     "a blank node property list");

   ------------------------------------------------------------------
   --  Rejections
   ------------------------------------------------------------------
   Check_Rejects (EX & "ex:s ex:p", "a statement with no object");
   Check_Rejects (EX & "{ ex:a ex:b ex:c ", "an unclosed formula");
   Check_Rejects (EX & "ex:s ex:p ( ex:a ", "an unclosed list");
   Check_Rejects ("ex:s ex:p ex:o .", "an undefined prefix");
   Check_Rejects ("<relative> <p> <o> .", "a relative IRI with no base");

   ------------------------------------------------------------------
   --  Regressions: defects found by review, kept fixed
   ------------------------------------------------------------------

   --  A bare "_:" is an unnamed existential, not an error.
   Check_N3 (EX & "_: ex:p ex:o .",
             "_:b1 <http://example.org/p> <http://example.org/o> ."
             & ASCII.LF,
             "a bare label reads as an unnamed existential");

   --  A literal the model refuses fails as a parse error, not as an
   --  exception the contract does not name.
   Check_Rejects (EX & "ex:s ex:p ""x""@en-abcdefghi .",
                  "an overlong language subtag");

   --  Nesting past the model's bound is a parse error on the way in,
   --  and a document that is nothing but open braces cannot exhaust
   --  the stack -- while formulas that stay empty may nest deeper
   --  than any term, which the corpus relies on.
   declare
      package SU renames Ada.Strings.Unbounded;

      function Nested (Levels : Natural) return String is
         Buffer : SU.Unbounded_String;
      begin
         for Ignored in 1 .. Levels loop
            SU.Append (Buffer, "{ <http://a> <http://b> ");
         end loop;
         SU.Append (Buffer, "<http://c>");
         for Ignored in 1 .. Levels loop
            SU.Append (Buffer, " }");
         end loop;
         SU.Append (Buffer, " .");
         return SU.To_String (Buffer);
      end Nested;

      Empty_Deep : SU.Unbounded_String;
   begin
      Check_Rejects (Nested (140), "nesting past the model's bound");
      Check_Rejects (Nested (60_000), "unbounded nesting");

      for Ignored in 1 .. 1_100 loop
         SU.Append (Empty_Deep, "{");
      end loop;
      for Ignored in 1 .. 1_100 loop
         SU.Append (Empty_Deep, "}");
      end loop;
      SU.Append (Empty_Deep, " .");
      Check_Equal
        (Written (SU.To_String (Empty_Deep)), "",
         "empty formulas may nest deeper than any term");
   end;

   IO.Put_Line ("  checks              " & Checks'Image);
   IO.Put_Line ("  failures            " & Failures'Image);

   if Failures = 0 then
      IO.Put_Line ("PASS n3_tests");
   else
      IO.Put_Line ("FAIL n3_tests");
      Ada.Command_Line.Set_Exit_Status (1);
   end if;
end N3_Tests;
