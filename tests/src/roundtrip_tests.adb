--  Exercises the line-based grammars and the write-then-read round trip.
--
--  Round-tripping is where a writer and a reader check each other. Note
--  what it can and cannot show here: blank node labels are arbitrary, and a
--  reader is entitled to rename them, so identity of labels is not an RDF
--  property and is not asserted. A document without blank nodes must survive
--  exactly; a document with them must survive in shape and then stay put,
--  which catches drift without claiming more than RDF guarantees. Deciding
--  the general case needs canonicalization.

with Ada.Command_Line;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Flyology_RDF.Datasets;
with Flyology_RDF.Quads;
with Flyology_RDF.Turtle_Parsers;

procedure Roundtrip_Tests is

   package IO renames Ada.Text_IO;
   package Unbounded renames Ada.Strings.Unbounded;
   package Datasets renames Flyology_RDF.Datasets;
   package Quads renames Flyology_RDF.Quads;
   package Parsers renames Flyology_RDF.Turtle_Parsers;

   use type Datasets.Dataset;
   use type Parsers.Parse_Status;
   use type Parsers.Diagnostic_Code;

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

   type Builder is limited new Parsers.Event_Sink with record
      Data      : Datasets.Dataset := Datasets.Empty;
      Diagnosed : Boolean := False;
      Last_Code : Parsers.Diagnostic_Code := Parsers.Malformed_Syntax;
   end record;

   overriding procedure On_Graph_Declaration
     (Target : in out Builder;
      Graph  : Quads.Graph_Name;
      Span   : Parsers.Source_Span) is null;

   overriding procedure On_Quad
     (Target : in out Builder;
      Value  : Quads.Quad;
      Span   : Parsers.Source_Span);

   overriding procedure On_Diagnostic
     (Target : in out Builder;
      Value  : Parsers.Parse_Diagnostic);

   overriding procedure On_Quad
     (Target : in out Builder;
      Value  : Quads.Quad;
      Span   : Parsers.Source_Span)
   is
      pragma Unreferenced (Span);
   begin
      Datasets.Insert (Target.Data, Value);
   end On_Quad;

   overriding procedure On_Diagnostic
     (Target : in out Builder;
      Value  : Parsers.Parse_Diagnostic) is
   begin
      Target.Diagnosed := True;
      Target.Last_Code := Parsers.Code (Value);
   end On_Diagnostic;

   procedure Load
     (Document  : String;
      Syntax    : Parsers.Syntax_Kind;
      Data      : out Datasets.Dataset;
      Succeeded : out Boolean;
      Diagnosis : out Parsers.Diagnostic_Code)
   is
      Sink   : Builder;
      Parser : Parsers.Parser :=
        Parsers.Create (Source_Name => "test", Syntax => Syntax);
   begin
      Parsers.Feed (Parser, Document, Sink);
      Succeeded := Parsers.Finish (Parser, Sink) = Parsers.Parse_Succeeded;
      Data := Sink.Data;
      Diagnosis := Sink.Last_Code;
   end Load;

   procedure Check_NQuads (Document, Expected, Label : String;
                           Syntax : Parsers.Syntax_Kind :=
                             Parsers.NQuads_Syntax) is
      Data      : Datasets.Dataset;
      Succeeded : Boolean;
      Diagnosis : Parsers.Diagnostic_Code;
   begin
      Load (Document, Syntax, Data, Succeeded, Diagnosis);
      Check (Succeeded, Label & " (parses)");
      Check_Equal (Datasets.To_NQuads (Data), Expected, Label);
   end Check_NQuads;

   procedure Check_Rejects
     (Document, Label : String;
      Syntax   : Parsers.Syntax_Kind := Parsers.NQuads_Syntax;
      Expected : Parsers.Diagnostic_Code := Parsers.Malformed_Syntax)
   is
      Data      : Datasets.Dataset;
      Succeeded : Boolean;
      Diagnosis : Parsers.Diagnostic_Code;
   begin
      Load (Document, Syntax, Data, Succeeded, Diagnosis);
      Check (not Succeeded, Label & " (rejected)");
      Check (Diagnosis = Expected,
             Label & " (diagnostic is "
             & Parsers.Diagnostic_Code'Image (Expected) & ", got "
             & Parsers.Diagnostic_Code'Image (Diagnosis) & ")");
   end Check_Rejects;

   S : constant String := "<http://example.org/s>";
   P : constant String := "<http://example.org/p>";
   O : constant String := "<http://example.org/o>";
   G : constant String := "<http://example.org/g>";

begin
   IO.Put_Line ("Round-trip tests");

   ------------------------------------------------------------------
   --  N-Triples and N-Quads
   ------------------------------------------------------------------
   Check_NQuads (S & " " & P & " " & O & " .",
                 S & " " & P & " " & O & " ." & ASCII.LF,
                 "a bare N-Triples statement");

   Check_NQuads (S & " " & P & " " & O & " " & G & " .",
                 S & " " & P & " " & O & " " & G & " ." & ASCII.LF,
                 "an N-Quads statement with a graph label");

   Check_NQuads
     (S & " " & P & " ""text"" ." & ASCII.LF
      & S & " " & P & " ""tagged""@en ." & ASCII.LF,
      S & " " & P & " ""tagged""@en ." & ASCII.LF
      & S & " " & P & " ""text""^^" &
      "<http://www.w3.org/2001/XMLSchema#string> ." & ASCII.LF,
      "literals, with output in serialization order");

   Check_NQuads
     (S & " " & P & " <<( " & S & " " & P & " " & O & " )>> .",
      S & " " & P & " <<(" & S & " " & P & " " & O & ")>> ." & ASCII.LF,
      "a triple term");

   Check_NQuads (S & " " & P & " " & O & " ." & ASCII.LF
                 & S & " " & P & " " & O & " ." & ASCII.LF,
                 S & " " & P & " " & O & " ." & ASCII.LF,
                 "a repeated statement collapses");

   ------------------------------------------------------------------
   --  The line grammars admit nothing the general one does
   ------------------------------------------------------------------
   Check_Rejects ("@prefix ex: <http://example.org/> ." & ASCII.LF
                  & "ex:s ex:p ex:o .",
                  "a prefix directive is not N-Quads");
   Check_Rejects (S & " a " & O & " .", "the a keyword is not N-Quads");
   Check_Rejects (S & " " & P & " ( " & O & " ) .",
                  "a collection is not N-Quads");
   Check_Rejects (S & " " & P & " [ " & P & " " & O & " ] .",
                  "a property list is not N-Quads");
   Check_Rejects (S & " " & P & " " & O & " ; " & P & " " & O & " .",
                  "a predicate-object list is not N-Quads");
   Check_Rejects ("<relative> " & P & " " & O & " .",
                  "a relative IRI is not N-Quads", Parsers.NQuads_Syntax,
                  Parsers.Invalid_IRI);
   Check_Rejects ("""literal"" " & P & " " & O & " .",
                  "a literal is not a subject");
   Check_Rejects (S & " ""literal"" " & O & " .",
                  "a literal is not a predicate");
   Check_Rejects (S & " " & P & " " & O & " " & G & " .",
                  "a graph label is not N-Triples",
                  Parsers.NTriples_Syntax, Parsers.Unsupported_Production);

   ------------------------------------------------------------------
   --  Write, then read back
   ------------------------------------------------------------------
   declare
      Turtle : constant String :=
        "@prefix ex: <http://example.org/> ." & ASCII.LF
        & "ex:s a ex:Thing ;" & ASCII.LF
        & "  ex:p ""text""@en-US , 42 ;" & ASCII.LF
        & "  ex:q <<( ex:a ex:b ex:c )>> ." & ASCII.LF
        & "GRAPH ex:g { ex:x ex:y ex:z }" & ASCII.LF;

      First, Second : Datasets.Dataset;
      Ok_First, Ok_Second : Boolean;
      Code_First, Code_Second : Parsers.Diagnostic_Code;
   begin
      Load (Turtle, Parsers.TriG_Syntax, First, Ok_First, Code_First);
      Check (Ok_First, "the source document parses");
      Check (Datasets.Length (First) = 5, "five statements");
      Check (Datasets.Graph_Count (First) = 2, "across two graphs");

      Load (Datasets.To_NQuads (First), Parsers.NQuads_Syntax,
            Second, Ok_Second, Code_Second);
      Check (Ok_Second, "its N-Quads output parses back");
      Check (First = Second,
             "a blank-node-free document round trips exactly");
      Check_Equal (Datasets.To_NQuads (Second), Datasets.To_NQuads (First),
                   "and serializes identically");
   end;

   ------------------------------------------------------------------
   --  With blank nodes: shape is preserved, and then it stays put
   ------------------------------------------------------------------
   declare
      Turtle : constant String :=
        "@prefix ex: <http://example.org/> ." & ASCII.LF
        & "ex:s ex:p [ ex:q ""nested"" ] , ( ex:a ex:b ) ." & ASCII.LF
        & "_:external ex:r ex:t ." & ASCII.LF;

      First, Second, Third : Datasets.Dataset;
      Ok : Boolean;
      Ignored : Parsers.Diagnostic_Code;
   begin
      Load (Turtle, Parsers.TriG_Syntax, First, Ok, Ignored);
      Check (Ok, "the blank-node document parses");

      Load (Datasets.To_NQuads (First), Parsers.NQuads_Syntax,
            Second, Ok, Ignored);
      Check (Ok, "its N-Quads output parses back");
      Check (Datasets.Length (Second) = Datasets.Length (First),
             "the statement count survives the round trip");
      Check (Datasets.Graph_Count (Second) = Datasets.Graph_Count (First),
             "the graph count survives the round trip");

      --  Labels may be renamed once, on the way in. They must not keep
      --  moving: a second round trip has to be a fixed point.
      Load (Datasets.To_NQuads (Second), Parsers.NQuads_Syntax,
            Third, Ok, Ignored);
      Check (Ok, "the second round trip parses");
      Check (Second = Third, "the round trip reaches a fixed point");
      Check_Equal (Datasets.To_NQuads (Third), Datasets.To_NQuads (Second),
                   "and is byte-stable thereafter");
   end;

   IO.Put_Line ("  checks              " & Checks'Image);
   IO.Put_Line ("  failures            " & Failures'Image);

   if Failures = 0 then
      IO.Put_Line ("PASS roundtrip_tests");
   else
      IO.Put_Line ("FAIL roundtrip_tests");
      Ada.Command_Line.Set_Exit_Status (1);
   end if;
end Roundtrip_Tests;
