--  Exercises the binary codec.
--
--  Injectivity is the property the encoding exists for, and it is claimed
--  structurally: a tag before anything variable, a length before every
--  variable field. The tests here try to break that claim from both sides --
--  round-tripping a wide spread of terms, and checking directly that shapes
--  which could plausibly collide do not.
--
--  The golden vectors are not decoration. They are what turns "the encoding
--  did not change" from a hope into a build failure, which is the only way
--  a format stays put across refactors that never intended to touch it.

with Ada.Command_Line;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Flyology_RDF.Codecs;
with Flyology_RDF.IRIs;
with Flyology_RDF.Quads;
with Flyology_RDF.Terms;

procedure Codec_Tests is

   package IO renames Ada.Text_IO;
   package Unbounded renames Ada.Strings.Unbounded;
   package Codecs renames Flyology_RDF.Codecs;
   package IRIs renames Flyology_RDF.IRIs;
   package Quads renames Flyology_RDF.Quads;
   package Terms renames Flyology_RDF.Terms;

   use type Quads.Quad;
   use type Terms.Term;

   Checks   : Natural := 0;
   Failures : Natural := 0;

   procedure Check (Condition : Boolean; Label : String) is
   begin
      Checks := Checks + 1;
      if not Condition then
         Failures := Failures + 1;
         IO.Put_Line ("  FAIL  " & Label);
      end if;
   end Check;

   procedure Check_Equal (Actual, Expected, Label : String) is
   begin
      Checks := Checks + 1;
      if Actual /= Expected then
         Failures := Failures + 1;
         IO.Put_Line ("  FAIL  " & Label);
         IO.Put_Line ("        got      " & Actual);
         IO.Put_Line ("        expected " & Expected);
      end if;
   end Check_Equal;

   Hex : constant String := "0123456789abcdef";

   function To_Hex (Value : String) return String is
      Buffer : Unbounded.Unbounded_String;
   begin
      for Item of Value loop
         declare
            Code : constant Natural := Character'Pos (Item);
         begin
            Unbounded.Append (Buffer, Hex (Code / 16 + 1));
            Unbounded.Append (Buffer, Hex (Code mod 16 + 1));
         end;
      end loop;
      return Unbounded.To_String (Buffer);
   end To_Hex;

   function I (Text : String) return IRIs.IRI is (IRIs.From_UTF_8 (Text));
   function T (Text : String) return Terms.Term
   is (Terms.IRI_Term (I (Text)));

   XSD_String : constant String :=
     "http://www.w3.org/2001/XMLSchema#string";

   --  Every term must survive encoding, and no two distinct terms may
   --  produce the same bytes. The second half is checked against every
   --  earlier term rather than a chosen few.
   Collisions     : Natural := 0;
   Encoded_Count  : Natural := 0;

   package Encoding_Lists is
      Store : array (1 .. 64) of Unbounded.Unbounded_String;
      Count : Natural := 0;
   end Encoding_Lists;

   procedure Round_Trip (Value : Terms.Term; Label : String) is
      Bytes : constant String := Codecs.Encode (Value);
   begin
      Encoded_Count := Encoded_Count + 1;
      Check (Codecs.Decode_Term (Bytes) = Value, Label & " round trips");

      for Index in 1 .. Encoding_Lists.Count loop
         if Unbounded.To_String (Encoding_Lists.Store (Index)) = Bytes then
            Collisions := Collisions + 1;
            IO.Put_Line
              ("  FAIL  " & Label & " collides with an earlier term");
         end if;
      end loop;

      if Encoding_Lists.Count < Encoding_Lists.Store'Last then
         Encoding_Lists.Count := Encoding_Lists.Count + 1;
         Encoding_Lists.Store (Encoding_Lists.Count) :=
           Unbounded.To_Unbounded_String (Bytes);
      end if;
   end Round_Trip;

   procedure Check_Rejects (Bytes : String; Label : String) is
      Ignored : Terms.Term := Terms.Blank_Node ("x");
   begin
      Ignored := Codecs.Decode_Term (Bytes);
      Check (False, Label & " must be rejected");
      pragma Unreferenced (Ignored);
   exception
      when Codecs.Invalid_Encoding =>
         Check (True, Label & " rejected");
   end Check_Rejects;

