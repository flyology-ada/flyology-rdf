with Flyology_IRI;

package body Flyology_RDF.IRIs is

   package Unbounded renames Ada.Strings.Unbounded;

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
        (Initialized => True,
         Bytes       => Unbounded.To_Unbounded_String (Value));
   end From_UTF_8;

   function Resolve (Base : IRI; Reference : String) return IRI is
      Base_Reference : Flyology_IRI.Reference;
      Base_Error     : Flyology_IRI.Parse_Error;
   begin
      Flyology_IRI.Try_Parse
        (Input      => Unbounded.To_String (Base.Bytes),
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
     (Unbounded.To_String (Value.Bytes));

   function Byte_Length (Value : IRI) return Natural is
     (Unbounded.Length (Value.Bytes));

   overriding function "=" (Left, Right : IRI) return Boolean is
      use type Unbounded.Unbounded_String;
   begin
      return Left.Bytes = Right.Bytes;
   end "=";

end Flyology_RDF.IRIs;
