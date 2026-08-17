--  Exercises the token scanner.
--
--  Two things get most of the attention. First, the token boundaries that
--  are easy to get wrong: a prefix that happens to spell a keyword, a
--  keyword directly abutting the next token, a local name containing dots
--  followed by the statement terminator. Second, chunk invariance -- the
--  same input scanned from a truncated buffer must produce exactly the
--  tokens that are fully present, and ask for more input rather than
--  guessing at the one that is not.

with Ada.Command_Line;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Flyology_RDF.Lexers;
with Flyology_RDF.Parser_Cursors;

procedure Lexer_Tests is

   package IO renames Ada.Text_IO;
   package Unbounded renames Ada.Strings.Unbounded;
   package Cursors renames Flyology_RDF.Parser_Cursors;
   package Lexers renames Flyology_RDF.Lexers;

   use type Lexers.Scan_Status;
   use type Lexers.Scan_Error_Kind;
   use type Lexers.Token_Kind;
   use type Lexers.String_Form;

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
         IO.Put_Line
           ("  FAIL  " & Label & ": got """ & Actual
            & """, expected """ & Expected & """");
      end if;
   end Check_Equal;

   --  One line per token, so a whole scan can be compared as a string.
   function Rendered (Value : Lexers.Token) return String is
      Base : constant String :=
        Lexers.Token_Kind'Image (Lexers.Kind (Value));
   begin
      case Lexers.Kind (Value) is
         when Lexers.Prefixed_Name_Token =>
            return Base & "(" & Lexers.Prefix (Value) & "|"
              & Lexers.Text (Value) & ")";
         when Lexers.IRI_Reference_Token | Lexers.Blank_Label_Token
            | Lexers.Integer_Token | Lexers.Decimal_Token
            | Lexers.Double_Token | Lexers.Boolean_Token =>
            return Base & "(" & Lexers.Text (Value) & ")";
         when Lexers.String_Token =>
            return Base & "(" & Lexers.Text (Value) & ")"
              & (if Lexers.Form (Value) = Lexers.Long_Quoted
                 then "[long]" else "");
         when Lexers.Language_Token =>
            return Base & "(" & Lexers.Text (Value) & ")"
              & (if Lexers.Has_Direction (Value)
                 then "[" & Lexers.Direction_Value'Image
                        (Lexers.Direction (Value)) & "]"
                 else "");
         when others =>
            return Base;
      end case;
   end Rendered;

   --  Scan every token in Text. Stops at the first non-token outcome and
   --  records it, so the caller can tell a clean end from a truncation.
   procedure Tokenize
     (Text        : String;
      Last_Chunk  : Boolean;
      Rendering   : out Unbounded.Unbounded_String;
      Final       : out Lexers.Scan_Status;
      Final_Error : out Lexers.Scan_Error_Kind)
   is
      Position : Cursors.Cursor_State := Cursors.Initial_State;
      Index    : Positive := Text'First;
      Result   : Lexers.Token := Lexers.Null_Token;
      Status   : Lexers.Scan_Status;
      Error    : Lexers.Scan_Error_Kind;
   begin
      Rendering := Unbounded.Null_Unbounded_String;
      loop
         Lexers.Scan
           (Text, Position, Index, Last_Chunk, Result, Status, Error);
         exit when Status /= Lexers.Token_Found;
         Unbounded.Append (Rendering, Rendered (Result));
         Unbounded.Append (Rendering, " ");
      end loop;
      Final := Status;
      Final_Error := Error;
   end Tokenize;

   function Scan_Of (Text : String) return String is
      Rendering : Unbounded.Unbounded_String;
      Final     : Lexers.Scan_Status;
      Error     : Lexers.Scan_Error_Kind;
   begin
      Tokenize (Text, True, Rendering, Final, Error);
      return Unbounded.To_String (Rendering);
   end Scan_Of;

   procedure Check_Scan (Text, Expected, Label : String) is
   begin
      Check_Equal (Scan_Of (Text), Expected, Label);
   end Check_Scan;

   procedure Check_Rejects
     (Text  : String;
      Why   : Lexers.Scan_Error_Kind;
      Label : String)
   is
      Rendering : Unbounded.Unbounded_String;
      Final     : Lexers.Scan_Status;
      Error     : Lexers.Scan_Error_Kind;
   begin
      Tokenize (Text, True, Rendering, Final, Error);
      Check (Final = Lexers.Scan_Error and then Error = Why,
             Label & " (got " & Lexers.Scan_Status'Image (Final)
             & "/" & Lexers.Scan_Error_Kind'Image (Error) & ")");
   end Check_Rejects;

   --  Every truncation of Text must yield a prefix of the full token
   --  sequence, and must never report an error that the full input does
   --  not.
   procedure Check_Chunk_Invariance (Text, Label : String) is
      Full        : constant String := Scan_Of (Text);
      Broke       : Boolean := False;
      Errored_At  : Natural := 0;
   begin
      for Cut in Text'First - 1 .. Text'Last loop
         declare
            Prefix    : constant String := Text (Text'First .. Cut);
            Rendering : Unbounded.Unbounded_String;
            Final     : Lexers.Scan_Status;
            Error     : Lexers.Scan_Error_Kind;
         begin
            --  A truncated buffer is never the final chunk, which is
            --  exactly what a chunk-fed caller reports.
            Tokenize (Prefix, False, Rendering, Final, Error);
            declare
               Partial : constant String :=
                 Unbounded.To_String (Rendering);
            begin
               if Final = Lexers.Scan_Error then
                  Broke := True;
                  Errored_At := Cut;
               elsif Partial'Length > Full'Length
                 or else Full (Full'First .. Full'First + Partial'Length - 1)
                         /= Partial
               then
                  Broke := True;
                  Errored_At := Cut;
               end if;
            end;
         end;
      end loop;

      Checks := Checks + 1;
      if Broke then
         Failures := Failures + 1;
         IO.Put_Line
           ("  FAIL  chunk invariance: " & Label
            & " (first divergence at cut" & Errored_At'Image & ")");
      end if;
   end Check_Chunk_Invariance;

begin
   IO.Put_Line ("Lexer tests");

   ------------------------------------------------------------------
   --  Basic token classes
   ------------------------------------------------------------------
   Check_Scan ("<http://example.org/a>",
               "IRI_REFERENCE_TOKEN(http://example.org/a) ", "IRI");
   Check_Scan ("_:b0", "BLANK_LABEL_TOKEN(b0) ", "blank label");
   Check_Scan ("ex:name", "PREFIXED_NAME_TOKEN(ex|name) ", "prefixed name");
   Check_Scan (":name", "PREFIXED_NAME_TOKEN(|name) ", "empty prefix");
   Check_Scan ("ex:", "PREFIXED_NAME_TOKEN(ex|) ", "empty local name");
   Check_Scan ("42", "INTEGER_TOKEN(42) ", "integer");
   Check_Scan ("-42", "INTEGER_TOKEN(-42) ", "signed integer");
   Check_Scan ("4.2", "DECIMAL_TOKEN(4.2) ", "decimal");
   Check_Scan ("4.2e10", "DOUBLE_TOKEN(4.2e10) ", "double");
   Check_Scan ("1E-3", "DOUBLE_TOKEN(1E-3) ", "double with signed exponent");
   Check_Scan ("true", "BOOLEAN_TOKEN(true) ", "boolean true");
   Check_Scan ("false", "BOOLEAN_TOKEN(false) ", "boolean false");
   Check_Scan ("^^", "DATATYPE_TOKEN ", "datatype marker");
   Check_Scan ("a", "A_TOKEN ", "the a keyword");

   ------------------------------------------------------------------
   --  Keyword boundaries -- the cases a look-ahead scanner gets wrong
   ------------------------------------------------------------------
   Check_Scan ("prefix:s", "PREFIXED_NAME_TOKEN(prefix|s) ",
               "a prefix named prefix is not the PREFIX keyword");
   Check_Scan ("PREFIX:x", "PREFIXED_NAME_TOKEN(PREFIX|x) ",
               "an uppercase prefix named PREFIX is still a prefix");
   Check_Scan ("base:x", "PREFIXED_NAME_TOKEN(base|x) ",
               "a prefix named base is not the BASE keyword");
   Check_Scan ("graph:x", "PREFIXED_NAME_TOKEN(graph|x) ",
               "a prefix named graph is not the GRAPH keyword");
   Check_Scan ("true:x", "PREFIXED_NAME_TOKEN(true|x) ",
               "a prefix named true is not the boolean");
   Check_Scan ("a:b", "PREFIXED_NAME_TOKEN(a|b) ",
               "a prefix named a is not the a keyword");

   Check_Scan ("a<http://example.org/C>",
               "A_TOKEN IRI_REFERENCE_TOKEN(http://example.org/C) ",
               "the a keyword needs no trailing whitespace");
   Check_Scan ("a[", "A_TOKEN OPEN_BRACKET_TOKEN ",
               "the a keyword abutting a bracket");

   --  Keywords the grammar writes in double quotes are case-insensitive.
   Check_Scan ("PREFIX", "SPARQL_PREFIX_TOKEN ", "PREFIX keyword");
   Check_Scan ("prefix", "SPARQL_PREFIX_TOKEN ", "lowercase prefix keyword");
   Check_Scan ("BASE", "SPARQL_BASE_TOKEN ", "BASE keyword");
   Check_Scan ("GRAPH", "GRAPH_TOKEN ", "GRAPH keyword");
   Check_Scan ("graph", "GRAPH_TOKEN ",
               "lowercase graph keyword is accepted");
   Check_Scan ("Graph", "GRAPH_TOKEN ", "mixed case graph keyword");

   ------------------------------------------------------------------
   --  Dots: inside a name, and as the statement terminator
   ------------------------------------------------------------------
   Check_Scan ("ex:a.b", "PREFIXED_NAME_TOKEN(ex|a.b) ",
               "a dot inside a local name");
   Check_Scan ("ex:a.b .",
               "PREFIXED_NAME_TOKEN(ex|a.b) DOT_TOKEN ",
               "a dotted local name followed by a terminator");
   Check_Scan ("ex:a.",
               "PREFIXED_NAME_TOKEN(ex|a) DOT_TOKEN ",
               "a local name may not end with a dot");
   Check_Scan ("ex.a:b", "PREFIXED_NAME_TOKEN(ex.a|b) ",
               "a dot inside a prefix");
   Check_Scan ("42 .", "INTEGER_TOKEN(42) DOT_TOKEN ",
               "an integer followed by a terminator");
   Check_Scan ("42.", "INTEGER_TOKEN(42) DOT_TOKEN ",
               "a dot after digits is a terminator when no digit follows");
   Check_Scan (".5", "DECIMAL_TOKEN(.5) ", "a decimal with no integer part");

   ------------------------------------------------------------------
   --  Strings
   ------------------------------------------------------------------
   Check_Scan ("""hello""", "STRING_TOKEN(hello) ", "short string");
   Check_Scan ("''", "STRING_TOKEN() ", "empty single-quoted string");
   Check_Scan ("""""", "STRING_TOKEN() ", "empty double-quoted string");
   Check_Scan ("''''''", "STRING_TOKEN()[long] ", "empty long string");
   Check_Scan ("""""""a""""""", "STRING_TOKEN(a)[long] ", "long string");
   Check_Scan ("""""""say """"hi"""" now""""""",
               "STRING_TOKEN(say """"hi"""" now)[long] ",
               "quotes inside a long string");
   Check_Scan ("""a\nb""", "STRING_TOKEN(a" & ASCII.LF & "b) ",
               "newline escape");
   Check_Scan ("""aAb""", "STRING_TOKEN(aAb) ", "four-digit escape");
   Check_Scan ("""a\U00000041b""", "STRING_TOKEN(aAb) ",
               "eight-digit escape");
   Check_Scan ("""\""""", "STRING_TOKEN("") ", "escaped quote");

   ------------------------------------------------------------------
   --  Language tags and directions
   ------------------------------------------------------------------
   Check_Scan ("@en", "LANGUAGE_TOKEN(en) ", "language tag");
   Check_Scan ("@en-US", "LANGUAGE_TOKEN(en-US) ", "language subtag");
   Check_Scan ("@en--ltr", "LANGUAGE_TOKEN(en)[LEFT_TO_RIGHT] ",
               "language tag with direction");
   Check_Scan ("@ar--rtl", "LANGUAGE_TOKEN(ar)[RIGHT_TO_LEFT] ",
               "right to left direction");
   Check_Scan ("@en-US--rtl", "LANGUAGE_TOKEN(en-US)[RIGHT_TO_LEFT] ",
               "subtag then direction");
   Check_Scan ("@prefix", "PREFIX_DIRECTIVE_TOKEN ", "prefix directive");
   Check_Scan ("@base", "BASE_DIRECTIVE_TOKEN ", "base directive");

   ------------------------------------------------------------------
   --  RDF 1.2 structure
   ------------------------------------------------------------------
   Check_Scan ("<<", "OPEN_QUOTED_TOKEN ", "quoted triple open");
   Check_Scan (">>", "CLOSE_QUOTED_TOKEN ", "quoted triple close");
   Check_Scan ("<<(", "OPEN_TRIPLE_TERM_TOKEN ", "triple term open");
   Check_Scan (")>>", "CLOSE_TRIPLE_TERM_TOKEN ", "triple term close");
   Check_Scan (")", "CLOSE_PAREN_TOKEN ", "plain close paren");
   Check_Scan ("{|", "OPEN_ANNOTATION_TOKEN ", "annotation open");
   Check_Scan ("|}", "CLOSE_ANNOTATION_TOKEN ", "annotation close");
   Check_Scan ("{", "OPEN_BRACE_TOKEN ", "graph block open");
   Check_Scan ("~", "REIFIER_TOKEN ", "reifier");

   ------------------------------------------------------------------
   --  Comments and whitespace
   ------------------------------------------------------------------
   Check_Scan ("# comment" & ASCII.LF & "42", "INTEGER_TOKEN(42) ",
               "a comment is skipped");
   Check_Scan ("  " & ASCII.HT & ASCII.LF & "42", "INTEGER_TOKEN(42) ",
               "whitespace is skipped");
   Check_Scan ("<http://example.org/#f>",
               "IRI_REFERENCE_TOKEN(http://example.org/#f) ",
               "a hash inside an IRI is not a comment");

   ------------------------------------------------------------------
   --  Rejections
   ------------------------------------------------------------------
   Check_Rejects ("<http://example.org/ a>", Lexers.Forbidden_Character,
                  "a raw space inside an IRI reference");
   Check_Rejects ("<http://example.org/<>", Lexers.Forbidden_Character,
                  "a raw angle bracket inside an IRI reference");
   Check_Rejects ("""a\qb""", Lexers.Malformed_Escape,
                  "an unknown string escape");
   Check_Rejects ("""a\uD800b""", Lexers.Malformed_Escape,
                  "a surrogate numeric escape");
   Check_Rejects ("""line" & ASCII.LF & "break""", Lexers.Unexpected_Character,
                  "a raw newline in a short string");
   Check_Rejects ("1e", Lexers.Malformed_Number,
                  "an exponent with no digits");
   Check_Rejects ("@", Lexers.Malformed_Language_Tag,
                  "an empty language tag");
   Check_Rejects ("@en--sideways", Lexers.Malformed_Language_Tag,
                  "an unknown direction");
   Check_Rejects ("_x", Lexers.Unexpected_Character,
                  "an underscore not starting a blank label");

   ------------------------------------------------------------------
   --  Chunk invariance
   ------------------------------------------------------------------
   Check_Chunk_Invariance
     ("<http://example.org/a> ex:p ""text"" .", "a simple statement");
   Check_Chunk_Invariance
     ("ex:s ex:p ""aAb""@en-US .", "escapes and a language tag");
   Check_Chunk_Invariance
     ("ex:s ex:p """"""long """"string"""""" .", "a long string");
   Check_Chunk_Invariance
     ("<< ex:s ex:p ex:o >> ex:q 4.2e1 .", "a quoted triple");
   Check_Chunk_Invariance
     ("<<( ex:s ex:p ex:o )>> ~ _:r .", "a triple term and a reifier");
   Check_Chunk_Invariance
     ("ex:a.b ex:c 42 . # trailing comment", "dotted name and a comment");
   Check_Chunk_Invariance
     ("@prefix ex: <http://example.org/> .", "a prefix directive");
   Check_Chunk_Invariance
     ("GRAPH <http://example.org/g> { ex:s ex:p ex:o }", "a graph block");
   Check_Chunk_Invariance
     ("ex:s ex:p ""x""@ar--rtl {| ex:q ex:r |} .", "an annotation");
   --  A four-byte scalar guarantees cuts inside a multi-byte sequence.
   Check_Chunk_Invariance
     ("ex:s ex:p ""emoji "
      & Character'Val (16#F0#) & Character'Val (16#9F#)
      & Character'Val (16#98#) & Character'Val (16#80#) & """ .",
      "a four-byte scalar inside a literal");

   IO.Put_Line ("  checks              " & Checks'Image);
   IO.Put_Line ("  failures            " & Failures'Image);

   if Failures = 0 then
      IO.Put_Line ("PASS lexer_tests");
   else
      IO.Put_Line ("FAIL lexer_tests");
      Ada.Command_Line.Set_Exit_Status (1);
   end if;
end Lexer_Tests;