begin
   IO.Put_Line ("Codec tests");

   ------------------------------------------------------------------
   --  Round trips across the whole term space
   ------------------------------------------------------------------
   Round_Trip (T ("http://example.org/a"), "an IRI");
   Round_Trip (T ("http://example.org/b"), "another IRI");
   Round_Trip (Terms.Blank_Node ("b0"), "a blank node");
   Round_Trip (Terms.Blank_Node ("b1"), "another blank node");
   Round_Trip (Terms.Literal ("", I (XSD_String)), "an empty literal");
   Round_Trip (Terms.Literal ("text", I (XSD_String)), "a typed literal");
   Round_Trip (Terms.Literal ("text", I ("http://example.org/dt")),
               "another datatype");
   Round_Trip (Terms.Language_Literal ("text", "en"), "a language literal");
   Round_Trip (Terms.Language_Literal ("text", "fr"), "another language");
   Round_Trip (Terms.Directional_Literal ("text", "en",
                                          Terms.Left_To_Right),
               "a left-to-right literal");
   Round_Trip (Terms.Directional_Literal ("text", "en",
                                          Terms.Right_To_Left),
               "a right-to-left literal");
   Round_Trip (Terms.Literal ("a" & ASCII.NUL & "b", I (XSD_String)),
               "a literal containing a null byte");
   Round_Trip (Terms.Literal ("héllo", I (XSD_String)),
               "a literal containing non-ASCII");
   Round_Trip
     (Terms.Triple_Term (T ("http://example.org/a"),
                         I ("http://example.org/p"),
                         T ("http://example.org/b")),
      "a triple term");
   Round_Trip
     (Terms.Triple_Term
        (T ("http://example.org/a"), I ("http://example.org/p"),
         Terms.Triple_Term (T ("http://example.org/b"),
                            I ("http://example.org/q"),
                            T ("http://example.org/c"))),
      "a nested triple term");

   Check (Collisions = 0, "no two distinct terms encode alike");

   ------------------------------------------------------------------
   --  Shapes that could collide if lengths were not written
   ------------------------------------------------------------------
   Check
     (Codecs.Encode (Terms.Blank_Node ("ab"))
      /= Codecs.Encode (Terms.Literal ("ab", I (XSD_String))),
      "a blank node and a literal with the same text differ");

   Check
     (Codecs.Encode (Terms.Literal ("ab", I ("http://example.org/x")))
      /= Codecs.Encode (Terms.Literal ("a", I ("bhttp://example.org/x"))),
      "a field boundary cannot be moved without changing the bytes");

   Check
     (Codecs.Encode (Terms.Language_Literal ("a", "enfr"))
      /= Codecs.Encode (Terms.Language_Literal ("a", "en")),
      "language tags of different length differ");

   ------------------------------------------------------------------
   --  Statements
   ------------------------------------------------------------------
   declare
      Statement : constant Quads.Quad :=
        Quads.Create (Quads.Default_Graph, T ("http://example.org/s"),
                      I ("http://example.org/p"),
                      T ("http://example.org/o"));
      Named : constant Quads.Quad :=
        Quads.Create (Quads.IRI_Graph (I ("http://example.org/g")),
                      T ("http://example.org/s"),
                      I ("http://example.org/p"),
                      T ("http://example.org/o"));
      Blank_Graph : constant Quads.Quad :=
        Quads.Create (Quads.Blank_Node_Graph (Terms.Blank_Node ("g")),
                      T ("http://example.org/s"),
                      I ("http://example.org/p"),
                      T ("http://example.org/o"));
   begin
      Check (Codecs.Decode_Quad (Codecs.Encode (Statement)) = Statement,
             "a default-graph statement round trips");
      Check (Codecs.Decode_Quad (Codecs.Encode (Named)) = Named,
             "a named-graph statement round trips");
      Check (Codecs.Decode_Quad (Codecs.Encode (Blank_Graph))
             = Blank_Graph,
             "a blank-node-graph statement round trips");
      Check (Codecs.Encode (Statement) /= Codecs.Encode (Named),
             "the graph is part of the encoding");
   end;

   ------------------------------------------------------------------
   --  Golden vectors: the format must not drift
   ------------------------------------------------------------------
   Check_Equal (To_Hex (Codecs.Encode (Terms.Blank_Node ("b0"))),
                "02026230",
                "golden vector: blank node b0");

   Check_Equal (To_Hex (Codecs.Encode (T ("http://example.org/a"))),
                "0114" & To_Hex ("http://example.org/a"),
                "golden vector: a twenty-byte IRI");

   Check_Equal
     (To_Hex (Codecs.Encode (Terms.Language_Literal ("hi", "en"))),
      "0301" & "02" & To_Hex ("hi")
      & "35" & To_Hex ("http://www.w3.org/1999/02/22-rdf-syntax-ns#"
                       & "langString")
      & "02" & To_Hex ("en"),
      "golden vector: a language literal");

   Check_Equal
     (To_Hex (Codecs.Encode
                (Terms.Directional_Literal ("hi", "ar",
                                            Terms.Right_To_Left))),
      "0303" & "02" & To_Hex ("hi")
      & "38" & To_Hex ("http://www.w3.org/1999/02/22-rdf-syntax-ns#"
                       & "dirLangString")
      & "02" & To_Hex ("ar") & "01",
      "golden vector: a right-to-left literal");

   ------------------------------------------------------------------
   --  Malformed input
   ------------------------------------------------------------------
   Check_Rejects ("", "empty input");
   Check_Rejects ([Character'Val (9)], "an unknown tag");
   Check_Rejects ([Character'Val (1)], "a truncated length");
   Check_Rejects ([Character'Val (1), Character'Val (5), 'a'],
                  "a length longer than the input");
   Check_Rejects ([Character'Val (1), Character'Val (0)],
                  "an IRI that is not absolute");
   Check_Rejects ([Character'Val (2), Character'Val (0)],
                  "a blank node with an empty label");
   Check_Rejects (Codecs.Encode (Terms.Blank_Node ("b0")) & "x",
                  "trailing input after a complete term");
   --  A direction without a language names a term the model cannot build.
   Check_Rejects ([Character'Val (3), Character'Val (2),
                   Character'Val (0), Character'Val (0),
                   Character'Val (0)],
                  "a direction with no language tag");
   --  Continuation bits that never terminate.
   Check_Rejects ([Character'Val (1), Character'Val (128),
                   Character'Val (128), Character'Val (128),
                   Character'Val (128), Character'Val (128),
                   Character'Val (128)],
                  "a length that never terminates");

   ------------------------------------------------------------------
   --  Regressions: defects found by review, kept fixed
   ------------------------------------------------------------------

   --  A language-tagged literal's datatype is fixed by the model, so
   --  bytes that say otherwise are not an encoding of any term.
   Check_Rejects
     ([Character'Val (3), Character'Val (1), Character'Val (1)] & "x"
      & [Character'Val (10)] & "http://foo"
      & [Character'Val (2)] & "en",
      "a language literal with a foreign datatype");

   --  A malformed quad must decode to Invalid_Encoding, not to whatever
   --  the term model raised while its components were being built.
   declare
      Bytes : constant String :=
        [Character'Val (1), Character'Val (8)] & "notaniri";
   begin
      Checks := Checks + 1;
      declare
         Ignored : constant Quads.Quad := Codecs.Decode_Quad (Bytes);
         pragma Unreferenced (Ignored);
      begin
         Failures := Failures + 1;
         IO.Put_Line ("  FAIL  a quad with a malformed graph IRI decoded");
      end;
   exception
      when Codecs.Invalid_Encoding =>
         null;
      when others =>
         Failures := Failures + 1;
         IO.Put_Line
           ("  FAIL  a malformed quad graph escaped as another exception");
   end;

   IO.Put_Line ("  checks              " & Checks'Image);
   IO.Put_Line ("  failures            "
                & Natural'Image (Failures + Collisions));

   if Failures + Collisions = 0 then
      IO.Put_Line ("PASS codec_tests");
   else
      IO.Put_Line ("FAIL codec_tests");
      Ada.Command_Line.Set_Exit_Status (1);
   end if;
end Codec_Tests;
