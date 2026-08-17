--  Exercises UTF-8 decoding and position tracking.
--
--  The distinction that matters most here is Incomplete versus Invalid. A
--  chunk-fed parser splits input at arbitrary byte boundaries, so a sequence
--  truncated by a chunk boundary must be distinguishable from one that is
--  simply wrong -- otherwise every split in the middle of a multi-byte
--  scalar becomes a spurious syntax error.

with Ada.Command_Line;
with Ada.Text_IO;
with Flyology_RDF.Parser_Cursors;

procedure Cursor_Tests is

   package IO renames Ada.Text_IO;
   package Cursors renames Flyology_RDF.Parser_Cursors;

   use type Cursors.Decode_Status;

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

   function B (Code : Natural) return Character
   is (Character'Val (Code));

   procedure Expect
     (Text            : String;
      Expected_Status : Cursors.Decode_Status;
      Expected_Scalar : Natural;
      Expected_Length : Natural;
      Label           : String)
   is
      Scalar : Cursors.Scalar_Value;
      Length : Natural;
      Status : Cursors.Decode_Status;
   begin
      Cursors.Decode (Text, Text'First, Scalar, Length, Status);
      Check (Status = Expected_Status, Label & " status");
      if Status = Cursors.Decoded then
         Check (Scalar = Expected_Scalar, Label & " scalar");
         Check (Length = Expected_Length, Label & " length");
      end if;
   end Expect;

   procedure Expect_Status
     (Text            : String;
      Expected_Status : Cursors.Decode_Status;
      Label           : String) is
   begin
      Expect (Text, Expected_Status, 0, 0, Label);
   end Expect_Status;

begin
   IO.Put_Line ("Cursor tests");

   ------------------------------------------------------------------
   --  Well-formed sequences of each length
   ------------------------------------------------------------------
   Expect ("A", Cursors.Decoded, 16#41#, 1, "ASCII");
   Expect ([B (16#00#)], Cursors.Decoded, 0, 1, "NUL");
   Expect ([B (16#7F#)], Cursors.Decoded, 16#7F#, 1, "DEL");
   Expect ([B (16#C3#), B (16#A9#)], Cursors.Decoded, 16#E9#, 2,
           "two-byte e-acute");
   Expect ([B (16#E2#), B (16#82#), B (16#AC#)], Cursors.Decoded,
           16#20AC#, 3, "three-byte euro sign");
   Expect ([B (16#F0#), B (16#9F#), B (16#98#), B (16#80#)],
           Cursors.Decoded, 16#1F600#, 4, "four-byte emoji");
   Expect ([B (16#F4#), B (16#8F#), B (16#BF#), B (16#BF#)],
           Cursors.Decoded, 16#10FFFF#, 4, "highest scalar");

   ------------------------------------------------------------------
   --  Truncation at a chunk boundary is Incomplete, not Invalid
   ------------------------------------------------------------------
   Expect_Status ([B (16#C3#)], Cursors.Incomplete, "two-byte truncated");
   Expect_Status ([B (16#E2#)], Cursors.Incomplete,
                  "three-byte truncated at one");
   Expect_Status ([B (16#E2#), B (16#82#)], Cursors.Incomplete,
                  "three-byte truncated at two");
   Expect_Status ([B (16#F0#)], Cursors.Incomplete,
                  "four-byte truncated at one");
   Expect_Status ([B (16#F0#), B (16#9F#), B (16#98#)], Cursors.Incomplete,
                  "four-byte truncated at three");

   ------------------------------------------------------------------
   --  Malformed input is Invalid even when it is also short, because the
   --  bytes already present rule out every completion.
   ------------------------------------------------------------------
   Expect_Status ([B (16#80#)], Cursors.Invalid, "lone continuation byte");
   Expect_Status ([B (16#BF#)], Cursors.Invalid, "lone continuation high");
   Expect_Status ([B (16#C0#), B (16#80#)], Cursors.Invalid,
                  "overlong two-byte NUL");
   Expect_Status ([B (16#C1#), B (16#BF#)], Cursors.Invalid,
                  "overlong two-byte DEL");
   Expect_Status ([B (16#E0#), B (16#80#)], Cursors.Invalid,
                  "overlong three-byte, detected before completion");
   Expect_Status ([B (16#E0#), B (16#9F#), B (16#BF#)], Cursors.Invalid,
                  "overlong three-byte, complete");
   Expect_Status ([B (16#ED#), B (16#A0#), B (16#80#)], Cursors.Invalid,
                  "surrogate D800");
   Expect_Status ([B (16#ED#), B (16#A0#)], Cursors.Invalid,
                  "surrogate detected before completion");
   Expect_Status ([B (16#F0#), B (16#80#)], Cursors.Invalid,
                  "overlong four-byte");
   Expect_Status ([B (16#F4#), B (16#90#)], Cursors.Invalid,
                  "above the highest scalar");
   Expect_Status ([B (16#F5#)], Cursors.Invalid, "F5 lead byte");
   Expect_Status ([B (16#FF#)], Cursors.Invalid, "FF lead byte");
   Expect_Status ([B (16#C3#), B (16#41#)], Cursors.Invalid,
                  "two-byte with a non-continuation second byte");
   Expect_Status ([B (16#E2#), B (16#82#), B (16#41#)], Cursors.Invalid,
                  "three-byte with a non-continuation third byte");

   ------------------------------------------------------------------
   --  Position tracking
   ------------------------------------------------------------------
   declare
      State : Cursors.Cursor_State := Cursors.Initial_State;
   begin
      Cursors.Advance (State, 16#41#, 1);
      Check (State.Byte_Offset = 1, "byte offset after one ASCII scalar");
      Check (State.Line = 1, "line unchanged by an ASCII scalar");
      Check (State.Column = 2, "column advanced by an ASCII scalar");

      --  Columns count scalars, not bytes, so a four-byte emoji is one
      --  column but four bytes.
      Cursors.Advance (State, 16#1F600#, 4);
      Check (State.Byte_Offset = 5, "byte offset counts bytes");
      Check (State.Column = 3, "column counts scalars");
   end;

   declare
      State : Cursors.Cursor_State := Cursors.Initial_State;
   begin
      Cursors.Advance (State, 16#0A#, 1);
      Check (State.Line = 2, "LF advances the line");
      Check (State.Column = 1, "LF resets the column");
   end;

   declare
      State : Cursors.Cursor_State := Cursors.Initial_State;
   begin
      Cursors.Advance (State, 16#0D#, 1);
      Cursors.Advance (State, 16#0A#, 1);
      Check (State.Line = 2, "CRLF advances the line exactly once");
      Check (State.Byte_Offset = 2, "CRLF still consumes two bytes");
   end;

   declare
      State : Cursors.Cursor_State := Cursors.Initial_State;
   begin
      Cursors.Advance (State, 16#0D#, 1);
      Cursors.Advance (State, 16#0D#, 1);
      Check (State.Line = 3, "two CRs are two line breaks");
   end;

   declare
      State : Cursors.Cursor_State := Cursors.Initial_State;
   begin
      Cursors.Advance (State, 16#0A#, 1);
      Cursors.Advance (State, 16#0A#, 1);
      Check (State.Line = 3, "two LFs are two line breaks");
   end;

   declare
      State : Cursors.Cursor_State := Cursors.Initial_State;
   begin
      --  An LF that does not directly follow a CR is its own line break,
      --  even when a CR appeared earlier on the line.
      Cursors.Advance (State, 16#0D#, 1);
      Cursors.Advance (State, 16#41#, 1);
      Cursors.Advance (State, 16#0A#, 1);
      Check (State.Line = 3, "CR, text, LF is two line breaks");
   end;

   IO.Put_Line ("  checks              " & Checks'Image);
   IO.Put_Line ("  failures            " & Failures'Image);

   if Failures = 0 then
      IO.Put_Line ("PASS cursor_tests");
   else
      IO.Put_Line ("FAIL cursor_tests");
      Ada.Command_Line.Set_Exit_Status (1);
   end if;
end Cursor_Tests;
