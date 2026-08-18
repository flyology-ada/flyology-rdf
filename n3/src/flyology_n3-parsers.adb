with Ada.Containers.Indefinite_Ordered_Maps;
with Ada.Containers.Indefinite_Ordered_Sets;

with Flyology_RDF.IRIs;
with Flyology_RDF.Terms;

package body Flyology_N3.Parsers is

   package Unbounded renames Ada.Strings.Unbounded;
   package IRIs renames Flyology_RDF.IRIs;
   package Lexers renames Flyology_RDF.Lexers;
   package Cursors renames Flyology_RDF.Parser_Cursors;
   package Terms renames Flyology_RDF.Terms;

   use type Lexers.Scan_Status;
   use type Lexers.Token_Kind;
   use type Lexers.Direction_Value;

   package Prefix_Maps is new Ada.Containers.Indefinite_Ordered_Maps
     (Key_Type => String, Element_Type => String);

   package Label_Sets is new Ada.Containers.Indefinite_Ordered_Sets
     (Element_Type => String);

   Log_Implies : constant String :=
     "http://www.w3.org/2000/10/swap/log#implies";
   OWL_Same_As : constant String := "http://www.w3.org/2002/07/owl#sameAs";
   RDF_Type    : constant String :=
     "http://www.w3.org/1999/02/22-rdf-syntax-ns#type";
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

   function Parse_Tokens
     (Tokens   : Token_Vectors.Vector;
      Base_IRI : String) return Model.Term;

   function Parse_Tokens
     (Tokens   : Token_Vectors.Vector;
      Base_IRI : String) return Model.Term
   is
      Next   : Positive := 1;

      Prefixes : Prefix_Maps.Map;
      Base     : Unbounded.Unbounded_String :=
        Unbounded.To_Unbounded_String (Base_IRI);

      --  Labels the document wrote itself, so a generated one never
      --  collides with them.
      Document_Labels : Label_Sets.Set;
      Blank_Counter   : Natural := 0;

      procedure Fail (Message : String);

      procedure Fail (Message : String) is
         Where : constant Cursors.Cursor_State :=
           (if Next <= Tokens.Last_Index
            then Lexers.Start_Position (Tokens (Next))
            elsif not Tokens.Is_Empty
            then Lexers.End_Position (Tokens.Last_Element)
            else Cursors.Initial_State);
      begin
         raise Parse_Error with
           Message & " at line" & Where.Line'Image
           & ", column" & Where.Column'Image;
      end Fail;

      --  Tokenize the whole document up front. N3 is parsed whole, so
      --  there is nothing to gain from interleaving.
      function At_End return Boolean is (Next > Tokens.Last_Index);

      function Peek return Lexers.Token_Kind
      is (if At_End then Lexers.Dot_Token else Lexers.Kind (Tokens (Next)));

      function Current return Lexers.Token
      is (Tokens (if At_End then Tokens.Last_Index else Next));

      procedure Advance is
      begin
         Next := Next + 1;
      end Advance;

      procedure Expect (Which : Lexers.Token_Kind; What : String) is
      begin
         if At_End or else Lexers.Kind (Tokens (Next)) /= Which then
            Fail ("expected " & What);
         end if;
         Advance;
      end Expect;

      function Fresh_Blank return Model.Term is
      begin
         loop
            Blank_Counter := Blank_Counter + 1;
            declare
               Image : constant String := Natural'Image (Blank_Counter);
               Label : constant String :=
                 "b" & Image (Image'First + 1 .. Image'Last);
            begin
               if not Document_Labels.Contains (Label) then
                  return Model.From_RDF (Terms.Blank_Node (Label));
               end if;
            end;
         end loop;
      end Fresh_Blank;

      --  A label the document wrote is kept as written. Rewriting it would
      --  rename every node on the way in, and rename it again on the next
      --  pass, so labels would grow instead of settling.
      function Document_Blank (Raw : String) return Model.Term is
      begin
         --  A bare "_:" is an existential with no name of its own, so it
         --  gets one that cannot collide.
         if Raw'Length = 0 then
            return Fresh_Blank;
         end if;
         if not Document_Labels.Contains (Raw) then
            Document_Labels.Insert (Raw);
         end if;
         return Model.From_RDF (Terms.Blank_Node (Raw));
      end Document_Blank;

      function Resolve (Reference : String) return IRIs.IRI is
      begin
         if Unbounded.Length (Base) = 0 then
            if not IRIs.Is_Valid (Reference) then
               Fail ("relative IRI with no base");
            end if;
            return IRIs.From_UTF_8 (Reference);
         end if;
         return IRIs.Resolve
           (IRIs.From_UTF_8 (Unbounded.To_String (Base)), Reference);
      exception
         when IRIs.Invalid_IRI | IRIs.Invalid_UTF_8 =>
            Fail ("invalid IRI");
            raise;
      end Resolve;

      function Expand (Value : Lexers.Token) return IRIs.IRI is
         Key : constant String := Lexers.Prefix (Value);
      begin
         if not Prefixes.Contains (Key) then
            --  An undeclared empty prefix names the document itself, which
            --  is how N3 has always read ":x" in a file that never said
            --  what ":" is. Any other undeclared prefix is an error.
            if Key = "" then
               return Resolve ("#" & Lexers.Text (Value));
            end if;
            Fail ("undefined prefix """ & Key & """");
         end if;
         return Resolve (Prefixes.Element (Key) & Lexers.Text (Value));
      end Expand;

      function Named (Text : String) return Model.Term
      is (Model.IRI_Term (IRIs.From_UTF_8 (Text)));

      --  Statements produced while reading a term -- by a path, a property
      --  list, or a list -- belong to the formula being built, not to the
      --  term. They are collected here and folded in by the caller.
      type Statement_Sink is limited record
         Items : Model.Builder;
      end record;

      function Parse_Expression
        (Into : in out Statement_Sink) return Model.Term;

      procedure Parse_Property_List
        (Subject : Model.Term;
         Into    : in out Statement_Sink);

      function Parse_Formula
        (Into : in out Statement_Sink) return Model.Term;

      function Parse_Literal return Model.Term is
         Value : constant Lexers.Token := Current;
      begin
         case Lexers.Kind (Value) is
            when Lexers.Integer_Token =>
               Advance;
               return Model.From_RDF
                 (Terms.Literal (Lexers.Text (Value),
                                 IRIs.From_UTF_8 (XSD_Integer)));
            when Lexers.Decimal_Token =>
               Advance;
               return Model.From_RDF
                 (Terms.Literal (Lexers.Text (Value),
                                 IRIs.From_UTF_8 (XSD_Decimal)));
            when Lexers.Double_Token =>
               Advance;
               return Model.From_RDF
                 (Terms.Literal (Lexers.Text (Value),
                                 IRIs.From_UTF_8 (XSD_Double)));
            when Lexers.Boolean_Token =>
               Advance;
               return Model.From_RDF
                 (Terms.Literal (Lexers.Text (Value),
                                 IRIs.From_UTF_8 (XSD_Boolean)));
            when Lexers.String_Token =>
               Advance;
               if Peek = Lexers.Language_Token then
                  declare
                     Tag : constant Lexers.Token := Current;
                  begin
                     Advance;
                     if Lexers.Has_Direction (Tag) then
                        return Model.From_RDF
                          (Terms.Directional_Literal
                             (Lexers.Text (Value), Lexers.Text (Tag),
                              (if Lexers.Direction (Tag)
                                    = Lexers.Left_To_Right
                               then Terms.Left_To_Right
                               else Terms.Right_To_Left)));
                     end if;
                     return Model.From_RDF
                       (Terms.Language_Literal
                          (Lexers.Text (Value), Lexers.Text (Tag)));
                  end;
               elsif Peek = Lexers.Datatype_Token then
                  Advance;
                  case Peek is
                     when Lexers.IRI_Reference_Token =>
                        declare
                           Datatype : constant IRIs.IRI :=
                             Resolve (Lexers.Text (Current));
                        begin
                           Advance;
                           return Model.From_RDF
                             (Terms.Literal (Lexers.Text (Value), Datatype));
                        end;
                     when Lexers.Prefixed_Name_Token =>
                        declare
                           Datatype : constant IRIs.IRI := Expand (Current);
                        begin
                           Advance;
                           return Model.From_RDF
                             (Terms.Literal (Lexers.Text (Value), Datatype));
                        end;
                     when others =>
                        Fail ("expected a datatype IRI");
                  end case;
               end if;
               return Model.From_RDF
                 (Terms.Literal (Lexers.Text (Value),
                                 IRIs.From_UTF_8 (XSD_String)));
            when others =>
               Fail ("expected a literal");
         end case;
         raise Parse_Error;
      end Parse_Literal;

      --  One term with no path suffix applied yet.
      function Parse_Path_Item
        (Into : in out Statement_Sink) return Model.Term is
      begin
         case Peek is
            when Lexers.IRI_Reference_Token =>
               return Result : constant Model.Term :=
                 Model.IRI_Term (Resolve (Lexers.Text (Current)))
               do
                  Advance;
               end return;

            when Lexers.Prefixed_Name_Token =>
               return Result : constant Model.Term :=
                 Model.IRI_Term (Expand (Current))
               do
                  Advance;
               end return;

            when Lexers.Blank_Label_Token =>
               return Result : constant Model.Term :=
                 Document_Blank (Lexers.Text (Current))
               do
                  Advance;
               end return;

            when Lexers.Variable_Token =>
               return Result : constant Model.Term :=
                 Model.Variable (Lexers.Text (Current))
               do
                  Advance;
               end return;

            when Lexers.String_Token | Lexers.Integer_Token
               | Lexers.Decimal_Token | Lexers.Double_Token
               | Lexers.Boolean_Token =>
               return Parse_Literal;

            when Lexers.Open_Brace_Token =>
               return Parse_Formula (Into);

            when Lexers.Open_Paren_Token =>
               --  N3 lists are first-class terms, not rdf:List chains.
               Advance;
               declare
                  Items : Model.Builder;
               begin
                  while Peek /= Lexers.Close_Paren_Token and then not At_End
                  loop
                     Model.Append (Items, Parse_Expression (Into));
                  end loop;
                  Expect (Lexers.Close_Paren_Token, "a closing parenthesis");
                  return Model.List (Items);
               end;

            when Lexers.Open_Bracket_Token =>
               Advance;
               declare
                  --  "[ id <iri> ... ]" states its properties about the
                  --  IRI named there rather than about a fresh node. The
                  --  bracket still groups the property list; it just no
                  --  longer introduces anything for it to be about.
                  function Bracket_Subject return Model.Term is
                  begin
                     if Peek = Lexers.Keyword_Token
                       and then Lexers.Text (Current) = "id"
                     then
                        Advance;
                        if Peek not in Lexers.IRI_Reference_Token
                                     | Lexers.Prefixed_Name_Token
                        then
                           Fail ("id names the subject, and a name is an"
                                 & " IRI");
                        end if;
                        return Parse_Path_Item (Into);
                     end if;
                     return Fresh_Blank;
                  end Bracket_Subject;

                  Subject : constant Model.Term := Bracket_Subject;
               begin
                  if Peek /= Lexers.Close_Bracket_Token then
                     Parse_Property_List (Subject, Into);
                  end if;
                  Expect (Lexers.Close_Bracket_Token, "a closing bracket");
                  return Subject;
               end;

            when others =>
               Fail ("expected a term");
         end case;
         raise Parse_Error;
      end Parse_Path_Item;

      --  A path names something indirectly: ":a!:b" is the :b of :a, and
      --  ":a^:b" is whatever has :a as its :b. Both introduce a fresh node
      --  and a statement about it, which is why reading a term can produce
      --  statements.
      function Parse_Expression
        (Into : in out Statement_Sink) return Model.Term
      is
         Result : Model.Term := Parse_Path_Item (Into);
      begin
         loop
            if Peek = Lexers.Forward_Path_Token then
               Advance;
               declare
                  Step   : constant Model.Term := Parse_Path_Item (Into);
                  Object : constant Model.Term := Fresh_Blank;
               begin
                  Model.Append
                    (Into.Items, Model.Create (Result, Step, Object));
                  Result := Object;
               end;
            elsif Peek = Lexers.Backward_Path_Token then
               Advance;
               declare
                  Step    : constant Model.Term := Parse_Path_Item (Into);
                  Subject : constant Model.Term := Fresh_Blank;
               begin
                  Model.Append
                    (Into.Items, Model.Create (Subject, Step, Result));
                  Result := Subject;
               end;
            else
               exit;
            end if;
         end loop;
         return Result;
      end Parse_Expression;

      function Parse_Verb
        (Into      : in out Statement_Sink;
         Reversed  : out Boolean) return Model.Term is
      begin
         Reversed := False;

         --  N3 lets a predicate be written in either direction: "has :p"
         --  reads forwards, "is :p of" and ":s <- :p :o" read backwards,
         --  each stating the same triple with its ends exchanged.
         if Peek = Lexers.Reverse_Arrow_Token then
            Advance;
            Reversed := True;
            return Parse_Expression (Into);
         end if;

         if Peek = Lexers.Keyword_Token then
            declare
               Word : constant String := Lexers.Text (Current);
            begin
               if Word = "has" then
                  Advance;
                  return Parse_Expression (Into);
               elsif Word = "is" then
                  Advance;
                  declare
                     Verb : constant Model.Term := Parse_Expression (Into);
                  begin
                     if Peek /= Lexers.Keyword_Token
                       or else Lexers.Text (Current) /= "of"
                     then
                        Fail ("expected ""of"" after ""is""");
                     end if;
                     Advance;
                     Reversed := True;
                     return Verb;
                  end;
               end if;
            end;
         end if;

         case Peek is
            when Lexers.A_Token =>
               Advance;
               return Named (RDF_Type);
            when Lexers.Implies_Token =>
               Advance;
               return Named (Log_Implies);
            when Lexers.Implied_By_Token =>
               --  "A <= B" states the same implication as "B => A"; the
               --  arrow names which side is which, not a second predicate.
               Advance;
               Reversed := True;
               return Named (Log_Implies);
            when Lexers.Equals_Token =>
               Advance;
               return Named (OWL_Same_As);
            when others =>
               return Parse_Expression (Into);
         end case;
      end Parse_Verb;

      procedure Parse_Property_List
        (Subject : Model.Term;
         Into    : in out Statement_Sink) is
      begin
         loop
            declare
               Reversed : Boolean;
               Verb     : constant Model.Term := Parse_Verb (Into, Reversed);
            begin
               loop
                  declare
                     Object : constant Model.Term := Parse_Expression (Into);
                  begin
                     if Reversed then
                        Model.Append
                          (Into.Items,
                           Model.Create (Object, Verb, Subject));
                     else
                        Model.Append
                          (Into.Items,
                           Model.Create (Subject, Verb, Object));
                     end if;
                  end;
                  exit when Peek /= Lexers.Comma_Token;
                  Advance;
               end loop;
            end;

            exit when Peek /= Lexers.Semicolon_Token;
            while Peek = Lexers.Semicolon_Token loop
               Advance;
            end loop;
            exit when At_End
              or else Peek in Lexers.Dot_Token | Lexers.Close_Bracket_Token
                            | Lexers.Close_Brace_Token;
         end loop;
      end Parse_Property_List;

      procedure Parse_Statement (Into : in out Statement_Sink);

      function Parse_Formula
        (Into : in out Statement_Sink) return Model.Term
      is
         pragma Unreferenced (Into);
         Inner : Statement_Sink;
      begin
         Expect (Lexers.Open_Brace_Token, "an opening brace");
         while not At_End and then Peek /= Lexers.Close_Brace_Token loop
            Parse_Statement (Inner);
         end loop;
         Expect (Lexers.Close_Brace_Token, "a closing brace");
         return Model.Formula (Inner.Items);
      end Parse_Formula;

      procedure Parse_Directive is
      begin
         case Peek is
            when Lexers.Prefix_Directive_Token
               | Lexers.Sparql_Prefix_Token =>
               declare
                  Terminated : constant Boolean :=
                    Peek = Lexers.Prefix_Directive_Token;
                  Name : Unbounded.Unbounded_String;
               begin
                  Advance;
                  if Peek /= Lexers.Prefixed_Name_Token
                    or else Lexers.Text (Current) /= ""
                  then
                     Fail ("expected a prefix name");
                  end if;
                  Name := Unbounded.To_Unbounded_String
                    (Lexers.Prefix (Current));
                  Advance;
                  if Peek /= Lexers.IRI_Reference_Token then
                     Fail ("expected a namespace IRI");
                  end if;
                  Prefixes.Include
                    (Unbounded.To_String (Name),
                     IRIs.To_UTF_8 (Resolve (Lexers.Text (Current))));
                  Advance;
                  if Terminated then
                     Expect (Lexers.Dot_Token, "a terminator");
                  end if;
               end;

            when Lexers.Base_Directive_Token | Lexers.Sparql_Base_Token =>
               declare
                  Terminated : constant Boolean :=
                    Peek = Lexers.Base_Directive_Token;
               begin
                  Advance;
                  if Peek /= Lexers.IRI_Reference_Token then
                     Fail ("expected a base IRI");
                  end if;
                  Base := Unbounded.To_Unbounded_String
                    (IRIs.To_UTF_8 (Resolve (Lexers.Text (Current))));
                  Advance;
                  if Terminated then
                     Expect (Lexers.Dot_Token, "a terminator");
                  end if;
               end;

            when Lexers.For_All_Token | Lexers.For_Some_Token =>
               --  Quantification is recorded by parsing it; scoping is a
               --  reasoner's concern, and this crate does not reason.
               Advance;
               loop
                  declare
                     Sink : Statement_Sink;
                     Ignored : constant Model.Term :=
                       Parse_Expression (Sink);
                  begin
                     pragma Unreferenced (Ignored);
                  end;
                  exit when Peek /= Lexers.Comma_Token;
                  Advance;
               end loop;
               Expect (Lexers.Dot_Token, "a terminator");

            when others =>
               Fail ("expected a directive");
         end case;
      end Parse_Directive;

      procedure Parse_Statement (Into : in out Statement_Sink) is
      begin
         case Peek is
            when Lexers.Prefix_Directive_Token
               | Lexers.Base_Directive_Token
               | Lexers.Sparql_Prefix_Token
               | Lexers.Sparql_Base_Token
               | Lexers.For_All_Token
               | Lexers.For_Some_Token =>
               Parse_Directive;

            when others =>
               declare
                  Subject : constant Model.Term := Parse_Expression (Into);
               begin
                  --  A term with no predicates is a statement in N3. It
                  --  may end at its own terminator, or at the brace that
                  --  closes the formula holding it, which is where the
                  --  last statement of a formula may leave the terminator
                  --  out.
                  if Peek = Lexers.Dot_Token then
                     Advance;
                     return;
                  elsif Peek = Lexers.Close_Brace_Token or else At_End then
                     return;
                  end if;
                  Parse_Property_List (Subject, Into);
               end;
               if Peek = Lexers.Close_Brace_Token then
                  --  The last statement of a formula may omit its
                  --  terminator, as it may in TriG.
                  return;
               end if;
               Expect (Lexers.Dot_Token, "a terminator");
         end case;
      end Parse_Statement;

      Document_Sink : Statement_Sink;

   begin
      if Base_IRI /= "" and then not IRIs.Is_Valid (Base_IRI) then
         raise Parse_Error with "base IRI is not absolute";
      end if;

      while not At_End loop
         Parse_Statement (Document_Sink);
      end loop;
      return Model.Formula (Document_Sink.Items);
   end Parse_Tokens;

   ---------------------------------------------------------------------
   --  Scanning
   ---------------------------------------------------------------------

   --  Scan as far as the bytes allow, appending whole tokens and reporting
   --  where the unread remainder begins. Ended says whether more bytes can
   --  still arrive: it is the difference between "this token is not
   --  finished yet" and "this token was never finished".
   procedure Scan_Chunk
     (Text     : String;
      Ended    : Boolean;
      Origin   : in out Cursors.Cursor_State;
      Consumed : out Natural;
      Tokens   : in out Token_Vectors.Vector)
   is
      Position : Cursors.Cursor_State := Origin;
      Index    : Positive := Text'First;
      Result   : Lexers.Token := Lexers.Null_Token;
      Status   : Lexers.Scan_Status;
      Error    : Lexers.Scan_Error_Kind;

      Consumed_Index    : Natural := Text'First;
      Consumed_Position : Cursors.Cursor_State := Origin;
   begin
      loop
         Lexers.Scan
           (Text, Position, Index, Ended, Result, Status, Error,
            Lexers.N3_Dialect);
         case Status is
            when Lexers.Token_Found =>
               Tokens.Append (Result);
               Consumed_Index := Index;
               Consumed_Position := Position;

            when Lexers.Needs_More_Input =>
               exit;

            when Lexers.End_Of_Input =>
               Consumed_Index := Index;
               Consumed_Position := Position;
               exit;

            when Lexers.Scan_Error =>
               raise Parse_Error with
                 "malformed token (" & Error'Image & ") at line"
                 & Position.Line'Image & ", column"
                 & Position.Column'Image;
         end case;
      end loop;
      Origin := Consumed_Position;
      Consumed := Consumed_Index;
   end Scan_Chunk;

   function Parse
     (Document : String;
      Base_IRI : String := "") return Model.Term
   is
      Tokens   : Token_Vectors.Vector;
      Origin   : Cursors.Cursor_State := Cursors.Initial_State;
      Consumed : Natural;
   begin
      Scan_Chunk (Document, True, Origin, Consumed, Tokens);
      return Parse_Tokens (Tokens, Base_IRI);
   end Parse;

   ---------------------------------------------------------------------
   --  Chunk-fed parsing
   ---------------------------------------------------------------------

   function Create (Base_IRI : String := "") return Parser is
     (Pending  => Unbounded.Null_Unbounded_String,
      Base     => Unbounded.To_Unbounded_String (Base_IRI),
      Origin   => Cursors.Initial_State,
      Tokens   => Token_Vectors.Empty_Vector,
      Finished => False);

   procedure Feed (Into : in out Parser; Bytes : String) is
      Text     : constant String :=
        Unbounded.To_String (Into.Pending) & Bytes;
      Consumed : Natural;
   begin
      if Into.Finished then
         raise Parser_State_Error with "parser has already finished";
      end if;
      Scan_Chunk (Text, False, Into.Origin, Consumed, Into.Tokens);
      Into.Pending :=
        Unbounded.To_Unbounded_String (Text (Consumed .. Text'Last));
   end Feed;

   function Finish (Into : in out Parser) return Model.Term is
      Text     : constant String := Unbounded.To_String (Into.Pending);
      Consumed : Natural;
   begin
      if Into.Finished then
         raise Parser_State_Error with "parser has already finished";
      end if;
      Into.Finished := True;
      Scan_Chunk (Text, True, Into.Origin, Consumed, Into.Tokens);
      Into.Pending := Unbounded.Null_Unbounded_String;
      return Parse_Tokens (Into.Tokens, Unbounded.To_String (Into.Base));
   end Finish;

end Flyology_N3.Parsers;
