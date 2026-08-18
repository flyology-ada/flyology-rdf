--  Benchmarks for flyology_rdf, flyology_n3 and flyology_sparql.
--
--  Every case is generated here rather than read from a corpus, so a run
--  measures the same work on any machine and needs nothing provisioned.
--  Each is timed several times and reported by its median: a mean is moved
--  by one descheduled iteration, and the middle of an odd number of runs is
--  not.
--
--  The output is one line per case, in a fixed order and a fixed shape, so
--  that two runs can be compared with a diff and a change can be measured
--  rather than felt.

with Ada.Command_Line;
with Ada.Real_Time;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with Flyology_RDF.Canonicalization;
with Flyology_RDF.Codecs;
with Flyology_RDF.Datasets;
with Flyology_RDF.NQuads_Writers;
with Flyology_RDF.Quads;
with Flyology_RDF.Turtle_Parsers;
with Flyology_RDF.Turtle_Writers;

with Flyology_N3.Model;
with Flyology_N3.Parsers;

with Flyology_SPARQL.Parsers;
with Flyology_SPARQL.Syntax;

procedure Benchmarks is

   package IO renames Ada.Text_IO;
   package RT renames Ada.Real_Time;
   package Unbounded renames Ada.Strings.Unbounded;
   package Canon renames Flyology_RDF.Canonicalization;
   package Codecs renames Flyology_RDF.Codecs;
   package Datasets renames Flyology_RDF.Datasets;
   package Quads renames Flyology_RDF.Quads;
   package Parsers renames Flyology_RDF.Turtle_Parsers;
   package Writers renames Flyology_RDF.Turtle_Writers;
   package Line_Writers renames Flyology_RDF.NQuads_Writers;

   use type RT.Time;

   --  Odd, so the median is an observation rather than an average of two.
   Repetitions : Natural := 7;

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

   function Load
     (Text   : String;
      Syntax : Parsers.Syntax_Kind) return Datasets.Dataset
   is
      Sink   : Collector;
      Parser : Parsers.Parser :=
        Parsers.Create
          (Source_Name => "bench",
           Base_IRI    => "http://example.org/bench/",
           Syntax      => Syntax);
      Ignored : Parsers.Parse_Status;
   begin
      Parsers.Feed (Parser, Text, Sink);
      Ignored := Parsers.Finish (Parser, Sink);
      return Sink.Data;
   end Load;

   function Decimal (Value : Natural) return String
   is (Ada.Strings.Fixed.Trim (Natural'Image (Value), Ada.Strings.Left));

   ---------------------------------------------------------------------
   --  Cases
   ---------------------------------------------------------------------

   --  Ordinary Turtle: prefixed names, a datatype, a language tag. The
   --  common path, and the one most consumers spend their time in.
   function Plain_Turtle (Statements : Positive) return String is
      Buffer : Unbounded.Unbounded_String;
   begin
      Unbounded.Append (Buffer, "@prefix : <http://example.org/vocab#> ." & ASCII.LF);
      Unbounded.Append (Buffer, "@prefix xsd: <http://www.w3.org/2001/XMLSchema#> ." & ASCII.LF);
      for Index in 1 .. Statements loop
         declare
            N : constant String := Decimal (Index);
         begin
            Unbounded.Append
              (Buffer,
               ":s" & N & " :p" & Decimal (Index mod 8) & " ""value " & N
               & """ ; :q " & N & " ; :r ""tagged""@en ; :t """ & N
               & """^^xsd:integer ." & ASCII.LF);
         end;
      end loop;
      return Unbounded.To_String (Buffer);
   end Plain_Turtle;

   --  Literals that make the scanner work: escapes it must decode and
   --  re-encode rather than copy.
   function Escaped_Turtle (Statements : Positive) return String is
      Buffer : Unbounded.Unbounded_String;
   begin
      Unbounded.Append (Buffer, "@prefix : <http://example.org/vocab#> ." & ASCII.LF);
      for Index in 1 .. Statements loop
         Unbounded.Append
           (Buffer,
            ":s" & Decimal (Index) & " :p ""a\tb\nc\""d\\eéf\U0001F600g"" ."
            & ASCII.LF);
      end loop;
      return Unbounded.To_String (Buffer);
   end Escaped_Turtle;

   --  N-Triples, where there is no prefix table and every IRI is written
   --  out. The line-oriented path.
   function Lines (Statements : Positive) return String is
      Buffer : Unbounded.Unbounded_String;
   begin
      for Index in 1 .. Statements loop
         declare
            N : constant String := Decimal (Index);
         begin
            Unbounded.Append
              (Buffer,
               "<http://example.org/vocab#s" & N & "> "
               & "<http://example.org/vocab#p> "
               & """value " & N & """ ." & ASCII.LF);
         end;
      end loop;
      return Unbounded.To_String (Buffer);
   end Lines;

   --  Blank nodes that look alike from their immediate surroundings, which
   --  is the case canonicalization has to work for rather than guess.
   function Blank_Web (Nodes : Positive) return String is
      Buffer : Unbounded.Unbounded_String;
   begin
      Unbounded.Append (Buffer, "@prefix : <http://example.org/vocab#> ." & ASCII.LF);
      for Index in 1 .. Nodes loop
         declare
            N : constant String := Decimal (Index);
            M : constant String := Decimal ((Index mod Nodes) + 1);
         begin
            Unbounded.Append
              (Buffer,
               "_:b" & N & " :next _:b" & M & " ; :label ""node"" ." & ASCII.LF);
         end;
      end loop;
      return Unbounded.To_String (Buffer);
   end Blank_Web;

   function N3_Document (Statements : Positive) return String is
      Buffer : Unbounded.Unbounded_String;
   begin
      Unbounded.Append (Buffer, "@prefix : <http://example.org/vocab#> ." & ASCII.LF);
      for Index in 1 .. Statements loop
         declare
            N : constant String := Decimal (Index);
         begin
            Unbounded.Append
              (Buffer,
               "{ :s" & N & " :p ?x } => { :s" & N & " :q ?x } ." & ASCII.LF);
         end;
      end loop;
      return Unbounded.To_String (Buffer);
   end N3_Document;

   function SPARQL_Query (Patterns : Positive) return String is
      Buffer : Unbounded.Unbounded_String;
   begin
      Unbounded.Append (Buffer, "PREFIX : <http://example.org/vocab#>" & ASCII.LF);
      Unbounded.Append (Buffer, "SELECT ?s (COUNT(?o) AS ?c) WHERE {" & ASCII.LF);
      for Index in 1 .. Patterns loop
         declare
            N : constant String := Decimal (Index);
         begin
            Unbounded.Append
              (Buffer,
               "  ?s :p" & N & " ?o" & N & " . OPTIONAL { ?s :q" & N
               & " ?r" & N & " } FILTER (?o" & N & " != " & N & ")"
               & ASCII.LF);
         end;
      end loop;
      Unbounded.Append (Buffer, "} GROUP BY ?s ORDER BY ?s LIMIT 10" & ASCII.LF);
      return Unbounded.To_String (Buffer);
   end SPARQL_Query;

   ---------------------------------------------------------------------
   --  Timing
   ---------------------------------------------------------------------

   type Duration_Array is array (Positive range <>) of Duration;

   function Median (Values : Duration_Array) return Duration is
      Sorted : Duration_Array := Values;
   begin
      for Outer in Sorted'First .. Sorted'Last - 1 loop
         for Inner in Outer + 1 .. Sorted'Last loop
            if Sorted (Inner) < Sorted (Outer) then
               declare
                  Swap : constant Duration := Sorted (Outer);
               begin
                  Sorted (Outer) := Sorted (Inner);
                  Sorted (Inner) := Swap;
               end;
            end if;
         end loop;
      end loop;
      return Sorted (Sorted'First + Sorted'Length / 2);
   end Median;

   --  Two decimals, right-aligned, so a column of results can be read
   --  down and two runs can be diffed.
   function Fixed (Value : Long_Float; Width : Positive) return String is
      Scaled : constant Long_Float := Long_Float'Rounding (Value * 100.0);
      Whole  : constant Long_Long_Integer := Long_Long_Integer (Scaled);
      Digits_Text : constant String :=
        Ada.Strings.Fixed.Trim
          (Long_Long_Integer'Image (abs Whole), Ada.Strings.Left);
      Padded : constant String :=
        (if Digits_Text'Length < 3
         then (1 .. 3 - Digits_Text'Length => '0') & Digits_Text
         else Digits_Text);
      Body_Text : constant String :=
        (if Whole < 0 then "-" else "")
        & Padded (Padded'First .. Padded'Last - 2) & "."
        & Padded (Padded'Last - 1 .. Padded'Last);
   begin
      if Body_Text'Length >= Width then
         return Body_Text;
      end if;
      return (1 .. Width - Body_Text'Length => ' ') & Body_Text;
   end Fixed;

   procedure Report (Name : String; Taken : Duration; Bytes : Natural) is
      Micros : constant Long_Float := Long_Float (Taken) * 1.0E6;
      Rate   : constant Long_Float :=
        (if Taken > 0.0
         then Long_Float (Bytes) / Long_Float (Taken) / 1.0E6
         else 0.0);
      Name_Field : String (1 .. 24) := (others => ' ');
   begin
      Name_Field (1 .. Natural'Min (Name'Length, 24)) :=
        Name (Name'First .. Name'First + Natural'Min (Name'Length, 24) - 1);
      IO.Put_Line
        ("  " & Name_Field & Fixed (Micros, 12) & " us "
         & Fixed (Rate, 9) & " MB/s");
   end Report;

   generic
      with procedure Work;
   procedure Measure (Name : String; Bytes : Natural);

   procedure Measure (Name : String; Bytes : Natural) is
      Taken : Duration_Array (1 .. Repetitions);
   begin
      --  One untimed pass, so that first-touch page faults and any lazy
      --  elaboration land outside the measurement.
      Work;
      for Round in Taken'Range loop
         declare
            Started : constant RT.Time := RT.Clock;
         begin
            Work;
            Taken (Round) :=
              RT.To_Duration (RT.Clock - Started);
         end;
      end loop;
      Report (Name, Median (Taken), Bytes);
   end Measure;

   ---------------------------------------------------------------------

   Turtle_Text  : constant String := Plain_Turtle (2_000);
   Escaped_Text : constant String := Escaped_Turtle (2_000);
   Lines_Text   : constant String := Lines (4_000);
   Blank_Text   : constant String := Blank_Web (40);
   N3_Text      : constant String := N3_Document (1_000);
   Query_Text   : constant String := SPARQL_Query (60);

   Turtle_Data : constant Datasets.Dataset :=
     Load (Turtle_Text, Parsers.Turtle_Syntax);
   Blank_Data  : constant Datasets.Dataset :=
     Load (Blank_Text, Parsers.Turtle_Syntax);

   procedure Parse_Turtle is
      Ignored : constant Datasets.Dataset :=
        Load (Turtle_Text, Parsers.Turtle_Syntax);
   begin
      pragma Unreferenced (Ignored);
   end Parse_Turtle;

   procedure Parse_Escaped is
      Ignored : constant Datasets.Dataset :=
        Load (Escaped_Text, Parsers.Turtle_Syntax);
   begin
      pragma Unreferenced (Ignored);
   end Parse_Escaped;

   procedure Parse_Lines is
      Ignored : constant Datasets.Dataset :=
        Load (Lines_Text, Parsers.NTriples_Syntax);
   begin
      pragma Unreferenced (Ignored);
   end Parse_Lines;

   --  The same document a byte at a time. The difference against the whole
   --  parse is what chunking costs.
   procedure Parse_Chunked is
      Sink   : Collector;
      Parser : Parsers.Parser :=
        Parsers.Create
          (Source_Name => "bench",
           Base_IRI    => "http://example.org/bench/",
           Syntax      => Parsers.Turtle_Syntax);
      Ignored : Parsers.Parse_Status;
   begin
      for Index in Turtle_Text'Range loop
         Parsers.Feed (Parser, Turtle_Text (Index .. Index), Sink);
      end loop;
      Ignored := Parsers.Finish (Parser, Sink);
   end Parse_Chunked;

   procedure Write_TriG is
      Ignored : constant String := Writers.To_TriG (Turtle_Data);
   begin
      pragma Unreferenced (Ignored);
   end Write_TriG;

   procedure Write_Lines is
      Total : Natural := 0;
      procedure Note (Statement : Quads.Quad);
      procedure Note (Statement : Quads.Quad) is
      begin
         Total := Total
           + Line_Writers.Write_Quad
               (Statement, Line_Writers.Implicit_Datatype)'Length;
      end Note;
   begin
      Datasets.Iterate (Turtle_Data, Note'Access);
   end Write_Lines;

   procedure Canonicalize_Ground is
      Ignored : constant String := Canon.To_Canonical_NQuads (Turtle_Data);
   begin
      pragma Unreferenced (Ignored);
   end Canonicalize_Ground;

   procedure Canonicalize_Blank is
      Ignored : constant String := Canon.To_Canonical_NQuads (Blank_Data);
   begin
      pragma Unreferenced (Ignored);
   end Canonicalize_Blank;

   procedure Codec_Round is
      Total : Natural := 0;
      procedure Note (Statement : Quads.Quad);
      procedure Note (Statement : Quads.Quad) is
         Encoded : constant String := Codecs.Encode (Statement);
         Back    : constant Quads.Quad := Codecs.Decode_Quad (Encoded);
      begin
         pragma Unreferenced (Back);
         Total := Total + Encoded'Length;
      end Note;
   begin
      Datasets.Iterate (Turtle_Data, Note'Access);
   end Codec_Round;

   procedure Parse_N3 is
      Ignored : constant Flyology_N3.Model.Term :=
        Flyology_N3.Parsers.Parse (N3_Text, "http://example.org/bench/");
   begin
      pragma Unreferenced (Ignored);
   end Parse_N3;

   procedure Parse_SPARQL is
      Ignored : constant Flyology_SPARQL.Syntax.Query :=
        Flyology_SPARQL.Parsers.Parse (Query_Text);
   begin
      pragma Unreferenced (Ignored);
   end Parse_SPARQL;

   ---------------------------------------------------------------------
   --  Scaling
   ---------------------------------------------------------------------
   --  A benchmark reports a number. It cannot say whether that number
   --  grows with the input or with its square, and the second is the
   --  failure that matters: it is invisible at the size measured here
   --  and fatal at the size a caller will use.
   --
   --  So run the same shape at two sizes and compare. The primary check
   --  counts bytes the scanner walked, which is exact and does not
   --  depend on how loaded the machine is. Feeding a byte at a time
   --  makes every token cross a chunk boundary, which is the condition
   --  under which a token is retained and walked again -- the shape of
   --  the last regression here.

   Scaling_Failures : Natural := 0;

   procedure Require
     (Condition : Boolean; Label : String; Detail : String);

   procedure Require
     (Condition : Boolean; Label : String; Detail : String) is
   begin
      if Condition then
         IO.Put_Line ("  ok    " & Label & "  " & Detail);
      else
         Scaling_Failures := Scaling_Failures + 1;
         IO.Put_Line ("  FAIL  " & Label & "  " & Detail);
      end if;
   end Require;

   --  Bytes walked per byte fed. Flat in the document size when scanning
   --  is linear: a token is walked once more for each chunk it spans,
   --  and tokens do not grow as the document does.
   function Scan_Ratio (Statements : Positive) return Long_Float is
      Text   : constant String := Plain_Turtle (Statements);
      Sink   : Collector;
      Parser : Parsers.Parser :=
        Parsers.Create
          (Source_Name => "bench",
           Base_IRI    => "http://example.org/bench/",
           Syntax      => Parsers.Turtle_Syntax);
      Ignored : Parsers.Parse_Status;
   begin
      for Index in Text'Range loop
         Parsers.Feed (Parser, Text (Index .. Index), Sink);
      end loop;
      Ignored := Parsers.Finish (Parser, Sink);
      declare
         Done : constant Parsers.Work_Statistics := Parsers.Work (Parser);
      begin
         return Long_Float (Done.Bytes_Scanned)
                / Long_Float (Natural'Max (1, Done.Bytes_Fed));
      end;
   end Scan_Ratio;

   --  Median time for one parse of a document of the given size.
   function Parse_Time (Statements : Positive) return Duration is
      Text  : constant String := Plain_Turtle (Statements);
      Taken : Duration_Array (1 .. Repetitions);

      procedure Once;

      procedure Once is
         Sink   : Collector;
         Parser : Parsers.Parser :=
           Parsers.Create
             (Source_Name => "bench",
              Base_IRI    => "http://example.org/bench/",
              Syntax      => Parsers.Turtle_Syntax);
         Ignored : Parsers.Parse_Status;
      begin
         Parsers.Feed (Parser, Text, Sink);
         Ignored := Parsers.Finish (Parser, Sink);
      end Once;
   begin
      Once;
      for Round in Taken'Range loop
         declare
            Started : constant RT.Time := RT.Clock;
         begin
            Once;
            Taken (Round) := RT.To_Duration (RT.Clock - Started);
         end;
      end loop;
      return Median (Taken);
   end Parse_Time;

   procedure Check_Scaling;

   procedure Check_Scaling is
      Small  : constant Positive := 500;
      Large  : constant Positive := 4 * Small;

      Ratio_Small : constant Long_Float := Scan_Ratio (Small);
      Ratio_Large : constant Long_Float := Scan_Ratio (Large);

      Time_Small : constant Duration := Parse_Time (Small);
      Time_Large : constant Duration := Parse_Time (Large);

      Growth : constant Long_Float :=
        (if Time_Small > 0.0
         then Long_Float (Time_Large) / Long_Float (Time_Small)
         else 1.0);
   begin
      IO.Put_Line ("");
      IO.Put_Line ("scaling, " & Small'Image & " to" & Large'Image
                   & " statements");

      --  Quadratic rescanning drives this up in proportion to the
      --  document; linear scanning leaves it where it was.
      Require
        (Ratio_Large <= Ratio_Small * 1.5,
         "scan work per byte is flat",
         Fixed (Ratio_Small, 1) & " then " & Fixed (Ratio_Large, 1));

      --  A backstop over everything the first check cannot see. Four
      --  times the input at four times the cost is linear; sixteen is
      --  quadratic. Eight leaves room for a loaded machine without
      --  leaving room for a squared term.
      Require
        (Growth <= 8.0,
         "time grows with input, not its square",
         Fixed (Growth, 1) & "x for 4x the input");
   end Check_Scaling;

   procedure Run_Parse_Turtle is new Measure (Parse_Turtle);
   procedure Run_Parse_Escaped is new Measure (Parse_Escaped);
   procedure Run_Parse_Lines is new Measure (Parse_Lines);
   procedure Run_Parse_Chunked is new Measure (Parse_Chunked);
   procedure Run_Write_TriG is new Measure (Write_TriG);
   procedure Run_Write_Lines is new Measure (Write_Lines);
   procedure Run_Canon_Ground is new Measure (Canonicalize_Ground);
   procedure Run_Canon_Blank is new Measure (Canonicalize_Blank);
   procedure Run_Codec is new Measure (Codec_Round);
   procedure Run_Parse_N3 is new Measure (Parse_N3);
   procedure Run_Parse_SPARQL is new Measure (Parse_SPARQL);

begin
   if Ada.Command_Line.Argument_Count > 0 then
      Repetitions := Natural'Value (Ada.Command_Line.Argument (1));
      if Repetitions mod 2 = 0 then
         Repetitions := Repetitions + 1;
      end if;
   end if;

   IO.Put_Line ("flyology_rdf benchmarks");
   IO.Put_Line ("  median of" & Repetitions'Image & " runs");
   IO.Put_Line ("");

   Run_Parse_Turtle ("turtle parse", Turtle_Text'Length);
   Run_Parse_Escaped ("turtle parse, escapes", Escaped_Text'Length);
   Run_Parse_Lines ("n-triples parse", Lines_Text'Length);
   Run_Parse_Chunked ("turtle parse, by byte", Turtle_Text'Length);
   Run_Write_TriG ("trig write", Turtle_Text'Length);
   Run_Write_Lines ("n-quads write", Turtle_Text'Length);
   Run_Canon_Ground ("canonicalize, ground", Turtle_Text'Length);
   Run_Canon_Blank ("canonicalize, blanks", Blank_Text'Length);
   Run_Codec ("codec round trip", Turtle_Text'Length);
   Run_Parse_N3 ("n3 parse", N3_Text'Length);
   Run_Parse_SPARQL ("sparql parse", Query_Text'Length);

   Check_Scaling;

   if Scaling_Failures > 0 then
      IO.Put_Line ("");
      IO.Put_Line ("FAIL benchmarks:" & Scaling_Failures'Image
                   & " scaling check(s)");
      Ada.Command_Line.Set_Exit_Status (1);
   end if;
end Benchmarks;
