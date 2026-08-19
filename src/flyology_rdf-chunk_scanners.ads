with Ada.Containers.Vectors;

with Flyology_RDF.Lexers;
with Flyology_RDF.Parser_Cursors;

--  Scanning a document that arrives in pieces, under a declared bound.
--
--  The Notation3 and SPARQL parsers both read a whole document into tokens
--  and then parse the tokens. They did it with the same fifty lines,
--  differing only in the dialect they passed, and neither bounded
--  anything. An unterminated token was retained and rescanned on every
--  chunk, so a document that never closes its first quote cost time
--  quadratic in what had arrived and memory linear in it, without limit.
--
--  Both scan through here now. A bound reached is an outcome the caller
--  reports in its own words, not an exception raised from underneath it.
package Flyology_RDF.Chunk_Scanners is

   --  What one document may cost to scan.
   --  @field Maximum_Bytes Total input accepted
   --  @field Maximum_Tokens Tokens retained; zero means no limit
   --  @field Maximum_Token_Bytes Longest single token. It also bounds the
   --     buffer held across a chunk boundary, which is what stops an
   --     unfinished token from being retained and rescanned without end
   type Scan_Limits is record
      Maximum_Bytes       : Positive := 64 * 1_024 * 1_024;
      Maximum_Tokens      : Natural  := 0;
      Maximum_Token_Bytes : Positive := 1_048_576;
   end record;

   --  How a scan ended.
   --  @enum Scanned Every token the bytes completed was appended
   --  @enum Malformed The bytes cannot begin or continue a token
   --  @enum Byte_Limit The document is longer than Maximum_Bytes
   --  @enum Token_Limit It holds more tokens than Maximum_Tokens
   --  @enum Token_Bytes_Limit One token is longer than
   --     Maximum_Token_Bytes, finished or not
   type Scan_Outcome is
     (Scanned, Malformed, Byte_Limit, Token_Limit, Token_Bytes_Limit);

   package Token_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Lexers.Token,
      "="          => Lexers."=");

   --  What one scan carries to the next.
   --  @field Origin Cursor where the retained bytes begin
   --  @field Bytes_Seen Input accepted so far, against Maximum_Bytes
   type Scan_State is record
      Origin     : Parser_Cursors.Cursor_State :=
        Parser_Cursors.Initial_State;
      Bytes_Seen : Natural := 0;
   end record;

   --  Scan as far as the bytes allow, appending whole tokens and
   --  reporting where the unread remainder begins.
   --  @param Text The retained bytes followed by the new ones
   --  @param Ended Whether more bytes can still arrive
   --  @param Dialect Grammar whose tokens these are
   --  @param Limits Bounds for this document
   --  @param State Carried between calls
   --  @param Tokens Extended with every token completed
   --  @param Consumed Index in Text where the remainder begins
   --  @param Outcome How this scan ended
   --  @param Stopped Cursor to report a failure at
   --  @param Error Why a Malformed outcome was reported
   procedure Scan_Chunk
     (Text     : String;
      Ended    : Boolean;
      Dialect  : Lexers.Dialect_Kind;
      Limits   : Scan_Limits;
      State    : in out Scan_State;
      Tokens   : in out Token_Vectors.Vector;
      Consumed : out Natural;
      Outcome  : out Scan_Outcome;
      Stopped  : out Parser_Cursors.Cursor_State;
      Error    : out Lexers.Scan_Error_Kind);

end Flyology_RDF.Chunk_Scanners;
