with Ada.Characters.Handling;
with GNAT.SHA256;
with GNAT.SHA384;

package body Flyology_RDF.Digests is

   --  GNAT documents the digest as hexadecimal but not its case, and
   --  RDFC-1.0 compares the lowercase form, so these normalise rather
   --  than assuming.

   function SHA_256 (Value : String) return Hex_Digest is
      Raw : constant String :=
        Ada.Characters.Handling.To_Lower (GNAT.SHA256.Digest (Value));
   begin
      return Result : Hex_Digest do
         Result := Raw (Raw'First .. Raw'First + Hex_Digest'Length - 1);
      end return;
   end SHA_256;

   function SHA_384 (Value : String) return Hex_Digest_384 is
      Raw : constant String :=
        Ada.Characters.Handling.To_Lower (GNAT.SHA384.Digest (Value));
   begin
      return Result : Hex_Digest_384 do
         Result := Raw (Raw'First .. Raw'First + Hex_Digest_384'Length - 1);
      end return;
   end SHA_384;

end Flyology_RDF.Digests;
