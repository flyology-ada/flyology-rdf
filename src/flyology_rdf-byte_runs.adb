with Interfaces;

with Flyology_SIMD.Backends.Native;

package body Flyology_RDF.Byte_Runs is

   package SIMD renames Flyology_SIMD;
   package Native renames Flyology_SIMD.Backends.Native;

   subtype U16 is Interfaces.Unsigned_16;

   use type U16;

   Block : constant := 16;

   --  Classification by nibble pair. A byte is special -- it ends the run
   --  and is handed back to the scalar loop -- exactly when the entry the
   --  low nibble selects and the entry the high nibble selects share a
   --  set bit. For an ASCII byte the high entry is the single bit named
   --  by its high nibble, so the low entry lists, bit by bit, which high
   --  nibbles make that low nibble special.
   --
   --  Bytes at 16#80# and above must always be special, because only the
   --  scalar loop validates a multi-byte sequence. Where every low entry
   --  already has some bit set, the high entries at 8 .. 15 are 16#FF#
   --  and any such byte matches. Where a class leaves low entries empty
   --  -- the string classes forbid almost nothing -- bit 7 marks the
   --  high half instead: every low entry carries it, the high entries at
   --  8 .. 15 carry only it, and the entry for high nibble 7, which no
   --  string class forbids anything in, stays clear so that 16#70# ..
   --  16#7F# remain content.

   Low_Nibble_Mask : constant SIMD.U8x16 := Native.Splat (16#0F#);
   Zero_Vector     : constant SIMD.U8x16 := Native.Zero;

   ASCII_High : constant SIMD.U8x16 := Native.From_Lanes
     ([16#01#, 16#02#, 16#04#, 16#08#, 16#10#, 16#20#, 16#40#, 16#80#,
       16#FF#, 16#FF#, 16#FF#, 16#FF#, 16#FF#, 16#FF#, 16#FF#, 16#FF#]);

   --  IRIREF: special at and below space, at '"', '<', '>', '\', '^',
   --  '`', '{', '|', '}', and above ASCII.
   IRI_Low : constant SIMD.U8x16 := Native.From_Lanes
     ([16#47#, 16#03#, 16#07#, 16#03#, 16#03#, 16#03#, 16#03#, 16#03#,
       16#03#, 16#03#, 16#03#, 16#83#, 16#AB#, 16#83#, 16#2B#, 16#03#]);

   --  A string body's special set is four bytes and the high half, which
   --  fits in direct comparisons against these; each comparison compiles
   --  to one vector instruction sequence with no call, where the nibble
   --  tables cost three out-of-line operations per block.
   Double_Quote : constant SIMD.U8x16 := Native.Splat (16#22#);
   Single_Quote : constant SIMD.U8x16 := Native.Splat (16#27#);
   Backslash    : constant SIMD.U8x16 := Native.Splat (16#5C#);
   Line_Feed    : constant SIMD.U8x16 := Native.Splat (16#0A#);
   Carriage     : constant SIMD.U8x16 := Native.Splat (16#0D#);
   High_Bit     : constant SIMD.U8x16 := Native.Splat (16#80#);

   --  First set bit of one byte, for locating the first special lane.
   First_Set : array (U16 range 0 .. 255) of Natural range 0 .. 8 :=
     [others => 0];

   function First_Special (Special_Bits : U16) return Natural
   with Pre => Special_Bits /= 0;

   function First_Special (Special_Bits : U16) return Natural
   is (if (Special_Bits and 16#FF#) /= 0
       then First_Set (Special_Bits and 16#FF#)
       else 8 + First_Set (Interfaces.Shift_Right (Special_Bits, 8)));

   function Classified_Run
     (Text : String;
      From : Positive;
      Low  : SIMD.U8x16;
      High : SIMD.U8x16) return Natural;
   pragma Inline (Classified_Run);

   function Classified_Run
     (Text : String;
      From : Positive;
      Low  : SIMD.U8x16;
      High : SIMD.U8x16) return Natural
   is
      Length : constant Natural := Text'Length;
      Offset : Natural := From - Text'First;
      Run    : Natural := 0;
   begin
      if Length < Block or else Offset > Length - Block then
         return 0;
      end if;

      declare
         Bytes : constant SIMD.Byte_Array (0 .. Length - 1)
         with Import, Address => Text'Address;
      begin
         loop
            declare
               Loaded : constant SIMD.U8x16 :=
                 Native.Load_Unaligned (Bytes, Offset);
               Class  : constant SIMD.U8x16 :=
                 Native.Bitwise_And
                   (Native.Table_Lookup
                      (Low, Native.Bitwise_And (Loaded, Low_Nibble_Mask)),
                    Native.Table_Lookup
                      (High, Native.Shift_Right_Logical (Loaded, 4)));
               Plain  : constant U16 :=
                 Native.To_Bit_Mask (Native.Equal (Class, Zero_Vector));
            begin
               if Plain /= 16#FFFF# then
                  return Run + First_Special (not Plain);
               end if;
               Run := Run + Block;
               Offset := Offset + Block;
               exit when Offset > Length - Block;
            end;
         end loop;
      end;

      return Run;
   end Classified_Run;

   function IRI_Run (Text : String; From : Positive) return Natural
   is (Classified_Run (Text, From, IRI_Low, ASCII_High));

   function String_Run
     (Text          : String;
      From          : Positive;
      Double_Quoted : Boolean) return Natural
   is
      Quote  : constant SIMD.U8x16 :=
        (if Double_Quoted then Double_Quote else Single_Quote);
      Length : constant Natural := Text'Length;
      Offset : Natural := From - Text'First;
      Run    : Natural := 0;
   begin
      if Length < Block or else Offset > Length - Block then
         return 0;
      end if;

      declare
         Bytes : constant SIMD.Byte_Array (0 .. Length - 1)
         with Import, Address => Text'Address;
      begin
         loop
            declare
               Loaded  : constant SIMD.U8x16 :=
                 Native.Load_Unaligned (Bytes, Offset);
               Special : constant U16 :=
                 Native.To_Bit_Mask (Native.Equal (Loaded, Quote))
                 or Native.To_Bit_Mask (Native.Equal (Loaded, Backslash))
                 or Native.To_Bit_Mask (Native.Equal (Loaded, Line_Feed))
                 or Native.To_Bit_Mask (Native.Equal (Loaded, Carriage))
                 or Native.To_Bit_Mask
                      (Native.Equal
                         (Native.Bitwise_And (Loaded, High_Bit), High_Bit));
            begin
               if Special /= 0 then
                  return Run + First_Special (Special);
               end if;
               Run := Run + Block;
               Offset := Offset + Block;
               exit when Offset > Length - Block;
            end;
         end loop;
      end;

      return Run;
   end String_Run;

begin
   for Value in U16 range 1 .. 255 loop
      declare
         Bit : Natural := 0;
      begin
         while (Interfaces.Shift_Right (Value, Bit) and 1) = 0 loop
            Bit := Bit + 1;
         end loop;
         First_Set (Value) := Bit;
      end;
   end loop;
end Flyology_RDF.Byte_Runs;
