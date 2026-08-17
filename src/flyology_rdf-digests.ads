--  Message digests.
--
--  Canonicalization needs SHA-256: RDFC-1.0 names it, and the canonical
--  blank node identifiers a conforming processor produces depend on it, so
--  this is a specification requirement rather than a utility that happens to
--  live here.
--
--  The implementation is GNAT's, which couples this crate to the GNAT
--  runtime. That is a deliberate and recorded choice: every compiler this
--  ecosystem targets is GNAT, and carrying a second SHA-256 would mean
--  maintaining cryptographic code to avoid a dependency the crate already
--  has in every other respect.
package Flyology_RDF.Digests is

   --  A SHA-256 digest rendered as lowercase hexadecimal, which is the form
   --  RDFC-1.0 hashes and compares.
   subtype Hex_Digest is String (1 .. 64);

   --  Digest a byte string.
   --  @param Value Bytes to digest
   --  @return The digest as 64 lowercase hexadecimal characters
   function SHA_256 (Value : String) return Hex_Digest;

end Flyology_RDF.Digests;
