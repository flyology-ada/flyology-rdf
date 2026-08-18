--  Runnable examples for flyology_rdf.
--
--  Every snippet the README and the website show is taken from here, and
--  here it is compiled and run. A documented example that nothing builds
--  stops being true without anyone noticing, which is the failure this
--  crate spends most of its test suite avoiding elsewhere.
--
--  Each example prints what it produced, so `alr run` is also the check
--  that the output in the documentation is the output you get.

with Ada.Strings.Unbounded;
with Ada.Text_IO;

with Flyology_RDF.Canonicalization;
with Flyology_RDF.Codecs;
with Flyology_RDF.Datasets;
with Flyology_RDF.IRIs;
with Flyology_RDF.Quads;
with Flyology_RDF.Terms;
with Flyology_RDF.Turtle_Parsers;
with Flyology_RDF.Turtle_Writers;

with Flyology_N3.Model;
with Flyology_N3.Parsers;
with Flyology_N3.Writers;

with Flyology_SPARQL.Parsers;
with Flyology_SPARQL.Syntax;
with Flyology_SPARQL.Writers;

procedure Examples is

   package IO renames Ada.Text_IO;
   package Unbounded renames Ada.Strings.Unbounded;
   package RDF renames Flyology_RDF;

   procedure Heading (Title : String) is
   begin
      IO.New_Line;
      IO.Put_Line ("== " & Title & " ==");
   end Heading;

   ------------------------------------------------------------------
   --  Reading

   --  A sink receives one event per statement as the parser reads it.
   --  Nothing is retained that the sink does not retain, which is what
   --  lets a document larger than memory be read.
   type Printer is limited new RDF.Turtle_Parsers.Event_Sink with record
      Seen : Natural := 0;
   end record;

   overriding procedure On_Graph_Declaration
     (Target : in out Printer;
      Graph  : RDF.Quads.Graph_Name;
      Span   : RDF.Turtle_Parsers.Source_Span) is null;

   overriding procedure On_Diagnostic
     (Target : in out Printer;
      Value  : RDF.Turtle_Parsers.Parse_Diagnostic) is null;

   overriding procedure On_Quad
     (Target : in out Printer;
      Value  : RDF.Quads.Quad;
      Span   : RDF.Turtle_Parsers.Source_Span);

   overriding procedure On_Quad
     (Target : in out Printer;
      Value  : RDF.Quads.Quad;
      Span   : RDF.Turtle_Parsers.Source_Span)
   is
      pragma Unreferenced (Span);
      Subject : constant RDF.Terms.Term := RDF.Quads.Subject (Value);
   begin
      Target.Seen := Target.Seen + 1;
      IO.Put_Line
        ("  subject "
         & (case RDF.Terms.Kind (Subject) is
               when RDF.Terms.IRI_Kind =>
                  RDF.IRIs.To_UTF_8 (RDF.Terms.IRI_Value (Subject)),
               when RDF.Terms.Blank_Node_Kind =>
                  "_:" & RDF.Terms.Label (Subject),
               when others => RDF.Terms.Lexical_Form (Subject)));
   end On_Quad;

   --  Collects into a dataset rather than printing.
   type Collector is limited new RDF.Turtle_Parsers.Event_Sink with record
      Data : RDF.Datasets.Dataset := RDF.Datasets.Empty;
   end record;

   overriding procedure On_Graph_Declaration
     (Target : in out Collector;
      Graph  : RDF.Quads.Graph_Name;
      Span   : RDF.Turtle_Parsers.Source_Span) is null;

   overriding procedure On_Diagnostic
     (Target : in out Collector;
      Value  : RDF.Turtle_Parsers.Parse_Diagnostic) is null;

   overriding procedure On_Quad
     (Target : in out Collector;
      Value  : RDF.Quads.Quad;
      Span   : RDF.Turtle_Parsers.Source_Span);

   overriding procedure On_Quad
     (Target : in out Collector;
      Value  : RDF.Quads.Quad;
      Span   : RDF.Turtle_Parsers.Source_Span)
   is
      pragma Unreferenced (Span);
   begin
      RDF.Datasets.Insert (Target.Data, Value);
   end On_Quad;

   use type RDF.Turtle_Parsers.Parse_Status;

   function Read
     (Text   : String;
      Syntax : RDF.Turtle_Parsers.Syntax_Kind :=
        RDF.Turtle_Parsers.Turtle_Syntax) return RDF.Datasets.Dataset
   is
      Sink   : Collector;
      Parser : RDF.Turtle_Parsers.Parser :=
        RDF.Turtle_Parsers.Create
          (Source_Name => "example",
           Base_IRI    => "http://example.org/",
           Syntax      => Syntax);
   begin
      RDF.Turtle_Parsers.Feed (Parser, Text, Sink);
      if RDF.Turtle_Parsers.Finish (Parser, Sink)
         /= RDF.Turtle_Parsers.Parse_Succeeded
      then
         raise Program_Error with "the example document did not parse";
      end if;
      return Sink.Data;
   end Read;

   Document : constant String :=
     "@prefix : <http://example.org/> ." & ASCII.LF
     & ":ada :wrote :notes ; :born ""1815-12-10"" ." & ASCII.LF
     & ":notes :about ""flight""@en ." & ASCII.LF;

