with Ada.Strings.Unbounded;

with Flyology_RDF.IRIs;

package body Flyology_RDF.NQuads_Writers is

   package Unbounded renames Ada.Strings.Unbounded;

   use type Terms.Term_Kind;
   use type Terms.Base_Direction;
   use type Quads.Graph_Name_Kind;

   XSD_String : constant String :=
     "http://www.w3.org/2001/XMLSchema#string";

   Hex_Digits : constant String := "0123456789ABCDEF";

   procedure Append_Escape_16
     (Buffer : in out Unbounded.Unbounded_String;
      Code   : Natural);

   procedure Append_Escape_16
     (Buffer : in out Unbounded.Unbounded_String;
      Code   : Natural) is
   begin
      Unbounded.Append (Buffer, "\u");
      Unbounded.Append (Buffer, Hex_Digits (Code / 4096 + 1));
      Unbounded.Append (Buffer, Hex_Digits ((Code / 256) mod 16 + 1));
      Unbounded.Append (Buffer, Hex_Digits ((Code / 16) mod 16 + 1));
      Unbounded.Append (Buffer, Hex_Digits (Code mod 16 + 1));
   end Append_Escape_16;

   --  Literal content. The canonical form spells a control character with
   --  a short escape wherever one exists, not only the characters that
   --  would otherwise end or reinterpret the literal, so all seven are
   --  listed here; every other control byte becomes a numeric escape,
   --  and all remaining UTF-8 passes through unchanged so that the
   --  output stays valid UTF-8 rather than ASCII.
   --  The same for a literal's lexical form, for the same reason.
   Escapes_In_Literal : constant array (Character) of Boolean :=
     [Character'Val (0) .. Character'Val (16#1F#) => True,
      Character'Val (16#7F#) => True,
      '"' | '\' => True,
      others => False];

   function Escape_Literal (Value : String) return String is
      Buffer : Unbounded.Unbounded_String;
   begin
      --  Most lexical forms contain nothing to escape, and for those the
      --  input is the output: one scan decides, and the character-by-
      --  character rebuild below is paid only when it changes something.
      if (for all Item of Value => not Escapes_In_Literal (Item)) then
         return Value;
      end if;

      for Item of Value loop
         case Item is
            when '"'      => Unbounded.Append (Buffer, "\""");
            when '\'      => Unbounded.Append (Buffer, "\\");
            when ASCII.LF => Unbounded.Append (Buffer, "\n");
            when ASCII.CR => Unbounded.Append (Buffer, "\r");
            when ASCII.HT => Unbounded.Append (Buffer, "\t");
            when ASCII.BS => Unbounded.Append (Buffer, "\b");
            when ASCII.FF => Unbounded.Append (Buffer, "\f");
            when others =>
               declare
                  Code : constant Natural := Character'Pos (Item);
               begin
                  if Code < 16#20# or else Code = 16#7F# then
                     Append_Escape_16 (Buffer, Code);
                  else
                     Unbounded.Append (Buffer, Item);
                  end if;
               end;
         end case;
      end loop;
      return Unbounded.To_String (Buffer);
   end Escape_Literal;

   --  IRI content. The IRIREF production forbids these outright, so they
   --  can only appear as escapes; an admitted IRI should contain none of
   --  them, but writing defensively costs nothing and keeps a malformed
   --  value from producing unparseable output.
   --  Deciding whether an IRI needs escaping is a scan over every byte of
   --  every IRI written, and asking nine separate questions of each byte
   --  costs more than asking one. The answers do not depend on anything
   --  but the byte, so they are worked out once.
   Escapes_In_IRI : constant array (Character) of Boolean :=
     [Character'Val (0) .. Character'Val (16#20#) => True,
      '<' | '>' | '"' | '{' | '}' | '|' | '^' | '`' | '\' => True,
      others => False];

   function Escape_IRI (Value : String) return String is
      Buffer : Unbounded.Unbounded_String;
   begin
      --  An admitted IRI contains nothing this production forbids, so the
      --  defensive rebuild below is almost never taken: one scan decides.
      if (for all Item of Value => not Escapes_In_IRI (Item)) then
         return Value;
      end if;

      for Item of Value loop
         declare
            Code : constant Natural := Character'Pos (Item);
         begin
            if Escapes_In_IRI (Item) then
               Append_Escape_16 (Buffer, Code);
            else
               Unbounded.Append (Buffer, Item);
            end if;
         end;
      end loop;
      return Unbounded.To_String (Buffer);
   end Escape_IRI;

   function Write_IRI (Value : IRIs.IRI) return String
   is ("<" & Escape_IRI (IRIs.To_UTF_8 (Value)) & ">");

   function Write_Term
     (Value : Terms.Term;
      Style : String_Datatype_Style := Explicit_Datatype) return String is
   begin
      case Terms.Kind (Value) is
         when Terms.IRI_Kind =>
            return Write_IRI (Terms.IRI_Value (Value));

         when Terms.Blank_Node_Kind =>
            return "_:" & Terms.Label (Value);

         when Terms.Literal_Kind =>
            declare
               Body_Text : constant String :=
                 """" & Escape_Literal (Terms.Lexical_Form (Value)) & """";
            begin
               if Terms.Has_Language (Value) then
                  --  A direction is written as a suffix of the tag, which
                  --  is where RDF 1.2 puts it.
                  return Body_Text & "@" & Terms.Language (Value)
                    & (if Terms.Has_Direction (Value)
                       then (if Terms.Direction (Value) = Terms.Left_To_Right
                             then "--ltr" else "--rtl")
                       else "");
               end if;

               declare
                  Datatype : constant IRIs.IRI := Terms.Datatype (Value);
               begin
                  if Style = Implicit_Datatype
                    and then IRIs.To_UTF_8 (Datatype) = XSD_String
                  then
                     return Body_Text;
                  end if;
                  return Body_Text & "^^" & Write_IRI (Datatype);
               end;
            end;

         when Terms.Triple_Term_Kind =>
            return "<<(" & Write_Term (Terms.Triple_Subject (Value), Style)
              & " " & Write_IRI (Terms.Triple_Predicate (Value))
              & " " & Write_Term (Terms.Triple_Object (Value), Style)
              & ")>>";
      end case;
   end Write_Term;

   function Write_Graph_Name (Value : Quads.Graph_Name) return String is
   begin
      if Quads.Kind (Value) = Quads.Default_Graph_Kind then
         return "";
      end if;
      return Write_Term (Quads.Name_Term (Value));
   end Write_Graph_Name;

   --  Writing a statement into the caller's buffer, one piece at a time.
   --  Every step below has a function form above that returns a String;
   --  those build the piece, hand it back, and have it copied in. These
   --  write it where it belongs, which for a conversion that streams is
   --  the difference between two copies of every statement and none.

   procedure Put (Buffer : in out String; Last : in out Natural;
                  Item : String);

   procedure Put (Buffer : in out String; Last : in out Natural;
                  Item : String) is
   begin
      Buffer (Last + 1 .. Last + Item'Length) := Item;
      Last := Last + Item'Length;
   end Put;

   procedure Put_Escape_16 (Buffer : in out String; Last : in out Natural;
                            Code : Natural);

   procedure Put_Escape_16 (Buffer : in out String; Last : in out Natural;
                            Code : Natural) is
   begin
      Put (Buffer, Last, "\u");
      Put (Buffer, Last, (1 => Hex_Digits (Code / 4096 + 1)));
      Put (Buffer, Last, (1 => Hex_Digits ((Code / 256) mod 16 + 1)));
      Put (Buffer, Last, (1 => Hex_Digits ((Code / 16) mod 16 + 1)));
      Put (Buffer, Last, (1 => Hex_Digits (Code mod 16 + 1)));
   end Put_Escape_16;

   procedure Put_IRI (Buffer : in out String; Last : in out Natural;
                      Value : IRIs.IRI);

   procedure Put_IRI (Buffer : in out String; Last : in out Natural;
                      Value : IRIs.IRI)
   is
      Text : constant String := IRIs.To_UTF_8 (Value);
   begin
      Put (Buffer, Last, "<");
      --  Almost every IRI needs nothing escaped, and for those this is one
      --  block move rather than a decision per byte.
      if (for all Item of Text => not Escapes_In_IRI (Item)) then
         Put (Buffer, Last, Text);
      else
         for Item of Text loop
            if Escapes_In_IRI (Item) then
               Put_Escape_16 (Buffer, Last, Character'Pos (Item));
            else
               Last := Last + 1;
               Buffer (Last) := Item;
            end if;
         end loop;
      end if;
      Put (Buffer, Last, ">");
   end Put_IRI;

   procedure Put_Term (Buffer : in out String; Last : in out Natural;
                       Value : Terms.Term; Style : String_Datatype_Style);

   procedure Put_Term (Buffer : in out String; Last : in out Natural;
                       Value : Terms.Term; Style : String_Datatype_Style) is
   begin
      case Terms.Kind (Value) is
         when Terms.IRI_Kind =>
            Put_IRI (Buffer, Last, Terms.IRI_Value (Value));

         when Terms.Blank_Node_Kind =>
            Put (Buffer, Last, "_:");
            Put (Buffer, Last, Terms.Label (Value));

         when Terms.Literal_Kind =>
            Put (Buffer, Last, """");
            declare
               Lexical : constant String := Terms.Lexical_Form (Value);
            begin
               if (for all Item of Lexical =>
                     not Escapes_In_Literal (Item))
               then
                  Put (Buffer, Last, Lexical);
               else
                  Put (Buffer, Last, Escape_Literal (Lexical));
               end if;
            end;
            Put (Buffer, Last, """");

            if Terms.Has_Language (Value) then
               Put (Buffer, Last, "@");
               Put (Buffer, Last, Terms.Language (Value));
               if Terms.Has_Direction (Value) then
                  Put (Buffer, Last,
                       (if Terms.Direction (Value) = Terms.Left_To_Right
                        then "--ltr" else "--rtl"));
               end if;
            else
               declare
                  Datatype : constant IRIs.IRI := Terms.Datatype (Value);
               begin
                  if Style /= Implicit_Datatype
                    or else IRIs.To_UTF_8 (Datatype) /= XSD_String
                  then
                     Put (Buffer, Last, "^^");
                     Put_IRI (Buffer, Last, Datatype);
                  end if;
               end;
            end if;

         when Terms.Triple_Term_Kind =>
            Put (Buffer, Last, "<<(");
            Put_Term (Buffer, Last, Terms.Triple_Subject (Value), Style);
            Put (Buffer, Last, " ");
            Put_IRI (Buffer, Last, Terms.Triple_Predicate (Value));
            Put (Buffer, Last, " ");
            Put_Term (Buffer, Last, Terms.Triple_Object (Value), Style);
            Put (Buffer, Last, ")>>");
      end case;
   end Put_Term;

   procedure Put_Quad
     (Value  : Quads.Quad;
      Buffer : in out String;
      Last   : in out Natural;
      Style  : String_Datatype_Style := Explicit_Datatype)
   is
      Graph : constant Quads.Graph_Name := Quads.Graph (Value);
   begin
      Put_Term (Buffer, Last, Quads.Subject (Value), Style);
      Put (Buffer, Last, " ");
      Put_IRI (Buffer, Last, Quads.Predicate (Value));
      Put (Buffer, Last, " ");
      Put_Term (Buffer, Last, Quads.Object (Value), Style);
      if Quads.Kind (Graph) /= Quads.Default_Graph_Kind then
         Put (Buffer, Last, " ");
         Put_Term (Buffer, Last, Quads.Name_Term (Graph), Style);
      end if;
      Put (Buffer, Last, " .");
   end Put_Quad;

   function Write_Quad
     (Value : Quads.Quad;
      Style : String_Datatype_Style := Explicit_Datatype) return String
   is
      Graph : constant String := Write_Graph_Name (Quads.Graph (Value));
   begin
      return Write_Term (Quads.Subject (Value), Style)
        & " " & Write_IRI (Quads.Predicate (Value))
        & " " & Write_Term (Quads.Object (Value), Style)
        & (if Graph = "" then "" else " " & Graph)
        & " .";
   end Write_Quad;

end Flyology_RDF.NQuads_Writers;
