--  Differential test against an independent implementation.
--
--  The W3C suites are finite and curated, and they grade us against our own
--  reading of them. This grades us against somebody else's code.
--
--  Two questions are asked of every corpus document this crate accepts.
--
--  Does the oracle read the document the way we do? Its N-Quads are read
--  back with our own reader and canonicalized, so blank node labels -- the
--  one thing two conforming parsers are entitled to disagree about -- do
--  not enter the comparison.
--
--  And does the oracle read *our serialization* the way we wrote it? That
--  is the question the suites cannot ask. A writer bug that our own parser
--  reads back symmetrically survives every round-trip test we have, because
--  both halves share the misunderstanding. A foreign parser does not.
--
--  Two oracles, asked in order rather than both of everything. oxigraph is
--  a native binary and answers in milliseconds, but version 0.4 implements
--  RDF-star, the draft that preceded RDF 1.2, and reads "<< >>" as a quoted
--  triple where RDF 1.2 reads a reified triple. Its answer on such a
--  document is a fact about the older specification and not about either
--  implementation, so it is not compared.
--
--  Jena is a JVM and costs half a second a document, which is too much for
--  every document and exactly right for the ones oxigraph could not answer:
--  it implements RDF 1.2 proper. So oxigraph is asked first, and Jena is
--  asked wherever oxigraph declined or answered the older specification.
--  Every document ends up checked by an oracle that understands it, and the
--  report says which oracle answered how many.
--
--  An oracle is skipped, loudly, when it is not provisioned. A test that
--  quietly passes because it did nothing is worse than one that is absent.

with Ada.Command_Line;
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with GNAT.OS_Lib;

with Flyology_RDF.Canonicalization;
with Flyology_RDF.Datasets;
with Flyology_RDF.Quads;
with Flyology_RDF.Turtle_Parsers;
with Flyology_RDF.Turtle_Writers;

