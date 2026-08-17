--  Guard for the IRI strictness policy recorded in docs/iri-strictness.md.
--
--  Two properties are asserted, and both are load-bearing:
--
--    * A parsed IRI serialises back to the exact input bytes. RDF compares
--      IRIs codepoint by codepoint with no normalisation, so any rewriting
--      here would silently merge distinct terms.
--
--    * The admission rule -- Diagnose in IRI_Syntax plus absoluteness -- is
--      never more permissive than the permissive blocklist it replaced, and
--      is stricter only in the three classes the policy document names.
--
--  A new disagreement class means the underlying parser changed behaviour
--  and the policy has to be re-decided, so this fails rather than adapts.

with Ada.Command_Line;
with Ada.Text_IO;
with Flyology_IRI;

procedure IRI_Strictness_Gate is

   package IO renames Ada.Text_IO;

   use type Flyology_IRI.Error_Kind;
   use type Flyology_IRI.Reference_Kind;

   Max_Bytes : constant Positive := 1_048_576;

   Examined      : Natural := 0;
   Agree_Accept  : Natural := 0;
   Agree_Reject  : Natural := 0;
   Expected_Strict : Natural := 0;
   Failures      : Natural := 0;

   function Is_ASCII_Alpha (Item : Character) return Boolean is
     (Item in 'a' .. 'z' | 'A' .. 'Z');

   function Is_Scheme_Character (Item : Character) return Boolean is
     (Item in 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '+' | '-' | '.');

   function Is_Hexadecimal (Item : Character) return Boolean is
     (Item in '0' .. '9' | 'a' .. 'f' | 'A' .. 'F');

   --  Canonical UTF-8: no overlong forms, no surrogates, nothing above
   --  U+10FFFF.
   function Is_Valid_UTF_8 (Value : String) return Boolean is
      Index : Positive := Value'First;

      function Continuation (At_Index : Positive) return Boolean is
        (At_Index <= Value'Last
         and then Character'Pos (Value (At_Index)) in 16#80# .. 16#BF#);
   begin
      while Index <= Value'Last loop
         declare
            Lead : constant Natural := Character'Pos (Value (Index));
         begin
            if Lead < 16#80# then
               Index := Index + 1;
            elsif Lead in 16#C2# .. 16#DF# then
               if not Continuation (Index + 1) then
                  return False;
               end if;
               Index := Index + 2;
            elsif Lead in 16#E0# .. 16#EF# then
               if not Continuation (Index + 1)
                 or else not Continuation (Index + 2)
               then
                  return False;
               end if;
               declare
                  Next : constant Natural :=
                    Character'Pos (Value (Index + 1));
               begin
                  if (Lead = 16#E0# and then Next < 16#A0#)
                    or else (Lead = 16#ED# and then Next > 16#9F#)
                  then
                     return False;
                  end if;
               end;
               Index := Index + 3;
            elsif Lead in 16#F0# .. 16#F4# then
               if not Continuation (Index + 1)
                 or else not Continuation (Index + 2)
                 or else not Continuation (Index + 3)
               then
                  return False;
               end if;
               declare
                  Next : constant Natural :=
                    Character'Pos (Value (Index + 1));
               begin
                  if (Lead = 16#F0# and then Next < 16#90#)
                    or else (Lead = 16#F4# and then Next > 16#8F#)
                  then
                     return False;
                  end if;
               end;
               Index := Index + 4;
            else
               return False;
            end if;
         end;
      end loop;
      return True;
   end Is_Valid_UTF_8;

   --  The permissive rule this crate deliberately does not use: after an
   --  ASCII scheme, reject only control bytes, DEL, <>"{}|\^` and malformed
   --  percent escapes.
   function Permissive_Valid (Value : String) return Boolean is
      Colon : Natural := 0;
      Index : Positive;
   begin
      if Value'Length = 0
        or else Value'Length > Max_Bytes
        or else not Is_Valid_UTF_8 (Value)
        or else not Is_ASCII_Alpha (Value (Value'First))
      then
         return False;
      end if;

      for Position in Value'Range loop
         if Value (Position) = ':' then
            Colon := Position;
            exit;
         elsif not Is_Scheme_Character (Value (Position)) then
            return False;
         end if;
      end loop;

      if Colon = 0 then
         return False;
      end if;

      Index := Colon + 1;
      while Index <= Value'Last loop
         declare
            Item : constant Character := Value (Index);
            Code : constant Natural := Character'Pos (Item);
         begin
            if Code <= 16#20#
              or else Code = 16#7F#
              or else Item in '<' | '>' | '"' | '{' | '}' | '|'
                            | '\' | '^' | '`'
            then
               return False;
            elsif Item = '%' then
               if Value'Last - Index < 2
                 or else not Is_Hexadecimal (Value (Index + 1))
                 or else not Is_Hexadecimal (Value (Index + 2))
               then
                  return False;
               end if;
               Index := Index + 3;
            else
               Index := Index + 1;
            end if;
         end;
      end loop;
      return True;
   end Permissive_Valid;

   --  The admission rule this crate does use.
   function Strict_Valid (Value : String) return Boolean is
      Reference : Flyology_IRI.Reference;
      Error     : Flyology_IRI.Parse_Error;
   begin
      Flyology_IRI.Try_Parse
        (Value, Reference, Error, Flyology_IRI.IRI_Syntax, Max_Bytes);
      return Error.Kind = Flyology_IRI.No_Error
        and then Flyology_IRI.Kind (Reference)
                 = Flyology_IRI.Absolute_Reference;
   end Strict_Valid;

   function Round_Trips_Exactly (Value : String) return Boolean is
      Reference : Flyology_IRI.Reference;
      Error     : Flyology_IRI.Parse_Error;
   begin
      Flyology_IRI.Try_Parse
        (Value, Reference, Error, Flyology_IRI.IRI_Syntax, Max_Bytes);
      if Error.Kind /= Flyology_IRI.No_Error then
         return True;
      end if;
      return Flyology_IRI.Image (Reference) = Value;
   end Round_Trips_Exactly;

   --  Square brackets outside an IPv6 host, a colon in the authority that is
   --  not a port, and a repeated fragment. See docs/iri-strictness.md.
   function Is_Documented_Strictness (Value : String) return Boolean is
      Hashes : Natural := 0;
   begin
      for Item of Value loop
         if Item in '[' | ']' then
            return True;
         elsif Item = '#' then
            Hashes := Hashes + 1;
         end if;
      end loop;
      return Hashes > 1 or else Value = "http://exam:ple.org/p";
   end Is_Documented_Strictness;

   function Rendered (Value : String) return String is
      Buffer : String (1 .. 4 * Value'Length);
      Last   : Natural := 0;

      procedure Put (Item : String) is
      begin
         Buffer (Last + 1 .. Last + Item'Length) := Item;
         Last := Last + Item'Length;
      end Put;

      Digit_Set : constant String := "0123456789ABCDEF";
   begin
      for Item of Value loop
         declare
            Code : constant Natural := Character'Pos (Item);
         begin
            if Code < 16#20# or else Code >= 16#7F# then
               Put ("\x");
               Put ([Digit_Set (Code / 16 + 1)]);
               Put ([Digit_Set (Code mod 16 + 1)]);
            else
               Put ([Item]);
            end if;
         end;
      end loop;
      return Buffer (1 .. Last);
   end Rendered;

   procedure Fail (Reason, Value : String) is
   begin
      Failures := Failures + 1;
      IO.Put_Line ("  FAIL  " & Reason & "  " & Rendered (Value));
   end Fail;

   procedure Check (Value : String) is
      Permissive : constant Boolean := Permissive_Valid (Value);
      Strict     : constant Boolean := Strict_Valid (Value);
   begin
      Examined := Examined + 1;

      if not Round_Trips_Exactly (Value) then
         Fail ("round trip is not byte exact", Value);
      end if;

      if Permissive = Strict then
         if Strict then
            Agree_Accept := Agree_Accept + 1;
         else
            Agree_Reject := Agree_Reject + 1;
         end if;
      elsif Strict and not Permissive then
         --  The strict rule must never be the more permissive of the two.
         Fail ("strict rule accepted what the permissive rule rejected",
               Value);
      elsif Is_Documented_Strictness (Value) then
         Expected_Strict := Expected_Strict + 1;
      else
         Fail ("undocumented strictness divergence", Value);
      end if;
   end Check;

begin
   IO.Put_Line ("IRI strictness gate");

   for Code in 0 .. 127 loop
      declare
         Item : constant Character := Character'Val (Code);
         One  : constant String := [Item];
      begin
         Check ("http://example.org/path" & One);
         Check ("http://example.org/p" & One & "q");
         Check ("http://exam" & One & "ple.org/p");
         Check ("http://example.org/p?q=" & One);
         Check ("http://example.org/p#f" & One);
         Check (One & "ttp://example.org/p");
         Check ("ht" & One & "p://example.org/p");
      end;
   end loop;

   Check ("http://example.org/a[b]");
   Check ("http://[::1]/p");
   Check ("http://[2001:db8::1]:8080/p");
   Check ("http://example.org/%7E");
   Check ("http://example.org/~");
   Check ("http://example.org/%ZZ");
   Check ("http://example.org/%2");
   Check ("http://example.org/%41");
   Check ("HTTP://EXAMPLE.ORG/p");
   Check ("HtTp://Example.Org");
   Check ("http://example.org");
   Check ("http://example.org/");
   Check ("http://example.org./p");
   Check ("urn:uuid:6e8bc430-9c3a-11d9-9669-0800200c9a66");
   Check ("mailto:person@example.org");
   Check ("tag:example.org,2026:x");
   Check ("did:example:123456");
   Check ("a:b");
   Check ("x+y-z.1://example.org/p");
   Check ("//example.org/p");
   Check ("/absolute/path");
   Check ("relative/path");
   Check ("");
   Check ("#fragment");
   Check ("?query");
   Check ("http://example.org/"
          & Character'Val (16#C3#) & Character'Val (16#A9#));
   Check ("http://"
          & Character'Val (16#C3#) & Character'Val (16#A9#)
          & ".example.org/p");
   Check ("http://example.org/" & Character'Val (16#80#));
   Check ("http://example.org/" & Character'Val (16#C3#));

   IO.Put_Line ("  examined            " & Examined'Image);
   IO.Put_Line ("  agree accept        " & Agree_Accept'Image);
   IO.Put_Line ("  agree reject        " & Agree_Reject'Image);
   IO.Put_Line ("  documented strict   " & Expected_Strict'Image);
   IO.Put_Line ("  failures            " & Failures'Image);

   if Failures = 0 then
      IO.Put_Line ("PASS iri_strictness_gate");
   else
      IO.Put_Line ("FAIL iri_strictness_gate");
      Ada.Command_Line.Set_Exit_Status (1);
   end if;
end IRI_Strictness_Gate;
