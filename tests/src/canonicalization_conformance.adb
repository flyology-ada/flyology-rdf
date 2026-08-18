--  Runs the W3C RDF Dataset Canonicalization (RDFC-1.0) test suite.
--
--  The crate ships canonicalization, and the suite that grades it was
--  already being fetched and pinned by the provisioning script without
--  anything reading it. A corpus that is downloaded and not run measures
--  nothing, so this reads it.
--
--  Each entry names an input dataset and its canonical form. The input is
--  parsed as N-Quads, canonicalized, and compared to the published result
--  byte for byte: RDFC-1.0 fixes both the labels and their order, so
--  anything weaker than equality would be grading something else.

with Ada.Command_Line;
with Ada.Containers.Indefinite_Ordered_Maps;
with Ada.Containers.Indefinite_Ordered_Sets;
with Ada.Directories;
with Ada.Exceptions;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with Flyology_RDF.Canonicalization;
with Flyology_RDF.Datasets;
with Flyology_RDF.IRIs;
with Flyology_RDF.Quads;
with Flyology_RDF.Terms;
with Flyology_RDF.Turtle_Parsers;

procedure Canonicalization_Conformance is

   package IO renames Ada.Text_IO;
   package Unbounded renames Ada.Strings.Unbounded;
   package Canon renames Flyology_RDF.Canonicalization;
   package Datasets renames Flyology_RDF.Datasets;
   package IRIs renames Flyology_RDF.IRIs;
   package Quads renames Flyology_RDF.Quads;
   package Terms renames Flyology_RDF.Terms;
   package Parsers renames Flyology_RDF.Turtle_Parsers;

   use type Parsers.Parse_Status;
   use type Terms.Term_Kind;
   use type Canon.Result_Status;

   package String_Maps is new Ada.Containers.Indefinite_Ordered_Maps
     (Key_Type => String, Element_Type => String);
   package String_Sets is new Ada.Containers.Indefinite_Ordered_Sets
     (Element_Type => String);

   MF : constant String :=
     "http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#";
   RDF_NS : constant String :=
     "http://www.w3.org/1999/02/22-rdf-syntax-ns#";
   RDFC : constant String :=
     "https://w3c.github.io/rdf-canon/tests/vocab#";

   Examined        : Natural := 0;
   Eval_Entries    : Natural := 0;
   Map_Entries     : Natural := 0;
   Negative        : Natural := 0;
   With_SHA_384    : Natural := 0;
   Skipped_Missing : Natural := 0;
   Wrong_Result    : Natural := 0;
   Divergences     : Unbounded.Unbounded_String;

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

   procedure Load
     (Text      : String;
      Base      : String;
      Data      : out Datasets.Dataset;
      Succeeded : out Boolean)
   is
      Sink   : Collector;
      Parser : Parsers.Parser :=
        Parsers.Create
          (Source_Name => "entry", Base_IRI => Base,
           Syntax      => Parsers.NQuads_Syntax);
   begin
      Parsers.Feed (Parser, Text, Sink);
      Succeeded := Parsers.Finish (Parser, Sink) = Parsers.Parse_Succeeded;
      Data := Sink.Data;
   exception
      when others =>
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
      return (if Cut = 0 then Value else Value (Cut + 1 .. Value'Last));
   end Local_Name;

   Types    : String_Maps.Map;
   Actions  : String_Maps.Map;
   Results  : String_Maps.Map;
   Names    : String_Maps.Map;
   Digests  : String_Maps.Map;
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
         elsif Predicate = MF & "result" then
            Results.Include (Subject, Key (Object));
         elsif Predicate = MF & "name" then
            Names.Include (Subject, Key (Object));
         elsif Predicate = RDFC & "hashAlgorithm" then
            Digests.Include (Subject, Key (Object));
         end if;
      end Note;
   begin
      Datasets.Iterate (Data, Note'Access);
   end Index_Manifest;

   --  Actions are relative to the manifest, which the parser resolved
   --  against the base below; the remainder is the path on disk.
   Manifest_Base : constant String := "http://example.org/canon/";

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

   --  A map result is a flat JSON object whose keys and values are all
   --  strings, which is the whole of what this suite writes. Pairing the
   --  quoted runs reads it exactly, and a real JSON parser would be a
   --  dependency taken to read four hundred bytes.
   function Read_Map (Path : String) return String_Maps.Map is
      Text   : constant String := Read_File (Path);
      Result : String_Maps.Map;
      Index  : Natural := Text'First;
      Key    : Unbounded.Unbounded_String;
      Have   : Boolean := False;
   begin
      while Index <= Text'Last loop
         if Text (Index) = '"' then
            declare
               First : constant Natural := Index + 1;
               Last  : Natural := First;
            begin
               while Last <= Text'Last and then Text (Last) /= '"' loop
                  Last := Last + 1;
               end loop;
               exit when Last > Text'Last;
               declare
                  Item : constant String := Text (First .. Last - 1);
               begin
                  if Have then
                     Result.Include (Unbounded.To_String (Key), Item);
                     Have := False;
                  else
                     Key := Unbounded.To_Unbounded_String (Item);
                     Have := True;
                  end if;
               end;
               Index := Last + 1;
            end;
         else
            Index := Index + 1;
         end if;
      end loop;
      return Result;
   end Read_Map;

   procedure Diverged (Entry_Name, Why : String) is
   begin
      Unbounded.Append
        (Divergences, "    " & Entry_Name & ": " & Why & ASCII.LF);
   end Diverged;

   procedure Run_Entry (Directory, Subject : String) is
      Kind_Name : constant String :=
        Local_Name (if Types.Contains (Subject)
                    then Types.Element (Subject) else "");
      Entry_Name : constant String :=
        (if Names.Contains (Subject) then Names.Element (Subject)
         else Subject);
      Digest : constant String :=
        (if Digests.Contains (Subject) then Digests.Element (Subject)
         else "SHA256");
   begin
      if Ada.Strings.Fixed.Index (Kind_Name, "RDFC10") = 0 then
         return;
      end if;

      if not Actions.Contains (Subject) then
         Skipped_Missing := Skipped_Missing + 1;
         return;
      end if;

      declare
         Input : constant String :=
           Directory & "/" & Relative_Path (Actions.Element (Subject));
      begin
         if not Ada.Directories.Exists (Input) then
            Skipped_Missing := Skipped_Missing + 1;
            return;
         end if;

         declare
            Data      : Datasets.Dataset;
            Succeeded : Boolean;
            Negative_Entry : constant Boolean :=
              Ada.Strings.Fixed.Index (Kind_Name, "Negative") > 0;
            Map_Entry : constant Boolean :=
              Ada.Strings.Fixed.Index (Kind_Name, "MapTest") > 0;
            Algorithm : constant Canon.Hash_Algorithm :=
              (if Digest = "SHA384" then Canon.SHA_384 else Canon.SHA_256);
         begin
            Examined := Examined + 1;
            if Negative_Entry then
               Negative := Negative + 1;
            elsif Map_Entry then
               Map_Entries := Map_Entries + 1;
            else
               Eval_Entries := Eval_Entries + 1;
            end if;
            if Digest = "SHA384" then
               With_SHA_384 := With_SHA_384 + 1;
            end if;

            Load (Read_File (Input), "http://example.org/canon/input/",
                  Data, Succeeded);
            if not Succeeded then
               Wrong_Result := Wrong_Result + 1;
               Diverged (Entry_Name, "the input did not parse as N-Quads");
               return;
            end if;

            declare
               Produced : Unbounded.Unbounded_String;
               Issued   : Canon.Label_Maps.Map;
               Status   : Canon.Result_Status;
            begin
               Canon.Canonicalize
                 (Data, Produced, Issued, Status,
                  Algorithm => Algorithm);

               if Negative_Entry then
                  --  A negative entry is a dataset built to be expensive.
                  --  Completing it is the failure.
                  if Status = Canon.Canonicalized then
                     Wrong_Result := Wrong_Result + 1;
                     Diverged (Entry_Name,
                               "canonicalized a dataset that should have"
                               & " exhausted the work bound");
                  end if;
                  return;
               end if;

               if Status /= Canon.Canonicalized then
                  Wrong_Result := Wrong_Result + 1;
                  Diverged (Entry_Name, "the work bound was reached");
                  return;
               end if;

               if not Results.Contains (Subject) then
                  Skipped_Missing := Skipped_Missing + 1;
                  return;
               end if;

               declare
                  Expected_Path : constant String :=
                    Directory & "/" & Relative_Path (Results.Element (Subject));
               begin
                  if not Ada.Directories.Exists (Expected_Path) then
                     Skipped_Missing := Skipped_Missing + 1;
                     return;
                  end if;

                  if Map_Entry then
                     declare
                        Expected : constant String_Maps.Map :=
                          Read_Map (Expected_Path);
                     begin
                        if Natural (Expected.Length)
                           /= Natural (Issued.Length)
                        then
                           Wrong_Result := Wrong_Result + 1;
                           Diverged
                             (Entry_Name,
                              "issued" & Issued.Length'Image
                              & " identifiers, expected"
                              & Expected.Length'Image);
                           return;
                        end if;
                        for Position in Expected.Iterate loop
                           declare
                              Label : constant String :=
                                String_Maps.Key (Position);
                              Want  : constant String :=
                                String_Maps.Element (Position);
                           begin
                              if not Issued.Contains (Label) then
                                 Wrong_Result := Wrong_Result + 1;
                                 Diverged
                                   (Entry_Name,
                                    "no identifier issued for _:" & Label);
                                 return;
                              elsif Issued.Element (Label) /= Want then
                                 Wrong_Result := Wrong_Result + 1;
                                 Diverged
                                   (Entry_Name,
                                    "_:" & Label & " was issued "
                                    & Issued.Element (Label) & ", expected "
                                    & Want);
                                 return;
                              end if;
                           end;
                        end loop;
                     end;
                     return;
                  end if;

                  declare
                     Expected : constant String := Read_File (Expected_Path);
                     Actual   : constant String :=
                       Unbounded.To_String (Produced);
                  begin
                     if Expected /= Actual then
                        Wrong_Result := Wrong_Result + 1;
                        Diverged
                          (Entry_Name,
                           "canonical form differs (expected"
                           & Expected'Length'Image & " bytes, produced"
                           & Actual'Length'Image & ")");
                     end if;
                  end;
               end;
            exception
               when Error : others =>
                  if Negative_Entry then
                     return;
                  end if;
                  Wrong_Result := Wrong_Result + 1;
                  Diverged
                    (Entry_Name, Ada.Exceptions.Exception_Message (Error));
            end;
         end;
      end;
   end Run_Entry;

   Corpus : constant String := "../tests/data/w3c-rdf-canon/tests";

begin
   IO.Put_Line ("RDFC-1.0 conformance");

   if not Ada.Directories.Exists (Corpus & "/manifest.ttl") then
      IO.Put_Line ("  SKIP  the corpus is not provisioned");
      IO.Put_Line ("        run ./scripts/provision-oracles.sh corpora");
      IO.Put_Line ("PASS canonicalization_conformance (skipped)");
      return;
   end if;

   declare
      Manifest  : Datasets.Dataset;
      Succeeded : Boolean;
      Sink      : Collector;
      Parser    : Parsers.Parser :=
        Parsers.Create
          (Source_Name => "manifest", Base_IRI => Manifest_Base,
           Syntax      => Parsers.Turtle_Syntax);
   begin
      Parsers.Feed (Parser, Read_File (Corpus & "/manifest.ttl"), Sink);
      Succeeded := Parsers.Finish (Parser, Sink) = Parsers.Parse_Succeeded;
      Manifest := Sink.Data;
      if not Succeeded then
         IO.Put_Line ("FAIL canonicalization_conformance: the manifest did"
                      & " not parse");
         Ada.Command_Line.Set_Exit_Status (1);
         return;
      end if;
      Index_Manifest (Manifest);
   end;

   for Subject of Subjects loop
      Run_Entry (Corpus, Subject);
   end loop;

   IO.Put_Line ("  entries examined    " & Examined'Image);
   IO.Put_Line ("    evaluation        " & Eval_Entries'Image);
   IO.Put_Line ("    identifier map    " & Map_Entries'Image);
   IO.Put_Line ("    negative          " & Negative'Image);
   IO.Put_Line ("    of those, SHA-384 " & With_SHA_384'Image);
   IO.Put_Line ("  skipped, missing    " & Skipped_Missing'Image);
   IO.Put_Line ("  wrong result        " & Wrong_Result'Image);

   if Unbounded.Length (Divergences) > 0 then
      IO.Put_Line ("  divergences:");
      IO.Put (Unbounded.To_String (Divergences));
   end if;

   if Examined = 0 then
      IO.Put_Line ("FAIL canonicalization_conformance: nothing was examined");
      Ada.Command_Line.Set_Exit_Status (1);
   elsif Wrong_Result > 0 then
      IO.Put_Line ("FAIL canonicalization_conformance");
      Ada.Command_Line.Set_Exit_Status (1);
   else
      IO.Put_Line ("PASS canonicalization_conformance");
   end if;
end Canonicalization_Conformance;
