private with Flyology_RDF.Shared_Texts;

--  Immutable RDF IRI values, represented by their exact validated UTF-8
--  bytes.
--
--  RDF compares IRIs codepoint by codepoint and applies no normalisation of
--  any kind, so this type stores what it was given and returns it unchanged.
--  Admission is RFC 3987 as implemented by Flyology_IRI in IRI_Syntax, plus a
--  requirement that the reference be absolute. See docs/iri-strictness.md for
--  the differential evidence behind that choice.
--
--  The exact bytes are the whole representation. Component offsets are
--  deliberately not retained: a document holds hundreds of thousands of
--  these, and nothing in the RDF model asks an IRI for its authority or its
--  path.
package Flyology_RDF.IRIs is

   --  Raised when input is not a canonical UTF-8 encoding of Unicode scalar
   --  values.
   Invalid_UTF_8 : exception;

   --  Raised when validated UTF-8 is not an absolute RFC 3987 IRI.
   Invalid_IRI : exception;

   --  Largest IRI this crate will admit, in encoded bytes.
   Maximum_IRI_Bytes : constant Positive := 1_048_576;

   --  An immutable RDF IRI value. Equality compares the exact validated
   --  UTF-8 bytes and performs no Unicode or IRI normalisation.
   type IRI is private;

   --  Construct an IRI from exact UTF-8 bytes.
   --  @param Value Bytes to validate and preserve
   --  @return An IRI containing exactly Value
   --  @exception Invalid_UTF_8 Value is malformed, truncated, overlong,
   --     a surrogate, or out of range
   --  @exception Invalid_IRI Value is well-formed UTF-8 but is not an
   --     absolute IRI, or exceeds Maximum_IRI_Bytes
   function From_UTF_8 (Value : String) return IRI;

   --  Test the admission rule without constructing an IRI or raising.
   --  @param Value Candidate bytes
   --  @return True exactly when From_UTF_8 would succeed
   function Is_Valid (Value : String) return Boolean;

   --  Resolve a possibly relative reference against an absolute base, using
   --  RFC 3986 section 5.2 merging and dot-segment removal.
   --  @param Base Absolute base IRI
   --  @param Reference Reference to resolve, absolute or relative
   --  @return The resolved absolute IRI
   --  @exception Invalid_IRI Reference is malformed, or the resolved result
   --     is not an absolute IRI
   function Resolve (Base : IRI; Reference : String) return IRI;

   --  Return an independent copy of the exact bytes supplied at
   --  construction.
   --  @param Value IRI to inspect
   --  @return Exact validated UTF-8 bytes of Value
   function To_UTF_8 (Value : IRI) return String;

   --  Return the encoded length without constructing a String copy.
   --  @param Value IRI to inspect
   --  @return Number of UTF-8 bytes, not Unicode scalar values
   function Byte_Length (Value : IRI) return Natural;

   --  Compare two IRIs by their exact UTF-8 bytes.
   --  @param Left First IRI
   --  @param Right Second IRI
   --  @return True exactly when both byte strings are equal
   overriding function "=" (Left, Right : IRI) return Boolean;

private

   --  Definite, so the types that carry an IRI can hold it directly
   --  rather than in a holder that allocates a cell for it.
   type IRI is record
      Bytes : Shared_Texts.Text;
   end record;

end Flyology_RDF.IRIs;
