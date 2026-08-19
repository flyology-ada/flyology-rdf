with Ada.Unchecked_Deallocation;

with Flyology_RDF.Terms;

package body Flyology_RDF.Turtle_Parsers is

   procedure Free is new Ada.Unchecked_Deallocation
     (Object => Token_Array, Name => Token_Array_Access);

   overriding procedure Finalize (Value : in out Statement_Buffer) is
   begin
      Value.Count := 0;
      Free (Value.Data);
   end Finalize;

   procedure Free is new Ada.Unchecked_Deallocation
     (Object => String, Name => String_Access);

   overriding procedure Finalize (Value : in out Byte_Buffer) is
   begin
      Value.Count := 0;
      Free (Value.Data);
   end Finalize;

   --  Make room for Extra more bytes.
   procedure Ensure_Byte_Room (Buffer : in out Byte_Buffer; Extra : Natural);

   procedure Ensure_Byte_Room (Buffer : in out Byte_Buffer; Extra : Natural)
   is
      Needed : constant Natural := Buffer.Count + Extra;
   begin
      if Needed > Buffer.Data'Last then
         declare
            Bigger : constant String_Access :=
              new String
                (1 .. Positive'Max (Needed, 2 * Buffer.Data'Last));
         begin
            Bigger (1 .. Buffer.Count) := Buffer.Data (1 .. Buffer.Count);
            Free (Buffer.Data);
            Buffer.Data := Bigger;
         end;
      end if;
   end Ensure_Byte_Room;

   --  Make room for one more token, so the scanner can build it in its
   --  slot. Reused slots are overwritten by the scan itself, which
   --  finalises whatever the previous statement left in them.
   procedure Ensure_Token_Room (Buffer : in out Statement_Buffer);

   procedure Ensure_Token_Room (Buffer : in out Statement_Buffer) is
   begin
      if Buffer.Count = Buffer.Data'Last then
         declare
            Bigger : constant Token_Array_Access :=
              new Token_Array (1 .. 2 * Buffer.Data'Last);
         begin
            Bigger (1 .. Buffer.Count) := Buffer.Data (1 .. Buffer.Count);
            Free (Buffer.Data);
            Buffer.Data := Bigger;
         end;
      end if;
   end Ensure_Token_Room;

   package Cursors renames Parser_Cursors;

   use type Lexers.Scan_Status;
   use type Lexers.Scan_Error_Kind;
   use type Lexers.Token_Kind;
   use type Lexers.Direction_Value;
   use type Terms.Term_Kind;
   use type Lexers.String_Form;

   XSD_String  : constant String :=
     "http://www.w3.org/2001/XMLSchema#string";
   XSD_Integer : constant String :=
     "http://www.w3.org/2001/XMLSchema#integer";
   XSD_Decimal : constant String :=
     "http://www.w3.org/2001/XMLSchema#decimal";
   XSD_Double  : constant String :=
     "http://www.w3.org/2001/XMLSchema#double";
   XSD_Boolean : constant String :=
     "http://www.w3.org/2001/XMLSchema#boolean";
   RDF_Type    : constant String :=
     "http://www.w3.org/1999/02/22-rdf-syntax-ns#type";
   RDF_First   : constant String :=
     "http://www.w3.org/1999/02/22-rdf-syntax-ns#first";
   RDF_Rest    : constant String :=
     "http://www.w3.org/1999/02/22-rdf-syntax-ns#rest";
   RDF_Nil     : constant String :=
     "http://www.w3.org/1999/02/22-rdf-syntax-ns#nil";
   RDF_Reifies : constant String :=
     "http://www.w3.org/1999/02/22-rdf-syntax-ns#reifies";

   --  Parsed once at elaboration: these are fixed text, and the grammar
   --  reaches for one of them at every literal, keyword "a", collection
   --  cell and reifier, so validating the same bytes each time would be
   --  pure repetition.
   XSD_String_IRI  : constant IRIs.IRI := IRIs.From_UTF_8 (XSD_String);
   XSD_Integer_IRI : constant IRIs.IRI := IRIs.From_UTF_8 (XSD_Integer);
   XSD_Decimal_IRI : constant IRIs.IRI := IRIs.From_UTF_8 (XSD_Decimal);
   XSD_Double_IRI  : constant IRIs.IRI := IRIs.From_UTF_8 (XSD_Double);
   XSD_Boolean_IRI : constant IRIs.IRI := IRIs.From_UTF_8 (XSD_Boolean);
   RDF_Type_IRI    : constant IRIs.IRI := IRIs.From_UTF_8 (RDF_Type);
   RDF_First_IRI   : constant IRIs.IRI := IRIs.From_UTF_8 (RDF_First);
   RDF_Rest_IRI    : constant IRIs.IRI := IRIs.From_UTF_8 (RDF_Rest);
   RDF_Nil_IRI     : constant IRIs.IRI := IRIs.From_UTF_8 (RDF_Nil);
   RDF_Reifies_IRI : constant IRIs.IRI := IRIs.From_UTF_8 (RDF_Reifies);

   --  Raised internally to abandon a statement; every raise site records the
   --  diagnostic first, so the handler only has to deliver it.
   Grammar_Error : exception;

   --  Whether Raw is a label the generator has already issued. Issued
   --  labels are exactly "b" followed by the canonical decimal of some
   --  count up to Counter -- except those the document had claimed first,
   --  which the generator skips; the caller rules those out. Asking the
   --  question arithmetically replaces a set that held every generated
   --  label only to answer it.
   function Is_Generated_Label
     (Raw : String; Counter : Natural) return Boolean;

   function Is_Generated_Label
     (Raw : String; Counter : Natural) return Boolean
   is
      Value : Long_Long_Integer := 0;
   begin
      if Raw'Length < 2
        or else Raw (Raw'First) /= 'b'
        or else Raw (Raw'First + 1) = '0'
        or else Raw'Length > 11
        --  Eleven characters is "b" and ten digits, and a ten-digit
        --  number without a leading zero can exceed any possible count;
        --  anything longer certainly does.
      then
         return False;
      end if;
      for Index in Raw'First + 1 .. Raw'Last loop
         if Raw (Index) not in '0' .. '9' then
            return False;
         end if;
         Value := Value * 10
           + Long_Long_Integer
               (Character'Pos (Raw (Index)) - Character'Pos ('0'));
      end loop;
      return Value <= Long_Long_Integer (Counter);
   end Is_Generated_Label;

   ----------------------------------------------------------------------
   --  Diagnostics
   ----------------------------------------------------------------------

   function Code (Value : Parse_Diagnostic) return Diagnostic_Code
   is (Value.Code_Value);

   function Production (Value : Parse_Diagnostic) return Production_Kind
   is (Value.Production_Value);

   function Span (Value : Parse_Diagnostic) return Source_Span
   is (Value.Span_Value);

   function Source_Name (Value : Parse_Diagnostic) return String
   is (Unbounded.To_String (Value.Source_Value));

   function To_Span
     (From, To : Cursors.Cursor_State) return Source_Span
   is (Start_Byte   => From.Byte_Offset,
       End_Byte     => To.Byte_Offset,
       Start_Line   => From.Line,
       Start_Column => From.Column,
       End_Line     => To.Line,
       End_Column   => To.Column);

   function Token_Span (Value : Lexers.Token) return Source_Span
   is (To_Span (Lexers.Start_Position (Value),
                Lexers.End_Position (Value)));

   ----------------------------------------------------------------------
   --  Construction
   ----------------------------------------------------------------------

   function Create
     (Source_Name       : String;
      Blank_Node_Prefix : String := "";
      Base_IRI          : String := "";
      Limits            : Parse_Limits := (others => <>);
      Syntax            : Syntax_Kind := TriG_Syntax;
      Work_Checkpoint   : Work_Checkpoint_Access := null) return Parser is
   begin
      if Base_IRI /= "" and then not IRIs.Is_Valid (Base_IRI) then
         raise Invalid_Configuration with
           "base IRI is not an absolute IRI";
      end if;

      return Result : Parser (Initialized => True) do
         Result.Source_Data := Unbounded.To_Unbounded_String (Source_Name);
         Result.Blank_Prefix :=
           Unbounded.To_Unbounded_String (Blank_Node_Prefix);
         if Base_IRI /= "" then
            Result.Base_Data := IRI_Holders.To_Holder
              (IRIs.From_UTF_8 (Base_IRI));
         end if;
         Result.Limits_Data := Limits;
         Result.Syntax_Data := Syntax;
         Result.Checkpoint := Work_Checkpoint;
         --  Never null, so no access anywhere else need test for it.
         Result.Statement.Data := new Token_Array (1 .. 64);
         Result.Pending.Data := new String (1 .. 4_096);
      end return;
   end Create;

   function Work (Value : Parser) return Work_Statistics
   is (Value.Work_Data);

   ----------------------------------------------------------------------
   --  Statement parsing
   ----------------------------------------------------------------------

   procedure Parse_Statement
     (Into   : in out Parser;
      Target : in out Event_Sink'Class;
      Failure : out Parse_Diagnostic;
      Failed  : out Boolean)
   is
      Tokens : Token_Array renames Into.Statement.Data.all;
      Last   : constant Natural := Into.Statement.Count;
      Next   : Positive := 1;

      Depth  : Natural := 0;

      function Peek_Kind return Lexers.Token_Kind
      is (if Next <= Last
          then Lexers.Kind (Tokens (Next))
          else Lexers.Dot_Token);

      function At_End return Boolean is (Next > Last);

      --  Index of the current token -- the last one once the statement is
      --  exhausted, so a rejection at the end still has a span. Reading
      --  Tokens (Cur) is a view of the token, never a copy of it.
      function Cur return Positive
      is (if Next <= Last then Next else Last);

      procedure Reject
        (Why  : Diagnostic_Code;
         What : Production_Kind);

      procedure Reject
        (Why  : Diagnostic_Code;
         What : Production_Kind) is
      begin
         Failure :=
           (Code_Value       => Why,
            Production_Value => What,
            Span_Value       => Token_Span (Tokens (Cur)),
            Source_Value     => Into.Source_Data);
         Failed := True;
         raise Grammar_Error;
      end Reject;

      procedure Advance;

      procedure Advance is
      begin
         Next := Next + 1;
      end Advance;

      procedure Expect
        (Which : Lexers.Token_Kind;
         What  : Production_Kind);

      procedure Expect
        (Which : Lexers.Token_Kind;
         What  : Production_Kind) is
      begin
         if At_End or else Lexers.Kind (Tokens (Next)) /= Which then
            Reject (Malformed_Syntax, What);
         end if;
         Advance;
      end Expect;

      procedure Enter_Nesting;

      procedure Enter_Nesting is
      begin
         Depth := Depth + 1;
         if Depth > Into.Limits_Data.Maximum_Nesting then
            Reject (Nesting_Limit, Statement_Production);
         end if;
      end Enter_Nesting;

      function Fresh_Blank_Label return String;

      --  A label for a construct the document did not name: a collection
      --  cell, a property list, an anonymous reifier. Any label the
      --  document has already used is skipped, so the two kinds share one
      --  namespace without colliding.
      function Fresh_Blank_Label return String is
      begin
         loop
            Into.Blank_Counter := Into.Blank_Counter + 1;
            declare
               Image : constant String :=
                 Natural'Image (Into.Blank_Counter);
               Label : constant String :=
                 "b" & Image (Image'First + 1 .. Image'Last);
            begin
               if not Into.Document_Labels.Contains (Label) then
                  --  The prefix is empty for every consumer that did not
                  --  ask for one; joining it on would copy the label to
                  --  say nothing.
                  if Unbounded.Length (Into.Blank_Prefix) = 0 then
                     return Label;
                  end if;
                  return Unbounded.To_String (Into.Blank_Prefix) & Label;
               end if;
            end;
         end loop;
      end Fresh_Blank_Label;

      --  A label the document wrote itself, carried through unchanged apart
      --  from the caller's prefix. Rewriting it would make reading back
      --  this crate's own output rename every node, and rename it again on
      --  the next pass, so labels would grow without bound instead of
      --  reaching a fixed point.
      --
      --  The one exception is a label a generated node has already taken:
      --  that node is in statements already emitted, and sharing its label
      --  would merge two nodes the document keeps distinct, so the
      --  document's label is renamed instead -- consistently, so its later
      --  occurrences name the same node.
      function Document_Blank_Label (Raw : String) return String is
      begin
         if Into.Renamed_Labels.Contains (Raw) then
            return Into.Renamed_Labels.Element (Raw);
         end if;
         if not Into.Document_Labels.Contains (Raw) then
            --  A document label the generator issued first would merge
            --  two distinct nodes, so it is renamed. One the document
            --  claimed first cannot have been issued at all: had it been,
            --  its first use here would have renamed it already, and the
            --  generator skips claimed labels ever after.
            if Is_Generated_Label (Raw, Into.Blank_Counter) then
               declare
                  Replacement : constant String := Fresh_Blank_Label;
               begin
                  Into.Renamed_Labels.Insert (Raw, Replacement);
                  return Replacement;
               end;
            end if;
            Into.Document_Labels.Insert (Raw);
         end if;
         if Unbounded.Length (Into.Blank_Prefix) = 0 then
            return Raw;
         end if;
         return Unbounded.To_String (Into.Blank_Prefix) & Raw;
      end Document_Blank_Label;

      function Resolve (Reference : String; What : Production_Kind)
        return IRIs.IRI;

      function Resolve (Reference : String; What : Production_Kind)
        return IRIs.IRI is
      begin
         declare
            Known : constant IRI_Caches.Cursor :=
              Into.IRI_Cache.Find (Reference);
         begin
            if IRI_Caches.Has_Element (Known) then
               return IRI_Caches.Element (Known);
            end if;
         end;

         declare
            Admitted : constant IRIs.IRI :=
              (if Is_Line_Based (Into.Syntax_Data)
                 or else Into.Base_Data.Is_Empty
               --  From_UTF_8 parses the reference to admit it, so asking
               --  Is_Valid first parsed every IRI in the document twice.
               --  The handler below turns its refusal into the same
               --  diagnostic the pre-check raised, so the second parse
               --  bought nothing.
               then IRIs.From_UTF_8 (Reference)
               else IRIs.Resolve (Into.Base_Data.Element, Reference));
         begin
            if Natural (Into.IRI_Cache.Length) < Maximum_Cached_IRIs then
               Into.IRI_Cache.Insert (Reference, Admitted);
            end if;
            return Admitted;
         end;
      exception
         when IRIs.Invalid_IRI | IRIs.Invalid_UTF_8 =>
            Reject (Invalid_IRI, What);
            raise;
      end Resolve;

      function Expand (Value : Lexers.Token) return IRIs.IRI;

      function Expand (Value : Lexers.Token) return IRIs.IRI is
         Key : constant String := Lexers.Name (Value);
         Cached : constant IRI_Caches.Cursor :=
           Into.Name_Cache.Find (Key);
      begin
         if IRI_Caches.Has_Element (Cached) then
            return IRI_Caches.Element (Cached);
         end if;

         declare
            --  The parts of the name are slices of the key already in
            --  hand, and the lookup is one Find, not a Contains and then
            --  an Element repeating the same hash and comparison.
            Colon : constant Positive :=
              Key'First + Lexers.Prefix_Length (Value);
            Known : constant Prefix_Maps.Cursor :=
              Into.Prefixes.Find (Key (Key'First .. Colon - 1));
         begin
            if not Prefix_Maps.Has_Element (Known) then
               Reject (Undefined_Prefix, IRI_Production);
            end if;
            declare
               --  Admitted directly rather than through Resolve: the
               --  IRI cache there is keyed by the full expansion, and a
               --  name that missed the name cache would pay that hash
               --  only to miss again -- a prefixed name and a written-out
               --  reference to the same IRI in one document is not the
               --  case to spend the hot path on.
               Reference : constant String :=
                 Prefix_Maps.Element (Known)
                 & Key (Colon + 1 .. Key'Last);
               Admitted  : constant IRIs.IRI :=
                 (if Into.Base_Data.Is_Empty
                  then IRIs.From_UTF_8 (Reference)
                  else IRIs.Resolve (Into.Base_Data.Element, Reference));
            begin
               if Natural (Into.Name_Cache.Length) < Maximum_Cached_Names
               then
                  Into.Name_Cache.Insert (Key, Admitted);
               end if;
               return Admitted;
            end;
         exception
            when IRIs.Invalid_IRI | IRIs.Invalid_UTF_8 =>
               Reject (Invalid_IRI, IRI_Production);
               raise;
         end;
      end Expand;

      procedure Emit
        (Subject   : Terms.Term;
         Predicate : IRIs.IRI;
         Object    : Terms.Term;
         Where     : Source_Span);

      procedure Emit
        (Subject   : Terms.Term;
         Predicate : IRIs.IRI;
         Object    : Terms.Term;
         Where     : Source_Span)
      is
         Graph : constant Quads.Graph_Name :=
           (if not Into.Graph_Is_Named then Quads.Default_Graph
            elsif Into.Graph_Is_Blank
            then Quads.Blank_Node_Graph
                   (Terms.Blank_Node
                      (Unbounded.To_String (Into.Current_Graph)))
            else Quads.IRI_Graph
                   (IRIs.From_UTF_8
                      (Unbounded.To_String (Into.Current_Graph))));
      begin
         Into.Quad_Count := Into.Quad_Count + 1;
         if Into.Limits_Data.Maximum_Quads /= 0
           and then Into.Quad_Count > Into.Limits_Data.Maximum_Quads
         then
            Reject (Quad_Limit, Statement_Production);
         end if;
         Into.Work_Data.Statements_Parsed :=
           Into.Work_Data.Statements_Parsed + 1;
         On_Quad (Target, Quads.Create (Graph, Subject, Predicate, Object),
                  Where);
      end Emit;

      function Parse_Object_Term return Terms.Term;
      function Parse_Subject_Term return Terms.Term;
      procedure Parse_Predicate_Object_List (Subject : Terms.Term);

      --  ( a b c ) expands to a chain of rdf:first / rdf:rest cells.
      function Parse_Collection return Terms.Term;

      function Parse_Collection return Terms.Term is
         Head    : Terms.Term := Terms.IRI_Term (RDF_Nil_IRI);
         Started : Boolean := False;
         Last    : Terms.Term := Head;
         Where   : constant Source_Span := Token_Span (Tokens (Cur));
      begin
         Enter_Nesting;
         Expect (Lexers.Open_Paren_Token, Collection_Production);

         while not At_End
           and then Peek_Kind /= Lexers.Close_Paren_Token
         loop
            declare
               Cell    : constant Terms.Term :=
                 Terms.Blank_Node (Fresh_Blank_Label);
               Element : constant Terms.Term := Parse_Object_Term;
            begin
               Emit (Cell, RDF_First_IRI, Element, Where);
               if Started then
                  Emit (Last, RDF_Rest_IRI, Cell, Where);
               else
                  Head := Cell;
                  Started := True;
               end if;
               Last := Cell;
            end;
         end loop;

         Expect (Lexers.Close_Paren_Token, Collection_Production);
         Depth := Depth - 1;

         if Started then
            Emit (Last, RDF_Rest_IRI,
                  Terms.IRI_Term (RDF_Nil_IRI), Where);
         end if;
         return Head;
      end Parse_Collection;

      --  [ p o ; ... ] introduces a fresh blank node as its subject.
      function Parse_Property_List return Terms.Term;

      function Parse_Property_List return Terms.Term is
         Subject : constant Terms.Term :=
           Terms.Blank_Node (Fresh_Blank_Label);
      begin
         Enter_Nesting;
         Expect (Lexers.Open_Bracket_Token, Object_Production);
         if Peek_Kind /= Lexers.Close_Bracket_Token then
            Parse_Predicate_Object_List (Subject);
         end if;
         Expect (Lexers.Close_Bracket_Token, Object_Production);
         Depth := Depth - 1;
         return Subject;
      end Parse_Property_List;

      function Parse_Verb return IRIs.IRI;

      function Parse_Verb return IRIs.IRI is
      begin
         case Peek_Kind is
            when Lexers.A_Token =>
               Advance;
               return RDF_Type_IRI;
            when Lexers.IRI_Reference_Token =>
               declare
                  Value : constant IRIs.IRI :=
                    Resolve (Lexers.Text (Tokens (Cur)), Predicate_Production);
               begin
                  Advance;
                  return Value;
               end;
            when Lexers.Prefixed_Name_Token =>
               declare
                  Value : constant IRIs.IRI := Expand (Tokens (Cur));
               begin
                  Advance;
                  return Value;
               end;
            when others =>
               Reject (Malformed_Syntax, Predicate_Production);
               raise Grammar_Error;
         end case;
      end Parse_Verb;

      --  <<( s p o )>> -- a term, with no statement of its own.
      function Parse_Triple_Term return Terms.Term;

      function Parse_Triple_Term return Terms.Term is
         Subject   : Terms.Term := Terms.Blank_Node ("placeholder");
         Predicate : IRIs.IRI := RDF_Type_IRI;
         Object    : Terms.Term := Terms.Blank_Node ("placeholder");
      begin
         Enter_Nesting;
         Expect (Lexers.Open_Triple_Term_Token, Triple_Term_Production);

         --  The RDF 1.2 grammar restricts these positions: a subject is an
         --  IRI or a blank node label, and an object adds literals and
         --  nested triple terms. Collections and property lists are not
         --  admitted in either, which is the check a look-ahead parser is
         --  most likely to omit.
         case Peek_Kind is
            when Lexers.IRI_Reference_Token =>
               Subject := Terms.IRI_Term
                 (Resolve (Lexers.Text (Tokens (Cur)), Triple_Term_Production));
               Advance;
            when Lexers.Prefixed_Name_Token =>
               Subject := Terms.IRI_Term (Expand (Tokens (Cur)));
               Advance;
            when Lexers.Blank_Label_Token =>
               Subject := Terms.Blank_Node
                 (Document_Blank_Label (Lexers.Text (Tokens (Cur))));
               Advance;
            when others =>
               Reject (Malformed_Syntax, Triple_Term_Production);
         end case;

         Predicate := Parse_Verb;

         case Peek_Kind is
            when Lexers.IRI_Reference_Token | Lexers.Prefixed_Name_Token
               | Lexers.Blank_Label_Token | Lexers.String_Token
               | Lexers.Integer_Token | Lexers.Decimal_Token
               | Lexers.Double_Token | Lexers.Boolean_Token
               | Lexers.Open_Triple_Term_Token =>
               Object := Parse_Object_Term;
            when others =>
               Reject (Malformed_Syntax, Triple_Term_Production);
         end case;

         Expect (Lexers.Close_Triple_Term_Token, Triple_Term_Production);
         Depth := Depth - 1;
         return Terms.Triple_Term (Subject, Predicate, Object);
      exception
         when Terms.Term_Limit_Error =>
            --  The term model bounds nesting and payload on its own; a
            --  caller who raises Maximum_Nesting past those bounds gets a
            --  diagnostic here rather than an exception.
            Reject (Nesting_Limit, Triple_Term_Production);
            raise Grammar_Error;
      end Parse_Triple_Term;

      --  A reifier names the reifying node; an absent one gets a fresh
      --  blank node. Only an IRI or a blank node may name it.
      function Parse_Reifier return Terms.Term;

      function Parse_Reifier return Terms.Term is
      begin
         Expect (Lexers.Reifier_Token, Statement_Production);
         case Peek_Kind is
            when Lexers.IRI_Reference_Token =>
               return Result : constant Terms.Term :=
                 Terms.IRI_Term
                   (Resolve (Lexers.Text (Tokens (Cur)), Statement_Production))
               do
                  Advance;
               end return;
            when Lexers.Prefixed_Name_Token =>
               return Result : constant Terms.Term :=
                 Terms.IRI_Term (Expand (Tokens (Cur)))
               do
                  Advance;
               end return;
            when Lexers.Blank_Label_Token =>
               return Result : constant Terms.Term :=
                 Terms.Blank_Node
                   (Document_Blank_Label (Lexers.Text (Tokens (Cur))))
               do
                  Advance;
               end return;
            when Lexers.Open_Bracket_Token =>
               --  "~[]" names the reifier with an ANON, which the grammar
               --  admits wherever it admits a blank node. The brackets
               --  must be empty: a property list would be stating things
               --  about the reifier, which the production does not allow.
               Advance;
               if Peek_Kind /= Lexers.Close_Bracket_Token then
                  Reject (Malformed_Syntax, Annotation_Production);
               end if;
               return Result : constant Terms.Term :=
                 Terms.Blank_Node (Fresh_Blank_Label)
               do
                  Advance;
               end return;
            when others =>
               return Terms.Blank_Node (Fresh_Blank_Label);
         end case;
      end Parse_Reifier;

      --  << s p o ~r >> reifies: it states the triple and names it.
      function Parse_Reified_Triple return Terms.Term;

      function Parse_Reified_Triple return Terms.Term is
         Where     : constant Source_Span := Token_Span (Tokens (Cur));
         Subject   : Terms.Term := Terms.Blank_Node ("placeholder");
         Predicate : IRIs.IRI := RDF_Type_IRI;
         Object    : Terms.Term := Terms.Blank_Node ("placeholder");
         Node      : Terms.Term := Terms.Blank_Node ("placeholder");
      begin
         Enter_Nesting;
         Expect (Lexers.Open_Quoted_Token, Statement_Production);

         case Peek_Kind is
            when Lexers.IRI_Reference_Token =>
               Subject := Terms.IRI_Term
                 (Resolve (Lexers.Text (Tokens (Cur)), Subject_Production));
               Advance;
            when Lexers.Prefixed_Name_Token =>
               Subject := Terms.IRI_Term (Expand (Tokens (Cur)));
               Advance;
            when Lexers.Blank_Label_Token =>
               Subject := Terms.Blank_Node
                 (Document_Blank_Label (Lexers.Text (Tokens (Cur))));
               Advance;
            when Lexers.Open_Quoted_Token =>
               Subject := Parse_Reified_Triple;
            when Lexers.Open_Bracket_Token =>
               --  "[]" is the anonymous blank node; a property list with
               --  content is a different production and not admitted here.
               if Next + 1 > Last
                 or else Lexers.Kind (Tokens (Next + 1))
                         /= Lexers.Close_Bracket_Token
               then
                  Reject (Malformed_Syntax, Subject_Production);
               end if;
               Advance;
               Advance;
               Subject := Terms.Blank_Node (Fresh_Blank_Label);
            when others =>
               Reject (Malformed_Syntax, Subject_Production);
         end case;

         Predicate := Parse_Verb;

         --  The object of a reified triple is narrower than an object in
         --  general: a collection or a property list is not admitted here.
         --  Reaching for the general routine is what lets those through.
         case Peek_Kind is
            when Lexers.IRI_Reference_Token | Lexers.Prefixed_Name_Token
               | Lexers.Blank_Label_Token | Lexers.String_Token
               | Lexers.Integer_Token | Lexers.Decimal_Token
               | Lexers.Double_Token | Lexers.Boolean_Token
               | Lexers.Open_Triple_Term_Token | Lexers.Open_Quoted_Token =>
               Object := Parse_Object_Term;
            when Lexers.Open_Bracket_Token =>
               if Next + 1 > Last
                 or else Lexers.Kind (Tokens (Next + 1))
                         /= Lexers.Close_Bracket_Token
               then
                  Reject (Malformed_Syntax, Object_Production);
               end if;
               Advance;
               Advance;
               Object := Terms.Blank_Node (Fresh_Blank_Label);
            when others =>
               Reject (Malformed_Syntax, Object_Production);
         end case;

         if Peek_Kind = Lexers.Reifier_Token then
            Node := Parse_Reifier;
         else
            Node := Terms.Blank_Node (Fresh_Blank_Label);
         end if;

         Expect (Lexers.Close_Quoted_Token, Statement_Production);
         Depth := Depth - 1;

         Emit (Node, RDF_Reifies_IRI,
               Terms.Triple_Term (Subject, Predicate, Object), Where);
         return Node;
      exception
         when Terms.Term_Limit_Error =>
            Reject (Nesting_Limit, Statement_Production);
            raise Grammar_Error;
      end Parse_Reified_Triple;

      function Parse_Literal return Terms.Term;

      function Parse_Literal return Terms.Term is
         Value : Lexers.Token renames Tokens (Next);
      begin
         case Lexers.Kind (Value) is
            when Lexers.Integer_Token =>
               Advance;
               return Terms.Literal
                 (Lexers.Text (Value), XSD_Integer_IRI);
            when Lexers.Decimal_Token =>
               Advance;
               return Terms.Literal
                 (Lexers.Text (Value), XSD_Decimal_IRI);
            when Lexers.Double_Token =>
               Advance;
               return Terms.Literal
                 (Lexers.Text (Value), XSD_Double_IRI);
            when Lexers.Boolean_Token =>
               Advance;
               return Terms.Literal
                 (Lexers.Text (Value), XSD_Boolean_IRI);
            when Lexers.String_Token =>
               Advance;
               --  A language tag, a datatype, or neither.
               if Peek_Kind = Lexers.Language_Token then
                  declare
                     Tag : Lexers.Token renames Tokens (Next);
                  begin
                     Advance;
                     if Lexers.Has_Direction (Tag) then
                        return Terms.Directional_Literal
                          (Lexers.Text (Value), Lexers.Text (Tag),
                           (if Lexers.Direction (Tag) = Lexers.Left_To_Right
                            then Terms.Left_To_Right
                            else Terms.Right_To_Left));
                     end if;
                     return Terms.Language_Literal
                       (Lexers.Text (Value), Lexers.Text (Tag));
                  end;
               elsif Peek_Kind = Lexers.Datatype_Token then
                  Advance;
                  case Peek_Kind is
                     when Lexers.IRI_Reference_Token =>
                        declare
                           Datatype : constant IRIs.IRI :=
                             Resolve (Lexers.Text (Tokens (Cur)),
                                      Literal_Production);
                        begin
                           Advance;
                           return Terms.Literal
                             (Lexers.Text (Value), Datatype);
                        end;
                     when Lexers.Prefixed_Name_Token =>
                        declare
                           Datatype : constant IRIs.IRI := Expand (Tokens (Cur));
                        begin
                           Advance;
                           return Terms.Literal
                             (Lexers.Text (Value), Datatype);
                        end;
                     when others =>
                        Reject (Malformed_Syntax, Literal_Production);
                  end case;
               end if;
               return Terms.Literal
                 (Lexers.Text (Value), XSD_String_IRI);
            when others =>
               Reject (Malformed_Syntax, Literal_Production);
         end case;
         raise Grammar_Error;
      exception
         when Terms.Invalid_Literal | Terms.Invalid_Language_Tag =>
            --  Grammar-shaped tokens can still name a literal the model
            --  refuses: a language tag outside the well-formed shape, or
            --  rdf:langString written as an explicit datatype. Both are
            --  rejections of the document, not failures of the parser.
            Reject (Malformed_Syntax, Literal_Production);
            raise Grammar_Error;
      end Parse_Literal;

      function Parse_Object_Term return Terms.Term is
      begin
         case Peek_Kind is
            when Lexers.IRI_Reference_Token =>
               return Result : constant Terms.Term :=
                 Terms.IRI_Term
                   (Resolve (Lexers.Text (Tokens (Cur)), Object_Production))
               do
                  Advance;
               end return;
            when Lexers.Prefixed_Name_Token =>
               return Result : constant Terms.Term :=
                 Terms.IRI_Term (Expand (Tokens (Cur)))
               do
                  Advance;
               end return;
            when Lexers.Blank_Label_Token =>
               return Result : constant Terms.Term :=
                 Terms.Blank_Node
                   (Document_Blank_Label (Lexers.Text (Tokens (Cur))))
               do
                  Advance;
               end return;
            when Lexers.String_Token | Lexers.Integer_Token
               | Lexers.Decimal_Token | Lexers.Double_Token
               | Lexers.Boolean_Token =>
               return Parse_Literal;
            when Lexers.Open_Paren_Token =>
               return Parse_Collection;
            when Lexers.Open_Bracket_Token =>
               return Parse_Property_List;
            when Lexers.Open_Triple_Term_Token =>
               return Parse_Triple_Term;
            when Lexers.Open_Quoted_Token =>
               return Parse_Reified_Triple;
            when others =>
               Reject (Malformed_Syntax, Object_Production);
               raise Grammar_Error;
         end case;
      end Parse_Object_Term;

      function Parse_Subject_Term return Terms.Term is
      begin
         case Peek_Kind is
            when Lexers.IRI_Reference_Token =>
               return Result : constant Terms.Term :=
                 Terms.IRI_Term
                   (Resolve (Lexers.Text (Tokens (Cur)), Subject_Production))
               do
                  Advance;
               end return;
            when Lexers.Prefixed_Name_Token =>
               return Result : constant Terms.Term :=
                 Terms.IRI_Term (Expand (Tokens (Cur)))
               do
                  Advance;
               end return;
            when Lexers.Blank_Label_Token =>
               return Result : constant Terms.Term :=
                 Terms.Blank_Node
                   (Document_Blank_Label (Lexers.Text (Tokens (Cur))))
               do
                  Advance;
               end return;
            when Lexers.Open_Paren_Token =>
               return Parse_Collection;
            when Lexers.Open_Bracket_Token =>
               return Parse_Property_List;
            when Lexers.Open_Quoted_Token =>
               return Parse_Reified_Triple;
            when others =>
               Reject (Malformed_Syntax, Subject_Production);
               raise Grammar_Error;
         end case;
      end Parse_Subject_Term;

      --  An annotation restates the preceding triple about its reifier.
      procedure Parse_Annotation
        (Subject   : Terms.Term;
         Predicate : IRIs.IRI;
         Object    : Terms.Term;
         Where     : Source_Span);

      procedure Parse_Annotation
        (Subject   : Terms.Term;
         Predicate : IRIs.IRI;
         Object    : Terms.Term;
         Where     : Source_Span) is
      begin
         while Peek_Kind in Lexers.Reifier_Token
                          | Lexers.Open_Annotation_Token
         loop
            declare
               Node : Terms.Term := Terms.Blank_Node ("placeholder");
            begin
               if Peek_Kind = Lexers.Reifier_Token then
                  Node := Parse_Reifier;
               else
                  Node := Terms.Blank_Node (Fresh_Blank_Label);
               end if;

               Emit (Node, RDF_Reifies_IRI,
                     Terms.Triple_Term (Subject, Predicate, Object), Where);

               if Peek_Kind = Lexers.Open_Annotation_Token then
                  Enter_Nesting;
                  Advance;
                  Parse_Predicate_Object_List (Node);
                  Expect (Lexers.Close_Annotation_Token,
                          Annotation_Production);
                  Depth := Depth - 1;
               end if;
            end;
         end loop;
      end Parse_Annotation;

      procedure Parse_Object_List
        (Subject   : Terms.Term;
         Predicate : IRIs.IRI);

      procedure Parse_Object_List
        (Subject   : Terms.Term;
         Predicate : IRIs.IRI) is
      begin
         loop
            declare
               Where  : constant Source_Span := Token_Span (Tokens (Cur));
               Object : constant Terms.Term := Parse_Object_Term;
            begin
               Emit (Subject, Predicate, Object, Where);
               Parse_Annotation (Subject, Predicate, Object, Where);
            end;
            exit when Peek_Kind /= Lexers.Comma_Token;
            Advance;
         end loop;
      end Parse_Object_List;

      procedure Parse_Predicate_Object_List (Subject : Terms.Term) is
      begin
         loop
            declare
               Predicate : constant IRIs.IRI := Parse_Verb;
            begin
               Parse_Object_List (Subject, Predicate);
            end;

            exit when Peek_Kind /= Lexers.Semicolon_Token;
            while Peek_Kind = Lexers.Semicolon_Token loop
               Advance;
            end loop;
            --  A trailing semicolon is permitted.
            exit when At_End
              or else Peek_Kind in Lexers.Dot_Token
                                 | Lexers.Close_Bracket_Token
                                 | Lexers.Close_Annotation_Token
                                 | Lexers.Close_Brace_Token;
         end loop;
      end Parse_Predicate_Object_List;

      procedure Parse_Directive;

      procedure Parse_Directive is
      begin
         case Peek_Kind is
            when Lexers.Prefix_Directive_Token
               | Lexers.Sparql_Prefix_Token =>
               declare
                  Terminated : constant Boolean :=
                    Peek_Kind = Lexers.Prefix_Directive_Token;
                  Name       : Unbounded.Unbounded_String;
               begin
                  Advance;
                  if Peek_Kind /= Lexers.Prefixed_Name_Token
                    or else Lexers.Text (Tokens (Cur)) /= ""
                  then
                     Reject (Malformed_Syntax, Directive_Production);
                  end if;
                  Name :=
                    Unbounded.To_Unbounded_String (Lexers.Prefix (Tokens (Cur)));
                  Advance;

                  if Peek_Kind /= Lexers.IRI_Reference_Token then
                     Reject (Malformed_Syntax, Directive_Production);
                  end if;
                  declare
                     Target_IRI : constant IRIs.IRI :=
                       Resolve (Lexers.Text (Tokens (Cur)), Directive_Production);
                  begin
                     Advance;
                     if Into.Limits_Data.Maximum_Prefixes /= 0
                       and then not Into.Prefixes.Contains
                                      (Unbounded.To_String (Name))
                       and then Natural (Into.Prefixes.Length)
                                >= Into.Limits_Data.Maximum_Prefixes
                     then
                        Reject (Prefix_Limit, Directive_Production);
                     end if;
                     Into.Prefixes.Include
                       (Unbounded.To_String (Name),
                        IRIs.To_UTF_8 (Target_IRI));
                     --  What a cached name means was decided by the
                     --  binding in force when it was admitted.
                     Into.Name_Cache.Clear;
                  end;

                  if Terminated then
                     Expect (Lexers.Dot_Token, Directive_Production);
                  end if;
               end;

            when Lexers.Base_Directive_Token | Lexers.Sparql_Base_Token =>
               declare
                  Terminated : constant Boolean :=
                    Peek_Kind = Lexers.Base_Directive_Token;
               begin
                  Advance;
                  if Peek_Kind /= Lexers.IRI_Reference_Token then
                     Reject (Malformed_Syntax, Directive_Production);
                  end if;
                  declare
                     Target_IRI : constant IRIs.IRI :=
                       Resolve (Lexers.Text (Tokens (Cur)), Directive_Production);
                  begin
                     Advance;
                     Into.Base_Data := IRI_Holders.To_Holder (Target_IRI);
                     --  What is cached was resolved against the
                     --  old base, so none of it survives a new one.
                     Into.IRI_Cache.Clear;
                  end;
                  if Terminated then
                     Expect (Lexers.Dot_Token, Directive_Production);
                  end if;
               end;

            when Lexers.Version_Directive_Token =>
               declare
                  Terminated : constant Boolean :=
                    Lexers.Text (Tokens (Cur)) = "@version";
               begin
                  Advance;
                  if Peek_Kind /= Lexers.String_Token then
                     Reject (Malformed_Syntax, Directive_Production);
                  elsif Lexers.Form (Tokens (Cur)) = Lexers.Long_Quoted then
                     --  A version is a short-quoted string; the long form
                     --  is admitted elsewhere but not here.
                     Reject (Malformed_Syntax, Directive_Production);
                  end if;
                  Advance;
                  if Terminated then
                     Expect (Lexers.Dot_Token, Directive_Production);
                  end if;
               end;

            when others =>
               Reject (Malformed_Syntax, Directive_Production);
         end case;
      end Parse_Directive;

      --  N-Triples and N-Quads: one statement per line, every IRI absolute,
      --  no abbreviation of any kind. Only the term positions differ from
      --  the general grammar, and they differ by being narrower, so this is
      --  written out rather than expressed as restrictions on the general
      --  routines -- a narrower grammar sharing a wider implementation is
      --  how false accepts get in.
      procedure Parse_Line_Statement;

      procedure Parse_Line_Statement is

         function Absolute (What : Production_Kind) return IRIs.IRI;

         function Absolute (What : Production_Kind) return IRIs.IRI is
         begin
            --  No base applies: these grammars require the IRI as written
            --  to be absolute.
            if not IRIs.Is_Valid (Lexers.Text (Tokens (Cur))) then
               Reject (Invalid_IRI, What);
            end if;
            return Result : constant IRIs.IRI :=
              IRIs.From_UTF_8 (Lexers.Text (Tokens (Cur)))
            do
               Advance;
            end return;
         end Absolute;

         function Line_Term
           (What          : Production_Kind;
            Allow_Literal : Boolean) return Terms.Term;

         function Line_Term
           (What          : Production_Kind;
            Allow_Literal : Boolean) return Terms.Term is
         begin
            case Peek_Kind is
               when Lexers.IRI_Reference_Token =>
                  return Terms.IRI_Term (Absolute (What));
               when Lexers.Blank_Label_Token =>
                  return Result : constant Terms.Term :=
                    Terms.Blank_Node
                      (Document_Blank_Label (Lexers.Text (Tokens (Cur))))
                  do
                     Advance;
                  end return;
               when Lexers.String_Token =>
                  if not Allow_Literal then
                     Reject (Malformed_Syntax, What);
                  elsif Lexers.Form (Tokens (Cur)) = Lexers.Long_Quoted
                    or else Lexers.Quote (Tokens (Cur)) /= '"'
                  then
                     --  The line-based grammars admit only the short
                     --  double-quoted form: neither the long form nor the
                     --  apostrophe is theirs.
                     Reject (Malformed_Syntax, Literal_Production);
                  end if;
                  return Parse_Literal;
               when Lexers.Open_Triple_Term_Token =>
                  --  A triple term is an object, never a subject or a
                  --  graph label. Allow_Literal marks the object position,
                  --  which is the same distinction.
                  if not Allow_Literal then
                     Reject (Malformed_Syntax, What);
                  end if;
                  return Parse_Triple_Term;
               when others =>
                  Reject (Malformed_Syntax, What);
                  raise Grammar_Error;
            end case;
         end Line_Term;

         function Line_Predicate return IRIs.IRI;

         function Line_Predicate return IRIs.IRI is
         begin
            if Peek_Kind /= Lexers.IRI_Reference_Token then
               Reject (Malformed_Syntax, Predicate_Production);
            end if;
            return Absolute (Predicate_Production);
         end Line_Predicate;

         Where     : constant Source_Span := Token_Span (Tokens (Cur));
         Subject   : constant Terms.Term :=
           Line_Term (Subject_Production, Allow_Literal => False);
         Predicate : constant IRIs.IRI := Line_Predicate;
         Object    : constant Terms.Term :=
           Line_Term (Object_Production, Allow_Literal => True);
      begin
         if Peek_Kind in Lexers.IRI_Reference_Token
                       | Lexers.Blank_Label_Token
         then
            if Into.Syntax_Data /= NQuads_Syntax then
               Reject (Unsupported_Production, Graph_Block_Production);
            end if;
            declare
               Name : constant Terms.Term :=
                 Line_Term (Graph_Block_Production, Allow_Literal => False);
            begin
               Into.Graph_Is_Named := True;
               Into.Graph_Is_Blank :=
                 Terms.Kind (Name) = Terms.Blank_Node_Kind;
               Into.Current_Graph := Unbounded.To_Unbounded_String
                 (if Into.Graph_Is_Blank
                  then Terms.Label (Name)
                  else IRIs.To_UTF_8 (Terms.IRI_Value (Name)));
            end;
         else
            Into.Graph_Is_Named := False;
            Into.Graph_Is_Blank := False;
         end if;

         --  The line-based grammars are line-based: a statement occupies
         --  one line, and a line holds one statement. Only spaces and tabs
         --  separate the terms, so the terminator sits on the line the
         --  subject opened, and the next statement opens on a later one.
         if Peek_Kind = Lexers.Dot_Token
           and then Lexers.Start_Position (Tokens (Cur)).Line /= Where.Start_Line
         then
            Reject (Malformed_Syntax, Statement_Production);
         end if;

         Emit (Subject, Predicate, Object, Where);
         Expect (Lexers.Dot_Token, Statement_Production);

         if Into.Line_Statement_Seen
           and then Where.Start_Line = Into.Last_Statement_Line
         then
            Reject (Malformed_Syntax, Statement_Production);
         end if;
         Into.Line_Statement_Seen := True;
         Into.Last_Statement_Line := Where.Start_Line;

         --  A graph label binds to its own statement only.
         Into.Graph_Is_Named := False;
         Into.Graph_Is_Blank := False;
      end Parse_Line_Statement;

      procedure Parse_Triples;

      procedure Parse_Triples is
      begin
         if Peek_Kind = Lexers.Open_Bracket_Token then
            --  A property list may stand alone as a statement, with or
            --  without further predicates attached to it -- but only
            --  because reading it stated something. An empty "[]" is an
            --  ANON, an ordinary subject, and a subject on its own is not
            --  a statement. Counting what reading it contributed tells
            --  the two apart.
            declare
               Before  : constant Natural := Into.Quad_Count;
               Subject : constant Terms.Term := Parse_Property_List;
            begin
               if Peek_Kind not in Lexers.Dot_Token
                                 | Lexers.Close_Brace_Token
                 and then not At_End
               then
                  Parse_Predicate_Object_List (Subject);
               elsif Into.Quad_Count = Before then
                  Reject (Malformed_Syntax, Statement_Production);
               end if;
            end;
         else
            declare
               Quoted  : constant Boolean :=
                 Peek_Kind = Lexers.Open_Quoted_Token;
               Subject : constant Terms.Term := Parse_Subject_Term;
            begin
               --  A reified triple states something on its own, so it may
               --  stand as a whole statement with no predicates after it.
               if not (Quoted
                       and then Peek_Kind in Lexers.Dot_Token
                                           | Lexers.Close_Brace_Token)
               then
                  Parse_Predicate_Object_List (Subject);
               end if;
            end;
         end if;
         if Peek_Kind = Lexers.Close_Brace_Token then
            --  The terminator was omitted before the closing brace, which
            --  TriG permits for the last statement of a block. The brace
            --  closes the block as well as ending the statement.
            if not Into.In_Graph_Block then
               Reject (Malformed_Syntax, Graph_Block_Production);
            end if;
            Advance;
            Into.In_Graph_Block := False;
            Into.Graph_Is_Named := False;
            Into.Graph_Is_Blank := False;
         else
            Expect (Lexers.Dot_Token, Statement_Production);
         end if;
      end Parse_Triples;

   begin
      Failed := False;
      Failure :=
        (Code_Value       => Malformed_Syntax,
         Production_Value => Document_Production,
         Span_Value       => <>,
         Source_Value     => Into.Source_Data);

      if Last = 0 then
         return;
      end if;

      if Is_Line_Based (Into.Syntax_Data) then
         Parse_Line_Statement;
         if not At_End then
            Reject (Malformed_Syntax, Statement_Production);
         end if;
         return;
      end if;

      case Lexers.Kind (Tokens (Next)) is
         when Lexers.Prefix_Directive_Token | Lexers.Base_Directive_Token
            | Lexers.Sparql_Prefix_Token | Lexers.Sparql_Base_Token
            | Lexers.Version_Directive_Token =>
            if Into.In_Graph_Block then
               --  A directive is a document-level statement; inside a
               --  graph block it is not a statement at all.
               Reject (Malformed_Syntax, Graph_Block_Production);
            end if;
            Parse_Directive;

         when Lexers.Graph_Token =>
            if Into.Syntax_Data = Turtle_Syntax then
               Reject (Unsupported_Production, Graph_Block_Production);
            end if;
            if Into.In_Graph_Block then
               --  Graph blocks do not nest.
               Reject (Malformed_Syntax, Graph_Block_Production);
            end if;
            declare
               Where : constant Source_Span := Token_Span (Tokens (Cur));
            begin
               Advance;
               case Peek_Kind is
                  when Lexers.IRI_Reference_Token =>
                     Into.Current_Graph := Unbounded.To_Unbounded_String
                       (IRIs.To_UTF_8
                          (Resolve (Lexers.Text (Tokens (Cur)),
                                    Graph_Block_Production)));
                     Into.Graph_Is_Blank := False;
                     Advance;
                  when Lexers.Prefixed_Name_Token =>
                     Into.Current_Graph := Unbounded.To_Unbounded_String
                       (IRIs.To_UTF_8 (Expand (Tokens (Cur))));
                     Into.Graph_Is_Blank := False;
                     Advance;
                  when Lexers.Blank_Label_Token =>
                     Into.Current_Graph := Unbounded.To_Unbounded_String
                       (Document_Blank_Label (Lexers.Text (Tokens (Cur))));
                     Into.Graph_Is_Blank := True;
                     Advance;
                  when Lexers.Open_Bracket_Token =>
                     Advance;
                     Expect (Lexers.Close_Bracket_Token,
                             Graph_Block_Production);
                     Into.Current_Graph :=
                       Unbounded.To_Unbounded_String (Fresh_Blank_Label);
                     Into.Graph_Is_Blank := True;
                  when others =>
                     Reject (Malformed_Syntax, Graph_Block_Production);
               end case;
               Into.Graph_Is_Named := True;
               Expect (Lexers.Open_Brace_Token, Graph_Block_Production);
               Into.In_Graph_Block := True;

               On_Graph_Declaration
                 (Target,
                  (if Into.Graph_Is_Blank
                   then Quads.Blank_Node_Graph
                          (Terms.Blank_Node
                             (Unbounded.To_String (Into.Current_Graph)))
                   else Quads.IRI_Graph
                          (IRIs.From_UTF_8
                             (Unbounded.To_String (Into.Current_Graph)))),
                  Where);
            end;

         when Lexers.Open_Brace_Token =>
            if Into.Syntax_Data = Turtle_Syntax then
               Reject (Unsupported_Production, Graph_Block_Production);
            end if;
            if Into.In_Graph_Block then
               --  Graph blocks do not nest.
               Reject (Malformed_Syntax, Graph_Block_Production);
            end if;
            Advance;
            Into.Graph_Is_Named := False;
            Into.Graph_Is_Blank := False;
            Into.In_Graph_Block := True;

         when Lexers.Close_Brace_Token =>
            if not Into.In_Graph_Block then
               Reject (Malformed_Syntax, Graph_Block_Production);
            end if;
            Advance;
            Into.In_Graph_Block := False;
            Into.Graph_Is_Named := False;
            Into.Graph_Is_Blank := False;

         when Lexers.IRI_Reference_Token | Lexers.Prefixed_Name_Token
            | Lexers.Blank_Label_Token | Lexers.Open_Bracket_Token =>
            if (Peek_Kind = Lexers.Open_Bracket_Token
                and then Next + 2 <= Last
                and then Lexers.Kind (Tokens (Next + 1))
                         = Lexers.Close_Bracket_Token
                and then Lexers.Kind (Tokens (Next + 2))
                         = Lexers.Open_Brace_Token)
              or else (Peek_Kind /= Lexers.Open_Bracket_Token
                       and then Next + 1 <= Last
                       and then Lexers.Kind (Tokens (Next + 1))
                                = Lexers.Open_Brace_Token)
            then
               --  A labelled graph block, written without the keyword.
               if Into.Syntax_Data /= TriG_Syntax then
                  Reject (Unsupported_Production, Graph_Block_Production);
               end if;
               if Into.In_Graph_Block then
                  --  Graph blocks do not nest.
                  Reject (Malformed_Syntax, Graph_Block_Production);
               end if;
               declare
                  Where : constant Source_Span := Token_Span (Tokens (Cur));
               begin
                  case Peek_Kind is
                     when Lexers.IRI_Reference_Token =>
                        Into.Current_Graph := Unbounded.To_Unbounded_String
                          (IRIs.To_UTF_8
                             (Resolve (Lexers.Text (Tokens (Cur)),
                                       Graph_Block_Production)));
                        Into.Graph_Is_Blank := False;
                     when Lexers.Prefixed_Name_Token =>
                        Into.Current_Graph := Unbounded.To_Unbounded_String
                          (IRIs.To_UTF_8 (Expand (Tokens (Cur))));
                        Into.Graph_Is_Blank := False;
                     when Lexers.Open_Bracket_Token =>
                        Advance;
                        Into.Current_Graph :=
                          Unbounded.To_Unbounded_String (Fresh_Blank_Label);
                        Into.Graph_Is_Blank := True;
                     when others =>
                        Into.Current_Graph := Unbounded.To_Unbounded_String
                          (Document_Blank_Label (Lexers.Text (Tokens (Cur))));
                        Into.Graph_Is_Blank := True;
                  end case;
                  Advance;
                  Into.Graph_Is_Named := True;
                  Expect (Lexers.Open_Brace_Token, Graph_Block_Production);
                  Into.In_Graph_Block := True;

                  On_Graph_Declaration
                    (Target,
                     (if Into.Graph_Is_Blank
                      then Quads.Blank_Node_Graph
                             (Terms.Blank_Node
                                (Unbounded.To_String (Into.Current_Graph)))
                      else Quads.IRI_Graph
                             (IRIs.From_UTF_8
                                (Unbounded.To_String
                                   (Into.Current_Graph)))),
                     Where);
               end;
            else
               Parse_Triples;
            end if;

         when others =>
            Parse_Triples;
      end case;

      if not At_End then
         Reject (Malformed_Syntax, Statement_Production);
      end if;

   exception
      when Grammar_Error =>
         Failed := True;
      when Terms.Invalid_Term | Terms.Invalid_Literal
         | Terms.Invalid_Language_Tag | Terms.Term_Limit_Error
         | IRIs.Invalid_IRI | IRIs.Invalid_UTF_8 =>
         --  A term the model refuses on a path the wrappers above missed.
         --  The pre-initialised diagnostic carries no precise span, but an
         --  escaped exception would abandon the parse state entirely.
         Failed := True;
   end Parse_Statement;

   ----------------------------------------------------------------------
   --  Feeding
   ----------------------------------------------------------------------

   --  A statement is complete at a '.' outside every bracket, at the brace
   --  that closes a graph block, or at the operand that ends a
   --  SPARQL-style directive, which carries no terminator of its own.
   --
   --  Called once per token as it is appended to the retained statement,
   --  and maintains the parser's running view of that statement -- its
   --  bracket depth and its leading token kinds -- so the decision is made
   --  from the newest token alone. Whenever it reports completion the
   --  statement is parsed and cleared, so a condition that holds is acted
   --  on at the first token that establishes it, exactly as a re-walk of
   --  the whole statement would have found it.
   procedure Note_Statement_Token
     (Into     : in out Parser;
      Value    : Lexers.Token;
      Complete : out Boolean);

   procedure Note_Statement_Token
     (Into     : in out Parser;
      Value    : Lexers.Token;
      Complete : out Boolean)
   is
      Kind   : constant Lexers.Token_Kind := Lexers.Kind (Value);
      Length : constant Natural := Into.Statement.Count;
   begin
      Complete := False;

      if Length = 1 then
         Into.First_Kind := Kind;
         Into.Second_Kind := Lexers.Dot_Token;
         Into.Statement_Depth := 0;
         --  The at-form carries a terminator; the keyword form does not.
         Into.First_Is_Terminated_Version :=
           Kind = Lexers.Version_Directive_Token
           and then Lexers.Text (Value) = "@version";
      elsif Length = 2 then
         Into.Second_Kind := Kind;
      end if;

      --  TriG names a graph either with the GRAPH keyword or by writing
      --  the label directly before the brace. The second form has to be
      --  recognised here or the brace never ends a statement and the dot
      --  inside the block ends it instead.
      if Length = 2
        and then Into.First_Kind in Lexers.IRI_Reference_Token
                                  | Lexers.Prefixed_Name_Token
                                  | Lexers.Blank_Label_Token
        and then Kind = Lexers.Open_Brace_Token
      then
         Complete := True;
         return;
      end if;

      --  The same, with an anonymous node: "[] { ... }".
      if Length = 3
        and then Into.First_Kind = Lexers.Open_Bracket_Token
        and then Into.Second_Kind = Lexers.Close_Bracket_Token
        and then Kind = Lexers.Open_Brace_Token
      then
         Complete := True;
         return;
      end if;

      case Into.First_Kind is
         when Lexers.Sparql_Prefix_Token =>
            Complete := Length = 3;
            return;
         when Lexers.Sparql_Base_Token =>
            Complete := Length = 2;
            return;
         when Lexers.Version_Directive_Token =>
            Complete :=
              Length = (if Into.First_Is_Terminated_Version then 3 else 2);
            return;
         when Lexers.Open_Brace_Token | Lexers.Close_Brace_Token =>
            Complete := True;
            return;
         when Lexers.Graph_Token =>
            Complete := Kind = Lexers.Open_Brace_Token;
            return;
         when others =>
            null;
      end case;

      case Kind is
         when Lexers.Open_Paren_Token | Lexers.Open_Bracket_Token
            | Lexers.Open_Quoted_Token | Lexers.Open_Triple_Term_Token
            | Lexers.Open_Annotation_Token =>
            Into.Statement_Depth := Into.Statement_Depth + 1;
         when Lexers.Close_Paren_Token | Lexers.Close_Bracket_Token
            | Lexers.Close_Quoted_Token | Lexers.Close_Triple_Term_Token
            | Lexers.Close_Annotation_Token =>
            Into.Statement_Depth := Into.Statement_Depth - 1;
         when Lexers.Dot_Token =>
            Complete := Into.Statement_Depth <= 0;
         when Lexers.Close_Brace_Token =>
            --  TriG lets the last statement in a graph block omit its
            --  terminator, so the closing brace ends the statement too.
            Complete := Into.Statement_Depth <= 0;
         when others =>
            null;
      end case;
   end Note_Statement_Token;

   procedure Deliver
     (Into   : in out Parser;
      Target : in out Event_Sink'Class;
      Ended  : Boolean);

   procedure Deliver
     (Into   : in out Parser;
      Target : in out Event_Sink'Class;
      Ended  : Boolean)
   is
      Text     : String renames Into.Pending.Data (1 .. Into.Pending.Count);
      Position : Cursors.Cursor_State := Into.Pending_Origin;
      Index    : Positive := Text'First;
      Status   : Lexers.Scan_Status;
      Error    : Lexers.Scan_Error_Kind;

      Consumed_Index    : Positive := Text'First;
      Consumed_Position : Cursors.Cursor_State := Into.Pending_Origin;

      procedure Report (Why : Diagnostic_Code; Where : Source_Span);

      procedure Report (Why : Diagnostic_Code; Where : Source_Span) is
         Failure : constant Parse_Diagnostic :=
           (Code_Value       => Why,
            Production_Value => Document_Production,
            Span_Value       => Where,
            Source_Value     => Into.Source_Data);
      begin
         Into.Failed := True;
         On_Diagnostic (Target, Failure);
      end Report;

   begin
      loop
         exit when Into.Failed;

         Ensure_Token_Room (Into.Statement);

         declare
            --  The scanner builds the token in the slot it will occupy,
            --  so completing one appends nothing and copies nothing. The
            --  slot only becomes part of the statement below, when the
            --  scan reports Token_Found.
            Result : Lexers.Token renames
              Into.Statement.Data (Into.Statement.Count + 1);
         begin
         declare
            Walked_From : constant Positive := Index;
         begin
            Lexers.Scan
              (Text, Position, Index, Ended, Result, Status, Error);

            --  An incomplete token means the scanner reached the end of
            --  what it had. It walked every byte from where it started
            --  to get there, and will walk them again next time.
            Into.Work_Data.Bytes_Scanned :=
              Into.Work_Data.Bytes_Scanned
              + Work_Count
                  (if Status = Lexers.Needs_More_Input
                   then Natural'Max (0, Text'Last - Walked_From + 1)
                   else Index - Walked_From);
         end;

         if Into.Checkpoint /= null then
            Into.Work_Units := Into.Work_Units + 1;
            if Into.Work_Units >= Work_Checkpoint_Interval then
               Into.Work_Units := 0;
               Into.Work_Data.Checkpoint_Calls :=
                 Into.Work_Data.Checkpoint_Calls + 1;
               Into.Checkpoint.all;
            end if;
         end if;

         case Status is
            when Lexers.Token_Found =>
               Consumed_Index := Index;
               Consumed_Position := Position;
               Into.Work_Data.Tokens_Scanned :=
                 Into.Work_Data.Tokens_Scanned + 1;

               if Lexers.Text_Length (Result)
                  > Into.Limits_Data.Maximum_Token_Bytes
               then
                  Report (Token_Limit, Token_Span (Result));
                  exit;
               end if;

               Into.Statement.Count := Into.Statement.Count + 1;
               Into.Work_Data.Maximum_Pending_Tokens :=
                 Work_Count'Max (Into.Work_Data.Maximum_Pending_Tokens,
                                 Work_Count (Into.Statement.Count));

               declare
                  Complete : Boolean;
               begin
                  Note_Statement_Token (Into, Result, Complete);
                  if Complete then
                     declare
                        Failure : Parse_Diagnostic;
                        Bad     : Boolean;
                     begin
                        Parse_Statement (Into, Target, Failure, Bad);
                        Into.Statement.Count := 0;
                        if Bad then
                           Into.Failed := True;
                           On_Diagnostic (Target, Failure);
                           exit;
                        end if;
                     end;
                  end if;
               end;

            when Lexers.Needs_More_Input =>
               if Ended then
                  --  The scanner wants bytes that will never arrive, so
                  --  the document ends inside a token.
                  Report (Malformed_Syntax, To_Span (Position, Position));
               end if;
               exit;

            when Lexers.End_Of_Input =>
               Consumed_Index := Index;
               Consumed_Position := Position;
               exit;

            when Lexers.Scan_Error =>
               Report
                 ((case Error is
                     when Lexers.Invalid_Encoding => Invalid_Encoding,
                     when others                  => Malformed_Syntax),
                  To_Span (Position, Position));
               exit;
         end case;
         end;
      end loop;

      --  Retain only what has not been consumed. Whitespace and completed
      --  tokens are dropped, so the buffer holds at most one partial token.
      --
      --  That partial token is bounded here rather than when it finishes.
      --  A token that never finishes never reached the check below, so an
      --  unterminated string or comment was retained whole and rescanned
      --  from its first byte on every chunk: time quadratic in what had
      --  arrived, and a buffer that grew to the byte limit however small
      --  the token limit was set.
      if not Into.Failed
        and then Text'Last - Consumed_Index + 1
                 > Into.Limits_Data.Maximum_Token_Bytes
      then
         Report (Token_Limit, To_Span (Consumed_Position, Position));
         Into.Pending.Count := 0;
         Into.Pending_Origin := Consumed_Position;
         return;
      end if;

      declare
         Kept : constant Natural := Text'Last - Consumed_Index + 1;
      begin
         --  Slide the unconsumed tail to the front of the buffer it is
         --  already in; the next Feed appends after it.
         if Kept > 0 and then Consumed_Index > 1 then
            Into.Pending.Data (1 .. Kept) :=
              Into.Pending.Data (Consumed_Index .. Text'Last);
         end if;
         Into.Pending.Count := Kept;
      end;
      Into.Pending_Origin := Consumed_Position;
      Into.Work_Data.Maximum_Pending_Bytes :=
        Work_Count'Max (Into.Work_Data.Maximum_Pending_Bytes,
                        Work_Count (Into.Pending.Count));
   exception
      when others =>
         --  A sink callback raising must poison the parse, as the spec
         --  promises: the statement in flight was partially delivered,
         --  and replaying it on the next Feed would emit it twice.
         Into.Failed := True;
         raise;
   end Deliver;

   procedure Feed
     (Into   : in out Parser;
      Bytes  : String;
      Target : in out Event_Sink'Class) is
   begin
      if Into.Finished then
         raise Parser_State_Error with "parser has already finished";
      elsif Into.Failed then
         return;
      end if;

      Into.Work_Data.Bytes_Fed :=
        Into.Work_Data.Bytes_Fed + Work_Count (Bytes'Length);

      --  Compare against the room left rather than adding first and
      --  testing after. The sum overflows when the caller sets the limit
      --  near the top of the range, and the subtraction cannot, because
      --  Byte_Count never passes Maximum_Bytes: this test returns first.
      if Bytes'Length
         > Into.Limits_Data.Maximum_Bytes - Into.Byte_Count
      then
         Into.Failed := True;
         On_Diagnostic
           (Target,
            (Code_Value       => Byte_Limit,
             Production_Value => Document_Production,
             Span_Value       => <>,
             Source_Value     => Into.Source_Data));
         return;
      end if;

      Into.Byte_Count := Into.Byte_Count + Bytes'Length;

      Ensure_Byte_Room (Into.Pending, Bytes'Length);
      Into.Pending.Data
        (Into.Pending.Count + 1 .. Into.Pending.Count + Bytes'Length) :=
        Bytes;
      Into.Pending.Count := Into.Pending.Count + Bytes'Length;
      Deliver (Into, Target, Ended => False);
   end Feed;

   function Finish
     (Into   : in out Parser;
      Target : in out Event_Sink'Class) return Parse_Status is
   begin
      if Into.Finished then
         raise Parser_State_Error with "parser has already finished";
      end if;

      if not Into.Failed then
         Deliver (Into, Target, Ended => True);
      end if;

      Into.Finished := True;

      if not Into.Failed
        and then (Into.Statement.Count /= 0
                  or else Into.In_Graph_Block)
      then
         Into.Failed := True;
         On_Diagnostic
           (Target,
            (Code_Value       => Malformed_Syntax,
             Production_Value => Document_Production,
             Span_Value       => <>,
             Source_Value     => Into.Source_Data));
      end if;

      return (if Into.Failed then Parse_Failed else Parse_Succeeded);
   end Finish;

end Flyology_RDF.Turtle_Parsers;