begin
   IO.Put_Line ("flyology_rdf examples");

   ---------------------------------------------------------------------
   Heading ("Read Turtle, one statement at a time");
   declare
      Sink   : Printer;
      Parser : RDF.Turtle_Parsers.Parser :=
        RDF.Turtle_Parsers.Create
          (Source_Name => "example",
           Base_IRI    => "http://example.org/",
           Syntax      => RDF.Turtle_Parsers.Turtle_Syntax);
   begin
      RDF.Turtle_Parsers.Feed (Parser, Document, Sink);
      if RDF.Turtle_Parsers.Finish (Parser, Sink)
         = RDF.Turtle_Parsers.Parse_Succeeded
      then
         IO.Put_Line ("  read" & Sink.Seen'Image & " statements");
      end if;
   end;

   ---------------------------------------------------------------------
   Heading ("Read input that arrives in pieces");
   declare
      Sink   : Collector;
      Parser : RDF.Turtle_Parsers.Parser :=
        RDF.Turtle_Parsers.Create
          (Source_Name => "example",
           Base_IRI    => "http://example.org/",
           Syntax      => RDF.Turtle_Parsers.Turtle_Syntax);
   begin
      --  The split may fall anywhere, including inside an escape or a
      --  literal. What comes out does not depend on where it fell.
      for Index in Document'Range loop
         RDF.Turtle_Parsers.Feed
           (Parser, Document (Index .. Index), Sink);
      end loop;
      if RDF.Turtle_Parsers.Finish (Parser, Sink)
         = RDF.Turtle_Parsers.Parse_Succeeded
      then
         IO.Put_Line
           ("  a byte at a time gives"
            & RDF.Datasets.Length (Sink.Data)'Image & " statements");
      end if;
   end;

   ---------------------------------------------------------------------
   Heading ("Build statements by hand");
   declare
      Data : RDF.Datasets.Dataset := RDF.Datasets.Empty;

      function I (Value : String) return RDF.IRIs.IRI
      is (RDF.IRIs.From_UTF_8 (Value));
   begin
      --  A predicate is typed as an IRI rather than a term, so a literal
      --  in predicate position does not compile.
      RDF.Datasets.Insert
        (Data,
         RDF.Quads.Create
           (Graph     => RDF.Quads.Default_Graph,
            Subject   => RDF.Terms.IRI_Term (I ("http://example.org/ada")),
            Predicate => I ("http://example.org/wrote"),
            Object    => RDF.Terms.Language_Literal ("notes", "en")));
      IO.Put_Line ("  the dataset holds" & RDF.Datasets.Length (Data)'Image
                   & " statement");
   end;

   ---------------------------------------------------------------------
   Heading ("Write Turtle with prefixes");
   declare
      Prefixes : RDF.Turtle_Writers.Prefix_Map :=
        RDF.Turtle_Writers.No_Prefixes;
      Data     : constant RDF.Datasets.Dataset := Read (Document);
   begin
      RDF.Turtle_Writers.Bind (Prefixes, "", "http://example.org/");
      IO.Put (RDF.Turtle_Writers.To_Turtle (Data, Prefixes));
   end;

   ---------------------------------------------------------------------
   Heading ("Decide whether two documents say the same thing");
   declare
      --  The same graph, written with different blank node labels and in
      --  a different order. Comparing the text says they differ.
      Left  : constant RDF.Datasets.Dataset :=
        Read ("_:a <http://example.org/p> _:b ."
              & " _:b <http://example.org/q> ""x"" .",
              RDF.Turtle_Parsers.NTriples_Syntax);
      Right : constant RDF.Datasets.Dataset :=
        Read ("_:y <http://example.org/q> ""x"" ."
              & " _:x <http://example.org/p> _:y .",
              RDF.Turtle_Parsers.NTriples_Syntax);
   begin
      IO.Put_Line
        ("  isomorphic: "
         & RDF.Canonicalization.Is_Isomorphic (Left, Right)'Image);
      IO.Put_Line ("  canonical form of the first:");
      IO.Put (RDF.Canonicalization.To_Canonical_NQuads (Left));
   end;

   ---------------------------------------------------------------------
   Heading ("Round-trip a term through the binary encoding");
   declare
      Original : constant RDF.Terms.Term :=
        RDF.Terms.Language_Literal ("flight", "en");
      Encoded  : constant String := RDF.Codecs.Encode (Original);
      Restored : constant RDF.Terms.Term := RDF.Codecs.Decode_Term (Encoded);
      use type RDF.Terms.Term;
   begin
      IO.Put_Line ("  encoded to" & Encoded'Length'Image & " bytes");
      IO.Put_Line ("  survives the round trip: "
                   & Boolean'Image (Original = Restored));
   end;

   ---------------------------------------------------------------------
   Heading ("Read Notation3, which RDF cannot express");
   declare
      Rule : constant String :=
        "@prefix : <http://example.org/> ." & ASCII.LF
        & "{ ?who :wrote ?what } => { ?what :by ?who } ." & ASCII.LF;
      Parsed : constant Flyology_N3.Model.Term :=
        Flyology_N3.Parsers.Parse (Rule, "http://example.org/");
   begin
      IO.Put_Line
        ("  the document is a formula of"
         & Flyology_N3.Model.Statement_Count (Parsed)'Image & " statement");
      IO.Put (Flyology_N3.Writers.To_N3 (Parsed));
   end;

   ---------------------------------------------------------------------
   Heading ("Read a SPARQL query and write it back");
   declare
      Query : constant String :=
        "PREFIX : <http://example.org/>"
        & " SELECT ?what WHERE { :ada :wrote ?what } LIMIT 10";
      Parsed : constant Flyology_SPARQL.Syntax.Query :=
        Flyology_SPARQL.Parsers.Parse (Query);
   begin
      IO.Put_Line
        ("  form: " & Flyology_SPARQL.Syntax.Form (Parsed)'Image);
      IO.Put (Flyology_SPARQL.Writers.To_SPARQL (Parsed));
   end;

   ---------------------------------------------------------------------
   Heading ("Every event carries its graph");
   declare
      Quoted : constant String :=
        "@prefix : <http://example.org/> ." & ASCII.LF
        & ":g { :ada :wrote :notes . }" & ASCII.LF;
      Data : constant RDF.Datasets.Dataset :=
        Read (Quoted, RDF.Turtle_Parsers.TriG_Syntax);

      procedure Note (Statement : RDF.Quads.Quad);

      procedure Note (Statement : RDF.Quads.Quad) is
         Where : constant RDF.Quads.Graph_Name :=
           RDF.Quads.Graph (Statement);
      begin
         IO.Put_Line
           ("  in "
            & (case RDF.Quads.Kind (Where) is
                  when RDF.Quads.Default_Graph_Kind => "the default graph",
                  when RDF.Quads.IRI_Graph_Kind =>
                     RDF.IRIs.To_UTF_8
                       (RDF.Terms.IRI_Value (RDF.Quads.Name_Term (Where))),
                  when RDF.Quads.Blank_Node_Graph_Kind => "a blank node"));
      end Note;
   begin
      RDF.Datasets.Iterate (Data, Note'Access);
   end;

   ---------------------------------------------------------------------
   Heading ("Bound the work and report what it cost");
   declare
      Limits : constant RDF.Turtle_Parsers.Parse_Limits :=
        (Maximum_Bytes       => 1_024 * 1_024,
         Maximum_Quads       => 1_000,   --  zero would mean no limit
         Maximum_Nesting     => 64,
         Maximum_Token_Bytes => 64 * 1_024,
         Maximum_Prefixes    => 256);
      Sink   : Collector;
      Parser : RDF.Turtle_Parsers.Parser :=
        RDF.Turtle_Parsers.Create
          (Source_Name => "example",
           Base_IRI    => "http://example.org/",
           Limits      => Limits,
           Syntax      => RDF.Turtle_Parsers.Turtle_Syntax);
   begin
      RDF.Turtle_Parsers.Feed (Parser, Document, Sink);
      if RDF.Turtle_Parsers.Finish (Parser, Sink)
         = RDF.Turtle_Parsers.Parse_Succeeded
      then
         declare
            Cost : constant RDF.Turtle_Parsers.Work_Statistics :=
              RDF.Turtle_Parsers.Work (Parser);
         begin
            IO.Put_Line
              ("  held at most" & Cost.Maximum_Pending_Bytes'Image
               & " bytes for" & Cost.Statements_Parsed'Image
               & " statements");
         end;
      end if;
   end;

   ---------------------------------------------------------------------
   Heading ("Build every kind of term");
   declare
      function I (Value : String) return RDF.IRIs.IRI
      is (RDF.IRIs.From_UTF_8 (Value));

      Named    : constant RDF.Terms.Term :=
        RDF.Terms.IRI_Term (I ("http://example.org/ada"));
      Unnamed  : constant RDF.Terms.Term := RDF.Terms.Blank_Node ("b1");
      Plain    : constant RDF.Terms.Term :=
        RDF.Terms.Literal ("flight", RDF.Terms.String_Datatype);
      In_English : constant RDF.Terms.Term :=
        RDF.Terms.Language_Literal ("flight", "en");
      Directed : constant RDF.Terms.Term :=
        RDF.Terms.Directional_Literal
          ("flight", "en", RDF.Terms.Left_To_Right);
   begin
      IO.Put_Line
        ("  kinds: " & RDF.Terms.Kind (Named)'Image
         & " " & RDF.Terms.Kind (Unnamed)'Image
         & " " & RDF.Terms.Kind (Plain)'Image);
      IO.Put_Line
        ("  the directional literal is"
         & RDF.Terms.Node_Count (Directed)'Image & " node, depth"
         & RDF.Terms.Depth (Directed)'Image);
      IO.Put_Line ("  language: " & RDF.Terms.Language (In_English));
   end;

   ---------------------------------------------------------------------
   Heading ("Work with a dataset");
   declare
      Data  : RDF.Datasets.Dataset := Read (Document);
      Count : Natural := 0;

      procedure Tally (Statement : RDF.Quads.Quad);

      procedure Tally (Statement : RDF.Quads.Quad) is
         pragma Unreferenced (Statement);
      begin
         Count := Count + 1;
      end Tally;
   begin
      RDF.Datasets.Iterate (Data, Tally'Access);
      IO.Put_Line
        ("  " & Count'Image & " statements in"
         & RDF.Datasets.Graph_Count (Data)'Image & " graph");

      --  A dataset is a set: inserting the same statement twice leaves one.
      declare
         Again : constant Natural := RDF.Datasets.Length (Data);
      begin
         RDF.Datasets.Insert
           (Data,
            RDF.Quads.Create
              (Graph     => RDF.Quads.Default_Graph,
               Subject   =>
                 RDF.Terms.IRI_Term
                   (RDF.IRIs.From_UTF_8 ("http://example.org/ada")),
               Predicate =>
                 RDF.IRIs.From_UTF_8 ("http://example.org/born"),
               Object    =>
                 RDF.Terms.Literal
                   ("1815-12-10", RDF.Terms.String_Datatype)));
         IO.Put_Line
           ("  reinserting one leaves"
            & RDF.Datasets.Length (Data)'Image & ", was" & Again'Image);
      end;
   end;

   ---------------------------------------------------------------------
   Heading ("Canonicalize and keep the identifier map");
   declare
      Data : constant RDF.Datasets.Dataset :=
        Read ("_:a <http://example.org/p> _:b .",
              RDF.Turtle_Parsers.NTriples_Syntax);
      Output : Unbounded.Unbounded_String;
      Issued : RDF.Canonicalization.Label_Maps.Map;
      Status : RDF.Canonicalization.Result_Status;
      use type RDF.Canonicalization.Result_Status;
   begin
      RDF.Canonicalization.Canonicalize
        (Value     => Data,
         Output    => Output,
         Labels    => Issued,
         Status    => Status,
         Algorithm => RDF.Canonicalization.SHA_256);
      if Status = RDF.Canonicalization.Canonicalized then
         for Position in Issued.Iterate loop
            IO.Put_Line
              ("  _:" & RDF.Canonicalization.Label_Maps.Key (Position)
               & " was issued "
               & RDF.Canonicalization.Label_Maps.Element (Position));
         end loop;
      end if;
   end;

   ---------------------------------------------------------------------
   Heading ("Walk a Notation3 formula");
   declare
      Rule : constant Flyology_N3.Model.Term :=
        Flyology_N3.Parsers.Parse
          ("@prefix : <http://example.org/> ." & ASCII.LF
           & "{ ?who :wrote ?what } => { ?what :by ?who } .",
           "http://example.org/");
   begin
      for Index in 1 .. Flyology_N3.Model.Statement_Count (Rule) loop
         declare
            Fact : constant Flyology_N3.Model.Statement :=
              Flyology_N3.Model.Statement_At (Rule, Index);
         begin
            IO.Put_Line
              ("  subject is a "
               & Flyology_N3.Model.Kind
                   (Flyology_N3.Model.Subject (Fact))'Image);
         end;
      end loop;
   end;

   ---------------------------------------------------------------------
   Heading ("Walk a SPARQL syntax tree");
   declare
      Parsed : constant Flyology_SPARQL.Syntax.Query :=
        Flyology_SPARQL.Parsers.Parse
          ("PREFIX : <http://example.org/>"
           & " SELECT ?what WHERE { :ada :wrote ?what }");
      Where : constant Flyology_SPARQL.Syntax.Node_Reference :=
        Flyology_SPARQL.Syntax.Where_Clause (Parsed);
      use type Flyology_SPARQL.Syntax.Node_Kind;
   begin
      for Index in 1 ..
        Flyology_SPARQL.Syntax.Child_Count (Parsed, Where)
      loop
         declare
            Node : constant Flyology_SPARQL.Syntax.Node_Reference :=
              Flyology_SPARQL.Syntax.Child (Parsed, Where, Index);
         begin
            if Flyology_SPARQL.Syntax.Kind (Parsed, Node)
               = Flyology_SPARQL.Syntax.Triple_Node
            then
               IO.Put_Line ("  a triple pattern");
            end if;
         end;
      end loop;
   end;

   ---------------------------------------------------------------------
   Heading ("A malformed document is diagnosed, not guessed at");
   declare
      Sink   : Collector;
      Parser : RDF.Turtle_Parsers.Parser :=
        RDF.Turtle_Parsers.Create (Source_Name => "example");
   begin
      RDF.Turtle_Parsers.Feed
        (Parser, "<http://example.org/s> ""not a predicate"" 1 .", Sink);
      IO.Put_Line
        ("  status: "
         & RDF.Turtle_Parsers.Finish (Parser, Sink)'Image);
   end;

   IO.New_Line;
   IO.Put_Line ("all examples ran");
end Examples;
