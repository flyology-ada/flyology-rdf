with Flyology_RDF.IRIs;
with Flyology_RDF.Terms;

package body Flyology_RDF.Turtle_Parsers is

   package Cursors renames Parser_Cursors;

   use type Lexers.Scan_Status;
   use type Lexers.Scan_Error_Kind;
   use type Lexers.Token_Kind;
   use type Lexers.Direction_Value;
   use type Terms.Term_Kind;

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

   --  Raised internally to abandon a statement; every raise site records the
   --  diagnostic first, so the handler only has to deliver it.
   Grammar_Error : exception;

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
         Result.Base_Data := Unbounded.To_Unbounded_String (Base_IRI);
         Result.Limits_Data := Limits;
         Result.Syntax_Data := Syntax;
         Result.Checkpoint := Work_Checkpoint;
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
      Tokens : Token_Vectors.Vector renames Into.Statement;
      Next   : Positive := Tokens.First_Index;

      Depth  : Natural := 0;

      function Peek_Kind return Lexers.Token_Kind
      is (if Next <= Tokens.Last_Index
          then Lexers.Kind (Tokens (Next))
          else Lexers.Dot_Token);

      function At_End return Boolean is (Next > Tokens.Last_Index);

      function Current return Lexers.Token
      is (Tokens (if At_End then Tokens.Last_Index else Next));

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
            Span_Value       => Token_Span (Current),
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
      function Document_Blank_Label (Raw : String) return String is
      begin
         if not Into.Document_Labels.Contains (Raw) then
            Into.Document_Labels.Insert (Raw);
         end if;
         return Unbounded.To_String (Into.Blank_Prefix) & Raw;
      end Document_Blank_Label;

      function Resolve (Reference : String; What : Production_Kind)
        return IRIs.IRI;

      function Resolve (Reference : String; What : Production_Kind)
        return IRIs.IRI is
      begin
         if Unbounded.Length (Into.Base_Data) = 0 then
            if not IRIs.Is_Valid (Reference) then
               Reject (Invalid_IRI, What);
            end if;
            return IRIs.From_UTF_8 (Reference);
         end if;

         return IRIs.Resolve
           (IRIs.From_UTF_8 (Unbounded.To_String (Into.Base_Data)),
            Reference);
      exception
         when IRIs.Invalid_IRI | IRIs.Invalid_UTF_8 =>
            Reject (Invalid_IRI, What);
            raise;
      end Resolve;

      function Expand (Value : Lexers.Token) return IRIs.IRI;

      function Expand (Value : Lexers.Token) return IRIs.IRI is
         Key : constant String := Lexers.Prefix (Value);
      begin
         if not Into.Prefixes.Contains (Key) then
            Reject (Undefined_Prefix, IRI_Production);
         end if;
         return Resolve
           (Into.Prefixes.Element (Key) & Lexers.Text (Value),
            IRI_Production);
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
         Head    : Terms.Term := Terms.IRI_Term (IRIs.From_UTF_8 (RDF_Nil));
         Started : Boolean := False;
         Last    : Terms.Term := Head;
         Where   : constant Source_Span := Token_Span (Current);
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
               Emit (Cell, IRIs.From_UTF_8 (RDF_First), Element, Where);
               if Started then
                  Emit (Last, IRIs.From_UTF_8 (RDF_Rest), Cell, Where);
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
            Emit (Last, IRIs.From_UTF_8 (RDF_Rest),
                  Terms.IRI_Term (IRIs.From_UTF_8 (RDF_Nil)), Where);
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
               return IRIs.From_UTF_8 (RDF_Type);
            when Lexers.IRI_Reference_Token =>
               declare
                  Value : constant IRIs.IRI :=
                    Resolve (Lexers.Text (Current), Predicate_Production);
               begin
                  Advance;
                  return Value;
               end;
            when Lexers.Prefixed_Name_Token =>
               declare
                  Value : constant IRIs.IRI := Expand (Current);
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
         Predicate : IRIs.IRI := IRIs.From_UTF_8 (RDF_Type);
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
                 (Resolve (Lexers.Text (Current), Triple_Term_Production));
               Advance;
            when Lexers.Prefixed_Name_Token =>
               Subject := Terms.IRI_Term (Expand (Current));
               Advance;
            when Lexers.Blank_Label_Token =>
               Subject := Terms.Blank_Node
                 (Document_Blank_Label (Lexers.Text (Current)));
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
                   (Resolve (Lexers.Text (Current), Statement_Production))
               do
                  Advance;
               end return;
            when Lexers.Prefixed_Name_Token =>
               return Result : constant Terms.Term :=
                 Terms.IRI_Term (Expand (Current))
               do
                  Advance;
               end return;
            when Lexers.Blank_Label_Token =>
               return Result : constant Terms.Term :=
                 Terms.Blank_Node
                   (Document_Blank_Label (Lexers.Text (Current)))
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
         Where     : constant Source_Span := Token_Span (Current);
         Subject   : Terms.Term := Terms.Blank_Node ("placeholder");
         Predicate : IRIs.IRI := IRIs.From_UTF_8 (RDF_Type);
         Object    : Terms.Term := Terms.Blank_Node ("placeholder");
         Node      : Terms.Term := Terms.Blank_Node ("placeholder");
      begin
         Enter_Nesting;
         Expect (Lexers.Open_Quoted_Token, Statement_Production);

         case Peek_Kind is
            when Lexers.IRI_Reference_Token =>
               Subject := Terms.IRI_Term
                 (Resolve (Lexers.Text (Current), Subject_Production));
               Advance;
            when Lexers.Prefixed_Name_Token =>
               Subject := Terms.IRI_Term (Expand (Current));
               Advance;
            when Lexers.Blank_Label_Token =>
               Subject := Terms.Blank_Node
                 (Document_Blank_Label (Lexers.Text (Current)));
               Advance;
            when Lexers.Open_Quoted_Token =>
               Subject := Parse_Reified_Triple;
            when others =>
               Reject (Malformed_Syntax, Subject_Production);
         end case;

         Predicate := Parse_Verb;
         Object := Parse_Object_Term;

         if Peek_Kind = Lexers.Reifier_Token then
            Node := Parse_Reifier;
         else
            Node := Terms.Blank_Node (Fresh_Blank_Label);
         end if;

         Expect (Lexers.Close_Quoted_Token, Statement_Production);
         Depth := Depth - 1;

         Emit (Node, IRIs.From_UTF_8 (RDF_Reifies),
               Terms.Triple_Term (Subject, Predicate, Object), Where);
         return Node;
      end Parse_Reified_Triple;

      function Parse_Literal return Terms.Term;

      function Parse_Literal return Terms.Term is
         Value : constant Lexers.Token := Current;
      begin
         case Lexers.Kind (Value) is
            when Lexers.Integer_Token =>
               Advance;
               return Terms.Literal
                 (Lexers.Text (Value), IRIs.From_UTF_8 (XSD_Integer));
            when Lexers.Decimal_Token =>
               Advance;
               return Terms.Literal
                 (Lexers.Text (Value), IRIs.From_UTF_8 (XSD_Decimal));
            when Lexers.Double_Token =>
               Advance;
               return Terms.Literal
                 (Lexers.Text (Value), IRIs.From_UTF_8 (XSD_Double));
            when Lexers.Boolean_Token =>
               Advance;
               return Terms.Literal
                 (Lexers.Text (Value), IRIs.From_UTF_8 (XSD_Boolean));
            when Lexers.String_Token =>
               Advance;
               --  A language tag, a datatype, or neither.
               if Peek_Kind = Lexers.Language_Token then
                  declare
                     Tag : constant Lexers.Token := Current;
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
                             Resolve (Lexers.Text (Current),
                                      Literal_Production);
                        begin
                           Advance;
                           return Terms.Literal
                             (Lexers.Text (Value), Datatype);
                        end;
                     when Lexers.Prefixed_Name_Token =>
                        declare
                           Datatype : constant IRIs.IRI := Expand (Current);
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
                 (Lexers.Text (Value), IRIs.From_UTF_8 (XSD_String));
            when others =>
               Reject (Malformed_Syntax, Literal_Production);
         end case;
         raise Grammar_Error;
      end Parse_Literal;

      function Parse_Object_Term return Terms.Term is
      begin
         case Peek_Kind is
            when Lexers.IRI_Reference_Token =>
               return Result : constant Terms.Term :=
                 Terms.IRI_Term
                   (Resolve (Lexers.Text (Current), Object_Production))
               do
                  Advance;
               end return;
            when Lexers.Prefixed_Name_Token =>
               return Result : constant Terms.Term :=
                 Terms.IRI_Term (Expand (Current))
               do
                  Advance;
               end return;
            when Lexers.Blank_Label_Token =>
               return Result : constant Terms.Term :=
                 Terms.Blank_Node
                   (Document_Blank_Label (Lexers.Text (Current)))
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
                   (Resolve (Lexers.Text (Current), Subject_Production))
               do
                  Advance;
               end return;
            when Lexers.Prefixed_Name_Token =>
               return Result : constant Terms.Term :=
                 Terms.IRI_Term (Expand (Current))
               do
                  Advance;
               end return;
            when Lexers.Blank_Label_Token =>
               return Result : constant Terms.Term :=
                 Terms.Blank_Node
                   (Document_Blank_Label (Lexers.Text (Current)))
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

               Emit (Node, IRIs.From_UTF_8 (RDF_Reifies),
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
               Where  : constant Source_Span := Token_Span (Current);
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
                    or else Lexers.Text (Current) /= ""
                  then
                     Reject (Malformed_Syntax, Directive_Production);
                  end if;
                  Name :=
                    Unbounded.To_Unbounded_String (Lexers.Prefix (Current));
                  Advance;

                  if Peek_Kind /= Lexers.IRI_Reference_Token then
                     Reject (Malformed_Syntax, Directive_Production);
                  end if;
                  declare
                     Target_IRI : constant IRIs.IRI :=
                       Resolve (Lexers.Text (Current), Directive_Production);
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
                       Resolve (Lexers.Text (Current), Directive_Production);
                  begin
                     Advance;
                     Into.Base_Data := Unbounded.To_Unbounded_String
                       (IRIs.To_UTF_8 (Target_IRI));
                  end;
                  if Terminated then
                     Expect (Lexers.Dot_Token, Directive_Production);
                  end if;
               end;

            when Lexers.Version_Directive_Token =>
               Advance;
               if Peek_Kind /= Lexers.String_Token then
                  Reject (Malformed_Syntax, Directive_Production);
               end if;
               Advance;

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
            if not IRIs.Is_Valid (Lexers.Text (Current)) then
               Reject (Invalid_IRI, What);
            end if;
            return Result : constant IRIs.IRI :=
              IRIs.From_UTF_8 (Lexers.Text (Current))
            do
               Advance;
            end return;
         end Absolute;

         function Line_Term
           (What         : Production_Kind;
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
                      (Document_Blank_Label (Lexers.Text (Current)))
                  do
                     Advance;
                  end return;
               when Lexers.String_Token =>
                  if not Allow_Literal then
                     Reject (Malformed_Syntax, What);
                  end if;
                  return Parse_Literal;
               when Lexers.Open_Triple_Term_Token =>
                  return Parse_Triple_Term;
               when others =>
                  Reject (Malformed_Syntax, What);
                  raise Grammar_Error;
            end case;
         end Line_Term;

         Where     : constant Source_Span := Token_Span (Current);
         Subject   : constant Terms.Term :=
           Line_Term (Subject_Production, Allow_Literal => False);
         Predicate : constant IRIs.IRI :=
           (if Peek_Kind = Lexers.IRI_Reference_Token
            then Absolute (Predicate_Production)
            else raise Grammar_Error);
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

         Emit (Subject, Predicate, Object, Where);
         Expect (Lexers.Dot_Token, Statement_Production);

         --  A graph label binds to its own statement only.
         Into.Graph_Is_Named := False;
         Into.Graph_Is_Blank := False;
      end Parse_Line_Statement;

      procedure Parse_Triples;

      procedure Parse_Triples is
      begin
         if Peek_Kind = Lexers.Open_Bracket_Token then
            --  A property list may stand alone as a statement, with or
            --  without further predicates attached to it.
            declare
               Subject : constant Terms.Term := Parse_Property_List;
            begin
               if Peek_Kind /= Lexers.Dot_Token and then not At_End then
                  Parse_Predicate_Object_List (Subject);
               end if;
            end;
         else
            declare
               Subject : constant Terms.Term := Parse_Subject_Term;
            begin
               Parse_Predicate_Object_List (Subject);
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

      if Tokens.Is_Empty then
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
            Parse_Directive;

         when Lexers.Graph_Token =>
            if Into.Syntax_Data = Turtle_Syntax then
               Reject (Unsupported_Production, Graph_Block_Production);
            end if;
            declare
               Where : constant Source_Span := Token_Span (Current);
            begin
               Advance;
               case Peek_Kind is
                  when Lexers.IRI_Reference_Token =>
                     Into.Current_Graph := Unbounded.To_Unbounded_String
                       (IRIs.To_UTF_8
                          (Resolve (Lexers.Text (Current),
                                    Graph_Block_Production)));
                     Into.Graph_Is_Blank := False;
                     Advance;
                  when Lexers.Prefixed_Name_Token =>
                     Into.Current_Graph := Unbounded.To_Unbounded_String
                       (IRIs.To_UTF_8 (Expand (Current)));
                     Into.Graph_Is_Blank := False;
                     Advance;
                  when Lexers.Blank_Label_Token =>
                     Into.Current_Graph := Unbounded.To_Unbounded_String
                       (Document_Blank_Label (Lexers.Text (Current)));
                     Into.Graph_Is_Blank := True;
                     Advance;
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
            | Lexers.Blank_Label_Token =>
            if Next + 1 <= Tokens.Last_Index
              and then Lexers.Kind (Tokens (Next + 1))
                       = Lexers.Open_Brace_Token
            then
               --  A labelled graph block, written without the keyword.
               if Into.Syntax_Data /= TriG_Syntax then
                  Reject (Unsupported_Production, Graph_Block_Production);
               end if;
               declare
                  Where : constant Source_Span := Token_Span (Current);
               begin
                  case Peek_Kind is
                     when Lexers.IRI_Reference_Token =>
                        Into.Current_Graph := Unbounded.To_Unbounded_String
                          (IRIs.To_UTF_8
                             (Resolve (Lexers.Text (Current),
                                       Graph_Block_Production)));
                        Into.Graph_Is_Blank := False;
                     when Lexers.Prefixed_Name_Token =>
                        Into.Current_Graph := Unbounded.To_Unbounded_String
                          (IRIs.To_UTF_8 (Expand (Current)));
                        Into.Graph_Is_Blank := False;
                     when others =>
                        Into.Current_Graph := Unbounded.To_Unbounded_String
                          (Document_Blank_Label (Lexers.Text (Current)));
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
   end Parse_Statement;

   ----------------------------------------------------------------------
   --  Feeding
   ----------------------------------------------------------------------

   --  A statement is complete at a '.' outside every bracket, at the brace
   --  that closes a graph block, or at the operand that ends a
   --  SPARQL-style directive, which carries no terminator of its own.
   function Statement_Is_Complete
     (Tokens : Token_Vectors.Vector) return Boolean;

   function Statement_Is_Complete
     (Tokens : Token_Vectors.Vector) return Boolean
   is
      Depth : Integer := 0;
   begin
      if Tokens.Is_Empty then
         return False;
      end if;

      --  TriG names a graph either with the GRAPH keyword or by writing
      --  the label directly before the brace. The second form has to be
      --  recognised here or the brace never ends a statement and the dot
      --  inside the block ends it instead.
      if Natural (Tokens.Length) >= 2
        and then Lexers.Kind (Tokens.First_Element)
                 in Lexers.IRI_Reference_Token
                  | Lexers.Prefixed_Name_Token
                  | Lexers.Blank_Label_Token
        and then Lexers.Kind (Tokens (Tokens.First_Index + 1))
                 = Lexers.Open_Brace_Token
      then
         return True;
      end if;

      case Lexers.Kind (Tokens.First_Element) is
         when Lexers.Sparql_Prefix_Token =>
            return Natural (Tokens.Length) = 3;
         when Lexers.Sparql_Base_Token | Lexers.Version_Directive_Token =>
            return Natural (Tokens.Length) = 2;
         when Lexers.Open_Brace_Token | Lexers.Close_Brace_Token =>
            return True;
         when Lexers.Graph_Token =>
            return Lexers.Kind (Tokens.Last_Element)
                   = Lexers.Open_Brace_Token;
         when others =>
            null;
      end case;

      for Value of Tokens loop
         case Lexers.Kind (Value) is
            when Lexers.Open_Paren_Token | Lexers.Open_Bracket_Token
               | Lexers.Open_Quoted_Token | Lexers.Open_Triple_Term_Token
               | Lexers.Open_Annotation_Token =>
               Depth := Depth + 1;
            when Lexers.Close_Paren_Token | Lexers.Close_Bracket_Token
               | Lexers.Close_Quoted_Token | Lexers.Close_Triple_Term_Token
               | Lexers.Close_Annotation_Token =>
               Depth := Depth - 1;
            when Lexers.Dot_Token =>
               if Depth <= 0 then
                  return True;
               end if;
            when Lexers.Close_Brace_Token =>
               --  TriG lets the last statement in a graph block omit its
               --  terminator, so the closing brace ends the statement too.
               if Depth <= 0 then
                  return True;
               end if;
            when others =>
               null;
         end case;
      end loop;
      return False;
   end Statement_Is_Complete;

   procedure Deliver
     (Into   : in out Parser;
      Target : in out Event_Sink'Class;
      Ended  : Boolean);

   procedure Deliver
     (Into   : in out Parser;
      Target : in out Event_Sink'Class;
      Ended  : Boolean)
   is
      Text     : constant String := Unbounded.To_String (Into.Pending);
      Position : Cursors.Cursor_State := Into.Pending_Origin;
      Index    : Positive := Text'First;
      Result   : Lexers.Token := Lexers.Null_Token;
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

         Lexers.Scan
           (Text, Position, Index, Ended, Result, Status, Error);

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

               if Lexers.Text (Result)'Length
                  > Into.Limits_Data.Maximum_Token_Bytes
               then
                  Report (Token_Limit, Token_Span (Result));
                  exit;
               end if;

               Into.Statement.Append (Result);
               Into.Work_Data.Maximum_Pending_Tokens :=
                 Natural'Max (Into.Work_Data.Maximum_Pending_Tokens,
                              Natural (Into.Statement.Length));

               if Statement_Is_Complete (Into.Statement) then
                  declare
                     Failure : Parse_Diagnostic;
                     Bad     : Boolean;
                  begin
                     Parse_Statement (Into, Target, Failure, Bad);
                     Into.Statement.Clear;
                     if Bad then
                        Into.Failed := True;
                        On_Diagnostic (Target, Failure);
                        exit;
                     end if;
                  end;
               end if;

            when Lexers.Needs_More_Input =>
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
      end loop;

      --  Retain only what has not been consumed. Whitespace and completed
      --  tokens are dropped, so the buffer holds at most one partial token.
      Into.Pending := Unbounded.To_Unbounded_String
        (Text (Consumed_Index .. Text'Last));
      Into.Pending_Origin := Consumed_Position;
      Into.Work_Data.Maximum_Pending_Bytes :=
        Natural'Max (Into.Work_Data.Maximum_Pending_Bytes,
                     Unbounded.Length (Into.Pending));
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

      Into.Byte_Count := Into.Byte_Count + Bytes'Length;
      Into.Work_Data.Bytes_Scanned :=
        Into.Work_Data.Bytes_Scanned + Bytes'Length;

      if Into.Byte_Count > Into.Limits_Data.Maximum_Bytes then
         Into.Failed := True;
         On_Diagnostic
           (Target,
            (Code_Value       => Byte_Limit,
             Production_Value => Document_Production,
             Span_Value       => <>,
             Source_Value     => Into.Source_Data));
         return;
      end if;

      Unbounded.Append (Into.Pending, Bytes);
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
        and then (not Into.Statement.Is_Empty
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
