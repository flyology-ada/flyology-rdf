--  Exercises the Turtle and TriG grammar.
--
--  Alongside ordinary coverage, two things get deliberate attention. The
--  RDF 1.2 quoted-triple and triple-term positions are restricted to IRIs,
--  blank nodes, and literals -- a parser that reuses its general object
--  routine there accepts collections and property lists, which is a false
--  accept and emits statements from inside a term. And every document is
--  parsed twice, once whole and once one byte at a time, because a
--  chunk-fed parser that agrees with itself only on whole buffers is not
--  chunk-fed.

with Ada.Command_Line;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Flyology_RDF.IRIs;
with Flyology_RDF.Quads;
with Flyology_RDF.Terms;
with Flyology_RDF.Turtle_Parsers;

procedure Parser_Tests is

   package IO renames Ada.Text_IO;
   package Unbounded renames Ada.Strings.Unbounded;
   package IRIs renames Flyology_RDF.IRIs;
   package Quads renames Flyology_RDF.Quads;
   package Terms renames Flyology_RDF.Terms;
   package Parsers renames Flyology_RDF.Turtle_Parsers;

   use type Parsers.Parse_Status;
   use type Parsers.Diagnostic_Code;
   use type Quads.Graph_Name_Kind;
   use type Terms.Term_Kind;
   use type Terms.Base_Direction;

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

   function Render (Value : Terms.Term) return String is
   begin
      case Terms.Kind (Value) is
         when Terms.IRI_Kind =>
            return "<" & IRIs.To_UTF_8 (Terms.IRI_Value (Value)) & ">";
         when Terms.Blank_Node_Kind =>
            return "_:" & Terms.Label (Value);
         when Terms.Literal_Kind =>
            if Terms.Has_Language (Value) then
               return """" & Terms.Lexical_Form (Value) & """@"
                 & Terms.Language (Value)
                 & (if Terms.Has_Direction (Value)
                    then (if Terms.Direction (Value) = Terms.Left_To_Right
                          then "--ltr" else "--rtl")
                    else "");
            end if;
            return """" & Terms.Lexical_Form (Value) & """^^<"
              & IRIs.To_UTF_8 (Terms.Datatype (Value)) & ">";
         when Terms.Triple_Term_Kind =>
            return "<<(" & Render (Terms.Triple_Subject (Value)) & " <"
              & IRIs.To_UTF_8 (Terms.Triple_Predicate (Value)) & "> "
              & Render (Terms.Triple_Object (Value)) & ")>>";
      end case;
   end Render;

   type Collector is limited new Parsers.Event_Sink with record
      Lines      : Unbounded.Unbounded_String;
      Diagnosed  : Boolean := False;
      Last_Code  : Parsers.Diagnostic_Code := Parsers.Malformed_Syntax;
      Graphs     : Natural := 0;
      --  When set, On_Quad raises, which is how a consumer's own failure
      --  reaches the parser.
      Fail_Quads : Boolean := False;
   end record;

   overriding procedure On_Graph_Declaration
     (Target : in out Collector;
      Graph  : Quads.Graph_Name;
      Span   : Parsers.Source_Span);

   overriding procedure On_Quad
     (Target : in out Collector;
      Value  : Quads.Quad;
      Span   : Parsers.Source_Span);

   overriding procedure On_Diagnostic
     (Target : in out Collector;
      Value  : Parsers.Parse_Diagnostic);

   overriding procedure On_Graph_Declaration
     (Target : in out Collector;
      Graph  : Quads.Graph_Name;
      Span   : Parsers.Source_Span)
   is
      pragma Unreferenced (Graph, Span);
   begin
      Target.Graphs := Target.Graphs + 1;
   end On_Graph_Declaration;

   overriding procedure On_Quad
     (Target : in out Collector;
      Value  : Quads.Quad;
      Span   : Parsers.Source_Span)
   is
      pragma Unreferenced (Span);
      Graph : constant Quads.Graph_Name := Quads.Graph (Value);
   begin
      if Target.Fail_Quads then
         raise Program_Error with "sink deliberately failing";
      end if;
      if Quads.Kind (Graph) /= Quads.Default_Graph_Kind then
         Unbounded.Append
           (Target.Lines, Render (Quads.Name_Term (Graph)) & " ");
      end if;
      Unbounded.Append
        (Target.Lines,
         Render (Quads.Subject (Value)) & " <"
         & IRIs.To_UTF_8 (Quads.Predicate (Value)) & "> "
         & Render (Quads.Object (Value)) & " .");
      Unbounded.Append (Target.Lines, ASCII.LF);
   end On_Quad;

   overriding procedure On_Diagnostic
     (Target : in out Collector;
      Value  : Parsers.Parse_Diagnostic) is
   begin
      Target.Diagnosed := True;
      Target.Last_Code := Parsers.Code (Value);
   end On_Diagnostic;

   --  Parse Document, either in one piece or one byte at a time.
   procedure Run
     (Document   : String;
      By_Byte    : Boolean;
      Output     : out Unbounded.Unbounded_String;
      Succeeded  : out Boolean;
      Diagnosis  : out Parsers.Diagnostic_Code;
      Syntax     : Parsers.Syntax_Kind := Parsers.TriG_Syntax;
      Base       : String := "")
   is
      Sink   : Collector;
      Parser : Parsers.Parser :=
        Parsers.Create
          (Source_Name => "test", Base_IRI => Base, Syntax => Syntax);
   begin
      if By_Byte then
         for Index in Document'Range loop
            Parsers.Feed (Parser, Document (Index .. Index), Sink);
         end loop;
      else
         Parsers.Feed (Parser, Document, Sink);
      end if;
      Succeeded := Parsers.Finish (Parser, Sink) = Parsers.Parse_Succeeded;
      Output := Sink.Lines;
      Diagnosis := Sink.Last_Code;
   end Run;

   --  Both feeding strategies must agree, and the result must match.
   procedure Check_Parse (Document, Expected, Label : String;
                          Base : String := "") is
      Whole, Split : Unbounded.Unbounded_String;
      Ok_Whole, Ok_Split : Boolean;
      Code_Whole, Code_Split : Parsers.Diagnostic_Code;
   begin
      Run (Document, False, Whole, Ok_Whole, Code_Whole, Base => Base);
      Run (Document, True, Split, Ok_Split, Code_Split, Base => Base);

      Check (Ok_Whole, Label & " (parse succeeds)");
      Check_Equal (Unbounded.To_String (Whole), Expected, Label);
      Check_Equal (Unbounded.To_String (Split), Unbounded.To_String (Whole),
                   Label & " (byte-at-a-time agrees)");
      Check (Ok_Split = Ok_Whole, Label & " (both feeds agree on status)");
   end Check_Parse;

   procedure Check_Rejects
     (Document, Label : String;
      Expected : Parsers.Diagnostic_Code := Parsers.Malformed_Syntax;
      Syntax   : Parsers.Syntax_Kind := Parsers.TriG_Syntax) is
      Whole, Split : Unbounded.Unbounded_String;
      Ok_Whole, Ok_Split : Boolean;
      Code_Whole, Code_Split : Parsers.Diagnostic_Code;
   begin
      Run (Document, False, Whole, Ok_Whole, Code_Whole, Syntax => Syntax);
      Run (Document, True, Split, Ok_Split, Code_Split, Syntax => Syntax);
      Check (not Ok_Whole, Label & " (rejected)");
      Check (not Ok_Split, Label & " (rejected byte-at-a-time)");
      Check (Code_Whole = Expected,
             Label & " (diagnostic is "
             & Parsers.Diagnostic_Code'Image (Expected) & ", got "
             & Parsers.Diagnostic_Code'Image (Code_Whole) & ")");
      --  A byte-at-a-time feed must fail the same way, not merely fail.
      --  Reading this code was assigned and never compared, so a chunked
      --  parse could report anything and pass.
      Check (Code_Split = Code_Whole,
             Label & " (same diagnostic byte-at-a-time, got "
             & Parsers.Diagnostic_Code'Image (Code_Split) & ")");
   end Check_Rejects;

   EX : constant String := "@prefix ex: <http://example.org/> ." & ASCII.LF;

   --  A token that never finishes never reached the completed-token check,
   --  so it was retained whole and rescanned from its first byte on every
   --  chunk. The bound is on the buffer now, so it bites while the token
   --  is still open.
   procedure Check_Unterminated_Is_Bounded is
      Sink   : Collector;
      Limits : constant Parsers.Parse_Limits :=
        (Maximum_Token_Bytes => 64, others => <>);
      Parser : Parsers.Parser :=
        Parsers.Create (Source_Name => "test", Limits => Limits);
      Chunk  : constant String (1 .. 32) := (others => 'x');
      Status : Parsers.Parse_Status;
   begin
      --  An opening quote and then bytes without end.
      Parsers.Feed (Parser, """", Sink);
      for Round in 1 .. 8 loop
         Parsers.Feed (Parser, Chunk, Sink);
      end loop;
      Status := Parsers.Finish (Parser, Sink);
      Check (Status = Parsers.Parse_Failed,
             "an unterminated token is refused, not accumulated");
      Check (Sink.Last_Code = Parsers.Token_Limit,
             "and the diagnostic is the token limit, got "
             & Parsers.Diagnostic_Code'Image (Sink.Last_Code));
      Check (Parsers.Work (Parser).Maximum_Pending_Bytes <= 128,
             "and the buffer never grew past the bound, reached"
             & Natural'Image (Parsers.Work (Parser).Maximum_Pending_Bytes));
   end Check_Unterminated_Is_Bounded;

begin
   Check_Unterminated_Is_Bounded;

   IO.Put_Line ("Parser tests");

   ------------------------------------------------------------------
   --  Core Turtle
   ------------------------------------------------------------------
   Check_Parse
     ("<http://example.org/s> <http://example.org/p> " &
      "<http://example.org/o> .",
      "<http://example.org/s> <http://example.org/p> " &
      "<http://example.org/o> ." & ASCII.LF,
      "a bare triple");

   --  RDF 1.2 gives reifier ::= '~' (iri | BlankNode)? and BlankNode
   --  admits ANON, so "~[]" names the statement with a fresh node. The
   --  corpus exercises ~:e, ~_:id and a bare ~, never this one.
   Check_Parse
     ("<http://e/s> <http://e/p> <http://e/o> ~[] .",
      "<http://e/s> <http://e/p> <http://e/o> ." & ASCII.LF
      & "_:b1 <http://www.w3.org/1999/02/22-rdf-syntax-ns#reifies> "
      & "<<(<http://e/s> <http://e/p> <http://e/o>)>> ." & ASCII.LF,
      "an ANON reifier names the statement");

   --  The brackets must be empty: a property list would state things
   --  about the reifier, which the production does not allow.
   Check_Rejects
     ("<http://e/s> <http://e/p> <http://e/o> ~[ <http://e/q> 1 ] .",
      "a property list as a reifier");

   --  "[]" is an ANON: an ordinary subject, and a subject on its own is
   --  not a statement. A property list with content is, because reading
   --  it stated something.
   Check_Rejects ("[] .", "a bare ANON as a statement");

   --  The line-based grammars are line-based: one statement to a line,
   --  and a statement may not wrap. Only spaces and tabs separate terms.
   Check_Rejects
     ("<http://e/s> <http://e/p> <http://e/o> ."
      & " <http://e/s> <http://e/p> <http://e/o2> .",
      "two N-Triples statements sharing a line",
      Syntax => Parsers.NTriples_Syntax);
   Check_Rejects
     ("<http://e/s> <http://e/p>" & ASCII.LF & " <http://e/o> .",
      "an N-Triples statement wrapped across lines",
      Syntax => Parsers.NTriples_Syntax);
   Check_Rejects
     ("<http://e/s> <http://e/p> <http://e/o> <http://e/g> ."
      & " <http://e/s> <http://e/p> <http://e/o2> <http://e/g> .",
      "two N-Quads statements sharing a line",
      Syntax => Parsers.NQuads_Syntax);
   Check_Rejects ("{ [] . }", "a bare ANON inside a graph block");

   Check_Parse
     (EX & "ex:s ex:p ex:o .",
      "<http://example.org/s> <http://example.org/p> " &
      "<http://example.org/o> ." & ASCII.LF,
      "prefixed names");

   Check_Parse
     (EX & "ex:s a ex:Thing .",
      "<http://example.org/s> " &
      "<http://www.w3.org/1999/02/22-rdf-syntax-ns#type> " &
      "<http://example.org/Thing> ." & ASCII.LF,
      "the a keyword expands to rdf:type");

   Check_Parse
     (EX & "ex:s ex:p ex:o , ex:o2 .",
      "<http://example.org/s> <http://example.org/p> " &
      "<http://example.org/o> ." & ASCII.LF &
      "<http://example.org/s> <http://example.org/p> " &
      "<http://example.org/o2> ." & ASCII.LF,
      "an object list");

   Check_Parse
     (EX & "ex:s ex:p ex:o ; ex:q ex:r .",
      "<http://example.org/s> <http://example.org/p> " &
      "<http://example.org/o> ." & ASCII.LF &
      "<http://example.org/s> <http://example.org/q> " &
      "<http://example.org/r> ." & ASCII.LF,
      "a predicate-object list");

   Check_Parse
     (EX & "ex:s ex:p ex:o ; .",
      "<http://example.org/s> <http://example.org/p> " &
      "<http://example.org/o> ." & ASCII.LF,
      "a trailing semicolon is permitted");

   ------------------------------------------------------------------
   --  Base resolution
   ------------------------------------------------------------------
   Check_Parse
     ("<s> <p> <o> .",
      "<http://example.org/base/s> <http://example.org/base/p> " &
      "<http://example.org/base/o> ." & ASCII.LF,
      "relative references resolve against the base",
      Base => "http://example.org/base/");

   Check_Parse
     ("@base <http://example.org/b/> ." & ASCII.LF & "<s> <p> <o> .",
      "<http://example.org/b/s> <http://example.org/b/p> " &
      "<http://example.org/b/o> ." & ASCII.LF,
      "a base directive takes effect");

   ------------------------------------------------------------------
   --  Literals
   ------------------------------------------------------------------
   Check_Parse
     (EX & "ex:s ex:p ""plain"" .",
      "<http://example.org/s> <http://example.org/p> ""plain""^^" &
      "<http://www.w3.org/2001/XMLSchema#string> ." & ASCII.LF,
      "a plain literal is xsd:string");

   Check_Parse
     (EX & "ex:s ex:p ""text""@EN-us .",
      "<http://example.org/s> <http://example.org/p> ""text""@en-us ." &
      ASCII.LF,
      "a language tag is lowercased");

   Check_Parse
     (EX & "ex:s ex:p ""نص""@ar--rtl .",
      "<http://example.org/s> <http://example.org/p> ""نص""@ar--rtl ." &
      ASCII.LF,
      "a directional literal");

   Check_Parse
     (EX & "ex:s ex:p 42 , 4.5 , 1e3 , true .",
      "<http://example.org/s> <http://example.org/p> ""42""^^" &
      "<http://www.w3.org/2001/XMLSchema#integer> ." & ASCII.LF &
      "<http://example.org/s> <http://example.org/p> ""4.5""^^" &
      "<http://www.w3.org/2001/XMLSchema#decimal> ." & ASCII.LF &
      "<http://example.org/s> <http://example.org/p> ""1e3""^^" &
      "<http://www.w3.org/2001/XMLSchema#double> ." & ASCII.LF &
      "<http://example.org/s> <http://example.org/p> ""true""^^" &
      "<http://www.w3.org/2001/XMLSchema#boolean> ." & ASCII.LF,
      "numeric and boolean literals");

   Check_Parse
     (EX & "ex:s ex:p ""7""^^ex:custom .",
      "<http://example.org/s> <http://example.org/p> ""7""^^" &
      "<http://example.org/custom> ." & ASCII.LF,
      "a datatype IRI");

   ------------------------------------------------------------------
   --  Blank nodes, collections, property lists
   ------------------------------------------------------------------
   --  A document's own labels pass through unchanged, so reading back this
   --  crate's output renames nothing. Rewriting them would rename again on
   --  every pass, and labels would grow without bound rather than reach a
   --  fixed point.
   Check_Parse
     (EX & "_:a ex:p _:b .",
      "_:a <http://example.org/p> _:b ." & ASCII.LF,
      "document blank node labels pass through unchanged");

   --  A generated label steps over one the document already used.
   Check_Parse
     (EX & "_:b1 ex:p [ ex:q ex:r ] .",
      "_:b2 <http://example.org/q> <http://example.org/r> ." & ASCII.LF &
      "_:b1 <http://example.org/p> _:b2 ." & ASCII.LF,
      "a generated label avoids a document label");

   Check_Parse
     (EX & "ex:s ex:p [ ex:q ex:r ] .",
      "_:b1 <http://example.org/q> <http://example.org/r> ." & ASCII.LF &
      "<http://example.org/s> <http://example.org/p> _:b1 ." & ASCII.LF,
      "a blank node property list");

   Check_Parse
     (EX & "ex:s ex:p ( ex:a ex:b ) .",
      "_:b1 <http://www.w3.org/1999/02/22-rdf-syntax-ns#first> " &
      "<http://example.org/a> ." & ASCII.LF &
      "_:b2 <http://www.w3.org/1999/02/22-rdf-syntax-ns#first> " &
      "<http://example.org/b> ." & ASCII.LF &
      "_:b1 <http://www.w3.org/1999/02/22-rdf-syntax-ns#rest> _:b2 ." &
      ASCII.LF &
      "_:b2 <http://www.w3.org/1999/02/22-rdf-syntax-ns#rest> " &
      "<http://www.w3.org/1999/02/22-rdf-syntax-ns#nil> ." & ASCII.LF &
      "<http://example.org/s> <http://example.org/p> _:b1 ." & ASCII.LF,
      "a collection");

   Check_Parse
     (EX & "ex:s ex:p () .",
      "<http://example.org/s> <http://example.org/p> " &
      "<http://www.w3.org/1999/02/22-rdf-syntax-ns#nil> ." & ASCII.LF,
      "the empty collection is rdf:nil");

   ------------------------------------------------------------------
   --  TriG
   ------------------------------------------------------------------
   Check_Parse
     (EX & "GRAPH ex:g { ex:s ex:p ex:o }",
      "<http://example.org/g> <http://example.org/s> " &
      "<http://example.org/p> <http://example.org/o> ." & ASCII.LF,
      "a GRAPH block");

   Check_Parse
     (EX & "graph ex:g { ex:s ex:p ex:o }",
      "<http://example.org/g> <http://example.org/s> " &
      "<http://example.org/p> <http://example.org/o> ." & ASCII.LF,
      "the graph keyword is case insensitive");

   Check_Parse
     (EX & "{ ex:s ex:p ex:o }",
      "<http://example.org/s> <http://example.org/p> " &
      "<http://example.org/o> ." & ASCII.LF,
      "an anonymous graph block is the default graph");

   Check_Rejects
     (EX & "GRAPH ex:g { ex:s ex:p ex:o }",
      "TriG syntax is rejected in Turtle mode",
      Parsers.Unsupported_Production, Parsers.Turtle_Syntax);

   ------------------------------------------------------------------
   --  RDF 1.2
   ------------------------------------------------------------------
   Check_Parse
     (EX & "ex:s ex:p <<( ex:a ex:b ex:c )>> .",
      "<http://example.org/s> <http://example.org/p> " &
      "<<(<http://example.org/a> <http://example.org/b> " &
      "<http://example.org/c>)>> ." & ASCII.LF,
      "a triple term as an object");

   Check_Parse
     (EX & "<< ex:a ex:b ex:c >> ex:p ex:o .",
      "_:b1 <http://www.w3.org/1999/02/22-rdf-syntax-ns#reifies> " &
      "<<(<http://example.org/a> <http://example.org/b> " &
      "<http://example.org/c>)>> ." & ASCII.LF &
      "_:b1 <http://example.org/p> <http://example.org/o> ." & ASCII.LF,
      "a reified triple as a subject");

   Check_Parse
     (EX & "<< ex:a ex:b ex:c ~ex:r >> ex:p ex:o .",
      "<http://example.org/r> " &
      "<http://www.w3.org/1999/02/22-rdf-syntax-ns#reifies> " &
      "<<(<http://example.org/a> <http://example.org/b> " &
      "<http://example.org/c>)>> ." & ASCII.LF &
      "<http://example.org/r> <http://example.org/p> " &
      "<http://example.org/o> ." & ASCII.LF,
      "a named reifier");

   Check_Parse
     (EX & "ex:s ex:p ex:o {| ex:q ex:r |} .",
      "<http://example.org/s> <http://example.org/p> " &
      "<http://example.org/o> ." & ASCII.LF &
      "_:b1 <http://www.w3.org/1999/02/22-rdf-syntax-ns#reifies> " &
      "<<(<http://example.org/s> <http://example.org/p> " &
      "<http://example.org/o>)>> ." & ASCII.LF &
      "_:b1 <http://example.org/q> <http://example.org/r> ." & ASCII.LF,
      "an annotation block");

   ------------------------------------------------------------------
   --  The restricted RDF 1.2 positions: these must NOT be accepted
   ------------------------------------------------------------------
   Check_Rejects
     (EX & "ex:s ex:p <<( ex:a ex:b ( 1 2 ) )>> .",
      "a collection is not a triple term object");
   Check_Rejects
     (EX & "ex:s ex:p <<( ex:a ex:b [ ex:c 1 ] )>> .",
      "a property list is not a triple term object");
   Check_Rejects
     (EX & "ex:s ex:p <<( ( 1 ) ex:b ex:c )>> .",
      "a collection is not a triple term subject");
   Check_Rejects
     (EX & "ex:s ex:p <<( [ ex:c 1 ] ex:b ex:c )>> .",
      "a property list is not a triple term subject");
   Check_Rejects
     (EX & "ex:s ex:p ex:o ~( 1 ) .",
      "a collection cannot name a reifier");
   Check_Rejects
     (EX & "ex:s ex:p ex:o ~[ ex:c 1 ] .",
      "a property list cannot name a reifier");
   Check_Rejects
     (EX & "ex:s ex:p ""x"" ex:q .",
      "a literal is not a subject position");

   ------------------------------------------------------------------
   --  Other rejections
   ------------------------------------------------------------------
   Check_Rejects (EX & "ex:s ex:p ex:o", "a missing terminator");

   --  The line-based grammars admit only the short double-quoted form.
   --  The token records how many quotes there were and now also which,
   --  because without that an apostrophe is indistinguishable from a
   --  double quote and N-Triples accepts a literal it has no rule for.
   Check_Rejects
     ("<http://e/s> <http://e/p> 'x' .",
      "a single-quoted literal in N-Triples",
      Syntax => Parsers.NTriples_Syntax);
   Check_Rejects
     ("<http://e/s> <http://e/p> 'x' <http://e/g> .",
      "a single-quoted literal in N-Quads",
      Syntax => Parsers.NQuads_Syntax);
   Check_Rejects ("ex:s ex:p ex:o .", "an undefined prefix",
                  Parsers.Undefined_Prefix);
   Check_Rejects (EX & "ex:s ""literal"" ex:o .",
                  "a literal is not a predicate");
   Check_Rejects ("<relative> <p> <o> .",
                  "a relative IRI with no base", Parsers.Invalid_IRI);
   Check_Rejects (EX & "{ ex:s ex:p ex:o ", "an unclosed graph block");

   ------------------------------------------------------------------
   --  Chunk invariance over a document exercising most productions
   ------------------------------------------------------------------
   declare
      Document : constant String :=
        "@prefix ex: <http://example.org/> ." & ASCII.LF
        & "# a comment" & ASCII.LF
        & "ex:s a ex:Thing ;" & ASCII.LF
        & "  ex:p ""text""@en-US , 42 , ( ex:a ex:b ) ;" & ASCII.LF
        & "  ex:q [ ex:r ""nested"" ] ." & ASCII.LF
        & "<< ex:s ex:p ex:o ~ex:r >> ex:said ""so"" ." & ASCII.LF
        & "GRAPH ex:g { ex:x ex:y <<( ex:a ex:b ex:c )>> }" & ASCII.LF;
      Whole, Split : Unbounded.Unbounded_String;
      Ok_Whole, Ok_Split : Boolean;
      Code_Whole, Code_Split : Parsers.Diagnostic_Code;
   begin
      Run (Document, False, Whole, Ok_Whole, Code_Whole);
      Run (Document, True, Split, Ok_Split, Code_Split);
      Check (Ok_Whole, "mixed document parses");
      Check (Ok_Split, "mixed document parses byte at a time");
      Check_Equal (Unbounded.To_String (Split), Unbounded.To_String (Whole),
                   "mixed document is chunk invariant");
   end;

   ------------------------------------------------------------------
   --  Regressions: defects found by review, kept fixed
   ------------------------------------------------------------------

   --  "@prefix" followed by a hyphen is a language tag, not a directive.
   Check_Parse
     ("<http://s> <http://p> ""chat""@prefix-de .",
      "<http://s> <http://p> ""chat""@prefix-de ." & ASCII.LF,
      "a language tag that starts like a directive");

   Check_Rejects ("_: <http://p> <http://o> .",
                  "an empty blank node label");
   Check_Rejects ("_:a%41 <http://p> <http://o> .",
                  "a percent escape in a blank node label");
   Check_Rejects ("_:a\! <http://p> <http://o> .",
                  "a reserved-character escape in a blank node label");
   Check_Rejects ("<http://s> <http://p> +.e0 .",
                  "a double with no digits before its dot-exponent");
   Check_Rejects (EX & "ex:s ex:p ""x""@en-abcdefghi .",
                  "a language subtag past eight characters");
   Check_Rejects
     ("<http://s> <http://p> ""x""^^"
      & "<http://www.w3.org/1999/02/22-rdf-syntax-ns#langString> .",
      "rdf:langString as an explicit datatype");
   Check_Rejects
     ("<http://g> { <http://g2> { <http://s> <http://p> <http://o> }",
      "a nested labelled graph block");
   Check_Rejects
     ("{ { <http://s> <http://p> <http://o> }",
      "a nested anonymous graph block");
   Check_Rejects
     ("<http://a> <http://b> <http://c> . "
      & [1 .. 3 => '"'] & "x" & [1 .. 2 => '"'],
      "an unterminated long string at the end of input");
   Check_Rejects
     ("<http://a> <http://b> <http://c> . " & Character'Val (16#C3#),
      "truncated UTF-8 at the end of input",
      Parsers.Invalid_Encoding);
   Check_Rejects ("<http://s> _:p <http://o> .",
                  "a blank node is not a line-based predicate",
                  Syntax => Parsers.NTriples_Syntax);

   --  A document label arriving after a generated label took its
   --  spelling names a different node, so it is renamed, not merged.
   Check_Parse
     ("[] <http://p> <http://o> . _:b1 <http://q> <http://r> .",
      "_:b1 <http://p> <http://o> ." & ASCII.LF &
      "_:b2 <http://q> <http://r> ." & ASCII.LF,
      "a later document label cannot merge with a generated one");

   --  And the rename is remembered, so every later mention of that label
   --  is the same node rather than a fresh one each time.
   Check_Parse
     ("[] <http://p> <http://o> . _:b1 <http://q> <http://r> ."
      & " _:b1 <http://s> <http://t> .",
      "_:b1 <http://p> <http://o> ." & ASCII.LF &
      "_:b2 <http://q> <http://r> ." & ASCII.LF &
      "_:b2 <http://s> <http://t> ." & ASCII.LF,
      "a renamed document label keeps its replacement");

   --  A sink that raises poisons the parse: nothing more is emitted, and
   --  Finish reports failure.
   declare
      Sink   : Collector;
      Parser : Parsers.Parser := Parsers.Create (Source_Name => "test");
   begin
      Sink.Fail_Quads := True;
      begin
         Parsers.Feed
           (Parser, "<http://s> <http://p> <http://o> . ", Sink);
         Check (False, "a sink exception propagates out of Feed");
      exception
         when Program_Error =>
            Check (True, "a sink exception propagates out of Feed");
      end;
      Sink.Fail_Quads := False;
      Sink.Lines := Unbounded.Null_Unbounded_String;
      Parsers.Feed (Parser, "<http://s2> <http://p2> <http://o2> . ", Sink);
      Check (Unbounded.Length (Sink.Lines) = 0,
             "a poisoned parser emits nothing");
      Check (Parsers.Finish (Parser, Sink) = Parsers.Parse_Failed,
             "a poisoned parser reports failure");
   end;

   IO.Put_Line ("  checks              " & Checks'Image);
   IO.Put_Line ("  failures            " & Failures'Image);

   if Failures = 0 then
      IO.Put_Line ("PASS parser_tests");
   else
      IO.Put_Line ("FAIL parser_tests");
      Ada.Command_Line.Set_Exit_Status (1);
   end if;
end Parser_Tests;
