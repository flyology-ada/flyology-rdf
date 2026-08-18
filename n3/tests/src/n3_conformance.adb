--  Runs the W3C Notation3 test suite.
--
--  N3 is specified outside the RDF suites and carries its own tests. Its
--  manifests are Turtle, so they are read with the RDF parser this crate
--  already depends on, and the entries are then run through the N3 parser.
--
--  Only the syntax entries are graded. The suite also carries reasoning
--  entries -- premise and conclusion pairs to be entailed -- and this crate
--  does not reason, so those are counted as skipped by reason rather than
--  quietly ignored or, worse, reported as passing.

with Ada.Command_Line;
with Ada.Exceptions;
with Ada.Containers.Indefinite_Ordered_Maps;
with Ada.Containers.Indefinite_Ordered_Sets;
with Ada.Directories;
use type Ada.Directories.File_Kind;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with Flyology_N3.Model;
with Flyology_N3.Parsers;
with Flyology_N3.Writers;

with Flyology_RDF.Datasets;
with Flyology_RDF.IRIs;
with Flyology_RDF.Quads;
with Flyology_RDF.Terms;
with Flyology_RDF.Turtle_Parsers;

procedure N3_Conformance is

   package IO renames Ada.Text_IO;
   package Unbounded renames Ada.Strings.Unbounded;
   package Datasets renames Flyology_RDF.Datasets;
   package IRIs renames Flyology_RDF.IRIs;
   package Quads renames Flyology_RDF.Quads;
   package Terms renames Flyology_RDF.Terms;
   package RDF_Parsers renames Flyology_RDF.Turtle_Parsers;
   package N3_Parsers renames Flyology_N3.Parsers;
   package N3_Writers renames Flyology_N3.Writers;
   package Model renames Flyology_N3.Model;

   use type RDF_Parsers.Parse_Status;
   use type Terms.Term_Kind;

   package String_Maps is new Ada.Containers.Indefinite_Ordered_Maps
     (Key_Type => String, Element_Type => String);

   package String_Sets is new Ada.Containers.Indefinite_Ordered_Sets
     (Element_Type => String);

   MF : constant String :=
     "http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#";
   RDF_NS : constant String :=
     "http://www.w3.org/1999/02/22-rdf-syntax-ns#";
   RDFT : constant String :=
     "http://www.w3.org/ns/rdftest#";

   Examined          : Natural := 0;
   Positive_Syntax   : Natural := 0;
   Negative_Syntax   : Natural := 0;

   --  Entries the working group withdrew. They are run and reported like
   --  any other, and counted apart, because a suite that keeps a
   --  withdrawn test is not asserting it: grading against one would
   --  measure agreement with a decision its own authors reversed. The
   --  status is published in the manifest, so this reads it rather than
   --  deciding it here.
   Streaming_Differed : Natural := 0;

   --  What this crate writes, read again by this crate. The corpus grades
   --  a parser over documents somebody else wrote and says nothing about
   --  the writer.
   Writer_Differed    : Natural := 0;
   --  How many documents the writer check compared. A divergence count
   --  of zero says nothing without it.
   Writer_Compared    : Natural := 0;
   Withdrawn          : Natural := 0;
   Withdrawn_Diverged : Natural := 0;
   Bytes_Parsed      : Natural := 0;
   Unexpected_Accept : Natural := 0;
   Unexpected_Reject : Natural := 0;
   Skipped_Reasoning : Natural := 0;
   Skipped_Missing   : Natural := 0;
   Manifests_Read    : Natural := 0;

   Divergences : Unbounded.Unbounded_String;

   type Collector is limited new RDF_Parsers.Event_Sink with record
      Data : Datasets.Dataset := Datasets.Empty;
   end record;

   overriding procedure On_Graph_Declaration
     (Target : in out Collector;
      Graph  : Quads.Graph_Name;
      Span   : RDF_Parsers.Source_Span) is null;

   overriding procedure On_Diagnostic
     (Target : in out Collector;
      Value  : RDF_Parsers.Parse_Diagnostic) is null;

   overriding procedure On_Quad
     (Target : in out Collector;
      Value  : Quads.Quad;
      Span   : RDF_Parsers.Source_Span);

   overriding procedure On_Quad
     (Target : in out Collector;
      Value  : Quads.Quad;
      Span   : RDF_Parsers.Source_Span)
   is
      pragma Unreferenced (Span);
   begin
      Datasets.Insert (Target.Data, Value);
   end On_Quad;

   function Read_File (Path : String) return String is
      File   : IO.File_Type;
      Buffer : Unbounded.Unbounded_String;
   begin
      IO.Open (File, IO.In_File, Path);
      while not IO.End_Of_File (File) loop
         Unbounded.Append (Buffer, IO.Get_Line (File));
         Unbounded.Append (Buffer, ASCII.LF);
      end loop;
      IO.Close (File);
      return Unbounded.To_String (Buffer);
   end Read_File;

   Manifest_Base : constant String := "http://example.org/manifest/";

   --  An action is a reference relative to its manifest, and in this suite
   --  it often names a subdirectory. Keeping only the last segment finds
   --  nothing; the whole remainder after the base is the path.
   function Relative_Path (Value : String) return String is
   begin
      if Value'Length > Manifest_Base'Length
        and then Value (Value'First .. Value'First + Manifest_Base'Length - 1)
                 = Manifest_Base
      then
         return Value (Value'First + Manifest_Base'Length .. Value'Last);
      end if;
      return Value;
   end Relative_Path;

   function Local_Name (Value : String) return String is
      Cut : Natural := 0;
   begin
      for Index in reverse Value'Range loop
         if Value (Index) in '#' | '/' then
            Cut := Index;
            exit;
         end if;
      end loop;
      return (if Cut = 0 then Value else Value (Cut + 1 .. Value'Last));
   end Local_Name;

   Types    : String_Maps.Map;
   Actions  : String_Maps.Map;
   Names    : String_Maps.Map;
   Approval : String_Maps.Map;
   Subjects : String_Sets.Set;

   procedure Index_Manifest (Data : Datasets.Dataset) is
      procedure Note (Statement : Quads.Quad);

      procedure Note (Statement : Quads.Quad) is
         Predicate : constant String :=
           IRIs.To_UTF_8 (Quads.Predicate (Statement));
         Object    : constant Terms.Term := Quads.Object (Statement);

         function Key (Value : Terms.Term) return String
         is (if Terms.Kind (Value) = Terms.IRI_Kind
             then IRIs.To_UTF_8 (Terms.IRI_Value (Value))
             elsif Terms.Kind (Value) = Terms.Blank_Node_Kind
             then "_:" & Terms.Label (Value)
             else Terms.Lexical_Form (Value));

         Subject : constant String := Key (Quads.Subject (Statement));
      begin
         Subjects.Include (Subject);
         if Predicate = RDF_NS & "type" then
            Types.Include (Subject, Key (Object));
         elsif Predicate = MF & "action" then
            Actions.Include (Subject, Key (Object));
         elsif Predicate = MF & "name" then
            Names.Include (Subject, Key (Object));
         elsif Predicate = RDFT & "approval" then
            Approval.Include (Subject, Local_Name (Key (Object)));
         end if;
      end Note;
   begin
      Datasets.Iterate (Data, Note'Access);
   end Index_Manifest;

   procedure Run_Entry (Directory, Subject : String) is
      Type_IRI : constant String :=
        (if Types.Contains (Subject) then Types.Element (Subject) else "");
      Kind_Name : constant String := Local_Name (Type_IRI);
      Entry_Name : constant String :=
        (if Names.Contains (Subject) then Names.Element (Subject)
         else Subject);
      Wants_Accept : Boolean;
   begin
      if Ada.Strings.Fixed.Index (Kind_Name, "Syntax") = 0 then
         if Ada.Strings.Fixed.Index (Kind_Name, "Test") > 0 then
            --  A reasoning entry: real, and out of this crate's scope.
            Skipped_Reasoning := Skipped_Reasoning + 1;
         end if;
         return;
      end if;

      if Ada.Strings.Fixed.Index (Kind_Name, "Negative") > 0 then
         Wants_Accept := False;
      elsif Ada.Strings.Fixed.Index (Kind_Name, "Positive") > 0 then
         Wants_Accept := True;
      else
         return;
      end if;

      if not Actions.Contains (Subject) then
         Skipped_Missing := Skipped_Missing + 1;
         return;
      end if;

      declare
         Path : constant String :=
           Directory & "/" & Relative_Path (Actions.Element (Subject));
      begin
         if not Ada.Directories.Exists (Path) then
            Skipped_Missing := Skipped_Missing + 1;
            return;
         end if;

         declare
            Text      : constant String := Read_File (Path);
            Succeeded : Boolean := True;
            Reason    : Unbounded.Unbounded_String;
            Retracted : constant Boolean :=
              Approval.Contains (Subject)
              and then Approval.Element (Subject) = "Rejected";
         begin
            Examined := Examined + 1;
            if Retracted then
               Withdrawn := Withdrawn + 1;
            end if;
            Bytes_Parsed := Bytes_Parsed + Text'Length;
            if Wants_Accept then
               Positive_Syntax := Positive_Syntax + 1;
            else
               Negative_Syntax := Negative_Syntax + 1;
            end if;

            begin
               declare
                  Base   : constant String := "http://example.org/n3/";
                  Result : constant Model.Term :=
                    N3_Parsers.Parse (Text, Base);
                  Whole  : constant String := N3_Writers.To_N3 (Result);
               begin
                  declare
                     Again : constant Model.Term :=
                       N3_Parsers.Parse (Whole, Base);
                  begin
                     Writer_Compared := Writer_Compared + 1;
                     if N3_Writers.To_N3 (Again) /= Whole then
                        Writer_Differed := Writer_Differed + 1;
                        Unbounded.Append
                          (Divergences,
                           "    " & Entry_Name
                           & ": its own N3 output does not read back"
                           & ASCII.LF);
                     end if;
                  end;

                  --  The same document fed one byte at a time has to come
                  --  out the same. Splitting at every boundary in turn is
                  --  the only way to be sure none of them is special, and
                  --  the writer's output is what makes two formulas
                  --  comparable.
                  declare
                     Streamed : N3_Parsers.Parser :=
                       N3_Parsers.Create (Base);
                  begin
                     for Index in Text'Range loop
                        N3_Parsers.Feed (Streamed, Text (Index .. Index));
                     end loop;
                     if N3_Writers.To_N3 (N3_Parsers.Finish (Streamed))
                        /= Whole
                     then
                        Streaming_Differed := Streaming_Differed + 1;
                        Unbounded.Append
                          (Divergences,
                           "    " & Entry_Name
                           & ": chunk-fed parse differs from whole"
                           & ASCII.LF);
                     end if;
                  end;
               end;
            exception
               when Error : others =>
                  --  Recording why sorts the divergences into causes
                  --  instead of leaving a list of names to open one by one.
                  Succeeded := False;
                  Reason := Unbounded.To_Unbounded_String
                    (Ada.Exceptions.Exception_Message (Error));
            end;

            if Wants_Accept = Succeeded then
               null;
            else
               declare
                  What : constant String :=
                    (if Wants_Accept then Unbounded.To_String (Reason)
                     else "accepted an invalid document");
               begin
                  if Retracted then
                     Withdrawn_Diverged := Withdrawn_Diverged + 1;
                  elsif Wants_Accept then
                     Unexpected_Reject := Unexpected_Reject + 1;
                  else
                     Unexpected_Accept := Unexpected_Accept + 1;
                  end if;
                  Unbounded.Append
                    (Divergences,
                     "    " & Entry_Name
                     & (if Retracted then " [withdrawn]" else "")
                     & ": " & What & ASCII.LF);
               end;
            end if;
         end;
      end;
   end Run_Entry;

   procedure Run_Manifest (Path : String) is
      Directory : constant String :=
        Ada.Directories.Containing_Directory (Path);
      Sink   : Collector;
      Parser : RDF_Parsers.Parser :=
        RDF_Parsers.Create
          (Source_Name => "manifest",
           Base_IRI    => Manifest_Base,
           Syntax      => RDF_Parsers.Turtle_Syntax);
   begin
      RDF_Parsers.Feed (Parser, Read_File (Path), Sink);
      if RDF_Parsers.Finish (Parser, Sink)
         /= RDF_Parsers.Parse_Succeeded
      then
         IO.Put_Line ("  could not read manifest: " & Path);
         return;
      end if;

      Manifests_Read := Manifests_Read + 1;
      Types.Clear;
      Actions.Clear;
      Names.Clear;
      Subjects.Clear;
      Index_Manifest (Sink.Data);

      for Subject of Subjects loop
         Run_Entry (Directory, Subject);
      end loop;
   end Run_Manifest;

   procedure Walk (Directory : String) is
      Search : Ada.Directories.Search_Type;
      Item   : Ada.Directories.Directory_Entry_Type;
   begin
      Ada.Directories.Start_Search
        (Search, Directory, "",
         [Ada.Directories.Directory => True,
          Ada.Directories.Ordinary_File => True,
          Ada.Directories.Special_File => False]);
      while Ada.Directories.More_Entries (Search) loop
         Ada.Directories.Get_Next_Entry (Search, Item);
         declare
            Name : constant String := Ada.Directories.Simple_Name (Item);
         begin
            if Name /= "." and then Name /= ".." and then Name /= ".git" then
               if Ada.Directories.Kind (Item) = Ada.Directories.Directory then
                  Walk (Ada.Directories.Full_Name (Item));
               elsif Name'Length > 12
                 and then Name (Name'First .. Name'First + 8) = "manifest-"
                 and then Name (Name'Last - 3 .. Name'Last) = ".ttl"
               then
                  --  The reasoner manifests are read too; their entries
                  --  are not syntax entries and are counted as skipped.
                  Run_Manifest (Ada.Directories.Full_Name (Item));
               elsif Name = "manifest.ttl" then
                  Run_Manifest (Ada.Directories.Full_Name (Item));
               end if;
            end if;
         end;
      end loop;
      Ada.Directories.End_Search (Search);
   end Walk;

   --  The N3 suites, and only those. The repository also carries a Turtle
   --  conformance suite, and grading it here would measure the wrong thing:
   --  N3 is a superset, so a document that is correctly bad for Turtle --
   --  "@forAll", "is ... of" -- is perfectly good N3. Its manifests are
   --  also named manifest-parser.ttl and the like rather than plainly
   --  manifest.ttl, which is why matching only the plain name found the
   --  Turtle suite and none of the N3 one.
   Corpus : constant String := "../../tests/data/w3c-n3-tests/N3Tests";

begin
   IO.Put_Line ("N3 conformance");

   if not Ada.Directories.Exists (Corpus) then
      IO.Put_Line ("  SKIP  the corpus is not provisioned");
      IO.Put_Line ("        run ../scripts/provision-oracles.sh corpora");
      IO.Put_Line ("PASS n3_conformance (skipped)");
      return;
   end if;

   Walk (Corpus);

   IO.Put_Line ("  manifests read      " & Manifests_Read'Image);
   IO.Put_Line ("  entries examined    " & Examined'Image);
   IO.Put_Line ("    positive syntax   " & Positive_Syntax'Image);
   IO.Put_Line ("    negative syntax   " & Negative_Syntax'Image);
   IO.Put_Line ("    of those, withdrawn" & Withdrawn'Image);
   IO.Put_Line ("  bytes parsed        " & Bytes_Parsed'Image);
   IO.Put_Line ("  skipped, reasoning  " & Skipped_Reasoning'Image);
   IO.Put_Line ("  skipped, missing    " & Skipped_Missing'Image);
   IO.Put_Line ("  rejected, valid     " & Unexpected_Reject'Image);
   IO.Put_Line ("  accepted, invalid   " & Unexpected_Accept'Image);
   IO.Put_Line ("  streaming differed  " & Streaming_Differed'Image);
   IO.Put_Line ("  writer compared     " & Writer_Compared'Image);
   IO.Put_Line ("  writer differed     " & Writer_Differed'Image);
   IO.Put_Line ("  withdrawn, diverged " & Withdrawn_Diverged'Image);

   if Unbounded.Length (Divergences) > 0 then
      IO.Put_Line ("  divergences:");
      IO.Put (Unbounded.To_String (Divergences));
   end if;

   if Examined = 0 then
      IO.Put_Line ("FAIL n3_conformance: the corpus is present but empty");
      Ada.Command_Line.Set_Exit_Status (1);
   elsif Unexpected_Accept + Unexpected_Reject + Streaming_Differed
         + Writer_Differed > 0
   then
      IO.Put_Line ("FAIL n3_conformance");
      Ada.Command_Line.Set_Exit_Status (1);
   else
      IO.Put_Line ("PASS n3_conformance");
   end if;
end N3_Conformance;
