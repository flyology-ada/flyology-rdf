--  Vector-classified runs of plain bytes for the scanner's hot loops.
--
--  The scanner decodes one scalar at a time, and for most of a document
--  that is one decode, one classification, and one position update per
--  byte of an IRI or a string body. Each function below looks at sixteen
--  bytes at once and reports how many leading bytes are certainly plain
--  content for one token class: printable ASCII that the scalar loop
--  would have consumed without doing anything but stepping past it.
--
--  Only the two classes whose runs are long enough to pay for a block
--  classification are here. A name averages a handful of bytes, and
--  classifying a sixteen-byte block costs about what two scalar steps
--  do, so names measured slower in bulk and stay with the scalar loop.
--
--  The scalar loop remains the authority. A run never includes a byte
--  that ends the token, opens an escape, breaks a line, or begins a
--  multi-byte sequence, so the caller's loop still decides every one of
--  those exactly as before; and near the end of the buffer the answer is
--  simply zero, which sends the caller down the unchanged scalar path.
package Flyology_RDF.Byte_Runs is

   --  Leading bytes at From that an IRIREF consumes verbatim: ASCII above
   --  space that is neither '>' nor '\' nor a character the production
   --  forbids between the angle brackets.
   --  @param Text Buffer being scanned
   --  @param From Index of the first candidate byte
   --  @return Count of plain bytes, possibly zero; never past Text'Last
   function IRI_Run (Text : String; From : Positive) return Natural
   with Pre => From >= Text'First;

   --  Leading bytes at From that a string body consumes verbatim: ASCII
   --  that is not the quote character, not '\', and not a line break.
   --  @param Text Buffer being scanned
   --  @param From Index of the first candidate byte
   --  @param Double_Quoted True when the string is quoted with '"'
   --  @return Count of plain bytes, possibly zero; never past Text'Last
   function String_Run
     (Text          : String;
      From          : Positive;
      Double_Quoted : Boolean) return Natural
   with Pre => From >= Text'First;

private

   pragma Inline (IRI_Run);
   pragma Inline (String_Run);

end Flyology_RDF.Byte_Runs;
