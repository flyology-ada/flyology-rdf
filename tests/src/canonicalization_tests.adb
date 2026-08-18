--  Exercises RDFC-1.0 canonicalization.
--
--  The property under test is the one nothing else in this crate could
--  decide: two datasets that differ only in what their blank nodes are
--  called must produce identical bytes, and two that differ in any other
--  way must not. The symmetric cases matter most -- a cycle of blank nodes
--  is exactly the shape that first-degree hashing cannot separate, so it is
--  what forces the expensive path to be exercised rather than skipped.

with Ada.Command_Line;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Flyology_RDF.Canonicalization;
with Flyology_RDF.Datasets;
with Flyology_RDF.Digests;
with Flyology_RDF.Quads;
with Flyology_RDF.Turtle_Parsers;

procedure Canonicalization_Tests is

   package IO renames Ada.Text_IO;
   package Unbounded renames Ada.Strings.Unbounded;
   package Canon renames Flyology_RDF.Canonicalization;
   package Datasets renames Flyology_RDF.Datasets;
   package Digests renames Flyology_RDF.Digests;
   package Quads renames Flyology_RDF.Quads;
   package Parsers renames Flyology_RDF.Turtle_Parsers;

   use type Canon.Result_Status;

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
      Data : Datasets.Dataset := Datasets.Empty;
   end record;

   overriding procedure On_Graph_Declaration
     (Target : in out Builder;
      Graph  : Quads.Graph_Name;
      Span   : Parsers.Source_Span) is null;

   overriding procedure On_Diagnostic
     (Target : in out Builder;
      Value  : Parsers.Parse_Diagnostic) is null;

   overriding procedure On_Quad
     (Target : in out Builder;
      Value  : Quads.Quad;
      Span   : Parsers.Source_Span);

   overriding procedure On_Quad
     (Target : in out Builder;
      Value  : Quads.Quad;
      Span   : Parsers.Source_Span)
   is
      pragma Unreferenced (Span);
   begin
      Datasets.Insert (Target.Data, Value);
   end On_Quad;

   function Load (Document : String) return Datasets.Dataset is
      Sink   : Builder;
      Parser : Parsers.Parser :=
        Parsers.Create
          (Source_Name => "test", Syntax => Parsers.NQuads_Syntax);
      Ignored : Parsers.Parse_Status;
   begin
      Parsers.Feed (Parser, Document, Sink);
      Ignored := Parsers.Finish (Parser, Sink);
      return Sink.Data;
   end Load;

   function Canonical (Document : String) return String
   is (Canon.To_Canonical_NQuads (Load (Document)));

   P  : constant String := "<http://example.org/p>";
   Q  : constant String := "<http://example.org/q>";
   O1 : constant String := "<http://example.org/o1>";
   O2 : constant String := "<http://example.org/o2>";
   NL : constant Character := ASCII.LF;

