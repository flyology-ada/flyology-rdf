private with Ada.Strings.Unbounded;

with Flyology_RDF.Parser_Cursors;

--  Turtle and TriG token scanner.
--
--  Scanning is separated from the grammar so that token boundaries are
--  decided in one place. Several classes of grammar bug come from deciding
--  them twice: a scanner that recognises the PREFIX keyword by looking at
--  the next few bytes will misread a prefixed name whose prefix happens to
--  be "prefix", and one that requires whitespace after the "a" keyword will
--  reject "a<http://example.org/C>", which is well formed.
--
--  Here a name-shaped run is always scanned to its end first, and only then
--  classified. Keywords are what is left over when a run is not followed by
--  a colon.
package Flyology_RDF.Lexers is

   --  A lexical class of the Turtle and TriG grammars.
   type Token_Kind is
     (--  Terms
      IRI_Reference_Token,      --  <http://example.org/>
      Prefixed_Name_Token,      --  ex:local, ex:, :local
      Blank_Label_Token,        --  _:label
      String_Token,             --  "text", 'text', """text""", '''text'''
      Integer_Token,            --  42
      Decimal_Token,            --  4.2
      Double_Token,             --  4.2e1
      Boolean_Token,            --  true, false
      A_Token,                  --  a

      --  Modifiers attaching to a preceding token
      Language_Token,           --  @en-us, @en--ltr
      Datatype_Token,           --  ^^

      --  Directives
      Prefix_Directive_Token,   --  @prefix
      Base_Directive_Token,     --  @base
      Sparql_Prefix_Token,      --  PREFIX
      Sparql_Base_Token,        --  BASE
      Version_Directive_Token,  --  VERSION
      Graph_Token,              --  GRAPH

      --  Structure
      Dot_Token,
      Semicolon_Token,
      Comma_Token,
      Open_Paren_Token,         --  (
      Close_Paren_Token,        --  )
      Open_Bracket_Token,       --  [
      Close_Bracket_Token,      --  ]
      Open_Brace_Token,         --  {
      Close_Brace_Token,        --  }

      --  RDF 1.2
      Open_Quoted_Token,        --  <<
      Close_Quoted_Token,       --  >>
      Open_Triple_Term_Token,   --  <<(
      Close_Triple_Term_Token,  --  )>>
      Reifier_Token,            --  ~
      Open_Annotation_Token,    --  {|
      Close_Annotation_Token);  --  |}

   --  Direction carried by a Direction_Token.
   type Direction_Value is (Left_To_Right, Right_To_Left);

   --  Which quoting form a String_Token was written with. The grammar needs
   --  this only to reject a long-quoted string where a short one is
   --  required; the value is identical either way.
   type String_Form is (Short_Quoted, Long_Quoted);

   --  Outcome of one scan attempt.
   --  @enum Token_Found A complete token was scanned
   --  @enum Needs_More_Input The buffer ends part-way through a token; the
   --     caller should append the next chunk and retry
   --  @enum End_Of_Input Only whitespace and comments remained
   --  @enum Scan_Error The bytes cannot begin or continue any token
   type Scan_Status is
     (Token_Found, Needs_More_Input, End_Of_Input, Scan_Error);

   --  Why a scan failed.
   type Scan_Error_Kind is
     (No_Error,
      Invalid_Encoding,        --  not canonical UTF-8
      Unterminated_Token,      --  input ended inside a token at Finish
      Malformed_Escape,        --  \q, \u12, a surrogate escape
      Malformed_Number,
      Malformed_Language_Tag,
      Forbidden_Character,     --  raw control byte inside <...>
      Unexpected_Character);

   --  A scanned token.
   type Token (<>) is private;

   --  Report the token's lexical class.
   --  @param Value Token to inspect
   --  @return The token's kind
   function Kind (Value : Token) return Token_Kind;

   --  Return the token's decoded value.
   --
   --  Escapes are already resolved: a String_Token carries the characters
   --  the literal denotes, and an IRI_Reference_Token carries the IRI text
   --  with its numeric escapes applied.
   --  @param Value Token to inspect
   --  @return The decoded text, empty for punctuation
   function Text (Value : Token) return String;

   --  Return the prefix part of a prefixed name, without the colon.
   --  @param Value Token to inspect
   --  @return The prefix, empty for a name written ":local"
   function Prefix (Value : Token) return String;

   --  Return the quoting form of a string token.
   --  @param Value Token to inspect
   --  @return Short_Quoted or Long_Quoted
   function Form (Value : Token) return String_Form;

   --  Report whether a language token carries a base direction.
   --
   --  RDF 1.2 writes the direction as a suffix of the language tag rather
   --  than as its own token, so "@en--ltr" is one token whose text is "en".
   --  @param Value Token to inspect
   --  @return True when Direction is meaningful
   function Has_Direction (Value : Token) return Boolean;

   --  Return the base direction of a language token.
   --  @param Value Token to inspect
   --  @return The direction
   function Direction (Value : Token) return Direction_Value;

   --  Position of the token's first byte.
   --  @param Value Token to inspect
   --  @return Cursor position where the token starts
   function Start_Position (Value : Token) return Parser_Cursors.Cursor_State;

   --  Position just past the token's last byte.
   --  @param Value Token to inspect
   --  @return Cursor position where the token ends
   function End_Position (Value : Token) return Parser_Cursors.Cursor_State;

   --  Scan one token from Text, beginning at the byte named by Position.
   --
   --  Leading whitespace and comments are consumed regardless of the
   --  outcome, so a caller that receives Needs_More_Input can retain only
   --  the bytes from the returned Position onwards.
   --
   --  Last_Chunk decides what the end of the buffer means, and the answer
   --  is genuinely different for the two cases. Mid-stream, a name or
   --  number running up to the last byte might continue in the next chunk,
   --  so the only safe answer is Needs_More_Input. On the final chunk the
   --  same bytes are a complete token, and a string or IRI reference left
   --  open is Unterminated_Token rather than a request for input that will
   --  never arrive.
   --  @param Text Buffer to scan
   --  @param Position Cursor at the first unscanned byte; advanced past the
   --     token on success, and past skipped whitespace otherwise
   --  @param Index Index into Text corresponding to Position; advanced the
   --     same way
   --  @param Last_Chunk True when no further input will follow this buffer
   --  @param Result The scanned token, meaningful only when Token_Found
   --  @param Status Outcome of the scan
   --  @param Error Why the scan failed, No_Error otherwise
   procedure Scan
     (Text       : String;
      Position   : in out Parser_Cursors.Cursor_State;
      Index      : in out Positive;
      Last_Chunk : Boolean;
      Result     : out Token;
      Status     : out Scan_Status;
      Error      : out Scan_Error_Kind);

   --  A token that carries no text, used where a Token is needed before one
   --  has been scanned.
   --  @return A Dot_Token at the initial position
   function Null_Token return Token;

   --  Compare two tokens by class and content, ignoring where they were
   --  found. Two occurrences of the same name in a document are equal.
   --  @param Left First token
   --  @param Right Second token
   --  @return True when the tokens denote the same lexeme
   overriding function "=" (Left, Right : Token) return Boolean;

private

   package Unbounded renames Ada.Strings.Unbounded;

   type Token (Initialized : Boolean) is record
      Kind_Value     : Token_Kind := Dot_Token;
      Text_Value     : Unbounded.Unbounded_String;
      Prefix_Value   : Unbounded.Unbounded_String;
      Form_Value     : String_Form := Short_Quoted;
      Has_Direction_Data : Boolean := False;
      Direction_Data : Direction_Value := Left_To_Right;
      Start_Value    : Parser_Cursors.Cursor_State :=
        Parser_Cursors.Initial_State;
      End_Value      : Parser_Cursors.Cursor_State :=
        Parser_Cursors.Initial_State;
   end record;

end Flyology_RDF.Lexers;
