with Ada.Characters.Handling;

package body Flyology_RDF.Lexers is

   package Cursors renames Parser_Cursors;

   use type Cursors.Decode_Status;

   subtype Scalar_Value is Cursors.Scalar_Value;

   --  What a look-ahead found.
   --  @enum Available A scalar was decoded
   --  @enum Exhausted The buffer ends here
   --  @enum Partial The buffer ends inside a scalar
   --  @enum Bad The bytes are not canonical UTF-8
   type Peek_Status is (Available, Exhausted, Partial, Bad);

   procedure Peek
     (Text   : String;
      Index  : Positive;
      Scalar : out Scalar_Value;
      Length : out Natural;
      Status : out Peek_Status);

   procedure Peek
     (Text   : String;
      Index  : Positive;
      Scalar : out Scalar_Value;
      Length : out Natural;
      Status : out Peek_Status)
   is
      Decode_Result : Cursors.Decode_Status;
   begin
      Scalar := 0;
      Length := 0;

      if Index > Text'Last then
         Status := Exhausted;
         return;
      end if;

      Cursors.Decode (Text, Index, Scalar, Length, Decode_Result);
      case Decode_Result is
         when Cursors.Decoded    => Status := Available;
         when Cursors.Incomplete => Status := Partial;
         when Cursors.Invalid    => Status := Bad;
      end case;
   end Peek;

   ----------------------------------------------------------------------
   --  Character classes from the Turtle grammar
   ----------------------------------------------------------------------

   function Is_Whitespace (Scalar : Scalar_Value) return Boolean
   is (Scalar in 16#09# | 16#0A# | 16#0D# | 16#20#);

   function Is_Digit (Scalar : Scalar_Value) return Boolean
   is (Scalar in 16#30# .. 16#39#);

   function Is_Hex (Scalar : Scalar_Value) return Boolean
   is (Scalar in 16#30# .. 16#39#
       or else Scalar in 16#41# .. 16#46#
       or else Scalar in 16#61# .. 16#66#);

   function Is_ASCII_Letter (Scalar : Scalar_Value) return Boolean
   is (Scalar in 16#41# .. 16#5A# or else Scalar in 16#61# .. 16#7A#);

   function Is_PN_Chars_Base (Scalar : Scalar_Value) return Boolean
   is (Is_ASCII_Letter (Scalar)
       or else Scalar in 16#00C0# .. 16#00D6#
       or else Scalar in 16#00D8# .. 16#00F6#
       or else Scalar in 16#00F8# .. 16#02FF#
       or else Scalar in 16#0370# .. 16#037D#
       or else Scalar in 16#037F# .. 16#1FFF#
       or else Scalar in 16#200C# .. 16#200D#
       or else Scalar in 16#2070# .. 16#218F#
       or else Scalar in 16#2C00# .. 16#2FEF#
       or else Scalar in 16#3001# .. 16#D7FF#
       or else Scalar in 16#F900# .. 16#FDCF#
       or else Scalar in 16#FDF0# .. 16#FFFD#
       or else Scalar in 16#10000# .. 16#EFFFF#);

   function Is_PN_Chars_U (Scalar : Scalar_Value) return Boolean
   is (Is_PN_Chars_Base (Scalar) or else Scalar = 16#5F#);

   function Is_PN_Chars (Scalar : Scalar_Value) return Boolean
   is (Is_PN_Chars_U (Scalar)
       or else Scalar = 16#2D#
       or else Is_Digit (Scalar)
       or else Scalar = 16#00B7#
       or else Scalar in 16#0300# .. 16#036F#
       or else Scalar in 16#203F# .. 16#2040#);

   --  Characters a backslash may escape inside a local name.
   function Is_PN_Local_Escapable (Scalar : Scalar_Value) return Boolean
   is (Scalar in 16#5F# | 16#7E# | 16#2E# | 16#2D# | 16#21# | 16#24#
                | 16#26# | 16#27# | 16#28# | 16#29# | 16#2A# | 16#2B#
                | 16#2C# | 16#3B# | 16#3D# | 16#2F# | 16#3F# | 16#23#
                | 16#40# | 16#25#);

   --  Characters the IRIREF production forbids between the angle brackets,
   --  independently of whether they are valid in an IRI.
   function Is_Forbidden_In_IRI_Reference
     (Scalar : Scalar_Value) return Boolean
   is (Scalar <= 16#20#
       or else Scalar in 16#3C# | 16#3E# | 16#22# | 16#7B# | 16#7D#
                       | 16#7C# | 16#5E# | 16#60# | 16#5C#);

   function Hex_Value (Scalar : Scalar_Value) return Natural
   is (if Scalar in 16#30# .. 16#39# then Scalar - 16#30#
       elsif Scalar in 16#41# .. 16#46# then Scalar - 16#41# + 10
       else Scalar - 16#61# + 10);

   ----------------------------------------------------------------------
   --  Encoding a scalar back into the token's decoded text
   ----------------------------------------------------------------------

   procedure Append_Scalar
     (Buffer : in out Unbounded.Unbounded_String;
      Scalar : Scalar_Value);

   procedure Append_Scalar
     (Buffer : in out Unbounded.Unbounded_String;
      Scalar : Scalar_Value) is
   begin
      if Scalar < 16#80# then
         Unbounded.Append (Buffer, Character'Val (Scalar));
      elsif Scalar < 16#800# then
         Unbounded.Append (Buffer, Character'Val (16#C0# + Scalar / 64));
         Unbounded.Append
           (Buffer, Character'Val (16#80# + Scalar mod 64));
      elsif Scalar < 16#1_0000# then
         Unbounded.Append (Buffer, Character'Val (16#E0# + Scalar / 4096));
         Unbounded.Append
           (Buffer, Character'Val (16#80# + (Scalar / 64) mod 64));
         Unbounded.Append
           (Buffer, Character'Val (16#80# + Scalar mod 64));
      else
         Unbounded.Append
           (Buffer, Character'Val (16#F0# + Scalar / 262144));
         Unbounded.Append
           (Buffer, Character'Val (16#80# + (Scalar / 4096) mod 64));
         Unbounded.Append
           (Buffer, Character'Val (16#80# + (Scalar / 64) mod 64));
         Unbounded.Append
           (Buffer, Character'Val (16#80# + Scalar mod 64));
      end if;
   end Append_Scalar;

   ----------------------------------------------------------------------
   --  Accessors
   ----------------------------------------------------------------------

   function Kind (Value : Token) return Token_Kind is (Value.Kind_Value);

   function Text (Value : Token) return String
   is (Unbounded.To_String (Value.Text_Value));

   function Prefix (Value : Token) return String
   is (Unbounded.To_String (Value.Prefix_Value));

   function Form (Value : Token) return String_Form is (Value.Form_Value);

   function Has_Direction (Value : Token) return Boolean
   is (Value.Has_Direction_Data);

   function Direction (Value : Token) return Direction_Value
   is (Value.Direction_Data);

   function Start_Position (Value : Token) return Cursors.Cursor_State
   is (Value.Start_Value);

   function End_Position (Value : Token) return Cursors.Cursor_State
   is (Value.End_Value);

   function Null_Token return Token
   is (Initialized => True, others => <>);

   overriding function "=" (Left, Right : Token) return Boolean is
      use type Unbounded.Unbounded_String;
   begin
      return Left.Kind_Value = Right.Kind_Value
        and then Left.Text_Value = Right.Text_Value
        and then Left.Prefix_Value = Right.Prefix_Value
        and then Left.Form_Value = Right.Form_Value
        and then Left.Has_Direction_Data = Right.Has_Direction_Data
        and then (not Left.Has_Direction_Data
                  or else Left.Direction_Data = Right.Direction_Data);
   end "=";

   ----------------------------------------------------------------------
   --  Scanning
   ----------------------------------------------------------------------

   procedure Scan
     (Text       : String;
      Position   : in out Cursors.Cursor_State;
      Index      : in out Positive;
      Last_Chunk : Boolean;
      Result     : out Token;
      Status     : out Scan_Status;
      Error      : out Scan_Error_Kind;
      Dialect    : Dialect_Kind := RDF_Dialect)
   is
      --  Working position, committed back to the caller only on success.
      Walk_Position : Cursors.Cursor_State := Position;
      Walk_Index    : Positive := Index;

      Start_Position_Value : Cursors.Cursor_State;
      Start_Index          : Positive;

      Buffer : Unbounded.Unbounded_String;
      Prefix_Buffer : Unbounded.Unbounded_String;

      Scalar : Scalar_Value;
      Length : Natural;
      Look   : Peek_Status;

      procedure Step (By_Scalar : Scalar_Value; By_Length : Positive);

      procedure Step (By_Scalar : Scalar_Value; By_Length : Positive) is
      begin
         Cursors.Advance (Walk_Position, By_Scalar, By_Length);
         Walk_Index := Walk_Index + By_Length;
      end Step;

      procedure Emit (Which : Token_Kind);

      procedure Emit (Which : Token_Kind) is
      begin
         Result :=
           (Initialized        => True,
            Kind_Value         => Which,
            Text_Value         => Buffer,
            Prefix_Value       => Prefix_Buffer,
            Form_Value         => Result.Form_Value,
            Has_Direction_Data => Result.Has_Direction_Data,
            Direction_Data     => Result.Direction_Data,
            Start_Value        => Start_Position_Value,
            End_Value          => Walk_Position);
         Position := Walk_Position;
         Index := Walk_Index;
         Status := Token_Found;
         Error := No_Error;
      end Emit;

      procedure Fail (Why : Scan_Error_Kind);

      procedure Fail (Why : Scan_Error_Kind) is
      begin
         Status := Scan_Error;
         Error := Why;
      end Fail;

      procedure Incomplete;

      procedure Incomplete is
      begin
         Status := Needs_More_Input;
         Error := No_Error;
      end Incomplete;

      --  For a token that cannot end at the buffer's end: mid-stream this
      --  is a request for the next chunk, but on the final chunk it is an
      --  unterminated string, IRI reference, or escape.
      procedure Want_More;

      procedure Want_More is
      begin
         if Last_Chunk then
            Fail (Unterminated_Token);
         else
            Incomplete;
         end if;
      end Want_More;

      --  For a token that *may* end at the buffer's end. On the final chunk
      --  the absence of a next character is reported as a space, which
      --  terminates every unquoted token and belongs to no character class,
      --  so each scanner stops exactly as it would at real whitespace.
      procedure Peek_Token_End
        (At_Index : Positive;
         Scalar   : out Scalar_Value;
         Length   : out Natural;
         Found    : out Peek_Status);

      procedure Peek_Token_End
        (At_Index : Positive;
         Scalar   : out Scalar_Value;
         Length   : out Natural;
         Found    : out Peek_Status) is
      begin
         Peek (Text, At_Index, Scalar, Length, Found);
         if Found = Exhausted and then Last_Chunk then
            Scalar := 16#20#;
            Length := 0;
            Found := Available;
         end if;
      end Peek_Token_End;

      --  Translate a look-ahead that is not Available into an outcome.
      --  Returns True when the caller should stop.
      function Halt_On (Found : Peek_Status) return Boolean;

      function Halt_On (Found : Peek_Status) return Boolean is
      begin
         case Found is
            when Available =>
               return False;
            when Exhausted | Partial =>
               Want_More;
               return True;
            when Bad =>
               Fail (Invalid_Encoding);
               return True;
         end case;
      end Halt_On;

      procedure Scan_Numeric_Escape (Digits_Wanted : Positive);

      --  \uXXXX and \UXXXXXXXX, with the backslash and marker already
      --  consumed.
      procedure Scan_Numeric_Escape (Digits_Wanted : Positive) is
         Value : Natural := 0;
      begin
         for Ignored in 1 .. Digits_Wanted loop
            Peek (Text, Walk_Index, Scalar, Length, Look);
            if Halt_On (Look) then
               return;
            elsif not Is_Hex (Scalar) then
               Fail (Malformed_Escape);
               return;
            end if;
            Value := Value * 16 + Hex_Value (Scalar);
            Step (Scalar, Length);
         end loop;

         --  A numeric escape may not name a surrogate or a value outside
         --  Unicode; those are not characters and cannot be re-encoded.
         if Value in 16#D800# .. 16#DFFF#
           or else Value > Cursors.Maximum_Scalar
         then
            Fail (Malformed_Escape);
            return;
         end if;

         Append_Scalar (Buffer, Value);
      end Scan_Numeric_Escape;

      procedure Scan_IRI_Reference;

      procedure Scan_IRI_Reference is
      begin
         --  The opening '<' is consumed by the caller.
         loop
            Peek (Text, Walk_Index, Scalar, Length, Look);
            if Halt_On (Look) then
               return;
            end if;

            if Scalar = 16#3E# then           --  '>'
               Step (Scalar, Length);
               Emit (IRI_Reference_Token);
               return;
            elsif Scalar = 16#5C# then        --  '\'
               Step (Scalar, Length);
               Peek (Text, Walk_Index, Scalar, Length, Look);
               if Halt_On (Look) then
                  return;
               end if;
               if Scalar = 16#75# then        --  'u'
                  Step (Scalar, Length);
                  Scan_Numeric_Escape (4);
               elsif Scalar = 16#55# then     --  'U'
                  Step (Scalar, Length);
                  Scan_Numeric_Escape (8);
               else
                  Fail (Malformed_Escape);
                  return;
               end if;
               if Status /= Token_Found and then Error /= No_Error then
                  return;
               elsif Status = Needs_More_Input then
                  return;
               end if;
            elsif Is_Forbidden_In_IRI_Reference (Scalar) then
               Fail (Forbidden_Character);
               return;
            else
               Append_Scalar (Buffer, Scalar);
               Step (Scalar, Length);
            end if;
         end loop;
      end Scan_IRI_Reference;

      procedure Scan_String (Quote : Scalar_Value);

      procedure Scan_String (Quote : Scalar_Value) is
         Long : Boolean := False;
      begin
         --  One quote is already consumed. Two more make it a long form;
         --  exactly two in total is the empty short string.
         Peek (Text, Walk_Index, Scalar, Length, Look);
         if Look = Available and then Scalar = Quote then
            Step (Scalar, Length);
            Peek (Text, Walk_Index, Scalar, Length, Look);
            if Look = Available and then Scalar = Quote then
               Step (Scalar, Length);
               Long := True;
            elsif Look = Partial then
               Incomplete;
               return;
            elsif Look = Bad then
               Fail (Invalid_Encoding);
               return;
            elsif Look = Exhausted and then not Last_Chunk then
               --  A third quote would make this a long string, and it may
               --  be in the next chunk.
               Incomplete;
               return;
            else
               --  Two quotes and then something else: the empty string.
               Result.Form_Value := Short_Quoted;
               Emit (String_Token);
               return;
            end if;
         elsif Look = Partial then
            Incomplete;
            return;
         elsif Look = Bad then
            Fail (Invalid_Encoding);
            return;
         end if;

         Result.Form_Value := (if Long then Long_Quoted else Short_Quoted);

         loop
            Peek (Text, Walk_Index, Scalar, Length, Look);
            if Halt_On (Look) then
               return;
            end if;

            if Scalar = Quote then
               if not Long then
                  Step (Scalar, Length);
                  Emit (String_Token);
                  return;
               end if;

               --  A long string ends at three quotes; one or two are
               --  content. Deciding needs up to two more scalars, so a
               --  buffer that ends here has to wait for them.
               declare
                  Run_Position : constant Cursors.Cursor_State :=
                    Walk_Position;
                  Run_Index    : constant Positive := Walk_Index;
                  Run          : Natural := 0;
               begin
                  while Run < 3 loop
                     Peek (Text, Walk_Index, Scalar, Length, Look);
                     exit when Look /= Available or else Scalar /= Quote;
                     Step (Scalar, Length);
                     Run := Run + 1;
                  end loop;

                  if Run = 3 then
                     Emit (String_Token);
                     return;
                  elsif Look = Partial or else Look = Exhausted then
                     Incomplete;
                     return;
                  elsif Look = Bad then
                     Fail (Invalid_Encoding);
                     return;
                  end if;

                  --  Fewer than three: they are content after all.
                  Walk_Position := Run_Position;
                  Walk_Index := Run_Index;
                  for Ignored in 1 .. Run loop
                     Append_Scalar (Buffer, Quote);
                     Step (Quote, 1);
                  end loop;
               end;
            elsif Scalar = 16#5C# then        --  '\'
               Step (Scalar, Length);
               Peek (Text, Walk_Index, Scalar, Length, Look);
               if Halt_On (Look) then
                  return;
               end if;
               case Scalar is
                  when 16#74# =>              --  \t
                     Append_Scalar (Buffer, 16#09#);
                     Step (Scalar, Length);
                  when 16#62# =>              --  \b
                     Append_Scalar (Buffer, 16#08#);
                     Step (Scalar, Length);
                  when 16#6E# =>              --  \n
                     Append_Scalar (Buffer, 16#0A#);
                     Step (Scalar, Length);
                  when 16#72# =>              --  \r
                     Append_Scalar (Buffer, 16#0D#);
                     Step (Scalar, Length);
                  when 16#66# =>              --  \f
                     Append_Scalar (Buffer, 16#0C#);
                     Step (Scalar, Length);
                  when 16#22# | 16#27# | 16#5C# =>
                     Append_Scalar (Buffer, Scalar);
                     Step (Scalar, Length);
                  when 16#75# =>              --  \uXXXX
                     Step (Scalar, Length);
                     Scan_Numeric_Escape (4);
                     if Status = Needs_More_Input
                       or else Status = Scan_Error
                     then
                        return;
                     end if;
                  when 16#55# =>              --  \UXXXXXXXX
                     Step (Scalar, Length);
                     Scan_Numeric_Escape (8);
                     if Status = Needs_More_Input
                       or else Status = Scan_Error
                     then
                        return;
                     end if;
                  when others =>
                     Fail (Malformed_Escape);
                     return;
               end case;
            elsif not Long
              and then Cursors.Is_Line_Break (Scalar)
            then
               --  A short string may not span lines.
               Fail (Unexpected_Character);
               return;
            else
               Append_Scalar (Buffer, Scalar);
               Step (Scalar, Length);
            end if;
         end loop;
      end Scan_String;

      --  Local names admit dots internally but may not end with one, so the
      --  scan records the last position that was a legal ending and backs
      --  up to it. Without that, "ex:a.b ." would swallow the terminator.
      procedure Scan_Local_Name (Blank_Label : Boolean := False);

      procedure Scan_Local_Name (Blank_Label : Boolean := False) is
         Good_Position : Cursors.Cursor_State := Walk_Position;
         Good_Index    : Positive := Walk_Index;
         Good_Length   : Natural := Unbounded.Length (Buffer);
         First         : Boolean := True;
      begin
         loop
            Peek_Token_End (Walk_Index, Scalar, Length, Look);

            if Look = Partial then
               Incomplete;
               return;
            elsif Look = Bad then
               Fail (Invalid_Encoding);
               return;
            elsif Look = Exhausted then
               --  Mid-stream, more input might extend the name.
               Incomplete;
               return;
            end if;

            if Scalar = 16#25# then           --  percent escape
               declare
                  Saved_Position : constant Cursors.Cursor_State :=
                    Walk_Position;
                  Saved_Index    : constant Positive := Walk_Index;
                  High, Low      : Scalar_Value;
                  Ignored_Length : Natural;
                  Inner          : Peek_Status;
               begin
                  Step (Scalar, Length);
                  Peek (Text, Walk_Index, High, Ignored_Length, Inner);
                  if Inner /= Available then
                     Walk_Position := Saved_Position;
                     Walk_Index := Saved_Index;
                     if Inner = Bad then
                        Fail (Invalid_Encoding);
                     else
                        Incomplete;
                     end if;
                     return;
                  end if;
                  Step (High, Ignored_Length);
                  Peek (Text, Walk_Index, Low, Ignored_Length, Inner);
                  if Inner /= Available then
                     Walk_Position := Saved_Position;
                     Walk_Index := Saved_Index;
                     if Inner = Bad then
                        Fail (Invalid_Encoding);
                     else
                        Incomplete;
                     end if;
                     return;
                  end if;
                  if not Is_Hex (High) or else not Is_Hex (Low) then
                     Fail (Malformed_Escape);
                     return;
                  end if;
                  Step (Low, Ignored_Length);
                  Append_Scalar (Buffer, 16#25#);
                  Append_Scalar (Buffer, High);
                  Append_Scalar (Buffer, Low);
               end;
            elsif Scalar = 16#5C# then        --  reserved-character escape
               declare
                  Escaped        : Scalar_Value;
                  Escaped_Length : Natural;
                  Inner          : Peek_Status;
               begin
                  Step (Scalar, Length);
                  Peek (Text, Walk_Index, Escaped, Escaped_Length, Inner);
                  if Inner /= Available then
                     if Inner = Bad then
                        Fail (Invalid_Encoding);
                     else
                        Incomplete;
                     end if;
                     return;
                  elsif not Is_PN_Local_Escapable (Escaped) then
                     Fail (Malformed_Escape);
                     return;
                  end if;
                  Append_Scalar (Buffer, Escaped);
                  Step (Escaped, Escaped_Length);
               end;
            elsif (if First
                   then --  A name may not open with a hyphen or a
                        --  combining mark, and a blank node label may not
                        --  open with a colon either.
                        (Is_PN_Chars_U (Scalar)
                         or else Is_Digit (Scalar)
                         or else (Scalar = 16#3A# and then not Blank_Label))
                   else Is_PN_Chars (Scalar)
                        or else (Scalar = 16#3A#
                                 and then not Blank_Label))
            then
               Append_Scalar (Buffer, Scalar);
               Step (Scalar, Length);
            elsif Scalar = 16#2E# then        --  '.' only if not final
               Append_Scalar (Buffer, Scalar);
               Step (Scalar, Length);
               First := False;
               goto Continue;
            else
               exit;
            end if;

            --  Reaching here means the character just consumed may legally
            --  end the name.
            Good_Position := Walk_Position;
            Good_Index := Walk_Index;
            Good_Length := Unbounded.Length (Buffer);
            First := False;

            <<Continue>>
         end loop;

         Walk_Position := Good_Position;
         Walk_Index := Good_Index;
         Unbounded.Head (Buffer, Good_Length);
         Emit (Prefixed_Name_Token);
      end Scan_Local_Name;

      procedure Scan_Number (Signed : Boolean);

      procedure Scan_Number (Signed : Boolean) is
         Seen_Digits   : Boolean := Signed;
         Is_Decimal    : Boolean := False;
         Is_Double     : Boolean := False;
         Digits_Before : Natural := 0;
      begin
         --  Integer part.
         loop
            Peek_Token_End (Walk_Index, Scalar, Length, Look);
            if Look = Partial then
               Incomplete;
               return;
            elsif Look = Bad then
               Fail (Invalid_Encoding);
               return;
            elsif Look = Exhausted then
               Incomplete;
               return;
            end if;
            exit when not Is_Digit (Scalar);
            Append_Scalar (Buffer, Scalar);
            Step (Scalar, Length);
            Digits_Before := Digits_Before + 1;
            Seen_Digits := True;
         end loop;

         --  A dot continues the number only when a digit follows it.
         if Scalar = 16#2E# then
            declare
               Saved_Position : constant Cursors.Cursor_State :=
                 Walk_Position;
               Saved_Index    : constant Positive := Walk_Index;
               Next           : Scalar_Value;
               Next_Length    : Natural;
               Inner          : Peek_Status;
            begin
               Step (Scalar, Length);
               Peek_Token_End (Walk_Index, Next, Next_Length, Inner);
               if Inner = Partial or else Inner = Exhausted then
                  Walk_Position := Saved_Position;
                  Walk_Index := Saved_Index;
                  Incomplete;
                  return;
               elsif Inner = Bad then
                  Fail (Invalid_Encoding);
                  return;
               end if;

               if Next in 16#65# | 16#45# then
                  --  A dot with an exponent behind it and no digits
                  --  between: still one number.
                  Is_Decimal := True;
                  Append_Scalar (Buffer, 16#2E#);
                  Scalar := Next;
               elsif Is_Digit (Next) then
                  Is_Decimal := True;
                  Append_Scalar (Buffer, 16#2E#);
                  while Inner = Available and then Is_Digit (Next) loop
                     Append_Scalar (Buffer, Next);
                     Step (Next, Next_Length);
                     Peek_Token_End (Walk_Index, Next, Next_Length, Inner);
                  end loop;
                  if Inner = Partial or else Inner = Exhausted then
                     Incomplete;
                     return;
                  elsif Inner = Bad then
                     Fail (Invalid_Encoding);
                     return;
                  end if;
                  Scalar := Next;
               else
                  --  The dot belongs to the grammar, not the number.
                  Walk_Position := Saved_Position;
                  Walk_Index := Saved_Index;
                  Scalar := 16#2E#;
               end if;
            end;
         end if;

         --  Exponent.
         if Scalar in 16#65# | 16#45# then    --  'e' or 'E'
            declare
               Saved_Position : constant Cursors.Cursor_State :=
                 Walk_Position;
               Saved_Index    : constant Positive := Walk_Index;
               Next           : Scalar_Value;
               Next_Length    : Natural;
               Inner          : Peek_Status;
               Exponent_Digits : Natural := 0;
            begin
               Append_Scalar (Buffer, Scalar);
               Step (Scalar, Length);

               Peek_Token_End (Walk_Index, Next, Next_Length, Inner);
               if Inner = Partial or else Inner = Exhausted then
                  Walk_Position := Saved_Position;
                  Walk_Index := Saved_Index;
                  Incomplete;
                  return;
               elsif Inner = Bad then
                  Fail (Invalid_Encoding);
                  return;
               end if;

               if Next in 16#2B# | 16#2D# then
                  Append_Scalar (Buffer, Next);
                  Step (Next, Next_Length);
                  Peek_Token_End (Walk_Index, Next, Next_Length, Inner);
                  if Inner = Partial or else Inner = Exhausted then
                     Walk_Position := Saved_Position;
                     Walk_Index := Saved_Index;
                     Incomplete;
                     return;
                  elsif Inner = Bad then
                     Fail (Invalid_Encoding);
                     return;
                  end if;
               end if;

               while Inner = Available and then Is_Digit (Next) loop
                  Append_Scalar (Buffer, Next);
                  Step (Next, Next_Length);
                  Exponent_Digits := Exponent_Digits + 1;
                  Peek_Token_End (Walk_Index, Next, Next_Length, Inner);
               end loop;

               if Exponent_Digits = 0 then
                  Fail (Malformed_Number);
                  return;
               elsif Inner = Partial or else Inner = Exhausted then
                  Incomplete;
                  return;
               elsif Inner = Bad then
                  Fail (Invalid_Encoding);
                  return;
               end if;
               Is_Double := True;
            end;
         end if;

         if not Seen_Digits and then Digits_Before = 0
           and then not Is_Decimal
         then
            Fail (Malformed_Number);
            return;
         end if;

         if Is_Double then
            Emit (Double_Token);
         elsif Is_Decimal then
            Emit (Decimal_Token);
         else
            Emit (Integer_Token);
         end if;
      end Scan_Number;

      procedure Scan_At_Sign;

      procedure Scan_At_Sign is
         Subtag_Length : Natural := 0;
      begin
         --  '@' already consumed. Letters follow, then hyphen-separated
         --  subtags, then optionally a '--' direction marker.
         loop
            Peek_Token_End (Walk_Index, Scalar, Length, Look);
            if Look = Partial then
               Incomplete;
               return;
            elsif Look = Bad then
               Fail (Invalid_Encoding);
               return;
            elsif Look = Exhausted then
               Incomplete;
               return;
            end if;
            exit when not Is_ASCII_Letter (Scalar);
            Append_Scalar (Buffer, Scalar);
            Step (Scalar, Length);
            Subtag_Length := Subtag_Length + 1;
         end loop;

         if Subtag_Length = 0 then
            Fail (Malformed_Language_Tag);
            return;
         end if;

         --  '@prefix' and '@base' are directives rather than language tags.
         --  The text is retained so that a parser expecting a language tag
         --  after a literal can still read them as one, which the grammar
         --  permits.
         declare
            Word : constant String := Unbounded.To_String (Buffer);
         begin
            if Word = "prefix" then
               Emit (Prefix_Directive_Token);
               return;
            elsif Word = "base" then
               Emit (Base_Directive_Token);
               return;
            elsif Word = "version" then
               --  Turtle 1.2 has both "@version" and the keyword form.
               --  Marking which was written lets the grammar require the
               --  terminator that only the at-form carries.
               Buffer := Unbounded.To_Unbounded_String ("@version");
               Emit (Version_Directive_Token);
               return;
            elsif Dialect = N3_Dialect and then Word = "forAll" then
               Emit (For_All_Token);
               return;
            elsif Dialect = N3_Dialect and then Word = "forSome" then
               Emit (For_Some_Token);
               return;
            end if;
         end;

         loop
            Peek_Token_End (Walk_Index, Scalar, Length, Look);
            if Look = Partial then
               Incomplete;
               return;
            elsif Look = Bad then
               Fail (Invalid_Encoding);
               return;
            elsif Look = Exhausted then
               Incomplete;
               return;
            end if;
            exit when Scalar /= 16#2D#;       --  '-'

            declare
               Saved_Position : constant Cursors.Cursor_State :=
                 Walk_Position;
               Saved_Index    : constant Positive := Walk_Index;
               Next           : Scalar_Value;
               Next_Length    : Natural;
               Inner          : Peek_Status;
               Run            : Natural := 0;
            begin
               Step (Scalar, Length);
               Peek_Token_End (Walk_Index, Next, Next_Length, Inner);
               if Inner = Partial or else Inner = Exhausted then
                  Walk_Position := Saved_Position;
                  Walk_Index := Saved_Index;
                  Incomplete;
                  return;
               elsif Inner = Bad then
                  Fail (Invalid_Encoding);
                  return;
               end if;

               if Next = 16#2D# then
                  --  A second hyphen: this is the direction marker.
                  Step (Next, Next_Length);
                  declare
                     Marker : Unbounded.Unbounded_String;
                  begin
                     loop
                        Peek_Token_End (Walk_Index, Next, Next_Length, Inner);
                        if Inner = Partial or else Inner = Exhausted then
                           Incomplete;
                           return;
                        elsif Inner = Bad then
                           Fail (Invalid_Encoding);
                           return;
                        end if;
                        exit when not Is_ASCII_Letter (Next);
                        Append_Scalar (Marker, Next);
                        Step (Next, Next_Length);
                     end loop;

                     if Unbounded.To_String (Marker) = "ltr" then
                        Result.Has_Direction_Data := True;
                        Result.Direction_Data := Left_To_Right;
                     elsif Unbounded.To_String (Marker) = "rtl" then
                        Result.Has_Direction_Data := True;
                        Result.Direction_Data := Right_To_Left;
                     else
                        Fail (Malformed_Language_Tag);
                        return;
                     end if;
                  end;
                  Emit (Language_Token);
                  return;
               end if;

               --  An ordinary subtag.
               Append_Scalar (Buffer, 16#2D#);
               while Inner = Available
                 and then (Is_ASCII_Letter (Next) or else Is_Digit (Next))
               loop
                  Append_Scalar (Buffer, Next);
                  Step (Next, Next_Length);
                  Run := Run + 1;
                  Peek_Token_End (Walk_Index, Next, Next_Length, Inner);
               end loop;

               if Inner = Partial or else Inner = Exhausted then
                  Incomplete;
                  return;
               elsif Inner = Bad then
                  Fail (Invalid_Encoding);
                  return;
               elsif Run = 0 then
                  Fail (Malformed_Language_Tag);
                  return;
               end if;
            end;
         end loop;

         Emit (Language_Token);
      end Scan_At_Sign;

      procedure Scan_Name_Run;

      procedure Scan_Name_Run is
         Good_Position : Cursors.Cursor_State;
         Good_Index    : Positive;
         Good_Length   : Natural;
      begin
         --  A run of name characters, then a decision: a colon makes it a
         --  prefix, and anything else makes it a keyword. Scanning the run
         --  to its end before deciding is what keeps a prefix named
         --  "prefix" from being read as the PREFIX keyword.
         loop
            Peek_Token_End (Walk_Index, Scalar, Length, Look);
            if Look = Partial then
               Incomplete;
               return;
            elsif Look = Bad then
               Fail (Invalid_Encoding);
               return;
            elsif Look = Exhausted then
               Incomplete;
               return;
            end if;
            exit when not Is_PN_Chars (Scalar) and then Scalar /= 16#2E#;

            --  A dot is part of a prefix only when the name continues.
            if Scalar = 16#2E# then
               Good_Position := Walk_Position;
               Good_Index := Walk_Index;
               Good_Length := Unbounded.Length (Buffer);
               Append_Scalar (Buffer, Scalar);
               Step (Scalar, Length);

               Peek_Token_End (Walk_Index, Scalar, Length, Look);
               if Look = Partial or else Look = Exhausted then
                  Incomplete;
                  return;
               elsif Look = Bad then
                  Fail (Invalid_Encoding);
                  return;
               end if;
               if not Is_PN_Chars (Scalar) and then Scalar /= 16#2E# then
                  Walk_Position := Good_Position;
                  Walk_Index := Good_Index;
                  Unbounded.Head (Buffer, Good_Length);
                  exit;
               end if;
            else
               Append_Scalar (Buffer, Scalar);
               Step (Scalar, Length);
            end if;
         end loop;

         Peek_Token_End (Walk_Index, Scalar, Length, Look);
         if Look = Partial then
            Incomplete;
            return;
         elsif Look = Bad then
            Fail (Invalid_Encoding);
            return;
         elsif Look = Exhausted then
            Incomplete;
            return;
         end if;

         if Scalar = 16#3A# then              --  ':' -- a prefixed name
            Prefix_Buffer := Buffer;
            Buffer := Unbounded.Null_Unbounded_String;
            Step (Scalar, Length);
            Scan_Local_Name;
            return;
         end if;

         declare
            Word  : constant String := Unbounded.To_String (Buffer);
            Upper : constant String :=
              Ada.Characters.Handling.To_Upper (Word);
         begin
            --  Keywords the grammar writes in double quotes are
            --  case-insensitive; those in single quotes are not.
            if Word = "a" then
               Emit (A_Token);
            elsif Word = "true" or else Word = "false" then
               Emit (Boolean_Token);
            elsif Upper = "PREFIX" then
               Emit (Sparql_Prefix_Token);
            elsif Upper = "BASE" then
               Emit (Sparql_Base_Token);
            elsif Upper = "GRAPH" then
               Emit (Graph_Token);
            elsif Upper = "VERSION" then
               Emit (Version_Directive_Token);
            elsif Dialect = SPARQL_Dialect then
               --  SPARQL has around a hundred keywords and they are not
               --  reserved. Classifying them here would put the language's
               --  vocabulary in the scanner and make every addition a
               --  scanner change, so the word is handed over as written.
               Emit (Keyword_Token);
            else
               Fail (Unexpected_Character);
            end if;
         end;
      end Scan_Name_Run;

   begin
      Result := Null_Token;
      Status := End_Of_Input;
      Error := No_Error;

      --  Whitespace and comments, skipped before the token starts so that a
      --  caller retaining unconsumed input does not retain them.
      loop
         Peek (Text, Walk_Index, Scalar, Length, Look);
         exit when Look /= Available;

         if Is_Whitespace (Scalar) then
            Step (Scalar, Length);
         elsif Scalar = 16#23# then           --  '#'
            declare
               Comment_Position : constant Cursors.Cursor_State :=
                 Walk_Position;
               Comment_Index    : constant Positive := Walk_Index;
            begin
               loop
                  Step (Scalar, Length);
                  Peek (Text, Walk_Index, Scalar, Length, Look);
                  exit when Look /= Available
                    or else Cursors.Is_Line_Break (Scalar);
               end loop;

               if Look = Bad then
                  Position := Walk_Position;
                  Index := Walk_Index;
                  Fail (Invalid_Encoding);
                  return;
               elsif Look /= Available then
                  if Last_Chunk then
                     --  The comment ends with the document.
                     Position := Walk_Position;
                     Index := Walk_Index;
                     Status := End_Of_Input;
                  else
                     --  The rest of the comment is in the next chunk. Give
                     --  back the part already consumed: keeping it would
                     --  leave the remainder to be scanned as code, which
                     --  turns a comment split across a chunk boundary into
                     --  a syntax error or, worse, into statements.
                     Position := Comment_Position;
                     Index := Comment_Index;
                     Status := Needs_More_Input;
                  end if;
                  return;
               end if;
            end;
         else
            exit;
         end if;
      end loop;

      --  Commit the whitespace skip regardless of what follows.
      Position := Walk_Position;
      Index := Walk_Index;

      case Look is
         when Exhausted =>
            Status := End_Of_Input;
            return;
         when Partial =>
            Status := Needs_More_Input;
            return;
         when Bad =>
            Fail (Invalid_Encoding);
            return;
         when Available =>
            null;
      end case;

      Start_Position_Value := Walk_Position;
      Start_Index := Walk_Index;
      pragma Unreferenced (Start_Index);

      case Scalar is
         when 16#3C# =>                       --  '<'
            if Dialect = SPARQL_Dialect then
               --  An IRI reference, the comparison operators, and the
               --  RDF 1.2 quoting brackets all share a first character,
               --  and only the whole token tells them apart, so this one
               --  place backtracks.
               declare
                  Saved_Position : constant Cursors.Cursor_State :=
                    Walk_Position;
                  Saved_Index    : constant Positive := Walk_Index;
                  Next           : Scalar_Value;
                  Next_Length    : Natural;
                  Inner          : Peek_Status;
               begin
                  Step (Scalar, Length);
                  Peek_Token_End (Walk_Index, Next, Next_Length, Inner);
                  if Inner = Partial or else Inner = Exhausted then
                     Incomplete;
                     return;
                  elsif Inner = Bad then
                     Fail (Invalid_Encoding);
                     return;
                  elsif Next = 16#3D# then
                     Step (Next, Next_Length);
                     Emit (Less_Or_Equal_Token);
                     return;
                  elsif Next = 16#3C# then
                     --  '<<' or '<<(': quoted triple or triple term.
                     Step (Next, Next_Length);
                     Peek_Token_End (Walk_Index, Next, Next_Length, Inner);
                     if Inner = Partial or else Inner = Exhausted then
                        Incomplete;
                        return;
                     elsif Inner = Bad then
                        Fail (Invalid_Encoding);
                        return;
                     elsif Next = 16#28# then
                        Step (Next, Next_Length);
                        Emit (Open_Triple_Term_Token);
                     else
                        Emit (Open_Quoted_Token);
                     end if;
                     return;
                  end if;

                  --  Try the IRI. If it does not scan, the '<' was an
                  --  operator after all.
                  Scan_IRI_Reference;
                  if Status = Token_Found
                    or else Status = Needs_More_Input
                  then
                     return;
                  end if;
                  Walk_Position := Saved_Position;
                  Walk_Index := Saved_Index;
                  Step (16#3C#, 1);
                  Emit (Less_Token);
                  return;
               end;
            end if;
            Step (Scalar, Length);
            Peek (Text, Walk_Index, Scalar, Length, Look);
            if Look = Partial or else Look = Exhausted then
               Want_More;
               return;
            elsif Look = Bad then
               Fail (Invalid_Encoding);
               return;
            end if;
            if Scalar = 16#3D# and then Dialect = N3_Dialect then
               --  '<=' cannot begin an IRI, because a scheme must start
               --  with a letter, so this needs no backtracking.
               Step (Scalar, Length);
               Emit (Implied_By_Token);
            elsif Scalar = 16#3C# then           --  '<<'
               Step (Scalar, Length);
               Peek_Token_End (Walk_Index, Scalar, Length, Look);
               if Look = Partial or else Look = Exhausted then
                  Incomplete;
                  return;
               elsif Look = Bad then
                  Fail (Invalid_Encoding);
                  return;
               end if;
               if Scalar = 16#28# then        --  '<<('
                  Step (Scalar, Length);
                  Emit (Open_Triple_Term_Token);
               else
                  Emit (Open_Quoted_Token);
               end if;
            else
               Scan_IRI_Reference;
            end if;

         when 16#22# | 16#27# =>              --  '"' or '''
            declare
               Quote : constant Scalar_Value := Scalar;
            begin
               Step (Scalar, Length);
               Scan_String (Quote);
            end;

         when 16#5F# =>                       --  '_'
            Step (Scalar, Length);
            Peek (Text, Walk_Index, Scalar, Length, Look);
            if Look = Partial or else Look = Exhausted then
               Want_More;
               return;
            elsif Look = Bad then
               Fail (Invalid_Encoding);
               return;
            elsif Scalar /= 16#3A# then
               Fail (Unexpected_Character);
               return;
            end if;
            Step (Scalar, Length);
            Scan_Local_Name (Blank_Label => True);
            if Status = Token_Found then
               Result.Kind_Value := Blank_Label_Token;
               Result.Prefix_Value := Unbounded.Null_Unbounded_String;
            end if;

         when 16#3A# =>                       --  ':' -- empty prefix
            Step (Scalar, Length);
            Scan_Local_Name;

         when 16#40# =>                       --  '@'
            Step (Scalar, Length);
            Scan_At_Sign;

         when 16#5E# =>                       --  '^' or '^^'
            Step (Scalar, Length);
            --  A lone caret is a whole token in N3, so the end of the
            --  buffer may legitimately follow it.
            Peek_Token_End (Walk_Index, Scalar, Length, Look);
            if Look = Partial or else Look = Exhausted then
               Incomplete;
               return;
            elsif Look = Bad then
               Fail (Invalid_Encoding);
               return;
            elsif Scalar /= 16#5E# then
               if Dialect /= RDF_Dialect then
                  Emit (Backward_Path_Token);
                  return;
               end if;
               Fail (Unexpected_Character);
               return;
            end if;
            Step (Scalar, Length);
            Emit (Datatype_Token);

         when 16#2B# | 16#2D# =>              --  '+' or '-'
            if Dialect = SPARQL_Dialect then
               declare
                  Sign           : constant Scalar_Value := Scalar;
                  Saved_Position : constant Cursors.Cursor_State :=
                    Walk_Position;
                  Saved_Index    : constant Positive := Walk_Index;
                  Next           : Scalar_Value;
                  Next_Length    : Natural;
                  Inner          : Peek_Status;
               begin
                  Step (Scalar, Length);
                  Peek_Token_End (Walk_Index, Next, Next_Length, Inner);
                  if Inner = Partial or else Inner = Exhausted then
                     Incomplete;
                     return;
                  elsif Inner = Bad then
                     Fail (Invalid_Encoding);
                     return;
                  elsif not Is_Digit (Next) and then Next /= 16#2E# then
                     Emit (if Sign = 16#2B# then Plus_Token
                           else Minus_Token);
                     return;
                  end if;
                  Walk_Position := Saved_Position;
                  Walk_Index := Saved_Index;
                  Scalar := Sign;
                  Length := 1;
               end;
            end if;
            Append_Scalar (Buffer, Scalar);
            Step (Scalar, Length);
            Scan_Number (Signed => False);

         when 16#30# .. 16#39# =>
            Scan_Number (Signed => False);

         when 16#2E# =>                       --  '.' -- dot or decimal
            declare
               Saved_Position : constant Cursors.Cursor_State :=
                 Walk_Position;
               Saved_Index    : constant Positive := Walk_Index;
               Next           : Scalar_Value;
               Next_Length    : Natural;
               Inner          : Peek_Status;
            begin
               Step (Scalar, Length);
               Peek_Token_End (Walk_Index, Next, Next_Length, Inner);
               if Inner = Partial then
                  Status := Needs_More_Input;
                  return;
               elsif Inner = Bad then
                  Fail (Invalid_Encoding);
                  return;
               elsif Inner = Available and then Is_Digit (Next) then
                  Walk_Position := Saved_Position;
                  Walk_Index := Saved_Index;
                  Scan_Number (Signed => False);
               else
                  Emit (Dot_Token);
               end if;
            end;

         when 16#3B# => Step (Scalar, Length); Emit (Semicolon_Token);
         when 16#2C# => Step (Scalar, Length); Emit (Comma_Token);
         when 16#28# => Step (Scalar, Length); Emit (Open_Paren_Token);
         when 16#5B# => Step (Scalar, Length); Emit (Open_Bracket_Token);
         when 16#5D# => Step (Scalar, Length); Emit (Close_Bracket_Token);
         when 16#7E# => Step (Scalar, Length); Emit (Reifier_Token);

         when 16#29# =>                       --  ')' or ')>>'
            Step (Scalar, Length);
            declare
               Saved_Position : constant Cursors.Cursor_State :=
                 Walk_Position;
               Saved_Index    : constant Positive := Walk_Index;
               Next           : Scalar_Value;
               Next_Length    : Natural;
               Inner          : Peek_Status;
            begin
               Peek_Token_End (Walk_Index, Next, Next_Length, Inner);
               if Inner = Partial or else Inner = Exhausted then
                  Incomplete;
                  return;
               elsif Inner = Available and then Next = 16#3E# then
                  Step (Next, Next_Length);
                  Peek_Token_End (Walk_Index, Next, Next_Length, Inner);
                  if Inner = Partial or else Inner = Exhausted then
                     Incomplete;
                     return;
                  elsif Inner = Available and then Next = 16#3E# then
                     Step (Next, Next_Length);
                     Emit (Close_Triple_Term_Token);
                     return;
                  end if;
                  Walk_Position := Saved_Position;
                  Walk_Index := Saved_Index;
               end if;
               Emit (Close_Paren_Token);
            end;

         when 16#3E# =>                       --  '>>', '>' or '>='
            if Dialect = SPARQL_Dialect then
               Step (Scalar, Length);
               Peek_Token_End (Walk_Index, Scalar, Length, Look);
               if Look = Partial or else Look = Exhausted then
                  Incomplete;
                  return;
               elsif Look = Bad then
                  Fail (Invalid_Encoding);
                  return;
               elsif Scalar = 16#3D# then
                  Step (Scalar, Length);
                  Emit (Greater_Or_Equal_Token);
               elsif Scalar = 16#3E# then
                  Step (Scalar, Length);
                  Emit (Close_Quoted_Token);
               else
                  Emit (Greater_Token);
               end if;
               return;
            end if;
            Step (Scalar, Length);
            Peek (Text, Walk_Index, Scalar, Length, Look);
            if Look = Partial or else Look = Exhausted then
               Want_More;
               return;
            elsif Look = Bad then
               Fail (Invalid_Encoding);
               return;
            elsif Scalar /= 16#3E# then
               Fail (Unexpected_Character);
               return;
            end if;
            Step (Scalar, Length);
            Emit (Close_Quoted_Token);

         when 16#7B# =>                       --  '{' or '{|'
            Step (Scalar, Length);
            declare
               Next        : Scalar_Value;
               Next_Length : Natural;
               Inner       : Peek_Status;
            begin
               Peek_Token_End (Walk_Index, Next, Next_Length, Inner);
               if Inner = Partial or else Inner = Exhausted then
                  Incomplete;
                  return;
               elsif Inner = Available and then Next = 16#7C# then
                  Step (Next, Next_Length);
                  Emit (Open_Annotation_Token);
               else
                  Emit (Open_Brace_Token);
               end if;
            end;

         when 16#7D# => Step (Scalar, Length); Emit (Close_Brace_Token);

         when 16#3F# | 16#24# =>              --  '?' or '$' -- a variable
            if Dialect = RDF_Dialect
              or else (Scalar = 16#24# and then Dialect /= SPARQL_Dialect)
            then
               Fail (Unexpected_Character);
               return;
            end if;
            Step (Scalar, Length);
            declare
               Length_Seen : Natural := 0;
            begin
               loop
                  Peek_Token_End (Walk_Index, Scalar, Length, Look);
                  if Look = Partial or else Look = Exhausted then
                     Incomplete;
                     return;
                  elsif Look = Bad then
                     Fail (Invalid_Encoding);
                     return;
                  end if;
                  exit when not Is_PN_Chars (Scalar);
                  Append_Scalar (Buffer, Scalar);
                  Step (Scalar, Length);
                  Length_Seen := Length_Seen + 1;
               end loop;
               if Length_Seen = 0 then
                  Fail (Unexpected_Character);
                  return;
               end if;
            end;
            Emit (Variable_Token);

         when 16#3D# =>                       --  '=' or '=>'
            if Dialect = RDF_Dialect then
               Fail (Unexpected_Character);
               return;
            elsif Dialect = SPARQL_Dialect then
               Step (Scalar, Length);
               Emit (Equals_Token);
               return;
            end if;
            Step (Scalar, Length);
            Peek_Token_End (Walk_Index, Scalar, Length, Look);
            if Look = Partial or else Look = Exhausted then
               Incomplete;
               return;
            elsif Look = Bad then
               Fail (Invalid_Encoding);
               return;
            elsif Scalar = 16#3E# then
               Step (Scalar, Length);
               Emit (Implies_Token);
            else
               Emit (Equals_Token);
            end if;

         when 16#21# =>                       --  '!' or '!='
            if Dialect = RDF_Dialect then
               Fail (Unexpected_Character);
               return;
            end if;
            Step (Scalar, Length);
            if Dialect = SPARQL_Dialect then
               Peek_Token_End (Walk_Index, Scalar, Length, Look);
               if Look = Partial or else Look = Exhausted then
                  Incomplete;
                  return;
               elsif Look = Bad then
                  Fail (Invalid_Encoding);
                  return;
               elsif Scalar = 16#3D# then
                  Step (Scalar, Length);
                  Emit (Not_Equal_Token);
                  return;
               end if;
            end if;
            Emit (Forward_Path_Token);

         when 16#7C# =>                       --  '|}' or '||'
            if Dialect = SPARQL_Dialect then
               Step (Scalar, Length);
               Peek_Token_End (Walk_Index, Scalar, Length, Look);
               if Look = Partial or else Look = Exhausted then
                  Incomplete;
                  return;
               elsif Look = Bad then
                  Fail (Invalid_Encoding);
                  return;
               elsif Scalar = 16#7C# then
                  Step (Scalar, Length);
                  Emit (Or_Token);
               elsif Scalar = 16#7D# then
                  Step (Scalar, Length);
                  Emit (Close_Annotation_Token);
               else
                  --  A single bar is the alternative operator in property
                  --  paths, which reuses the forward-path token.
                  Emit (Forward_Path_Token);
               end if;
               return;
            end if;
            Step (Scalar, Length);
            Peek (Text, Walk_Index, Scalar, Length, Look);
            if Look = Partial or else Look = Exhausted then
               Want_More;
               return;
            elsif Look = Bad then
               Fail (Invalid_Encoding);
               return;
            elsif Scalar /= 16#7D# then
               Fail (Unexpected_Character);
               return;
            end if;
            Step (Scalar, Length);
            Emit (Close_Annotation_Token);

         when 16#26# =>                       --  '&&'
            if Dialect /= SPARQL_Dialect then
               Fail (Unexpected_Character);
               return;
            end if;
            Step (Scalar, Length);
            Peek_Token_End (Walk_Index, Scalar, Length, Look);
            if Look = Partial or else Look = Exhausted then
               Incomplete;
               return;
            elsif Look = Bad then
               Fail (Invalid_Encoding);
               return;
            elsif Scalar /= 16#26# then
               Fail (Unexpected_Character);
               return;
            end if;
            Step (Scalar, Length);
            Emit (And_Token);

         when 16#2A# =>                       --  '*'
            if Dialect /= SPARQL_Dialect then
               Fail (Unexpected_Character);
               return;
            end if;
            Step (Scalar, Length);
            Emit (Star_Token);

         when 16#2F# =>                       --  '/'
            if Dialect /= SPARQL_Dialect then
               Fail (Unexpected_Character);
               return;
            end if;
            Step (Scalar, Length);
            Emit (Slash_Token);

         when others =>
            if Is_PN_Chars_Base (Scalar) then
               Scan_Name_Run;
            else
               Fail (Unexpected_Character);
            end if;
      end case;
   end Scan;

end Flyology_RDF.Lexers;