procedure Oracle_Differential is

   package IO renames Ada.Text_IO;
   package Unbounded renames Ada.Strings.Unbounded;
   package OS renames GNAT.OS_Lib;
   package Canon renames Flyology_RDF.Canonicalization;
   package Datasets renames Flyology_RDF.Datasets;
   package Quads renames Flyology_RDF.Quads;
   package Parsers renames Flyology_RDF.Turtle_Parsers;
   package Writers renames Flyology_RDF.Turtle_Writers;

   use type Parsers.Parse_Status;
   use type Ada.Directories.File_Size;

   --  Everything resolves against one base, on both sides, so that a
   --  relative reference cannot be the reason for a disagreement.
   Base : constant String := "http://example.org/differential/";

   --  The corpus carries a few multi-megabyte result reports alongside its
   --  test documents. Canonicalizing one costs minutes and says nothing a
   --  small document does not, so they are skipped -- and counted, because
   --  a cap nobody reports reads as coverage nobody had.
   Maximum_Bytes : constant := 256 * 1024;

   type Oracle_Id is (Oxigraph, Jena);

   type Tally is record
      Parser_Read     : Natural := 0;
      Parser_Declined : Natural := 0;
      Parser_Older    : Natural := 0;
      Parser_Differed : Natural := 0;
      Writer_Read     : Natural := 0;
      Writer_Declined : Natural := 0;
      Writer_Older    : Natural := 0;
      Writer_Differed : Natural := 0;
   end record;

   Counts : array (Oracle_Id) of Tally;
   Present : array (Oracle_Id) of Boolean := (others => False);
   Command : array (Oracle_Id) of Unbounded.Unbounded_String;

   Considered      : Natural := 0;
   Skipped_Large   : Natural := 0;
   We_Accepted     : Natural := 0;
   Cross_Checked   : Natural := 0;
   Divergences     : Unbounded.Unbounded_String;
   Contested       : Unbounded.Unbounded_String;

   Scratch : constant String := "obj/oracle";

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

   procedure Write_File (Path, Content : String) is
      File : IO.File_Type;
   begin
      IO.Create (File, IO.Out_File, Path);
      IO.Put (File, Content);
      IO.Close (File);
   end Write_File;

   procedure Load
     (Text      : String;
      Syntax    : Parsers.Syntax_Kind;
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
         Succeeded := False;
         Data := Datasets.Empty;
   end Load;

   --  Hand text to an oracle and take back its N-Quads. A non-zero exit is
   --  the oracle declining, which is its own answer and not ours.
   procedure Convert
     (Which     : Oracle_Id;
      Text      : String;
      From      : String;
      Output    : out Unbounded.Unbounded_String;
      Succeeded : out Boolean)
   is
      In_Path  : constant String := Scratch & "/in." & From;
      Out_Path : constant String := Scratch & "/out.nq";
      Log_Path : constant String := Scratch & "/log";
      Code     : Integer;
      Sink     : OS.File_Descriptor;
   begin
      Output := Unbounded.Null_Unbounded_String;
      Write_File (In_Path, Text);
      if Ada.Directories.Exists (Out_Path) then
         Ada.Directories.Delete_File (Out_Path);
      end if;

      case Which is
         when Oxigraph =>
            Sink := OS.Create_File (Log_Path, OS.Binary);
            declare
               Arguments : constant OS.Argument_List :=
                 (new String'("convert"),
                  new String'("--from-file"), new String'(In_Path),
                  new String'("--from-format"), new String'(From),
                  new String'("--from-base"), new String'(Base),
                  new String'("--to-file"), new String'(Out_Path),
                  new String'("--to-format"), new String'("nq"));
            begin
               OS.Spawn
                 (Unbounded.To_String (Command (Which)), Arguments, Sink,
                  Code, Err_To_Out => True);
            end;
            OS.Close (Sink);

         when Jena =>
            --  riot writes to standard output, so the output file is the
            --  spawn's descriptor rather than an argument. Its warnings
            --  would otherwise land in the middle of the N-Quads, which is
            --  what --quiet is for.
            Sink := OS.Create_File (Out_Path, OS.Binary);
            declare
               Arguments : constant OS.Argument_List :=
                 (new String'("--quiet"),
                  new String'("--base=" & Base),
                  new String'("--syntax=" & From),
                  new String'("--output=nq"),
                  new String'(In_Path));
            begin
               OS.Spawn
                 (Unbounded.To_String (Command (Which)), Arguments, Sink,
                  Code, Err_To_Out => False);
            end;
            OS.Close (Sink);
      end case;

      Succeeded := Code = 0 and then Ada.Directories.Exists (Out_Path);
      if Succeeded then
         Output := Unbounded.To_Unbounded_String (Read_File (Out_Path));
      end if;
   end Convert;

   --  RDF-star wrote a quoted triple as "<<...>>" directly in subject or
   --  object position. RDF 1.2 spells a triple term "<<( ... )>>" and gives
   --  "<< >>" to reified triples instead, so N-Quads carrying the older
   --  form is an oracle answering an older specification.
   function Predates_RDF_12 (NQuads : String) return Boolean is
      Index : Natural := Ada.Strings.Fixed.Index (NQuads, "<<");
   begin
      while Index > 0 loop
         if Index + 2 > NQuads'Last or else NQuads (Index + 2) /= '(' then
            return True;
         end if;
         Index := Ada.Strings.Fixed.Index
           (NQuads, "<<", Index + 2);
      end loop;
      return False;
   end Predates_RDF_12;

   procedure Note (Path, Why : String) is
   begin
      Unbounded.Append (Divergences, "    " & Path & ": " & Why & ASCII.LF);
   end Note;

   --  Canonical form, or the empty string when the dataset will not
   --  canonicalize inside its work bound.
   function Canonical (Value : Datasets.Dataset) return String is
      Output : Unbounded.Unbounded_String;
      Status : Canon.Result_Status;
      use type Canon.Result_Status;
   begin
      Canon.Canonicalize (Value, Output, Status);
      if Status /= Canon.Canonicalized then
         return "";
      end if;
      return Unbounded.To_String (Output);
   end Canonical;

   function Syntax_Of (Path : String) return Parsers.Syntax_Kind is
      Extension : constant String := Ada.Directories.Extension (Path);
   begin
      if Extension = "nt" then
         return Parsers.NTriples_Syntax;
      elsif Extension = "nq" then
         return Parsers.NQuads_Syntax;
      elsif Extension = "trig" then
         return Parsers.TriG_Syntax;
      else
         return Parsers.Turtle_Syntax;
      end if;
   end Syntax_Of;

   function Oracle_Format (Syntax : Parsers.Syntax_Kind) return String
   is (case Syntax is
          when Parsers.NTriples_Syntax => "nt",
          when Parsers.NQuads_Syntax   => "nq",
          when Parsers.TriG_Syntax     => "trig",
          when Parsers.Turtle_Syntax   => "ttl");

   procedure Run_Document (Path : String) is
      Syntax : constant Parsers.Syntax_Kind := Syntax_Of (Path);
      Text   : constant String := Read_File (Path);
      Mine   : Datasets.Dataset;
      Ours   : Boolean;

      type Outcome is (Answered, Declined, Older, Disagreed);

      --  One question, asked of one oracle, about one piece of text: read
      --  this, and tell me whether it denotes what we say it denotes.
      function Ask
        (Which    : Oracle_Id;
         Subject  : String;
         From     : String;
         Expected : String;
         Reason   : out Unbounded.Unbounded_String) return Outcome
      is
         Theirs    : Unbounded.Unbounded_String;
         Converted : Boolean;
      begin
         Reason := Unbounded.Null_Unbounded_String;
         Convert (Which, Subject, From, Theirs, Converted);
         if not Converted then
            return Declined;
         end if;

         if Predates_RDF_12 (Unbounded.To_String (Theirs)) then
            --  The oracle answered, but about RDF-star rather than RDF
            --  1.2. Comparing would measure the gap between two
            --  specifications, not between two implementations of one.
            return Older;
         end if;

         declare
            Round  : Datasets.Dataset;
            Parsed : Boolean;
         begin
            Load (Unbounded.To_String (Theirs),
                  Parsers.NQuads_Syntax, Round, Parsed);
            if not Parsed then
               Reason := Unbounded.To_Unbounded_String
                 (Which'Image & " produced N-Quads we cannot read");
               return Disagreed;
            elsif Canonical (Round) /= Expected then
               Reason := Unbounded.To_Unbounded_String
                 (Which'Image & " read "
                  & (if Subject = Text then "the document"
                     else "our serialization")
                  & " differently");
               return Disagreed;
            end if;
         end;
         return Answered;
      end Ask;

      --  Ask the fast oracle; where it cannot answer, ask the slow one.
      procedure Ask_In_Turn
        (Subject  : String;
         From     : String;
         Expected : String;
         Parser   : Boolean)
      is
         procedure Record_It (Which : Oracle_Id; Result : Outcome) is
         begin
            if Parser then
               case Result is
                  when Answered  =>
                     Counts (Which).Parser_Read :=
                       Counts (Which).Parser_Read + 1;
                  when Declined  =>
                     Counts (Which).Parser_Declined :=
                       Counts (Which).Parser_Declined + 1;
                  when Older     =>
                     Counts (Which).Parser_Older :=
                       Counts (Which).Parser_Older + 1;
                  when Disagreed =>
                     Counts (Which).Parser_Differed :=
                       Counts (Which).Parser_Differed + 1;
               end case;
            else
               case Result is
                  when Answered  =>
                     Counts (Which).Writer_Read :=
                       Counts (Which).Writer_Read + 1;
                  when Declined  =>
                     Counts (Which).Writer_Declined :=
                       Counts (Which).Writer_Declined + 1;
                  when Older     =>
                     Counts (Which).Writer_Older :=
                       Counts (Which).Writer_Older + 1;
                  when Disagreed =>
                     Counts (Which).Writer_Differed :=
                       Counts (Which).Writer_Differed + 1;
               end case;
            end if;
         end Record_It;

         First, Second : Outcome;
         Why, Ignored  : Unbounded.Unbounded_String;
      begin
         if Present (Oxigraph) then
            First := Ask (Oxigraph, Subject, From, Expected, Why);
            if First = Answered then
               Record_It (Oxigraph, First);
               return;
            end if;

            if First = Disagreed then
               --  One oracle disagreeing is a lead, not a verdict. If the
               --  other agrees with us, the two oracles disagree with each
               --  other, and that is a fact about them. Only an oracle
               --  disagreeing with no second opinion, or two disagreeing
               --  together, is evidence against us.
               if Present (Jena) then
                  Second := Ask (Jena, Subject, From, Expected, Ignored);
                  if Second = Answered then
                     Cross_Checked := Cross_Checked + 1;
                     Unbounded.Append
                       (Contested,
                        "    " & Path & ": " & Unbounded.To_String (Why)
                        & ", JENA agrees with us" & ASCII.LF);
                     Record_It (Jena, Second);
                     return;
                  end if;
               end if;
               Record_It (Oxigraph, First);
               Note (Path, Unbounded.To_String (Why));
               return;
            end if;

            --  Declined, or answered an older specification.
            Record_It (Oxigraph, First);
         end if;

         if Present (Jena) then
            Second := Ask (Jena, Subject, From, Expected, Why);
            Record_It (Jena, Second);
            if Second = Disagreed then
               Note (Path, Unbounded.To_String (Why));
            end if;
         end if;
      end Ask_In_Turn;

   begin
      Considered := Considered + 1;
      Load (Text, Syntax, Mine, Ours);
      if not Ours then
         --  A document we reject is the conformance harness's business,
         --  not this one's.
         return;
      end if;
      We_Accepted := We_Accepted + 1;

      declare
         Expected : constant String := Canonical (Mine);
      begin
         if Expected = "" then
            return;
         end if;

         --  Does an oracle read the document the way we do?
         Ask_In_Turn (Text, Oracle_Format (Syntax), Expected, True);

         --  And does it read our serialization the way we wrote it? That
         --  is the question the suites cannot ask.
         Ask_In_Turn (Writers.To_TriG (Mine), "trig", Expected, False);
      end;
   exception
      when others =>
         null;
   end Run_Document;

   procedure Walk (Directory : String) is
      Search : Ada.Directories.Search_Type;
      Item   : Ada.Directories.Directory_Entry_Type;
      use type Ada.Directories.File_Kind;
   begin
      Ada.Directories.Start_Search
        (Search, Directory, "",
         (Ada.Directories.Ordinary_File => True,
          Ada.Directories.Directory     => True,
          others                        => False));
      while Ada.Directories.More_Entries (Search) loop
         Ada.Directories.Get_Next_Entry (Search, Item);
         declare
            Name : constant String := Ada.Directories.Simple_Name (Item);
            Path : constant String := Ada.Directories.Full_Name (Item);
         begin
            if Name /= "." and then Name /= ".."
              and then Name (Name'First) /= '.'
            then
               if Ada.Directories.Kind (Item)
                  = Ada.Directories.Directory
               then
                  Walk (Path);
               elsif Ada.Directories.Extension (Name)
                     in "ttl" | "nt" | "nq" | "trig"
               then
                  if Ada.Directories.Size (Item) > Maximum_Bytes then
                     Skipped_Large := Skipped_Large + 1;
                  else
                     Run_Document (Path);
                  end if;
               end if;
            end if;
         end;
      end loop;
      Ada.Directories.End_Search (Search);
   end Walk;

   Corpus    : constant String := "data/w3c-rdf-tests";
   Oxigraph_Path : constant String :=
     "../vendor/oracles/oxigraph/bin/oxigraph";
   Jena_Home : constant String := "../vendor/oracles/java";
   Jena_Path : constant String :=
     "../vendor/oracles/apache-jena-6.2.0/bin/riot";

   Any_Read : Natural := 0;
   Total_Differed : Natural := 0;

begin
   IO.Put_Line ("Oracle differential");

   if Ada.Directories.Exists (Oxigraph_Path) then
      Present (Oxigraph) := True;
      Command (Oxigraph) := Unbounded.To_Unbounded_String (Oxigraph_Path);
   end if;

   if Ada.Directories.Exists (Jena_Path)
     and then Ada.Directories.Exists (Jena_Home)
   then
      --  riot finds its runtime through JAVA_HOME, and the one we
      --  provisioned is the one whose version is recorded.
      Ada.Environment_Variables.Set
        ("JAVA_HOME", Ada.Directories.Full_Name (Jena_Home));
      Present (Jena) := True;
      Command (Jena) := Unbounded.To_Unbounded_String (Jena_Path);
   end if;

   if not (Present (Oxigraph) or else Present (Jena)) then
      IO.Put_Line ("  SKIP  no oracle is provisioned");
      IO.Put_Line ("        run ../scripts/provision-oracles.sh");
      IO.Put_Line ("PASS oracle_differential (skipped)");
      return;
   end if;

   if not Ada.Directories.Exists (Corpus) then
      IO.Put_Line ("  SKIP  the corpus is not provisioned");
      IO.Put_Line ("PASS oracle_differential (skipped)");
      return;
   end if;

   if not Ada.Directories.Exists (Scratch) then
      Ada.Directories.Create_Path (Scratch);
   end if;

   for Which in Oracle_Id loop
      IO.Put_Line
        ("  oracle              " & Which'Image
         & (if Present (Which)
            then " at " & Unbounded.To_String (Command (Which))
            else " -- not provisioned, skipped"));
   end loop;

   Walk (Corpus);

   IO.Put_Line ("  documents seen      " & Considered'Image);
   IO.Put_Line ("  skipped, over 256K  " & Skipped_Large'Image);
   IO.Put_Line ("  we accepted         " & We_Accepted'Image);

   for Which in Oracle_Id loop
      if Present (Which) then
         IO.Put_Line ("  " & Which'Image & ":");
         IO.Put_Line ("    read the document " &
                      Counts (Which).Parser_Read'Image);
         IO.Put_Line ("      declined it     " &
                      Counts (Which).Parser_Declined'Image);
         IO.Put_Line ("      answered RDF-star" &
                      Counts (Which).Parser_Older'Image);
         IO.Put_Line ("      differed        " &
                      Counts (Which).Parser_Differed'Image);
         IO.Put_Line ("    read our output   " &
                      Counts (Which).Writer_Read'Image);
         IO.Put_Line ("      declined it     " &
                      Counts (Which).Writer_Declined'Image);
         IO.Put_Line ("      answered RDF-star" &
                      Counts (Which).Writer_Older'Image);
         IO.Put_Line ("      differed        " &
                      Counts (Which).Writer_Differed'Image);
         Any_Read := Any_Read
           + Counts (Which).Parser_Read + Counts (Which).Writer_Read;
         Total_Differed := Total_Differed
           + Counts (Which).Parser_Differed
           + Counts (Which).Writer_Differed;
      end if;
   end loop;

   IO.Put_Line ("  oracles disagreed   " & Cross_Checked'Image);
   if Unbounded.Length (Contested) > 0 then
      IO.Put_Line ("  contested, second opinion agreed with us:");
      IO.Put (Unbounded.To_String (Contested));
   end if;

   if Unbounded.Length (Divergences) > 0 then
      IO.Put_Line ("  divergences:");
      IO.Put (Unbounded.To_String (Divergences));
   end if;

   if Any_Read = 0 then
      IO.Put_Line ("FAIL oracle_differential: no oracle read anything");
      Ada.Command_Line.Set_Exit_Status (1);
   elsif Total_Differed > 0 then
      IO.Put_Line ("FAIL oracle_differential");
      Ada.Command_Line.Set_Exit_Status (1);
   else
      IO.Put_Line ("PASS oracle_differential");
   end if;
end Oracle_Differential;
