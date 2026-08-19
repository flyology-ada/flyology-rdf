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
