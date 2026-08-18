--  Message digests.
--
--  Canonicalization needs these: RDFC-1.0 names SHA-256 as its default and
--  SHA-384 as the one alternative, and the canonical blank node identifiers
--  a conforming processor produces depend on which was used, so this is a
--  specification requirement rather than a utility that happens to live
--  here.
--
--  The implementation is GNAT's, which couples this crate to the GNAT
--  runtime. That is a deliberate and recorded choice: every compiler this
--  ecosystem targets is GNAT, and carrying our own SHA would mean
--  maintaining cryptographic code to avoid a dependency the crate already
--  has in every other respect.
package Flyology_RDF.Digests is

   --  The digests RDFC-1.0 admits.
   --  @enum SHA_256 The default
   --  @enum SHA_384 The alternative a manifest may ask for
   type Hash_Algorithm is (SHA_256, SHA_384);

   --  A SHA-256 digest rendered as lowercase hexadecimal, which is the form
   --  RDFC-1.0 hashes and compares.
   subtype Hex_Digest is String (1 .. 64);

   --  The same for SHA-384.
   subtype Hex_Digest_384 is String (1 .. 96);

   --  Digest a byte string with SHA-256.
   --  @param Value Bytes to digest
   --  @return The digest as 64 lowercase hexadecimal characters
   function SHA_256 (Value : String) return Hex_Digest;

   --  Digest a byte string with SHA-384.
   --  @param Value Bytes to digest
   --  @return The digest as 96 lowercase hexadecimal characters
   function SHA_384 (Value : String) return Hex_Digest_384;

   --  Digest with whichever algorithm was asked for. Canonicalization
   --  compares digests as strings and never assumes a length, so the two
   --  are interchangeable here.
   --  @param Value Bytes to digest
   --  @param Algorithm Which digest to use
   --  @return The digest as lowercase hexadecimal
   function Digest
     (Value : String; Algorithm : Hash_Algorithm) return String
   is (case Algorithm is
          when SHA_256 => SHA_256 (Value),
          when SHA_384 => SHA_384 (Value));

end Flyology_RDF.Digests;
