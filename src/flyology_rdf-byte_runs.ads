--  Vector-classified runs of plain bytes for the scanner's hot loops.
--
--  The scanner decodes one scalar at a time, and for most of a document
--  that is one decode, one classification, and one position update per
--  byte of an IRI, a string body, or a name. Each function below looks at
--  sixteen bytes at once and reports how many leading bytes are certainly
--  plain content for one token class: printable ASCII that the scalar
--  loop would have consumed without doing anything but stepping past it.
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

   --  Leading bytes at From that continue a name run: ASCII letters,
   --  digits, '_' and '-'. A dot or colon ends the run because the scalar
   --  loop decides what either means.
   --  @param Text Buffer being scanned
   --  @param From Index of the first candidate byte
   --  @return Count of plain bytes, possibly zero; never past Text'Last
   function Name_Run (Text : String; From : Positive) return Natural
   with Pre => From >= Text'First;

   --  Leading bytes at From that continue a local name and may legally
   --  end one: the name-run characters, plus ':' unless the name is a
   --  blank node label. Dot, percent, and backslash end the run because
   --  the scalar loop owns each of those decisions.
   --  @param Text Buffer being scanned
   --  @param From Index of the first candidate byte
   --  @param Blank_Label True when scanning a blank node label
   --  @return Count of plain bytes, possibly zero; never past Text'Last
   function Local_Name_Run
     (Text        : String;
      From        : Positive;
      Blank_Label : Boolean) return Natural
   with Pre => From >= Text'First;

private

   pragma Inline (IRI_Run);
   pragma Inline (String_Run);
   pragma Inline (Name_Run);
   pragma Inline (Local_Name_Run);

end Flyology_RDF.Byte_Runs;
