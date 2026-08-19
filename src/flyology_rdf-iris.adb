with Flyology_IRI;
with Flyology_RDF.Shared_Texts;

package body Flyology_RDF.IRIs is

   use type Flyology_IRI.Error_Kind;
   use type Flyology_IRI.Reference_Kind;

   --  Flyology_IRI defaults to 8 KiB, which is far below what an RDF
   --  document may legitimately contain, so every call below states the
   --  bound explicitly. Relying on the default would reject long IRIs with
   --  an unrelated diagnostic.
   function Admits (Value : String) return Boolean;

   function Admits (Value : String) return Boolean is
      Reference : Flyology_IRI.Reference;
      Error     : Flyology_IRI.Parse_Error;
   begin
      if Value'Length = 0 or else Value'Length > Maximum_IRI_Bytes then
         return False;
      end if;

      Flyology_IRI.Try_Parse
        (Input      => Value,
         Value      => Reference,
         Error      => Error,
         Syntax     => Flyology_IRI.IRI_Syntax,
         Max_Length => Maximum_IRI_Bytes);

      return Error.Kind = Flyology_IRI.No_Error
        and then Flyology_IRI.Kind (Reference)
                 = Flyology_IRI.Absolute_Reference;
   end Admits;

   function Is_Valid (Value : String) return Boolean is
     (Admits (Value));

   function From_UTF_8 (Value : String) return IRI is
      Reference : Flyology_IRI.Reference;
      Error     : Flyology_IRI.Parse_Error;
   begin
      if Value'Length = 0 then
         raise Invalid_IRI with "IRI input is empty";
      elsif Value'Length > Maximum_IRI_Bytes then
         raise Invalid_IRI with "IRI input exceeds the maximum byte length";
      end if;

      Flyology_IRI.Try_Parse
        (Input      => Value,
         Value      => Reference,
         Error      => Error,
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
      elsif Flyology_IRI.Kind (Reference)
            /= Flyology_IRI.Absolute_Reference
      then
         raise Invalid_IRI with "IRI input is not absolute";
      end if;

      --  Store the caller's bytes, not the parser's serialisation. They are
      --  equal today -- the strictness gate asserts it over 925 cases -- and
      --  storing the input keeps that a property of this package rather than
      --  a standing assumption about another crate.
      return
        (Bytes => Shared_Texts.To_Text (Value));
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
           (Bytes => Shared_Texts.To_Text (Reference));
      end if;

      Flyology_IRI.Try_Parse
        (Input      => Shared_Texts.To_String (Base.Bytes),
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
     (Shared_Texts.To_String (Value.Bytes));

   function Byte_Length (Value : IRI) return Natural is
     (Shared_Texts.Length (Value.Bytes));

   overriding function "=" (Left, Right : IRI) return Boolean is
   begin
      return Shared_Texts."=" (Left.Bytes, Right.Bytes);
   end "=";

end Flyology_RDF.IRIs;
