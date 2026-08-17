package body Flyology_RDF.Parser_Cursors with SPARK_Mode is

   --  Sequence length implied by a lead byte, or zero when the byte cannot
   --  begin one. C0 and C1 are excluded because they could only ever encode
   --  an overlong form of an ASCII scalar.
   function Lead_Length (Lead : Natural) return Natural
   is (if Lead < 16#80# then 1
       elsif Lead in 16#C2# .. 16#DF# then 2
       elsif Lead in 16#E0# .. 16#EF# then 3
       elsif Lead in 16#F0# .. 16#F4# then 4
       else 0);

   function Is_Continuation (Item : Character) return Boolean
   is (Character'Pos (Item) in 16#80# .. 16#BF#);

   procedure Decode
     (Text   : String;
      Index  : Positive;
      Scalar : out Scalar_Value;
      Length : out Natural;
      Status : out Decode_Status)
   is
      Lead      : constant Natural := Character'Pos (Text (Index));
      Needed    : constant Natural := Lead_Length (Lead);
      Available : constant Natural := Text'Last - Index + 1;
      Value     : Natural := 0;
   begin
      Scalar := 0;
      Length := 0;

      if Needed = 0 then
         Status := Invalid;
         return;
      end if;

      if Needed = 1 then
         Scalar := Lead;
         Length := 1;
         Status := Decoded;
         return;
      end if;

      --  Check whatever continuation bytes are present before deciding
      --  between Incomplete and Invalid: a truncated sequence whose present
      --  bytes are already wrong is an error, not a chunk boundary.
      for Offset in 1 .. Natural'Min (Needed - 1, Available - 1) loop
         if not Is_Continuation (Text (Index + Offset)) then
            Status := Invalid;
            return;
         end if;
      end loop;

      --  The second byte carries the range restrictions that rule out
      --  overlong forms and the surrogate block, so it is worth checking as
      --  soon as it is present rather than after the whole sequence.
      if Available >= 2 then
         declare
            Next : constant Natural := Character'Pos (Text (Index + 1));
         begin
            if (Lead = 16#E0# and then Next < 16#A0#)
              or else (Lead = 16#ED# and then Next > 16#9F#)
              or else (Lead = 16#F0# and then Next < 16#90#)
              or else (Lead = 16#F4# and then Next > 16#8F#)
            then
               Status := Invalid;
               return;
            end if;
         end;
      end if;

      if Available < Needed then
         Status := Incomplete;
         return;
      end if;

      case Needed is
         when 2 => Value := Lead - 16#C0#;
         when 3 => Value := Lead - 16#E0#;
         when 4 => Value := Lead - 16#F0#;
         when others => Value := 0;
      end case;

      for Offset in 1 .. Needed - 1 loop
         Value :=
           Value * 64 + (Character'Pos (Text (Index + Offset)) - 16#80#);
      end loop;

      if Value > Maximum_Scalar then
         Status := Invalid;
         return;
      end if;

      Scalar := Value;
      Length := Needed;
      Status := Decoded;
   end Decode;

   procedure Advance
     (State  : in out Cursor_State;
      Scalar : Scalar_Value;
      Length : Positive) is
   begin
      State.Byte_Offset := State.Byte_Offset + Length;

      if Scalar = 16#0A# and then State.After_Carriage_Return then
         --  The LF half of a CRLF pair. The line already advanced on the CR.
         State.After_Carriage_Return := False;
      elsif Is_Line_Break (Scalar) then
         State.Line := State.Line + 1;
         State.Column := 1;
         State.After_Carriage_Return := Scalar = 16#0D#;
      else
         State.Column := State.Column + 1;
         State.After_Carriage_Return := False;
      end if;
   end Advance;

end Flyology_RDF.Parser_Cursors;
