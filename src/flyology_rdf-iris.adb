with Flyology_IRI;
with Ada.Unchecked_Deallocation;
with System.Atomic_Counters;

package body Flyology_RDF.IRIs is

   procedure Free is new Ada.Unchecked_Deallocation
     (Object => Shared_Bytes, Name => Shared_Bytes_Access);

   --  A document names a great many distinct IRIs and drops them again,
   --  so released blocks are kept and handed back out. They are held in a
   --  few capacity classes, because a block serves any IRI that fits it;
   --  anything longer than the largest class is allocated exactly and
   --  freed on release, since those are rare and holding one would tie up
   --  as much memory as all the small ones together.
   --
   --  The lists are per task, so no lock is needed: a block released by
   --  another task simply joins that task's list, which is correct
   --  because a free block belongs to nobody. Each is bounded so a burst
   --  of IRIs is not held for the life of the process.
   Class_Sizes : constant array (1 .. 4) of Natural := [32, 64, 128, 256];
   Class_Limit : constant := 128;

   type Class_Lists is array (Class_Sizes'Range) of Shared_Bytes_Access;
   type Class_Counts is array (Class_Sizes'Range) of Natural;

   Recycled       : Class_Lists := [others => null];
   Recycled_Count : Class_Counts := [others => 0];
   pragma Thread_Local_Storage (Recycled);
   pragma Thread_Local_Storage (Recycled_Count);

   function Class_For (Length : Natural) return Natural;
   function Hold (Value : String) return IRI;

   function Class_For (Length : Natural) return Natural is
   begin
      for Index in Class_Sizes'Range loop
         if Length <= Class_Sizes (Index) then
            return Index;
         end if;
      end loop;
      return 0;
   end Class_For;

   function Hold (Value : String) return IRI is
      Class : constant Natural := Class_For (Value'Length);
      Block : Shared_Bytes_Access;
   begin
      if Class /= 0 and then Recycled (Class) /= null then
         Block := Recycled (Class);
         Recycled (Class) := Block.Next_Free;
         Recycled_Count (Class) := Recycled_Count (Class) - 1;
         Block.Next_Free := null;
         System.Atomic_Counters.Initialize (Block.References);
      elsif Class /= 0 then
         Block := new Shared_Bytes (Capacity => Class_Sizes (Class));
      else
         Block := new Shared_Bytes (Capacity => Value'Length);
      end if;

      Block.Length := Value'Length;
      Block.Data (1 .. Value'Length) := Value;

      return Result : IRI do
         Result.Payload := Block;
      end return;
   end Hold;

   overriding procedure Adjust (Value : in out IRI) is
   begin
      if Value.Payload /= null then
         System.Atomic_Counters.Increment (Value.Payload.References);
      end if;
   end Adjust;

   overriding procedure Finalize (Value : in out IRI) is
      Doomed : Shared_Bytes_Access := Value.Payload;
      Class  : Natural;
   begin
      Value.Payload := null;
      if Doomed = null
        or else not System.Atomic_Counters.Decrement (Doomed.References)
      then
         return;
      end if;

      Class := Class_For (Doomed.Capacity);
      if Class /= 0
        and then Class_Sizes (Class) = Doomed.Capacity
        and then Recycled_Count (Class) < Class_Limit
      then
         Doomed.Length := 0;
         Doomed.Next_Free := Recycled (Class);
         Recycled (Class) := Doomed;
         Recycled_Count (Class) := Recycled_Count (Class) + 1;
      else
         Free (Doomed);
      end if;
   end Finalize;


   use type Flyology_IRI.Error_Kind;

   --  Flyology_IRI defaults to 8 KiB, which is far below what an RDF
   --  document may legitimately contain, so every call below states the
   --  bound explicitly. Relying on the default would reject long IRIs with
   --  an unrelated diagnostic.
   function Admits (Value : String) return Boolean;

   --  Whether Value opens with a scheme, which is what makes a reference
   --  absolute: a ':' before any '/', '?' or '#'. Flyology_IRI classifies
   --  a successfully parsed reference as absolute under exactly this test
   --  -- a colon in that position whose prefix is not a well-formed scheme
   --  fails its parse outright -- so, joined with a successful parse, this
   --  scan reproduces its Absolute_Reference verdict without asking it to
   --  build a Reference, which is what allocates.
   function Opens_With_Scheme (Value : String) return Boolean;

   function Opens_With_Scheme (Value : String) return Boolean is
   begin
      for C of Value loop
         case C is
            when ':' =>
               return True;
            when '/' | '?' | '#' =>
               return False;
            when others =>
               null;
         end case;
      end loop;
      return False;
   end Opens_With_Scheme;

   --  A one-pass check for the shape almost every IRI in a real document
   --  takes: an ASCII scheme://authority/path?query#fragment out of the
   --  RFC 3986 character sets, with no percent-escape, no userinfo, no IP
   --  literal, and at most a digits-only port. True means Flyology_IRI
   --  would certainly admit the bytes as an absolute reference, because
   --  each component test below is exactly its test narrowed to this
   --  shape. False decides nothing: the caller falls back to the general
   --  parser, which stays the sole authority on rejection. Percent
   --  escapes, userinfo, IP literals and every non-ASCII byte take the
   --  general path unexamined.
   function Certainly_Absolute (Value : String) return Boolean;

   Scheme_OK : constant array (Character) of Boolean :=
     ('A' .. 'Z' | 'a' .. 'z' | '0' .. '9' | '+' | '-' | '.' => True,
      others => False);

   --  unreserved and sub-delims: the reg-name grammar.
   Host_OK : constant array (Character) of Boolean :=
     ('A' .. 'Z' | 'a' .. 'z' | '0' .. '9' | '-' | '.' | '_' | '~'
      | '!' | '$' | '&' | ''' | '(' | ')' | '*' | '+' | ',' | ';' | '='
        => True,
      others => False);

   --  pchar without pct-encoded, plus '/'.
   Path_OK : constant array (Character) of Boolean :=
     ('A' .. 'Z' | 'a' .. 'z' | '0' .. '9' | '-' | '.' | '_' | '~'
      | '!' | '$' | '&' | ''' | '(' | ')' | '*' | '+' | ',' | ';' | '='
      | ':' | '@' | '/' => True,
      others => False);

   --  The query and fragment grammar: pchar plus '/' and '?'.
   Query_OK : constant array (Character) of Boolean :=
     ('A' .. 'Z' | 'a' .. 'z' | '0' .. '9' | '-' | '.' | '_' | '~'
      | '!' | '$' | '&' | ''' | '(' | ')' | '*' | '+' | ',' | ';' | '='
      | ':' | '@' | '/' | '?' => True,
      others => False);

   function Certainly_Absolute (Value : String) return Boolean is
      Index : Positive := Value'First;
   begin
      --  scheme = ALPHA *( ALPHA / DIGIT / "+" / "-" / "." ) ":"
      if Value (Index) not in 'A' .. 'Z' | 'a' .. 'z' then
         return False;
      end if;
      loop
         Index := Index + 1;
         if Index > Value'Last then
            return False;
         end if;
         exit when not Scheme_OK (Value (Index));
      end loop;
      if Value (Index) /= ':' then
         return False;
      end if;
      Index := Index + 1;

      --  //authority, ending at '/', '?', '#' or the end. One ':' at most,
      --  splitting host from a digits-only port; everything else must be a
      --  reg-name byte, so userinfo, IP literals and escapes fall back.
      if Index + 1 <= Value'Last
        and then Value (Index) = '/'
        and then Value (Index + 1) = '/'
      then
         Index := Index + 2;
         declare
            Port_Colon : Natural := 0;
         begin
            while Index <= Value'Last
              and then Value (Index) not in '/' | '?' | '#'
            loop
               if Value (Index) = ':' then
                  if Port_Colon /= 0 then
                     return False;
                  end if;
                  Port_Colon := Index;
               elsif not Host_OK (Value (Index)) then
                  return False;
               end if;
               Index := Index + 1;
            end loop;
            if Port_Colon /= 0 then
               for Digit in Port_Colon + 1 .. Index - 1 loop
                  if Value (Digit) not in '0' .. '9' then
                     return False;
                  end if;
               end loop;
            end if;
         end;
      end if;

      --  path, then ?query, then #fragment, each a plain character run.
      while Index <= Value'Last and then Value (Index) not in '?' | '#' loop
         if not Path_OK (Value (Index)) then
            return False;
         end if;
         Index := Index + 1;
      end loop;
      if Index <= Value'Last and then Value (Index) = '?' then
         Index := Index + 1;
         while Index <= Value'Last and then Value (Index) /= '#' loop
            if not Query_OK (Value (Index)) then
               return False;
            end if;
            Index := Index + 1;
         end loop;
      end if;
      if Index <= Value'Last and then Value (Index) = '#' then
         Index := Index + 1;
         while Index <= Value'Last loop
            if not Query_OK (Value (Index)) then
               return False;
            end if;
            Index := Index + 1;
         end loop;
      end if;
      return True;
   end Certainly_Absolute;

   function Admits (Value : String) return Boolean is
   begin
      if Value'Length = 0 or else Value'Length > Maximum_IRI_Bytes then
         return False;
      end if;

      return Certainly_Absolute (Value)
        or else (Opens_With_Scheme (Value)
                 and then Flyology_IRI.Can_Parse
                   (Input      => Value,
                    Syntax     => Flyology_IRI.IRI_Syntax,
                    Max_Length => Maximum_IRI_Bytes));
   end Admits;

   function Is_Valid (Value : String) return Boolean is
     (Admits (Value));

   function From_UTF_8 (Value : String) return IRI is
      Error : Flyology_IRI.Parse_Error;
   begin
      if Value'Length = 0 then
         raise Invalid_IRI with "IRI input is empty";
      elsif Value'Length > Maximum_IRI_Bytes then
         raise Invalid_IRI with "IRI input exceeds the maximum byte length";
      end if;

      if Certainly_Absolute (Value) then
         return Hold (Value);
      end if;

      --  Diagnose applies the same grammar Try_Parse does -- both are one
      --  call to the same analysis -- but reports the verdict alone, so
      --  admitting an IRI allocates nothing where Try_Parse built a parsed
      --  Reference this function immediately threw away.
      Error := Flyology_IRI.Diagnose
        (Input      => Value,
         Syntax     => Flyology_IRI.IRI_Syntax,
         Max_Length => Maximum_IRI_Bytes);

      --  Separating the two exceptions keeps the diagnostic honest: a caller
      --  that handed over mis-encoded bytes has a different problem from one
      --  that handed over a well-formed relative reference.
      if Error.Kind = Flyology_IRI.Invalid_Character then
         raise Invalid_UTF_8 with
           "IRI input is not a canonical UTF-8 Unicode scalar sequence";
      elsif Error.Kind /= Flyology_IRI.No_Error then
         raise Invalid_IRI with "IRI input is not a valid IRI";
      elsif not Opens_With_Scheme (Value) then
         raise Invalid_IRI with "IRI input is not absolute";
      end if;

      --  Store the caller's bytes, not the parser's serialisation. They are
      --  equal today -- the strictness gate asserts it over 925 cases -- and
      --  storing the input keeps that a property of this package rather than
      --  a standing assumption about another crate.
      return
        Hold (Value);
   end From_UTF_8;

   --  Whether Reference could contain a "." or ".." path segment. Such a
   --  segment can only follow a '/', or the ':' that ends the scheme, or
   --  open the string, so a reference with no dot in any of those
   --  positions is known to be free of them without being parsed. The
   --  test errs towards False positives -- a dot after a ':' inside a
   --  query, say -- which only means taking the general path below.
   function Might_Hold_Dot_Segment (Reference : String) return Boolean;

   function Might_Hold_Dot_Segment (Reference : String) return Boolean is
   begin
      for Index in Reference'Range loop
         if Reference (Index) = '.'
           and then (Index = Reference'First
                     or else Reference (Index - 1) in '/' | ':')
         then
            return True;
         end if;
      end loop;
      return False;
   end Might_Hold_Dot_Segment;

   function Resolve (Base : IRI; Reference : String) return IRI is
      Base_Reference : Flyology_IRI.Reference;
      Base_Error     : Flyology_IRI.Parse_Error;
   begin
      --  RFC 3986 section 5.2.2 keeps a reference that carries its own
      --  scheme as it stands, apart from removing dot segments from its
      --  path. A reference this crate admits as an IRI that also cannot
      --  contain a dot segment therefore resolves to exactly its own
      --  bytes, and deciding that costs one parse of the reference where
      --  the general path parses the base, the reference, and the
      --  recomposed result. Prefixed names expand to exactly such
      --  references, so this is the path a Turtle document mostly takes.
      if not Might_Hold_Dot_Segment (Reference)
        and then Admits (Reference)
      then
         return
           Hold (Reference);
      end if;

      Flyology_IRI.Try_Parse
        (Input      => To_UTF_8 (Base),
         Value      => Base_Reference,
         Error      => Base_Error,
         Syntax     => Flyology_IRI.IRI_Syntax,
         Max_Length => Maximum_IRI_Bytes);

      if Base_Error.Kind /= Flyology_IRI.No_Error then
         --  Unreachable through the public constructor, which admits only
         --  parseable absolutes; kept so a future representation change
         --  fails loudly rather than silently resolving against nothing.
         raise Invalid_IRI with "base IRI is not parseable";
      end if;

      declare
         Resolved : constant Flyology_IRI.Reference :=
           Flyology_IRI.Resolve
             (Base       => Base_Reference,
              Relative   => Reference,
              Max_Length => Maximum_IRI_Bytes);
      begin
         return From_UTF_8 (Flyology_IRI.Image (Resolved));
      end;
   exception
      when Flyology_IRI.Malformed_Reference =>
         raise Invalid_IRI with "IRI reference cannot be resolved";
   end Resolve;

   function To_UTF_8 (Value : IRI) return String is
     (if Value.Payload = null then ""
      else Value.Payload.Data (1 .. Value.Payload.Length));

   function Byte_Length (Value : IRI) return Natural is
     (if Value.Payload = null then 0 else Value.Payload.Length);

   overriding function "=" (Left, Right : IRI) return Boolean is
   begin
      if Left.Payload = Right.Payload then
         return True;
      elsif Left.Payload = null or else Right.Payload = null then
         return False;
      end if;
      return Left.Payload.Data (1 .. Left.Payload.Length)
             = Right.Payload.Data (1 .. Right.Payload.Length);
   end "=";

end Flyology_RDF.IRIs;
