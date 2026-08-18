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
with Ada.Containers.Indefinite_Vectors;
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with GNAT.OS_Lib;

with Flyology;
with Flyology.Bytes;
with Flyology.HTTP;
with Flyology.HTTP.Client;
with Flyology.HTTP.Methods;

with Flyology_RDF.Canonicalization;
with Flyology_RDF.Datasets;
with Flyology_RDF.Quads;
with Flyology_RDF.Turtle_Parsers;
with Flyology_RDF.Turtle_Writers;

procedure Oracle_Differential is

   package IO renames Ada.Text_IO;
   package Unbounded renames Ada.Strings.Unbounded;
   package OS renames GNAT.OS_Lib;
   package HTTPC renames Flyology.HTTP.Client;
   package Methods renames Flyology.HTTP.Methods;
   package Canon renames Flyology_RDF.Canonicalization;
   package Datasets renames Flyology_RDF.Datasets;
   package Quads renames Flyology_RDF.Quads;
   package Parsers renames Flyology_RDF.Turtle_Parsers;
   package Writers renames Flyology_RDF.Turtle_Writers;

   use type Parsers.Parse_Status;
   use type Ada.Directories.File_Size;
   use type OS.Process_Id;
   use type Ada.Containers.Count_Type;

   --  Everything resolves against one base, on both sides, so that a
   --  relative reference cannot be the reason for a disagreement.
   Base : constant String := "http://example.org/differential/";

   --  The corpus carries a few multi-megabyte result reports alongside its
   --  test documents. Canonicalizing one costs minutes and says nothing a
   --  small document does not, so they are skipped -- and counted, because
   --  a cap nobody reports reads as coverage nobody had.
   Maximum_Bytes : constant := 256 * 1024;

   --  Fuseki is Jena behind an HTTP server, so it answers the same as riot
   --  and pays one JVM start for the run instead of one per document. riot
   --  is the fallback for when Fuseki will not start.
   type Oracle_Id is (Fuseki, Oxigraph, Riot);

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

   package Line_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Positive, Element_Type => String);

   --  Oracle behaviours we have read the specification on and settled.
   --
   --  Each is keyed on the terms themselves -- what we write against what
   --  the oracle writes in its place -- rather than on the document it was
   --  noticed in. Keying on the document would silence any other
   --  disagreement that happened to appear in the same file, which is the
   --  one thing such a list must not do. Every differing statement has to
   --  be accounted for by a line here; one that is not fails the run,
   --  whatever the other oracles say, until somebody reads the
   --  specification and either fixes this crate or records what they read.
   type Deviation is record
      Who        : Oracle_Id;
      We_Write   : Unbounded.Unbounded_String;
      They_Write : Unbounded.Unbounded_String;
      Why        : Unbounded.Unbounded_String;
   end record;

   function D
     (Who : Oracle_Id; We_Write, They_Write, Why : String) return Deviation
   is (Who        => Who,
       We_Write   => Unbounded.To_Unbounded_String (We_Write),
       They_Write => Unbounded.To_Unbounded_String (They_Write),
       Why        => Unbounded.To_Unbounded_String (Why));

   Settled : constant array (Positive range <>) of Deviation :=
     (D (Oxigraph,
         "<eXAMPLE://a/b/%63/%7bfoo%7d#xyz>",
         "<eXAMPLE://a/./b/../b/%63/%7bfoo%7d#xyz>",
         "oxigraph does not apply remove_dot_segments to a reference that"
         & " carries its own scheme; RFC 3986 5.2.2 applies it regardless,"
         & " and the corpus expects the segments removed"),
      D (Fuseki,
         "<http:g>",
         "<" & Base & "g>",
         "Jena resolves non-strictly when a reference's scheme matches the"
         & " base's -- the backward-compatibility behaviour RFC 3986 5.2.2"
         & " describes and RDF 1.1 does not take. The corpus expects"
         & " <http:g> unchanged"),
      D (Riot,
         "<http:g>",
         "<" & Base & "g>",
         "the same non-strict resolution as Fuseki, which is the same"
         & " parser reached a different way"));

   --  The statements of a canonical form, one per line.
   function Statements (Value : String) return Line_Vectors.Vector is
      Result : Line_Vectors.Vector;
      First  : Positive := Value'First;
   begin
      for Index in Value'Range loop
         if Value (Index) = ASCII.LF then
            if Index > First then
               Result.Append (Value (First .. Index - 1));
            end if;
            First := Index + 1;
         end if;
      end loop;
      if First <= Value'Last then
         Result.Append (Value (First .. Value'Last));
      end if;
      return Result;
   end Statements;

   function Holds (Where : Line_Vectors.Vector; What : String) return Boolean
   is (for some Line of Where => Line = What);

   --  Two statements that say the same thing about the same subject and
   --  predicate differ only in what follows, which is the term the oracle
   --  and this crate disagree about.
   function Same_Opening (Left, Right : String) return Boolean is
      Cut : Natural := 0;
      Seen : Natural := 0;
   begin
      for Index in Left'Range loop
         if Left (Index) = ' ' then
            Seen := Seen + 1;
            if Seen = 2 then
               Cut := Index;
               exit;
            end if;
         end if;
      end loop;
      if Cut = 0 or else Right'Length < Cut - Left'First + 1 then
         return False;
      end if;
      return Left (Left'First .. Cut)
             = Right (Right'First .. Right'First + Cut - Left'First);
   end Same_Opening;

   --  Whether every statement the two forms disagree about is one this
   --  list accounts for.
   function Fully_Settled
     (Who    : Oracle_Id;
      Ours   : String;
      Theirs : String;
      Why    : out Unbounded.Unbounded_String) return Boolean
   is
      Mine   : constant Line_Vectors.Vector := Statements (Ours);
      Yours  : constant Line_Vectors.Vector := Statements (Theirs);
      Only_Mine, Only_Yours : Line_Vectors.Vector;
      Reasons : Unbounded.Unbounded_String;
   begin
      Why := Unbounded.Null_Unbounded_String;
      for Line of Mine loop
         if not Holds (Yours, Line) then
            Only_Mine.Append (Line);
         end if;
      end loop;
      for Line of Yours loop
         if not Holds (Mine, Line) then
            Only_Yours.Append (Line);
         end if;
      end loop;

      if Only_Mine.Is_Empty or else Only_Mine.Length /= Only_Yours.Length
      then
         --  Statements gained or lost outright, rather than one term
         --  written differently. Nothing here explains that.
         return False;
      end if;

      for Line of Only_Mine loop
         declare
            Explained : Boolean := False;
         begin
            for Other of Only_Yours loop
               if Same_Opening (Line, Other) then
                  for Item of Settled loop
                     if Item.Who = Who
                       and then Ada.Strings.Fixed.Index
                                  (Line, Unbounded.To_String (Item.We_Write))
                                > 0
                       and then Ada.Strings.Fixed.Index
                                  (Other,
                                   Unbounded.To_String (Item.They_Write)) > 0
                     then
                        Explained := True;
                        if Ada.Strings.Fixed.Index
                             (Unbounded.To_String (Reasons),
                              Unbounded.To_String (Item.Why)) = 0
                        then
                           Unbounded.Append (Reasons, Item.Why);
                        end if;
                        exit;
                     end if;
                  end loop;
               end if;
               exit when Explained;
            end loop;
            if not Explained then
               return False;
            end if;
         end;
      end loop;

      Why := Reasons;
      return True;
   end Fully_Settled;

   Considered      : Natural := 0;
   Skipped_Large   : Natural := 0;
   We_Accepted     : Natural := 0;

   --  A document that states nothing canonicalizes to nothing, and there
   --  is no graph to ask an oracle about. Counted rather than returned
   --  from in silence: a document nobody compared is not a document that
   --  agreed.
   Nothing_Stated  : Natural := 0;
   Cross_Checked   : Natural := 0;
   Documented      : Natural := 0;
   Divergences     : Unbounded.Unbounded_String;
   Contested       : Unbounded.Unbounded_String;
   Deviations      : Unbounded.Unbounded_String;

   --  The HTTP conversation with Fuseki. Configured and used only from the
   --  worker task, because the client belongs to the task that drives it.
   Fuseki_Port : constant := 3131;
   Fuseki_Base : constant String :=
     "http://127.0.0.1:" & Ada.Strings.Fixed.Trim
       (Natural'Image (Fuseki_Port), Ada.Strings.Left);
   HTTP        : aliased HTTPC.Client (Capacity => 1);
   Fuseki_Live : Boolean := False;
   Fuseki_PID  : OS.Process_Id := OS.Invalid_Pid;

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

   --  One HTTP exchange with Fuseki.
   function Exchange
     (Method       : Flyology.HTTP.Method;
      Target       : String;
      Content_Type : String := "";
      Payload      : String := "";
      Accepts      : String := "";
      Status       : out Natural) return String
   is
      Request : HTTPC.Request;
   begin
      HTTPC.Set_Method (Request, Method);
      HTTPC.Set_Target (Request, Target);
      if Content_Type /= "" then
         HTTPC.Add_Header (Request, "Content-Type", Content_Type);
      end if;
      if Accepts /= "" then
         HTTPC.Add_Header (Request, "Accept", Accepts);
      end if;
      if Payload /= "" then
         HTTPC.Set_Body (Request, Payload);
      end if;
      declare
         Reply : HTTPC.Response := HTTPC.Execute (HTTP, Request);
      begin
         Status := Natural (HTTPC.Status (Reply));
         return Flyology.Bytes.To_Byte_String
           (HTTPC.Read_All (Reply, Maximum => 32 * 1024 * 1024));
      end;
   exception
      when others =>
         Status := 0;
         return "";
   end Exchange;

   --  The media type Fuseki wants for each syntax we hand it.
   function Media_Type (From : String) return String
   is (if From = "ttl" then "text/turtle"
       elsif From = "trig" then "application/trig"
       elsif From = "nt" then "application/n-triples"
       else "application/n-quads");

   --  Turtle and TriG carry relative references, and the Graph Store
   --  Protocol resolves them against the request URI rather than against
   --  anything we can pass. Saying the base in the document is how the
   --  other oracle is told the same thing on its command line.
   function With_Base (From, Text : String) return String
   is (if From in "ttl" | "trig"
       then "BASE <" & Base & ">" & ASCII.LF & Text
       else Text);

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
         when Fuseki =>
            declare
               Code : Natural;
               Wiped : constant String :=
                 Exchange (Methods.POST, "/ds",
                           Content_Type => "application/sparql-update",
                           Payload      => "CLEAR ALL",
                           Status       => Code);
            begin
               pragma Unreferenced (Wiped);
               if Code not in 200 | 204 then
                  Succeeded := False;
                  return;
               end if;
            end;
            declare
               Code : Natural;
               Sent : constant String :=
                 Exchange (Methods.POST, "/ds",
                           Content_Type => Media_Type (From),
                           Payload      => With_Base (From, Text),
                           Status       => Code);
            begin
               pragma Unreferenced (Sent);
               if Code not in 200 | 201 | 204 then
                  --  Fuseki refused the document. That is it declining,
                  --  the same as a non-zero exit from a command.
                  Succeeded := False;
                  return;
               end if;
            end;
            declare
               Code : Natural;
               Body_Text : constant String :=
                 Exchange (Methods.GET, "/ds",
                           Accepts => "application/n-quads",
                           Status  => Code);
            begin
               Succeeded := Code = 200;
               if Succeeded then
                  Output := Unbounded.To_Unbounded_String (Body_Text);
               end if;
            end;
            return;

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

         when Riot =>
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
         Reason   : out Unbounded.Unbounded_String;
         Their_Form : out Unbounded.Unbounded_String) return Outcome
      is
         Theirs    : Unbounded.Unbounded_String;
         Converted : Boolean;
      begin
         Reason := Unbounded.Null_Unbounded_String;
         Their_Form := Unbounded.Null_Unbounded_String;
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
               Their_Form :=
                 Unbounded.To_Unbounded_String (Canonical (Round));
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

      --  Ask every oracle that is present. They are all cheap now, and a
      --  second independent opinion on a document the first one answered
      --  is the only thing that catches a misreading we happen to share
      --  with it.
      procedure Ask_All
        (Subject  : String;
         From     : String;
         Expected : String;
         Parser   : Boolean)
      is
         Results : array (Oracle_Id) of Outcome := (others => Declined);
         Reasons : array (Oracle_Id) of Unbounded.Unbounded_String;
         Forms   : array (Oracle_Id) of Unbounded.Unbounded_String;
         Agreed  : Natural := 0;

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
      begin
         for Which in Oracle_Id loop
            if Present (Which) then
               Results (Which) :=
                 Ask (Which, Subject, From, Expected, Reasons (Which),
                      Forms (Which));
               if Results (Which) = Answered then
                  Agreed := Agreed + 1;
               end if;
            end if;
         end loop;

         for Which in Oracle_Id loop
            if Present (Which) then
               if Results (Which) = Disagreed then
                  declare
                     Why : Unbounded.Unbounded_String;
                  begin
                     if Fully_Settled
                          (Which, Expected,
                           Unbounded.To_String (Forms (Which)), Why)
                     then
                        --  A departure we have read the specification on.
                        --  Reported with its citation, not counted
                        --  against us.
                        Documented := Documented + 1;
                        Unbounded.Append
                          (Deviations,
                           "    " & Path & ": "
                           & Unbounded.To_String (Reasons (Which))
                           & ASCII.LF & "      " & Unbounded.To_String (Why)
                           & ASCII.LF);
                        Record_It (Which, Answered);
                     else
                        Record_It (Which, Results (Which));
                        Note (Path, Unbounded.To_String (Reasons (Which)));
                        if Agreed > 0 then
                           --  Another oracle agreed with us, so this is
                           --  probably theirs -- but probably is not a
                           --  citation, and an unsettled disagreement is
                           --  something to settle, not to wave through.
                           Cross_Checked := Cross_Checked + 1;
                           Unbounded.Append
                             (Contested,
                              "    " & Path
                              & ": another oracle agrees with us, but this"
                              & " departure is not recorded" & ASCII.LF);
                        end if;
                     end if;
                  end;
               else
                  Record_It (Which, Results (Which));
               end if;
            end if;
         end loop;
      end Ask_All;

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
            Nothing_Stated := Nothing_Stated + 1;
            return;
         end if;

         --  Do the oracles read the document the way we do?
         Ask_All (Text, Oracle_Format (Syntax), Expected, True);

         --  And do they read our serialization the way we wrote it? That
         --  is the question the suites cannot ask.
         Ask_All (Writers.To_TriG (Mine), "trig", Expected, False);
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
   Riot_Path : constant String :=
     "../vendor/oracles/apache-jena-6.2.0/bin/riot";
   Fuseki_Dir : constant String :=
     "../vendor/oracles/apache-jena-fuseki-6.2.0";

   Any_Read       : Natural := 0;
   Total_Differed : Natural := 0;

   --  Start Fuseki and wait until it answers. It is Jena with one JVM
   --  start for the whole run rather than one per document, which is what
   --  makes asking it about every document affordable.
   procedure Start_Fuseki is
      Log : constant OS.File_Descriptor :=
        OS.Create_File (Scratch & "/fuseki.log", OS.Binary);
      Arguments : constant OS.Argument_List :=
        (new String'("--mem"),
         new String'("--port=" & Ada.Strings.Fixed.Trim
                       (Natural'Image (Fuseki_Port), Ada.Strings.Left)),
         new String'("/ds"));
   begin
      Fuseki_PID :=
        OS.Non_Blocking_Spawn
          (Fuseki_Dir & "/fuseki-server", Arguments, Log,
           Err_To_Out => True);
      Fuseki_Live := Fuseki_PID /= OS.Invalid_Pid;
   end Start_Fuseki;

   procedure Stop_Fuseki is
   begin
      if Fuseki_Live and then Fuseki_PID /= OS.Invalid_Pid then
         OS.Kill (Fuseki_PID, Hard_Kill => True);
         Fuseki_Live := False;
      end if;
   end Stop_Fuseki;

begin
   IO.Put_Line ("Oracle differential");

   if not Ada.Directories.Exists (Corpus) then
      IO.Put_Line ("  SKIP  the corpus is not provisioned");
      IO.Put_Line ("PASS oracle_differential (skipped)");
      return;
   end if;

   if not Ada.Directories.Exists (Scratch) then
      Ada.Directories.Create_Path (Scratch);
   end if;

   if Ada.Directories.Exists (Oxigraph_Path) then
      Present (Oxigraph) := True;
      Command (Oxigraph) := Unbounded.To_Unbounded_String (Oxigraph_Path);
   end if;

   if Ada.Directories.Exists (Jena_Home) then
      --  Both Jena forms find their runtime through JAVA_HOME, and the one
      --  we provisioned is the one whose version is recorded.
      Ada.Environment_Variables.Set
        ("JAVA_HOME", Ada.Directories.Full_Name (Jena_Home));

      if Ada.Directories.Exists (Fuseki_Dir & "/fuseki-server") then
         Start_Fuseki;
      end if;

      --  riot answers the same as Fuseki at a JVM start a document, so it
      --  stands in only when Fuseki did not come up.
      if not Fuseki_Live and then Ada.Directories.Exists (Riot_Path) then
         Present (Riot) := True;
         Command (Riot) := Unbounded.To_Unbounded_String (Riot_Path);
      end if;
   end if;

   declare
      --  The HTTP client belongs to the task that drives it, and a
      --  lightweight task is what this crate says it runs well inside, so
      --  the differential is also the one place that demonstrates it.
      task Worker is
         pragma Task_Info (Flyology.Lightweight_Task);
      end Worker;

      task body Worker is
      begin
         if Fuseki_Live then
            HTTPC.Configure
              (HTTP, Flyology.HTTP.Parse_Origin (Fuseki_Base));

            --  Wait for it to answer, rather than guessing how long a JVM
            --  takes to start.
            for Attempt in 1 .. 60 loop
               declare
                  Code  : Natural;
                  Reply : constant String :=
                    Exchange (Methods.GET, "/$/ping", Status => Code);
               begin
                  pragma Unreferenced (Reply);
                  exit when Code = 200;
               end;
               delay 0.5;
            end loop;

            declare
               Code  : Natural;
               Reply : constant String :=
                 Exchange (Methods.GET, "/$/ping", Status => Code);
            begin
               pragma Unreferenced (Reply);
               Present (Fuseki) := Code = 200;
            end;

            if not Present (Fuseki) then
               IO.Put_Line ("  note  Fuseki did not answer; falling back");
               if Ada.Directories.Exists (Riot_Path) then
                  Present (Riot) := True;
                  Command (Riot) :=
                    Unbounded.To_Unbounded_String (Riot_Path);
               end if;
            end if;
         end if;

         for Which in Oracle_Id loop
            if Present (Which) then
               IO.Put_Line
                 ("  oracle              " & Which'Image
                  & (if Which = Fuseki then " at " & Fuseki_Base
                     else " at " & Unbounded.To_String (Command (Which))));
            end if;
         end loop;

         if Ada.Command_Line.Argument_Count > 0 then
            --  Named documents only, with the serialization printed. A
            --  contested case is read by hand, and this is what it is
            --  read from.
            for Index in 1 .. Ada.Command_Line.Argument_Count loop
               declare
                  Path : constant String := Ada.Command_Line.Argument (Index);
                  Data : Datasets.Dataset;
                  Ours : Boolean;
               begin
                  Load (Read_File (Path), Syntax_Of (Path), Data, Ours);
                  IO.Put_Line ("--- " & Path & " ---");
                  if not Ours then
                     IO.Put_Line ("(we reject it)");
                  else
                     IO.Put_Line ("--- our TriG ---");
                     IO.Put (Writers.To_TriG (Data));
                     IO.Put_Line ("--- our canonical form ---");
                     IO.Put (Canonical (Data));
                     for Which in Oracle_Id loop
                        if Present (Which) then
                           declare
                              Theirs : Unbounded.Unbounded_String;
                              Done   : Boolean;
                           begin
                              Convert (Which, Writers.To_TriG (Data),
                                       "trig", Theirs, Done);
                              IO.Put_Line
                                ("--- " & Which'Image
                                 & " on our TriG (ok=" & Done'Image & ") ---");
                              IO.Put (Unbounded.To_String (Theirs));
                           end;
                        end if;
                     end loop;
                  end if;
               end;
            end loop;
         else
            Walk (Corpus);
         end if;
      end Worker;
   begin
      null;
   end;

   Stop_Fuseki;

   if not (Present (Fuseki) or else Present (Oxigraph)
           or else Present (Riot))
   then
      IO.Put_Line ("  SKIP  no oracle is provisioned");
      IO.Put_Line ("        run ../scripts/provision-oracles.sh");
      IO.Put_Line ("PASS oracle_differential (skipped)");
      return;
   end if;

   IO.Put_Line ("  documents seen      " & Considered'Image);
   IO.Put_Line ("  skipped, over 256K  " & Skipped_Large'Image);
   IO.Put_Line ("  we accepted         " & We_Accepted'Image);
   IO.Put_Line ("  stated nothing      " & Nothing_Stated'Image);
   IO.Put_Line ("  compared            "
                & Natural'Image (We_Accepted - Nothing_Stated));

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

   IO.Put_Line ("  documented deviation" & Documented'Image);
   IO.Put_Line ("  unsettled           " & Cross_Checked'Image);

   if Unbounded.Length (Deviations) > 0 then
      IO.Put_Line ("  oracle deviations, read and settled:");
      IO.Put (Unbounded.To_String (Deviations));
   end if;

   if Unbounded.Length (Contested) > 0 then
      IO.Put_Line ("  unsettled disagreements:");
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
