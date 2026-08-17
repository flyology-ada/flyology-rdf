with Ada.Characters.Handling;
with GNAT.SHA256;

package body Flyology_RDF.Digests is

   function SHA_256 (Value : String) return Hex_Digest is
      --  GNAT documents the digest as hexadecimal but not its case, and
      --  RDFC-1.0 compares the lowercase form, so this normalises rather
      --  than assuming.
      Raw : constant String :=
        Ada.Characters.Handling.To_Lower (GNAT.SHA256.Digest (Value));
   begin
      return Result : Hex_Digest do
         Result := Raw (Raw'First .. Raw'First + 63);
      end return;
   end SHA_256;

end Flyology_RDF.Digests;
