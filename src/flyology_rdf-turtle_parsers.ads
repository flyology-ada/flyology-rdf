private with Ada.Containers.Indefinite_Holders;
private with Ada.Containers.Indefinite_Hashed_Maps;
private with Ada.Finalization;
private with Ada.Strings.Hash;
private with Ada.Containers.Indefinite_Ordered_Sets;
private with Ada.Strings.Unbounded;
private with Flyology_RDF.IRIs;
private with Flyology_RDF.Lexers;

with Flyology_RDF.Parser_Cursors;
with Flyology_RDF.Quads;

--  Chunk-fed RDF 1.2 Turtle and TriG parser.
--
--  Input may be split at any byte boundary, including inside a multi-byte
--  scalar, an escape, or a long string, and produces the same event stream
--  regardless of how it was split.
--
--  Events are emitted as soon as a statement completes. A consumer that
--  needs a document to be admitted atomically holds them until Finish
--  reports success; one that is streaming into a store can act immediately.
package Flyology_RDF.Turtle_Parsers is

   --  Which document grammar to accept.
   --
   --  The line-based grammars are here rather than in a package of their
   --  own because they are a subset of this one down to the token level:
   --  they reuse the same scanner, the same event sink, the same
   --  diagnostics, and the same chunk-feeding machinery, and differ only in
   --  which productions are admitted.
   --  @enum Turtle_Syntax Reject graph blocks and the GRAPH keyword
   --  @enum TriG_Syntax Accept Turtle statements and TriG graph blocks
   --  @enum NTriples_Syntax One absolute-IRI statement per line, no graph
   --  @enum NQuads_Syntax N-Triples with an optional graph label
   type Syntax_Kind is
     (Turtle_Syntax, TriG_Syntax, NTriples_Syntax, NQuads_Syntax);

   --  Report whether a grammar is one of the line-based ones, which admit
   --  no directives, no abbreviations, and no relative references.
   --  @param Value Grammar to classify
   --  @return True for N-Triples and N-Quads
   function Is_Line_Based (Value : Syntax_Kind) return Boolean
   is (Value in NTriples_Syntax | NQuads_Syntax);

   --  Bounds a caller imposes on one parse.
   --  @field Maximum_Bytes Total input accepted
   --  @field Maximum_Quads Statements emitted, zero for no limit
   --  @field Maximum_Nesting Depth of collections, property lists, quoted
   --     triples, and annotations combined
   --  @field Maximum_Token_Bytes Longest single token
   --  @field Maximum_Prefixes Distinct prefixes bound by directives
   type Parse_Limits is record
      Maximum_Bytes       : Positive := 64 * 1_024 * 1_024;
      Maximum_Quads       : Natural  := 0;
      Maximum_Nesting     : Positive := 128;
      Maximum_Token_Bytes : Positive := 1_048_576;
      Maximum_Prefixes    : Natural  := 4_096;
   end record;

   --  A region of the input, given at both ends so that a caller can
   --  underline it without rescanning.
   --  @field Start_Byte Offset of the first byte, zero when unset
   --  @field End_Byte Offset one past the last byte
   --  @field Start_Line Line the region opens on, counting from one
   --  @field Start_Column Column the region opens on, counting from one
   --  @field End_Line Line the region closes on
   --  @field End_Column Column the region closes on
   type Source_Span is record
      Start_Byte   : Natural  := 0;
      End_Byte     : Natural  := 0;
      Start_Line   : Positive := 1;
      Start_Column : Positive := 1;
      End_Line     : Positive := 1;
      End_Column   : Positive := 1;
   end record;

   --  Why a parse failed.
   --  @enum Malformed_Syntax Input is outside the accepted grammar
   --  @enum Invalid_Encoding Input is not canonical UTF-8
   --  @enum Invalid_IRI A resolved IRI is not a valid absolute IRI
   --  @enum Undefined_Prefix A prefixed name used an unbound prefix
   --  @enum Byte_Limit Maximum_Bytes exceeded
   --  @enum Quad_Limit Maximum_Quads exceeded
   --  @enum Nesting_Limit Maximum_Nesting exceeded
   --  @enum Token_Limit Maximum_Token_Bytes exceeded
   --  @enum Prefix_Limit Maximum_Prefixes exceeded
   --  @enum Unsupported_Production A production this grammar rejects
   type Diagnostic_Code is
     (Malformed_Syntax,
      Invalid_Encoding,
      Invalid_IRI,
      Undefined_Prefix,
      Byte_Limit,
      Quad_Limit,
      Nesting_Limit,
      Token_Limit,
      Prefix_Limit,
      Unsupported_Production);

   --  Which part of the grammar was being read.
   --  @enum Document_Production The document as a whole
   --  @enum Directive_Production A prefix, base or version directive
   --  @enum Graph_Block_Production A TriG graph block
   --  @enum Statement_Production One statement
   --  @enum Subject_Production The subject position
   --  @enum Predicate_Production The predicate position
   --  @enum Object_Production The object position
   --  @enum IRI_Production An IRI, absolute or relative
   --  @enum Blank_Label_Production A blank node label
   --  @enum Literal_Production A literal and its datatype or tag
   --  @enum Collection_Production A parenthesised collection
   --  @enum Triple_Term_Production An RDF 1.2 triple term
   --  @enum Annotation_Production An RDF 1.2 annotation or reifier
   type Production_Kind is
     (Document_Production,
      Directive_Production,
      Graph_Block_Production,
      Statement_Production,
      Subject_Production,
      Predicate_Production,
      Object_Production,
      IRI_Production,
      Blank_Label_Production,
      Literal_Production,
      Collection_Production,
      Triple_Term_Production,
      Annotation_Production);

   --  A typed parse failure.
   type Parse_Diagnostic is private;

   --  Return the failure category.
   --  @param Value Diagnostic to inspect
   --  @return The diagnostic code
   function Code (Value : Parse_Diagnostic) return Diagnostic_Code;

   --  Return the production that failed.
   --  @param Value Diagnostic to inspect
   --  @return The production kind
   function Production (Value : Parse_Diagnostic) return Production_Kind;

   --  Return the region of input responsible.
   --  @param Value Diagnostic to inspect
   --  @return The source span
   function Span (Value : Parse_Diagnostic) return Source_Span;

   --  Return the source name supplied at Create.
   --  @param Value Diagnostic to inspect
   --  @return The source name
   function Source_Name (Value : Parse_Diagnostic) return String;

   --  Receives parse events.
   type Event_Sink is limited interface;

   --  Called when a graph block or GRAPH declaration names a graph.
   --  @param Target The sink
   --  @param Graph The graph being entered
   --  @param Span Region naming the graph
   procedure On_Graph_Declaration
     (Target : in out Event_Sink;
      Graph  : Quads.Graph_Name;
      Span   : Source_Span) is abstract;

   --  Called once per statement.
   --  @param Target The sink
   --  @param Value The statement
   --  @param Span Region that produced it
   procedure On_Quad
     (Target : in out Event_Sink;
      Value  : Quads.Quad;
      Span   : Source_Span) is abstract;

   --  Called once, when the parse fails.
   --  @param Target The sink
   --  @param Value The diagnostic
   procedure On_Diagnostic
     (Target : in out Event_Sink;
      Value  : Parse_Diagnostic) is abstract;

   --  Outcome of a completed parse.
   --  @enum Parse_Succeeded Every statement was read and delivered
   --  @enum Parse_Failed A diagnostic was delivered and reading stopped
   type Parse_Status is (Parse_Succeeded, Parse_Failed);

   --  Raised when a parser is used after it has finished or failed.
   Parser_State_Error : exception;

   --  Raised when Create is given a base IRI that is not absolute.
   Invalid_Configuration : exception;

   --  A parse in progress.
   type Parser (<>) is limited private;

   --  Optional cooperative-yield callback, invoked periodically while
   --  scanning. It exists so that a lightweight-task runtime can interleave,
   --  and is deliberately typed as a plain access-to-procedure so that this
   --  crate depends on no runtime at all.
   type Work_Checkpoint_Access is access procedure;

   --  Scan units between checkpoint callbacks.
   Work_Checkpoint_Interval : constant Positive := 4_096;

   --  Begin a parse.
   --  @param Source_Name Name reported in diagnostics
   --  @param Blank_Node_Prefix Prepended to every blank node label, both
   --     those the document writes and those the parser generates, so that
   --     labels from two documents parsed by the same consumer cannot
   --     collide. Within one document the parser keeps its generated labels
   --     clear of the document's own, so reading back what this crate wrote
   --     renames nothing and is a fixed point
   --  @param Base_IRI Absolute IRI relative references resolve against, or
   --     empty for none
   --  @param Limits Bounds for this parse
   --  @param Syntax Grammar to accept
   --  @param Work_Checkpoint Optional cooperative-yield callback
   --  @return A parser ready to be fed
   --  @exception Invalid_Configuration Base_IRI is neither empty nor an
   --     absolute IRI
   function Create
     (Source_Name       : String;
      Blank_Node_Prefix : String := "";
      Base_IRI          : String := "";
      Limits            : Parse_Limits := (others => <>);
      Syntax            : Syntax_Kind := TriG_Syntax;
      Work_Checkpoint   : Work_Checkpoint_Access := null) return Parser;

   --  Supply the next bytes of input, emitting every event they complete.
   --
   --  If a sink callback raises, the exception propagates unchanged and the
   --  parser is poisoned: no later Feed emits anything, and Finish reports
   --  failure.
   --  @param Into Parser to feed
   --  @param Bytes Next chunk, which may split any token
   --  @param Target Sink receiving events
   --  @exception Parser_State_Error Into has already finished
   procedure Feed
     (Into   : in out Parser;
      Bytes  : String;
      Target : in out Event_Sink'Class);

   --  Complete the parse, emitting any final events.
   --  @param Into Parser to finish
   --  @param Target Sink receiving events
   --  @return Whether the document was accepted
   --  @exception Parser_State_Error Into has already finished
   function Finish
     (Into   : in out Parser;
      Target : in out Event_Sink'Class) return Parse_Status;

   --  Deterministic account of scanning work, for tests that need to pin
   --  behaviour rather than timing.
   --  @field Bytes_Fed Input bytes handed to the parser
   --  @field Bytes_Scanned Input bytes the scanner walked over. Larger
   --    than Bytes_Fed, because a token split across chunks is walked
   --    again when the rest of it arrives. The ratio between the two is
   --    bounded; if it grows with input size, scanning has become
   --    quadratic.
   --  @field Tokens_Scanned Tokens produced
   --  @field Statements_Parsed Statements completed
   --  @field Checkpoint_Calls Cooperative callbacks invoked
   --  @field Maximum_Pending_Bytes Largest retained partial token
   --  @field Maximum_Pending_Tokens Largest retained statement, in tokens
   --  Counts are 64-bit rather than Natural. Bytes_Scanned is several
   --  times Bytes_Fed, and Maximum_Bytes is the caller's to set, so a
   --  caller who raises it can drive a 32-bit count past its range. A
   --  statistic that ends a parse it was only observing is a poor trade,
   --  and clamping is worse: the benchmark scaling check divides these,
   --  so a clamped count would read as flat exactly where the input is
   --  largest and the check matters most.
   type Work_Count is range 0 .. 2 ** 63 - 1;

   type Work_Statistics is record
      Bytes_Fed              : Work_Count := 0;
      Bytes_Scanned          : Work_Count := 0;
      Tokens_Scanned         : Work_Count := 0;
      Statements_Parsed      : Work_Count := 0;
      Checkpoint_Calls       : Work_Count := 0;
      Maximum_Pending_Bytes  : Work_Count := 0;
      Maximum_Pending_Tokens : Work_Count := 0;
   end record;

   --  Report the work this parser has done.
   --  @param Value Parser to inspect
   --  @return The accumulated statistics
   function Work (Value : Parser) return Work_Statistics;

private

   package Unbounded renames Ada.Strings.Unbounded;

   --  The tokens of the statement being accumulated. A plain array that
   --  is reused from one statement to the next rather than a vector: the
   --  scanner writes each token straight into its slot, resetting the
   --  count re-parses nothing and finalises nothing, and reading a token
   --  back is an array index rather than a checked reference object.
   type Token_Array is array (Positive range <>) of Lexers.Token;
   type Token_Array_Access is access Token_Array;

   type Statement_Buffer is
     new Ada.Finalization.Limited_Controlled with record
      Data  : Token_Array_Access;
      Count : Natural := 0;
   end record;

   overriding procedure Finalize (Value : in out Statement_Buffer);

   --  Bytes retained because they are a partial token, held in one heap
   --  buffer that is reused from chunk to chunk. An Unbounded_String here
   --  copied every chunk twice: once appending it, and once taking the
   --  whole text back out to scan it.
   type String_Access is access String;

   type Byte_Buffer is
     new Ada.Finalization.Limited_Controlled with record
      Data  : String_Access;
      Count : Natural := 0;
   end record;

   overriding procedure Finalize (Value : in out Byte_Buffer);

   --  Admitting an IRI means parsing it, and a document says the same
   --  IRIs over and over -- every predicate, every type, every datatype.
   --  Holding the ones already admitted turns each repeat into a lookup
   --  and a reference count bump. It is bounded, because a cache a
   --  document can grow without limit is the same hazard as any other
   --  unbounded buffer, and cleared whenever the base changes, since the
   --  base is what a relative reference was resolved against.
   Maximum_Cached_IRIs : constant := 4_096;

   package IRI_Caches is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type    => IRIs.IRI,
      Hash            => Ada.Strings.Hash,
      Equivalent_Keys => "=",
      "="             => IRIs."=");

   --  Admitted IRIs of prefixed names, keyed by the name as written --
   --  "ex:name" -- rather than by the IRI it expands to. The name is a
   --  fraction of the length of the expansion, so probing this map costs
   --  a fraction of the hash, and a hit skips the prefix lookup and the
   --  concatenation as well as the parse. A prefix can contain no colon,
   --  so the key cannot conflate two bindings; the map is cleared when
   --  any prefix is bound, since a rebinding changes what a name means.
   Maximum_Cached_Names : constant := 4_096;

   --  Hashed rather than ordered. Every prefixed name in a document looks
   --  its prefix up, and an ordered map answers that by walking a tree and
   --  comparing strings at each step. Nothing here needs the ordering.
   package Prefix_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type    => String,
      Hash            => Ada.Strings.Hash,
      Equivalent_Keys => "=");

   package Label_Sets is new Ada.Containers.Indefinite_Ordered_Sets
     (Element_Type => String);

   package IRI_Holders is new Ada.Containers.Indefinite_Holders
     (Element_Type => IRIs.IRI,
      "="          => IRIs."=");

   type Parse_Diagnostic is record
      Code_Value       : Diagnostic_Code := Malformed_Syntax;
      Production_Value : Production_Kind := Document_Production;
      Span_Value       : Source_Span;
      Source_Value     : Unbounded.Unbounded_String;
   end record;

   type Parser (Initialized : Boolean) is limited record
      Source_Data     : Unbounded.Unbounded_String;
      Blank_Prefix    : Unbounded.Unbounded_String;

      --  The base, held as a parsed IRI from the moment it is set --
      --  construction or a base directive -- so that resolving each
      --  reference of the document does not re-validate it. Empty when no
      --  base applies.
      Base_Data       : IRI_Holders.Holder;
      Limits_Data     : Parse_Limits;
      Syntax_Data     : Syntax_Kind := TriG_Syntax;
      Checkpoint      : Work_Checkpoint_Access;

      --  Bytes retained because they are a partial token.
      Pending         : Byte_Buffer;
      Pending_Origin  : Parser_Cursors.Cursor_State :=
        Parser_Cursors.Initial_State;

      --  Tokens retained because they are a partial statement.
      Statement       : Statement_Buffer;
      Nesting         : Natural := 0;

      --  A running view of Statement -- bracket depth and the leading
      --  token kinds -- maintained as each token is appended, so deciding
      --  whether the statement is complete does not re-walk every token
      --  retained so far once per token scanned.
      Statement_Depth : Integer := 0;
      First_Kind      : Lexers.Token_Kind := Lexers.Dot_Token;
      Second_Kind     : Lexers.Token_Kind := Lexers.Dot_Token;
      First_Is_Terminated_Version : Boolean := False;

      Prefixes        : Prefix_Maps.Map;
      Current_Graph   : Unbounded.Unbounded_String;
      Graph_Is_Named  : Boolean := False;
      Graph_Is_Blank  : Boolean := False;
      In_Graph_Block  : Boolean := False;

      --  Labels the document wrote itself, so that a generated label
      --  never collides with one of them.
      Document_Labels : Label_Sets.Set;

      --  Document labels whose spelling a generated label had already
      --  taken, mapped to the replacement each was issued.
      Renamed_Labels  : Prefix_Maps.Map;
      --  Where the last line-based statement began, so that two of them
      --  cannot share a line.
      Last_Statement_Line : Positive := 1;
      Line_Statement_Seen : Boolean := False;

      Blank_Counter   : Natural := 0;
      Quad_Count      : Natural := 0;
      IRI_Cache       : IRI_Caches.Map;
      Name_Cache      : IRI_Caches.Map;
      --  The graph a statement belongs to changes only at a graph
      --  block, but every statement needs it. Rebuilding it per
      --  statement re-admits the graph IRI each time.
      Graph_Cache       : Quads.Graph_Name;
      Graph_Cache_Key   : Unbounded.Unbounded_String;
      Graph_Cache_Named : Boolean := False;
      Graph_Cache_Blank : Boolean := False;
      Graph_Cache_Valid : Boolean := False;
      Byte_Count      : Natural := 0;
      Work_Data       : Work_Statistics;
      Work_Units      : Natural := 0;

      Failed          : Boolean := False;
      Finished        : Boolean := False;
   end record;

end Flyology_RDF.Turtle_Parsers;
