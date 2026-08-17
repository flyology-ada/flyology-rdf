--  Runs the W3C RDF test suite.
--
--  The manifests are Turtle, so this reads them with the parser under test.
--  That is not circular in any way that matters: a manifest exercises only
--  the plainest constructs, and a parser too broken to read one is a parser
--  that would fail its own first entry anyway. What it buys is that the
--  corpus is never out of step with a hand-maintained index of itself.
--
--  The output is evidence, not a verdict. A harness that prints "passed"
--  has told you nothing about how much it looked at, and a count that
--  quietly shrinks is the failure mode worth guarding against -- so the
--  numbers below are the point, and a run that examines nothing says so
--  loudly rather than passing.

with Ada.Command_Line;
with Ada.Containers.Indefinite_Ordered_Maps;
with Ada.Containers.Indefinite_Ordered_Sets;
with Ada.Directories;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with Flyology_RDF.Canonicalization;
with Flyology_RDF.Datasets;
with Flyology_RDF.IRIs;
with Flyology_RDF.NQuads_Writers;
with Flyology_RDF.Quads;
with Flyology_RDF.Terms;
with Flyology_RDF.Turtle_Parsers;

procedure Conformance is

   package IO renames Ada.Text_IO;
   package Unbounded renames Ada.Strings.Unbounded;
   package Canon renames Flyology_RDF.Canonicalization;
   package Datasets renames Flyology_RDF.Datasets;
   package IRIs renames Flyology_RDF.IRIs;
   package Quads renames Flyology_RDF.Quads;
   package Terms renames Flyology_RDF.Terms;
   package Parsers renames Flyology_RDF.Turtle_Parsers;
   package Writers renames Flyology_RDF.NQuads_Writers;

   use type Parsers.Parse_Status;
   use type Terms.Term_Kind;

   package String_Maps is new Ada.Containers.Indefinite_Ordered_Maps
     (Key_Type => String, Element_Type => String);

   package String_Sets is new Ada.Containers.Indefinite_Ordered_Sets
     (Element_Type => String);

   MF : constant String :=
     "http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#";
   RDFT : constant String :=
     "http://www.w3.org/ns/rdftest#";
   RDF_NS : constant String :=
     "http://www.w3.org/1999/02/22-rdf-syntax-ns#";

   --  Evidence.
   Examined          : Natural := 0;
   Positive_Syntax   : Natural := 0;
   Negative_Syntax   : Natural := 0;
   Evaluation        : Natural := 0;
   Negative_Eval     : Natural := 0;
   Bytes_Parsed      : Natural := 0;
   Unexpected_Accept : Natural := 0;
   Unexpected_Reject : Natural := 0;
   Wrong_Result      : Natural := 0;
   Skipped_Unknown   : Natural := 0;
   Skipped_Missing   : Natural := 0;
   Manifests_Read    : Natural := 0;

   Failures : Unbounded.Unbounded_String;

   procedure Note_Failure (Entry_Name, Reason : String) is
   begin
      Unbounded.Append
        (Failures, "    " & Entry_Name & ": " & Reason & ASCII.LF);
   end Note_Failure;

   type Collector is limited new Parsers.Event_Sink with record
      Data : Datasets.Dataset := Datasets.Empty;
   end record;

   overriding procedure On_Graph_Declaration
     (Target : in out Collector;
      Graph  : Quads.Graph_Name;
      Span   : Parsers.Source_Span) is null;

   overriding procedure On_Diagnostic
     (Target : in out Collector;
      Value  : Parsers.Parse_Diagnostic) is null;

   overriding procedure On_Quad
     (Target : in out Collector;
      Value  : Quads.Quad;
      Span   : Parsers.Source_Span);

   overriding procedure On_Quad
     (Target : in out Collector;
      Value  : Quads.Quad;
      Span   : Parsers.Source_Span)
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

   --  Parse a document, reporting whether it was accepted and what it said.
   procedure Load
     (Text      : String;
      Syntax    : Parsers.Syntax_Kind;
      Base      : String;
      Data      : out Datasets.Dataset;
      Succeeded : out Boolean)
   is
      Sink   : Collector;
      Parser : Parsers.Parser :=
        Parsers.Create
          (Source_Name => "entry", Base_IRI => Base, Syntax => Syntax);
   begin
      Parsers.Feed (Parser, Text, Sink);
      Succeeded := Parsers.Finish (Parser, Sink) = Parsers.Parse_Succeeded;
      Data := Sink.Data;
   exception
      when others =>
         --  A parser that raises where it should diagnose is still a
         --  rejection, but it is worth not conflating the two.
         Succeeded := False;
         Data := Datasets.Empty;
   end Load;

   function Local_Name (Value : String) return String is
      Cut : Natural := 0;
   begin
      for Index in reverse Value'Range loop
         if Value (Index) in '#' | '/' then
            Cut := Index;
            exit;
         end if;
      end loop;
      if Cut = 0 then
         return Value;
      end if;
      return Value (Cut + 1 .. Value'Last);
   end Local_Name;

   function Ends_With (Value, Suffix : String) return Boolean
   is (Value'Length >= Suffix'Length
       and then Value (Value'Last - Suffix'Length + 1 .. Value'Last)
                = Suffix);

   --  An index over one manifest, so entries can be looked up by subject
   --  without rescanning the dataset for every question asked of it.
   type Index is record
      Types   : String_Maps.Map;   --  subject -> type IRI
      Actions : String_Maps.Map;   --  subject -> action IRI
      Results : String_Maps.Map;   --  subject -> result IRI
      Names   : String_Maps.Map;   --  subject -> mf:name
      Firsts  : String_Maps.Map;   --  list cell -> element
      Rests   : String_Maps.Map;   --  list cell -> next cell
      Entries : String_Maps.Map;   --  manifest -> entry list head
      Subjects : String_Sets.Set;
   end record;

   procedure Build_Index (Data : Datasets.Dataset; Into : out Index) is
      Result : Index;

      procedure Note (Statement : Quads.Quad);

      procedure Note (Statement : Quads.Quad) is
         Subject   : constant Terms.Term := Quads.Subject (Statement);
         Predicate : constant String :=
           IRIs.To_UTF_8 (Quads.Predicate (Statement));
         Object    : constant Terms.Term := Quads.Object (Statement);

         function Key (Value : Terms.Term) return String
         is (if Terms.Kind (Value) = Terms.IRI_Kind
             then IRIs.To_UTF_8 (Terms.IRI_Value (Value))
             elsif Terms.Kind (Value) = Terms.Blank_Node_Kind
             then "_:" & Terms.Label (Value)
             else Writers.Write_Term (Value));
      begin
         Result.Subjects.Include (Key (Subject));

         if Predicate = RDF_NS & "type" then
            Result.Types.Include (Key (Subject), Key (Object));
         elsif Predicate = MF & "action" then
            Result.Actions.Include (Key (Subject), Key (Object));
         elsif Predicate = MF & "result" then
            Result.Results.Include (Key (Subject), Key (Object));
         elsif Predicate = MF & "name" then
            Result.Names.Include
              (Key (Subject),
               (if Terms.Kind (Object) = Terms.Literal_Kind
                then Terms.Lexical_Form (Object) else Key (Object)));
         elsif Predicate = MF & "entries" then
            Result.Entries.Include (Key (Subject), Key (Object));
         elsif Predicate = RDF_NS & "first" then
            Result.Firsts.Include (Key (Subject), Key (Object));
         elsif Predicate = RDF_NS & "rest" then
            Result.Rests.Include (Key (Subject), Key (Object));
         end if;
      end Note;
   begin
      Datasets.Iterate (Data, Note'Access);
      Into := Result;
   end Build_Index;

   --  Several entries resolve relative references against the document's
   --  own location, so the base has to be the address the suite is
   --  published at rather than a placeholder. It is derived from the
   --  file's position in the checkout, which is the same thing.
   Corpus_Base : constant String := "https://w3c.github.io/rdf-tests/";

   function Published_Base (Directory : String) return String is
      Marker : constant String := "w3c-rdf-tests/";
      Cut    : constant Natural :=
        Ada.Strings.Fixed.Index (Directory, Marker);
   begin
      if Cut = 0 then
         return Corpus_Base;
      end if;
      return Corpus_Base
        & Directory (Cut + Marker'Length .. Directory'Last) & "/";
   end Published_Base;

   --  Turn a file IRI into a path relative to the manifest's directory.
   function Local_Path (Directory, Reference : String) return String is
      Name : constant String := Local_Name (Reference);
   begin
      return Ada.Directories.Compose (Directory, Name);
   end Local_Path;

   procedure Run_Entry
     (Directory  : String;
      Base       : String;
      Catalogue  : Index;
      Subject    : String)
   is
      Type_IRI : constant String :=
        (if Catalogue.Types.Contains (Subject)
         then Catalogue.Types.Element (Subject) else "");
      Kind_Name : constant String := Local_Name (Type_IRI);

      Entry_Name : constant String :=
        (if Catalogue.Names.Contains (Subject)
         then Catalogue.Names.Element (Subject) else Subject);

      Syntax : Parsers.Syntax_Kind := Parsers.Turtle_Syntax;

      Wants_Accept : Boolean := True;
      Is_Eval      : Boolean := False;
   begin
      if Type_IRI'Length = 0
        or else Ada.Strings.Fixed.Index (Type_IRI, RDFT) /= Type_IRI'First
      then
         --  Not an rdftest entry; manifests carry other statements too.
         return;
      end if;

      --  The type's local name gives both the grammar and the expectation.
      if Ada.Strings.Fixed.Index (Kind_Name, "NQuads") > 0 then
         Syntax := Parsers.NQuads_Syntax;
      elsif Ada.Strings.Fixed.Index (Kind_Name, "NTriples") > 0 then
         Syntax := Parsers.NTriples_Syntax;
      elsif Ada.Strings.Fixed.Index (Kind_Name, "Trig") > 0
        or else Ada.Strings.Fixed.Index (Kind_Name, "TriG") > 0
      then
         Syntax := Parsers.TriG_Syntax;
      elsif Ada.Strings.Fixed.Index (Kind_Name, "Turtle") > 0 then
         Syntax := Parsers.Turtle_Syntax;
      else
         Skipped_Unknown := Skipped_Unknown + 1;
         return;
      end if;

      if Ends_With (Kind_Name, "NegativeSyntax") then
         Wants_Accept := False;
      elsif Ends_With (Kind_Name, "NegativeEval") then
         Wants_Accept := False;
         Is_Eval := True;
      elsif Ends_With (Kind_Name, "Eval") then
         Is_Eval := True;
      elsif not Ends_With (Kind_Name, "PositiveSyntax") then
         Skipped_Unknown := Skipped_Unknown + 1;
         return;
      end if;

      if not Catalogue.Actions.Contains (Subject) then
         Skipped_Missing := Skipped_Missing + 1;
         return;
      end if;

      declare
         Action : constant String :=
           Local_Path (Directory, Catalogue.Actions.Element (Subject));
      begin
         if not Ada.Directories.Exists (Action) then
            Skipped_Missing := Skipped_Missing + 1;
            return;
         end if;

         declare
            Text      : constant String := Read_File (Action);
            Data      : Datasets.Dataset;
            Succeeded : Boolean;
         begin
            Examined := Examined + 1;
            Bytes_Parsed := Bytes_Parsed + Text'Length;

            Load (Text, Syntax,
                  Base & Local_Name (Catalogue.Actions.Element (Subject)),
                  Data, Succeeded);

            if Wants_Accept then
               if Is_Eval then
                  Evaluation := Evaluation + 1;
               else
                  Positive_Syntax := Positive_Syntax + 1;
               end if;

               if not Succeeded then
                  Unexpected_Reject := Unexpected_Reject + 1;
                  Note_Failure (Entry_Name, "rejected a valid document");
                  return;
               end if;
            else
               if Is_Eval then
                  Negative_Eval := Negative_Eval + 1;
               else
                  Negative_Syntax := Negative_Syntax + 1;
               end if;

               if Succeeded then
                  Unexpected_Accept := Unexpected_Accept + 1;
                  Note_Failure (Entry_Name, "accepted an invalid document");
               end if;
               return;
            end if;

            --  An evaluation entry names the dataset the document denotes.
            --  Comparing by canonical form rather than by labels is the
            --  whole reason canonicalization is in this crate.
            if Is_Eval and then Catalogue.Results.Contains (Subject) then
               declare
                  Expected_Path : constant String :=
                    Local_Path (Directory,
                                Catalogue.Results.Element (Subject));
               begin
                  if not Ada.Directories.Exists (Expected_Path) then
                     Skipped_Missing := Skipped_Missing + 1;
                     return;
                  end if;

                  declare
                     Expected_Text : constant String :=
                       Read_File (Expected_Path);
                     Expected      : Datasets.Dataset;
                     Expected_Ok   : Boolean;
                     Expected_Syntax : constant Parsers.Syntax_Kind :=
                       (if Ends_With (Expected_Path, ".nq")
                        then Parsers.NQuads_Syntax
                        else Parsers.NTriples_Syntax);
                  begin
                     Bytes_Parsed := Bytes_Parsed + Expected_Text'Length;
                     Load (Expected_Text, Expected_Syntax, "",
                           Expected, Expected_Ok);
                     if not Expected_Ok then
                        Skipped_Missing := Skipped_Missing + 1;
                        return;
                     end if;

                     if not Canon.Is_Isomorphic (Data, Expected) then
                        Wrong_Result := Wrong_Result + 1;
                        Note_Failure
                          (Entry_Name, "parsed to a different dataset");
                     end if;
                  end;
               end;
            end if;
         end;
      end;
   exception
      when others =>
         Unexpected_Reject := Unexpected_Reject + 1;
         Note_Failure (Entry_Name, "raised while being run");
   end Run_Entry;

   procedure Run_Manifest (Path : String) is
      Directory : constant String :=
        Ada.Directories.Containing_Directory (Path);
      Text      : constant String := Read_File (Path);
      Data      : Datasets.Dataset;
      Succeeded : Boolean;
      Catalogue : Index;
   begin
      Load (Text, Parsers.Turtle_Syntax,
            Published_Base (Directory), Data, Succeeded);
      if not Succeeded then
         IO.Put_Line ("  could not read manifest: " & Path);
         return;
      end if;

      Manifests_Read := Manifests_Read + 1;
      Build_Index (Data, Catalogue);

      --  Every subject carrying an rdftest type is an entry. Walking the
      --  mf:entries list would be tidier, but a manifest that lists an
      --  entry it does not type, or types one it does not list, should
      --  still be run rather than silently halved.
      for Subject of Catalogue.Subjects loop
         Run_Entry (Directory, Published_Base (Directory),
                    Catalogue, Subject);
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
               case Ada.Directories.Kind (Item) is
                  when Ada.Directories.Directory =>
                     Walk (Ada.Directories.Full_Name (Item));
                  when others =>
                     if Name = "manifest.ttl" then
                        Run_Manifest (Ada.Directories.Full_Name (Item));
                     end if;
               end case;
            end if;
         end;
      end loop;
      Ada.Directories.End_Search (Search);
   end Walk;

   Corpus : constant String := "data/w3c-rdf-tests";

begin
   IO.Put_Line ("W3C conformance");

   if not Ada.Directories.Exists (Corpus) then
      --  Absent rather than failing: the corpus is fetched by a script that
      --  needs the network. Saying so plainly beats a green run that
      --  examined nothing.
      IO.Put_Line ("  SKIP  the corpus is not provisioned");
      IO.Put_Line ("        run ./scripts/provision-oracles.sh corpora");
      IO.Put_Line ("PASS conformance (skipped)");
      return;
   end if;

   Walk (Corpus);

   IO.Put_Line ("  manifests read      " & Manifests_Read'Image);
   IO.Put_Line ("  entries examined    " & Examined'Image);
   IO.Put_Line ("    positive syntax   " & Positive_Syntax'Image);
   IO.Put_Line ("    negative syntax   " & Negative_Syntax'Image);
   IO.Put_Line ("    evaluation        " & Evaluation'Image);
   IO.Put_Line ("    negative eval     " & Negative_Eval'Image);
   IO.Put_Line ("  bytes parsed        " & Bytes_Parsed'Image);
   IO.Put_Line ("  skipped, unknown    " & Skipped_Unknown'Image);
   IO.Put_Line ("  skipped, missing    " & Skipped_Missing'Image);
   IO.Put_Line ("  rejected, valid     " & Unexpected_Reject'Image);
   IO.Put_Line ("  accepted, invalid   " & Unexpected_Accept'Image);
   IO.Put_Line ("  wrong result        " & Wrong_Result'Image);

   if Unbounded.Length (Failures) > 0 then
      IO.Put_Line ("  divergences:");
      IO.Put (Unbounded.To_String (Failures));
   end if;

   --  A corpus that is present but produced nothing is the failure this
   --  whole harness exists to make visible.
   if Examined = 0 then
      IO.Put_Line ("FAIL conformance: the corpus is present but empty");
      Ada.Command_Line.Set_Exit_Status (1);
   elsif Unexpected_Accept + Unexpected_Reject + Wrong_Result > 0 then
      IO.Put_Line ("FAIL conformance");
      Ada.Command_Line.Set_Exit_Status (1);
   else
      IO.Put_Line ("PASS conformance");
   end if;
end Conformance;
