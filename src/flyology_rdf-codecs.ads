with Flyology_RDF.Quads;
with Flyology_RDF.Terms;

--  Compact binary encoding for terms and statements.
--
--  This exists for callers that need to put a term in a cache, a key, or a
--  message and want something smaller and faster to compare than a
--  serialization meant for people.
--
--  The encoding is injective by construction rather than by inspection:
--  every value begins with a tag naming its kind, and every variable-length
--  field carries its length, so no two distinct terms can produce the same
--  bytes and no field boundary depends on scanning for a delimiter. That is
--  the property the whole thing is for, and it is what the golden vectors
--  in the tests defend.
--
--  > The format is EXPERIMENTAL. It is versioned, and the version will be
--  > raised rather than the bytes quietly changed, but it is not yet a
--  > compatibility commitment: the question of whether blank node identity
--  > belongs in a portable encoding at all is not settled, and settling it
--  > after promising stability would mean an immediate second version.
package Flyology_RDF.Codecs is

   --  Raised when bytes are not a valid encoding, including when they are
   --  well formed but describe a term this crate will not build.
   Invalid_Encoding : exception;

   --  Identifies the encoding, for callers that store or transmit it.
   Format_Identifier : constant String := "flyology-rdf-binary-v1";

   --  Encode a term.
   --  @param Value Term to encode
   --  @return The encoded bytes
   function Encode (Value : Terms.Term) return String;

   --  Encode a statement.
   --  @param Value Statement to encode
   --  @return The encoded bytes
   function Encode (Value : Quads.Quad) return String;

   --  Decode a term, which must occupy the whole of Bytes.
   --  @param Bytes Encoded term
   --  @return The decoded term
   --  @exception Invalid_Encoding Bytes are malformed, truncated, or carry
   --     trailing input
   function Decode_Term (Bytes : String) return Terms.Term;

   --  Decode a statement, which must occupy the whole of Bytes.
   --  @param Bytes Encoded statement
   --  @return The decoded statement
   --  @exception Invalid_Encoding Bytes are malformed, truncated, or carry
   --     trailing input
   function Decode_Quad (Bytes : String) return Quads.Quad;

end Flyology_RDF.Codecs;
