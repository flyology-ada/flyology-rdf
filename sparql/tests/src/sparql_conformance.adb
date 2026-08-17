--  Runs the W3C SPARQL test suite.
--
--  The SPARQL suites live in the same repository as the RDF ones, and their
--  manifests are Turtle, so they are read with the RDF parser this crate
--  already depends on and the entries are run through the query parser.
--
--  Only the syntax entries are graded, and that is the honest limit of what
--  a parser can be held to. The suite is mostly evaluation: a query, a
--  dataset, and the results it should produce. Those need an engine, so
--  they are counted as skipped by reason rather than ignored or, worse,
--  reported as passing.

with Ada.Command_Line;
with Ada.Containers.Indefinite_Ordered_Maps;
with Ada.Containers.Indefinite_Ordered_Sets;
with Ada.Directories;
use type Ada.Directories.File_Kind;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with Flyology_SPARQL.Parsers;
with Flyology_SPARQL.Syntax;

with Flyology_RDF.Datasets;
with Flyology_RDF.IRIs;
with Flyology_RDF.Quads;
with Flyology_RDF.Terms;
with Flyology_RDF.Turtle_Parsers;

procedure SPARQL_Conformance is

   package IO renames Ada.Text_IO;
   package Unbounded renames Ada.Strings.Unbounded;
   package Datasets renames Flyology_RDF.Datasets;
   package IRIs renames Flyology_RDF.IRIs;
   package Quads renames Flyology_RDF.Quads;
   package Terms renames Flyology_RDF.Terms;
   package RDF_Parsers renames Flyology_RDF.Turtle_Parsers;
   package Query_Parsers renames Flyology_SPARQL.Parsers;
   package Query_Syntax renames Flyology_SPARQL.Syntax;

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

   Examined          : Natural := 0;
   Positive_Syntax   : Natural := 0;
   Negative_Syntax   : Natural := 0;
   Bytes_Parsed      : Natural := 0;
   Unexpected_Accept : Natural := 0;
   Unexpected_Reject : Natural := 0;
   Skipped_Evaluation : Natural := 0;
   Skipped_Update     : Natural := 0;
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

   Types   : String_Maps.Map;
   Actions : String_Maps.Map;
   Names   : String_Maps.Map;
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
            --  An evaluation entry: real, and out of this crate's scope.
            Skipped_Evaluation := Skipped_Evaluation + 1;
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
           Ada.Directories.Compose
             (Directory, Local_Name (Actions.Element (Subject)));
      begin
         if not Ada.Directories.Exists (Path) then
            Skipped_Missing := Skipped_Missing + 1;
            return;
         end if;

         --  An update is not a query. Grading a .ru file against a query
         --  parser measures nothing about the parser and quietly inflates
         --  the divergence count with documents it was never meant to read.
         if Path'Length > 3
           and then Path (Path'Last - 2 .. Path'Last) = ".ru"
         then
            Skipped_Update := Skipped_Update + 1;
            return;
         end if;

         declare
            Text      : constant String := Read_File (Path);
            Succeeded : Boolean := True;
         begin
            Examined := Examined + 1;
            Bytes_Parsed := Bytes_Parsed + Text'Length;
            if Wants_Accept then
               Positive_Syntax := Positive_Syntax + 1;
            else
               Negative_Syntax := Negative_Syntax + 1;
            end if;

            begin
               declare
                  Result : constant Query_Syntax.Query :=
                    Query_Parsers.Parse (Text);
                  Ignored : constant Query_Syntax.Query_Form :=
                    Query_Syntax.Form (Result);
               begin
                  pragma Unreferenced (Ignored);
               end;
            exception
               when others =>
                  Succeeded := False;
            end;

            if Wants_Accept and then not Succeeded then
               Unexpected_Reject := Unexpected_Reject + 1;
               Unbounded.Append
                 (Divergences,
                  "    " & Entry_Name & ": rejected a valid document"
                  & ASCII.LF);
            elsif not Wants_Accept and then Succeeded then
               Unexpected_Accept := Unexpected_Accept + 1;
               Unbounded.Append
                 (Divergences,
                  "    " & Entry_Name & ": accepted an invalid document"
                  & ASCII.LF);
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
           Base_IRI    => "http://example.org/manifest/",
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
               elsif Name = "manifest.ttl" then
                  Run_Manifest (Ada.Directories.Full_Name (Item));
               end if;
            end if;
         end;
      end loop;
      Ada.Directories.End_Search (Search);
   end Walk;

   Corpus : constant String := "../../tests/data/w3c-sparql-tests";

begin
   IO.Put_Line ("SPARQL conformance");

   if not Ada.Directories.Exists (Corpus) then
      IO.Put_Line ("  SKIP  the corpus is not provisioned");
      IO.Put_Line ("        run ../scripts/provision-oracles.sh corpora");
      IO.Put_Line ("PASS sparql_conformance (skipped)");
      return;
   end if;

   Walk (Corpus);

   IO.Put_Line ("  manifests read      " & Manifests_Read'Image);
   IO.Put_Line ("  entries examined    " & Examined'Image);
   IO.Put_Line ("    positive syntax   " & Positive_Syntax'Image);
   IO.Put_Line ("    negative syntax   " & Negative_Syntax'Image);
   IO.Put_Line ("  bytes parsed        " & Bytes_Parsed'Image);
   IO.Put_Line ("  skipped, evaluation " & Skipped_Evaluation'Image);
   IO.Put_Line ("  skipped, update     " & Skipped_Update'Image);
   IO.Put_Line ("  skipped, missing    " & Skipped_Missing'Image);
   IO.Put_Line ("  rejected, valid     " & Unexpected_Reject'Image);
   IO.Put_Line ("  accepted, invalid   " & Unexpected_Accept'Image);

   if Unbounded.Length (Divergences) > 0 then
      IO.Put_Line ("  divergences:");
      IO.Put (Unbounded.To_String (Divergences));
   end if;

   if Examined = 0 then
      IO.Put_Line ("FAIL sparql_conformance: the corpus is present but empty");
      Ada.Command_Line.Set_Exit_Status (1);
   elsif Unexpected_Accept + Unexpected_Reject > 0 then
      IO.Put_Line ("FAIL sparql_conformance");
      Ada.Command_Line.Set_Exit_Status (1);
   else
      IO.Put_Line ("PASS sparql_conformance");
   end if;
end SPARQL_Conformance;