begin
   IO.Put_Line ("Canonicalization tests");

   ------------------------------------------------------------------
   --  The digest the specification names
   ------------------------------------------------------------------
   Check_Equal
     (Digests.SHA_256 (""),
      "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
      "SHA-256 of the empty string");
   Check_Equal
     (Digests.SHA_256 ("abc"),
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
      "SHA-256 of abc");

   ------------------------------------------------------------------
   --  No blank nodes: canonicalization is just sorted N-Quads
   ------------------------------------------------------------------
   Check_Equal
     (Canonical ("<http://example.org/s> " & P & " " & O1 & " ."),
      "<http://example.org/s> " & P & " " & O1 & " ." & NL,
      "a ground statement is unchanged");

   ------------------------------------------------------------------
   --  Blank node relabelling is invisible
   ------------------------------------------------------------------
   Check_Equal
     (Canonical ("_:a " & P & " " & O1 & " ."),
      "_:c14n0 " & P & " " & O1 & " ." & NL,
      "a lone blank node becomes c14n0");

   Check_Equal
     (Canonical ("_:zzz " & P & " " & O1 & " ."),
      Canonical ("_:a " & P & " " & O1 & " ."),
      "the input label does not survive");

   --  Distinguishable by their surroundings alone.
   Check_Equal
     (Canonical ("_:a " & P & " " & O1 & " ." & NL
                 & "_:b " & P & " " & O2 & " ."),
      Canonical ("_:x " & P & " " & O1 & " ." & NL
                 & "_:y " & P & " " & O2 & " ."),
      "two distinguishable blank nodes canonicalize alike");

   --  Order of presentation must not matter.
   Check_Equal
     (Canonical ("_:b " & P & " " & O2 & " ." & NL
                 & "_:a " & P & " " & O1 & " ."),
      Canonical ("_:a " & P & " " & O1 & " ." & NL
                 & "_:b " & P & " " & O2 & " ."),
      "statement order does not matter");

   ------------------------------------------------------------------
   --  Symmetric shapes: the case first-degree hashing cannot settle
   ------------------------------------------------------------------
   Check_Equal
     (Canonical ("_:a " & P & " _:b ." & NL & "_:b " & P & " _:a ."),
      Canonical ("_:x " & P & " _:y ." & NL & "_:y " & P & " _:x ."),
      "a two-cycle of blank nodes canonicalizes alike");

   Check_Equal
     (Canonical ("_:a " & P & " _:b ." & NL
                 & "_:b " & P & " _:c ." & NL
                 & "_:c " & P & " _:a ."),
      Canonical ("_:p " & P & " _:q ." & NL
                 & "_:q " & P & " _:r ." & NL
                 & "_:r " & P & " _:p ."),
      "a three-cycle canonicalizes alike");

   --  Twins: two blank nodes with identical surroundings. They cannot be
   --  told apart, and must not be conflated either.
   declare
      Twins : constant String :=
        "_:a " & P & " " & O1 & " ." & NL
        & "_:b " & P & " " & O1 & " .";
   begin
      Check_Equal
        (Canonical (Twins),
         "_:c14n0 " & P & " " & O1 & " ." & NL
         & "_:c14n1 " & P & " " & O1 & " ." & NL,
         "indistinguishable twins both get labels");
      Check_Equal (Canonical (Twins), Canonical (Twins),
                   "and the result is stable");
   end;

   ------------------------------------------------------------------
   --  Different datasets must not collide
   ------------------------------------------------------------------
   Check
     (Canonical ("_:a " & P & " " & O1 & " .")
      /= Canonical ("_:a " & P & " " & O2 & " ."),
      "a different object gives a different canonical form");

   Check
     (Canonical ("_:a " & P & " _:b ." & NL & "_:b " & P & " _:a .")
      /= Canonical ("_:a " & P & " _:b ." & NL & "_:b " & Q & " _:a ."),
      "a different predicate gives a different canonical form");

   Check
     (Canonical ("_:a " & P & " " & O1 & " .")
      /= Canonical ("_:a " & P & " " & O1 & " ." & NL
                    & "_:b " & P & " " & O1 & " ."),
      "an extra statement gives a different canonical form");

   ------------------------------------------------------------------
   --  Idempotence
   ------------------------------------------------------------------
   declare
      Once  : constant String :=
        Canonical ("_:a " & P & " _:b ." & NL & "_:b " & P & " _:a .");
      Twice : constant String := Canon.To_Canonical_NQuads (Load (Once));
   begin
      Check_Equal (Twice, Once, "canonicalization is idempotent");
   end;

   ------------------------------------------------------------------
   --  Isomorphism, which is what a round trip actually needs
   ------------------------------------------------------------------
   Check
     (Canon.Is_Isomorphic
        (Load ("_:a " & P & " _:b ." & NL & "_:b " & P & " _:a ."),
         Load ("_:m " & P & " _:n ." & NL & "_:n " & P & " _:m .")),
      "relabelled cycles are isomorphic");

   Check
     (not Canon.Is_Isomorphic
        (Load ("_:a " & P & " " & O1 & " ."),
         Load ("_:a " & P & " " & O2 & " .")),
      "differing datasets are not isomorphic");

   Check
     (Canon.Is_Isomorphic (Datasets.Empty, Datasets.Empty),
      "empty datasets are isomorphic");

   ------------------------------------------------------------------
   --  Named graphs and quoted triples participate
   ------------------------------------------------------------------
   Check_Equal
     (Canonical ("_:a " & P & " " & O1 & " _:g ."),
      Canonical ("_:x " & P & " " & O1 & " _:h ."),
      "a blank node naming a graph is canonicalized too");

   Check_Equal
     (Canonical ("_:a " & P & " <<( _:b " & P & " " & O1 & " )>> ."),
      Canonical ("_:x " & P & " <<( _:y " & P & " " & O1 & " )>> ."),
      "a blank node inside a quoted triple is canonicalized too");

   ------------------------------------------------------------------
   --  The work bound is reported, not hit and hidden
   ------------------------------------------------------------------
   declare
      Output : Unbounded.Unbounded_String;
      Status : Canon.Result_Status;
   begin
      Canon.Canonicalize
        (Load ("_:a " & P & " _:b ." & NL & "_:b " & P & " _:a ."),
         Output, Status, Maximum_Work => 1);
      Check (Status = Canon.Work_Limit_Reached,
             "a tiny work bound is reported rather than exceeded");
      Check (Unbounded.Length (Output) = 0,
             "and no partial output is offered");
   end;

   declare
      Raised : Boolean := False;
      Text   : Unbounded.Unbounded_String;
   begin
      Text := Unbounded.To_Unbounded_String
        (Canon.To_Canonical_NQuads
           (Load ("_:a " & P & " _:b ."), Maximum_Work => 1));
      Check (Unbounded.Length (Text) = 0, "unreachable");
   exception
      when Canon.Work_Limit_Error =>
         Raised := True;
         Check (Raised, "the function form raises at the bound");
   end;

   IO.Put_Line ("  checks              " & Checks'Image);
   IO.Put_Line ("  failures            " & Failures'Image);

   if Failures = 0 then
      IO.Put_Line ("PASS canonicalization_tests");
   else
      IO.Put_Line ("FAIL canonicalization_tests");
      Ada.Command_Line.Set_Exit_Status (1);
   end if;
end Canonicalization_Tests;
