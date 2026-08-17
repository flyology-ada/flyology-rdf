--  UTF-8 scalar decoding with byte, line, and column tracking.
--
--  Diagnostics carry a full source span rather than a message, so every byte
--  the parser consumes has to move a position forward exactly once. This
--  package owns that arithmetic and nothing else, which keeps it small
--  enough to reason about and free of any dependency on the term model.
package Flyology_RDF.Parser_Cursors with SPARK_Mode is

   --  A position in the input.
   --  @field Byte_Offset Bytes consumed so far, zero before the first
   --  @field Line One-based line number
   --  @field Column One-based column, counted in scalars rather than bytes
   --  @field After_Carriage_Return True when the previous scalar was CR, so
   --     that a following LF completes one line break instead of starting a
   --     second one
   type Cursor_State is record
      Byte_Offset             : Natural  := 0;
      Line                    : Positive := 1;
      Column                  : Positive := 1;
      After_Carriage_Return   : Boolean  := False;
   end record;

   --  The position before any input has been consumed.
   Initial_State : constant Cursor_State :=
     (Byte_Offset           => 0,
      Line                  => 1,
      Column                => 1,
      After_Carriage_Return => False);

   --  Outcome of decoding one scalar.
   --  @enum Decoded A complete, canonical scalar was decoded
   --  @enum Incomplete The input ends part-way through a sequence, which is
   --     a chunk boundary rather than an error
   --  @enum Invalid The bytes are not a canonical UTF-8 encoding
   type Decode_Status is (Decoded, Incomplete, Invalid);

   --  Largest scalar value Unicode defines.
   Maximum_Scalar : constant := 16#10FFFF#;

   subtype Scalar_Value is Natural range 0 .. Maximum_Scalar;

   --  Decode the scalar beginning at Text (Index).
   --
   --  Incomplete is reported only when the remaining bytes are a valid
   --  prefix of some longer sequence, so a caller feeding input in chunks
   --  can distinguish "wait for more" from "this input is wrong".
   --  @param Text Buffer to read from
   --  @param Index Position of the lead byte
   --  @param Scalar The decoded scalar value, meaningful only when Decoded
   --  @param Length Bytes consumed, meaningful only when Decoded
   --  @param Status Outcome of the decode
   procedure Decode
     (Text   : String;
      Index  : Positive;
      Scalar : out Scalar_Value;
      Length : out Natural;
      Status : out Decode_Status)
   with
     Pre  => Index >= Text'First and then Index <= Text'Last,
     Post => (if Status = Decoded
              then Length in 1 .. 4
                and then Index + Length - 1 <= Text'Last
              else Length = 0);

   --  Move a position past one decoded scalar.
   --
   --  CR, LF, and CRLF each advance the line exactly once, which is what
   --  makes a column number comparable across platforms.
   --  @param State Position to advance
   --  @param Scalar The scalar just consumed
   --  @param Length Its encoded length in bytes
   procedure Advance
     (State  : in out Cursor_State;
      Scalar : Scalar_Value;
      Length : Positive)
   with
     Pre  => Length <= 4
             and then State.Byte_Offset <= Natural'Last - Length
             and then State.Line < Positive'Last
             and then State.Column < Positive'Last,
     Post => State.Byte_Offset = State'Old.Byte_Offset + Length;

   --  Report whether a scalar ends a line.
   --  @param Scalar Scalar to classify
   --  @return True for LF and CR
   function Is_Line_Break (Scalar : Scalar_Value) return Boolean
   is (Scalar = 16#0A# or else Scalar = 16#0D#);

end Flyology_RDF.Parser_Cursors;
