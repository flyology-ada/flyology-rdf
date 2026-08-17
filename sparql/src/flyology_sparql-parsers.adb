with Ada.Characters.Handling;
with Ada.Containers.Indefinite_Ordered_Sets;
with Ada.Containers.Indefinite_Vectors;

with Flyology_RDF.Lexers;
with Flyology_RDF.Parser_Cursors;

package body Flyology_SPARQL.Parsers is

   package Lexers renames Flyology_RDF.Lexers;
   package Cursors renames Flyology_RDF.Parser_Cursors;

   use type Lexers.Scan_Status;
   use type Lexers.Token_Kind;
   use type Lexers.String_Form;
   use type Syntax.Node_Kind;
   use type Syntax.Node_Reference;

   package String_Sets is new Ada.Containers.Indefinite_Ordered_Sets
     (Element_Type => String);

   package Token_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Lexers.Token,
      "="          => Lexers."=");

   function Upper (Value : String) return String
   is (Ada.Characters.Handling.To_Upper (Value));

   function Parse (Query_Text : String) return Syntax.Query is

      Tokens  : Token_Vectors.Vector;
      Next    : Positive := 1;
      Tree    : Syntax.Builder;

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

      procedure Tokenize is
         Position : Cursors.Cursor_State := Cursors.Initial_State;
         Index    : Positive := Query_Text'First;
         Result   : Lexers.Token := Lexers.Null_Token;
         Status   : Lexers.Scan_Status;
         Error    : Lexers.Scan_Error_Kind;
      begin
         loop
            Lexers.Scan
              (Query_Text, Position, Index, True, Result, Status, Error,
               Lexers.SPARQL_Dialect);
            case Status is
               when Lexers.Token_Found => Tokens.Append (Result);
               when Lexers.End_Of_Input => exit;
               when others =>
                  raise Parse_Error with
                    "malformed token (" & Error'Image & ") at line"
                    & Position.Line'Image & ", column"
                    & Position.Column'Image;
            end case;
         end loop;
      end Tokenize;

      function At_End return Boolean is (Next > Tokens.Last_Index);

      function Peek return Lexers.Token_Kind
      is (if At_End then Lexers.Dot_Token else Lexers.Kind (Tokens (Next)));

      function Current return Lexers.Token
      is (Tokens (if At_End then Tokens.Last_Index else Next));

      procedure Advance is
      begin
         Next := Next + 1;
      end Advance;

      --  SPARQL keywords are not reserved, so a keyword is recognised by
      --  what it says rather than by its token kind alone.
      --  Some words already have tokens of their own, because the RDF
      --  grammars needed them; GRAPH is one. A keyword test that only
      --  looked at Keyword_Token would miss exactly those.
      function At_Keyword (Word : String) return Boolean
      is (not At_End
          and then ((Peek = Lexers.Keyword_Token
                     and then Upper (Lexers.Text (Current)) = Word)
                    or else (Word = "GRAPH" and then Peek = Lexers.Graph_Token)
                    or else (Word = "PREFIX"
                             and then Peek = Lexers.Sparql_Prefix_Token)
                    or else (Word = "BASE"
                             and then Peek = Lexers.Sparql_Base_Token)));

      function Take_Keyword (Word : String) return Boolean is
      begin
         if At_Keyword (Word) then
            Advance;
            return True;
         end if;
         return False;
      end Take_Keyword;

      procedure Expect (Which : Lexers.Token_Kind; What : String) is
      begin
         if At_End or else Peek /= Which then
            Fail ("expected " & What);
         end if;
         Advance;
      end Expect;

      procedure Expect_Keyword (Word : String) is
      begin
         if not Take_Keyword (Word) then
            Fail ("expected " & Word);
         end if;
      end Expect_Keyword;

      function Node
        (Variant : Syntax.Node_Kind;
         Text    : String := "";
         Detail  : String := "") return Syntax.Node_Reference
      is (Syntax.Add_Node (Tree, Variant, Text, Detail));

      Blank_Counter : Natural := 0;

      --  Collections, property lists and unnamed reifiers each need a node
      --  the query did not name.
      function Fresh_Blank return Syntax.Node_Reference is
      begin
         Blank_Counter := Blank_Counter + 1;
         declare
            Image : constant String := Natural'Image (Blank_Counter);
         begin
            return Node (Syntax.Blank_Node,
                         "g" & Image (Image'First + 1 .. Image'Last));
         end;
      end Fresh_Blank;

      function Parse_Expression return Syntax.Node_Reference;
      function Parse_Group return Syntax.Node_Reference;

      ------------------------------------------------------------------
      --  Terms
      ------------------------------------------------------------------

      function Parse_Term return Syntax.Node_Reference is
      begin
         case Peek is
            when Lexers.IRI_Reference_Token =>
               return Result : constant Syntax.Node_Reference :=
                 Node (Syntax.IRI_Node, Lexers.Text (Current))
               do
                  Advance;
               end return;

            when Lexers.Prefixed_Name_Token =>
               return Result : constant Syntax.Node_Reference :=
                 Node (Syntax.Prefixed_Node, Lexers.Text (Current),
                       Lexers.Prefix (Current))
               do
                  Advance;
               end return;

            when Lexers.Blank_Label_Token =>
               return Result : constant Syntax.Node_Reference :=
                 Node (Syntax.Blank_Node, Lexers.Text (Current))
               do
                  Advance;
               end return;

            when Lexers.Variable_Token =>
               return Result : constant Syntax.Node_Reference :=
                 Node (Syntax.Variable_Node, Lexers.Text (Current))
               do
                  Advance;
               end return;

            when Lexers.A_Token =>
               return Result : constant Syntax.Node_Reference :=
                 Node (Syntax.A_Node)
               do
                  Advance;
               end return;

            when Lexers.Integer_Token | Lexers.Decimal_Token
               | Lexers.Double_Token | Lexers.Boolean_Token =>
               return Result : constant Syntax.Node_Reference :=
                 Node (Syntax.Literal_Node, Lexers.Text (Current),
                       Lexers.Token_Kind'Image (Peek))
               do
                  Advance;
               end return;

            when Lexers.String_Token =>
               declare
                  Lexical : constant String := Lexers.Text (Current);
               begin
                  Advance;
                  if Peek = Lexers.Language_Token then
                     declare
                        Tag : constant String := Lexers.Text (Current);
                     begin
                        Advance;
                        return Node (Syntax.Literal_Node, Lexical, "@" & Tag);
                     end;
                  elsif Peek = Lexers.Datatype_Token then
                     Advance;
                     declare
                        Datatype : constant Syntax.Node_Reference :=
                          Parse_Term;
                        Result : constant Syntax.Node_Reference :=
                          Node (Syntax.Literal_Node, Lexical, "^^");
                     begin
                        Syntax.Add_Child (Tree, Result, Datatype);
                        return Result;
                     end;
                  end if;
                  return Node (Syntax.Literal_Node, Lexical);
               end;

            when others =>
               Fail ("expected a term");
         end case;
         raise Parse_Error;
      end Parse_Term;

      ------------------------------------------------------------------
      --  Expressions, in precedence order
      ------------------------------------------------------------------

      function Parse_Primary return Syntax.Node_Reference is
      begin
         if Peek = Lexers.Open_Paren_Token then
            Advance;
            declare
               Inner : constant Syntax.Node_Reference := Parse_Expression;
            begin
               Expect (Lexers.Close_Paren_Token, "a closing parenthesis");
               return Inner;
            end;
         end if;

         --  A triple term is a term, so it belongs in an expression as
         --  much as in a pattern.
         if Peek = Lexers.Open_Triple_Term_Token then
            Advance;
            declare
               Result : constant Syntax.Node_Reference :=
                 Node (Syntax.Triple_Term_Node);
            begin
               --  Its components are terms, not expressions: a triple
               --  term quotes a statement, and a statement is made of
               --  terms. The subject of a statement is never a literal.
               declare
                  Subject : constant Syntax.Node_Reference := Parse_Term;
               begin
                  if Syntax.Kind (Syntax.To_Query (Tree), Subject)
                     = Syntax.Literal_Node
                  then
                     Fail ("a literal cannot be a subject");
                  end if;
                  Syntax.Add_Child (Tree, Result, Subject);
               end;
               Syntax.Add_Child (Tree, Result, Parse_Term);
               Syntax.Add_Child (Tree, Result, Parse_Term);
               Expect (Lexers.Close_Triple_Term_Token,
                       "a triple term terminator");
               return Result;
            end;
         end if;

         if At_Keyword ("EXISTS")
           or else (At_Keyword ("NOT")
                    and then Next + 1 <= Tokens.Last_Index
                    and then Lexers.Kind (Tokens (Next + 1))
                             = Lexers.Keyword_Token
                    and then Upper (Lexers.Text (Tokens (Next + 1)))
                             = "EXISTS")
         then
            declare
               Negated : constant Boolean := At_Keyword ("NOT");
               Result  : Syntax.Node_Reference;
            begin
               Advance;
               if Negated then
                  Expect_Keyword ("EXISTS");
               end if;
               Result := Node (Syntax.Exists_Node,
                               (if Negated then "NOT EXISTS" else "EXISTS"));
               Syntax.Add_Child (Tree, Result, Parse_Group);
               return Result;
            end;
         end if;

         --  A keyword here begins a built-in call; anything else is a term
         --  or, if a parenthesis follows an IRI, a function call.
         if Peek = Lexers.Keyword_Token then
            declare
               Name   : constant String := Lexers.Text (Current);
               Result : Syntax.Node_Reference;
            begin
               Advance;
               Result := Node (Syntax.Call_Node, Name);
               if Peek = Lexers.Open_Paren_Token then
                  Advance;
                  if Peek = Lexers.Star_Token then
                     --  COUNT(*)
                     Advance;
                     Syntax.Add_Child
                       (Tree, Result, Node (Syntax.Variable_Node, "*"));
                  elsif Peek /= Lexers.Close_Paren_Token then
                     if Take_Keyword ("DISTINCT") then
                        Syntax.Add_Child
                          (Tree, Result,
                           Node (Syntax.Call_Node, "DISTINCT"));
                     end if;
                     loop
                        Syntax.Add_Child (Tree, Result, Parse_Expression);
                        exit when Peek /= Lexers.Comma_Token;
                        Advance;
                     end loop;
                     if Peek = Lexers.Semicolon_Token then
                        --  GROUP_CONCAT(?x ; SEPARATOR = ", ")
                        Advance;
                        Expect_Keyword ("SEPARATOR");
                        Expect (Lexers.Equals_Token, "an equals sign");
                        declare
                           Separator : constant Syntax.Node_Reference :=
                             Node (Syntax.Call_Node, "SEPARATOR");
                        begin
                           Syntax.Add_Child
                             (Tree, Separator, Parse_Term);
                           Syntax.Add_Child (Tree, Result, Separator);
                        end;
                     end if;
                  end if;
                  Expect (Lexers.Close_Paren_Token,
                          "a closing parenthesis");
               end if;
               return Result;
            end;
         end if;

         declare
            Term : constant Syntax.Node_Reference := Parse_Term;
         begin
            if Syntax.Kind (Syntax.To_Query (Tree), Term)
               = Syntax.Blank_Node
            then
               Fail ("a blank node has no meaning in an expression");
            end if;

            if Peek = Lexers.Open_Paren_Token
              and then Syntax.Kind (Syntax.To_Query (Tree), Term)
                       in Syntax.IRI_Node | Syntax.Prefixed_Node
            then
               --  An IRI followed by an argument list is a function call.
               Advance;
               declare
                  Result : constant Syntax.Node_Reference :=
                    Node (Syntax.Call_Node, "");
               begin
                  Syntax.Add_Child (Tree, Result, Term);
                  if Peek /= Lexers.Close_Paren_Token then
                     loop
                        Syntax.Add_Child (Tree, Result, Parse_Expression);
                        exit when Peek /= Lexers.Comma_Token;
                        Advance;
                     end loop;
                  end if;
                  Expect (Lexers.Close_Paren_Token,
                          "a closing parenthesis");
                  return Result;
               end;
            end if;
            return Term;
         end;
      end Parse_Primary;

      function Parse_Unary return Syntax.Node_Reference is
      begin
         if Peek in Lexers.Forward_Path_Token | Lexers.Plus_Token
                  | Lexers.Minus_Token
         then
            declare
               Operator : constant String :=
                 (case Peek is
                     when Lexers.Forward_Path_Token => "!",
                     when Lexers.Plus_Token         => "+",
                     when others                    => "-");
               Result : Syntax.Node_Reference;
            begin
               Advance;
               Result := Node (Syntax.Unary_Node, Operator);
               Syntax.Add_Child (Tree, Result, Parse_Unary);
               return Result;
            end;
         end if;
         return Parse_Primary;
      end Parse_Unary;

      function Parse_Multiplicative return Syntax.Node_Reference is
         Left : Syntax.Node_Reference := Parse_Unary;
      begin
         while Peek in Lexers.Star_Token | Lexers.Slash_Token loop
            declare
               Operator : constant String :=
                 (if Peek = Lexers.Star_Token then "*" else "/");
               Result : Syntax.Node_Reference;
            begin
               Advance;
               Result := Node (Syntax.Arithmetic_Node, Operator);
               Syntax.Add_Child (Tree, Result, Left);
               Syntax.Add_Child (Tree, Result, Parse_Unary);
               Left := Result;
            end;
         end loop;
         return Left;
      end Parse_Multiplicative;

      --  A numeric token that carries its own sign.
      function At_Signed_Number return Boolean
      is (Peek in Lexers.Integer_Token | Lexers.Decimal_Token
                | Lexers.Double_Token
          and then Lexers.Text (Current)'Length > 0
          and then Lexers.Text (Current) (Lexers.Text (Current)'First)
                   in '+' | '-');

      function Parse_Additive return Syntax.Node_Reference is
         Left : Syntax.Node_Reference := Parse_Multiplicative;
      begin
         while At_Signed_Number loop
            declare
               Text : constant String := Lexers.Text (Current);
               Operator : constant String := [1 => Text (Text'First)];
               Result   : constant Syntax.Node_Reference :=
                 Node (Syntax.Arithmetic_Node, Operator);
               Operand  : constant Syntax.Node_Reference :=
                 Node (Syntax.Literal_Node,
                       Text (Text'First + 1 .. Text'Last),
                       Lexers.Token_Kind'Image (Peek));
            begin
               Advance;
               Syntax.Add_Child (Tree, Result, Left);
               Syntax.Add_Child (Tree, Result, Operand);
               Left := Result;
            end;
         end loop;

         while Peek in Lexers.Plus_Token | Lexers.Minus_Token loop
            declare
               Operator : constant String :=
                 (if Peek = Lexers.Plus_Token then "+" else "-");
               Result : Syntax.Node_Reference;
            begin
               Advance;
               Result := Node (Syntax.Arithmetic_Node, Operator);
               Syntax.Add_Child (Tree, Result, Left);
               Syntax.Add_Child (Tree, Result, Parse_Multiplicative);
               Left := Result;
            end;
         end loop;
         return Left;
      end Parse_Additive;

      function Parse_Relational return Syntax.Node_Reference is
         Left : constant Syntax.Node_Reference := Parse_Additive;
      begin
         if Peek in Lexers.Equals_Token | Lexers.Not_Equal_Token
                  | Lexers.Less_Token | Lexers.Greater_Token
                  | Lexers.Less_Or_Equal_Token
                  | Lexers.Greater_Or_Equal_Token
         then
            declare
               Operator : constant String :=
                 (case Peek is
                     when Lexers.Equals_Token           => "=",
                     when Lexers.Not_Equal_Token        => "!=",
                     when Lexers.Less_Token             => "<",
                     when Lexers.Greater_Token          => ">",
                     when Lexers.Less_Or_Equal_Token    => "<=",
                     when others                        => ">=");
               Result : Syntax.Node_Reference;
            begin
               Advance;
               Result := Node (Syntax.Compare_Node, Operator);
               Syntax.Add_Child (Tree, Result, Left);
               Syntax.Add_Child (Tree, Result, Parse_Additive);
               return Result;
            end;
         end if;

         if At_Keyword ("IN") or else At_Keyword ("NOT") then
            declare
               Negated : constant Boolean := At_Keyword ("NOT");
               Result  : Syntax.Node_Reference;
            begin
               Advance;
               if Negated then
                  Expect_Keyword ("IN");
               end if;
               Result := Node (Syntax.In_Node,
                               (if Negated then "NOT IN" else "IN"));
               Syntax.Add_Child (Tree, Result, Left);
               Expect (Lexers.Open_Paren_Token, "an opening parenthesis");
               if Peek /= Lexers.Close_Paren_Token then
                  loop
                     Syntax.Add_Child (Tree, Result, Parse_Expression);
                     exit when Peek /= Lexers.Comma_Token;
                     Advance;
                  end loop;
               end if;
               Expect (Lexers.Close_Paren_Token, "a closing parenthesis");
               return Result;
            end;
         end if;

         return Left;
      end Parse_Relational;

      function Parse_Conjunction return Syntax.Node_Reference is
         Left : Syntax.Node_Reference := Parse_Relational;
      begin
         while Peek = Lexers.And_Token loop
            Advance;
            declare
               Result : constant Syntax.Node_Reference :=
                 Node (Syntax.And_Node, "&&");
            begin
               Syntax.Add_Child (Tree, Result, Left);
               Syntax.Add_Child (Tree, Result, Parse_Relational);
               Left := Result;
            end;
         end loop;
         return Left;
      end Parse_Conjunction;

      function Parse_Expression return Syntax.Node_Reference is
         Left : Syntax.Node_Reference := Parse_Conjunction;
      begin
         while Peek = Lexers.Or_Token loop
            Advance;
            declare
               Result : constant Syntax.Node_Reference :=
                 Node (Syntax.Or_Node, "||");
            begin
               Syntax.Add_Child (Tree, Result, Left);
               Syntax.Add_Child (Tree, Result, Parse_Conjunction);
               Left := Result;
            end;
         end loop;
         return Left;
      end Parse_Expression;

      ------------------------------------------------------------------
      --  Patterns
      ------------------------------------------------------------------

      --  A property path, as far as sequence, alternative, inverse and the
      --  three cardinality operators. The whole path is kept as one term
      --  whose children are its parts, because a path is written as one
      --  thing and should be written back as one.
      function Parse_Path return Syntax.Node_Reference is

         function Parse_Path_Primary return Syntax.Node_Reference is
         begin
            if Peek = Lexers.Backward_Path_Token then
               Advance;
               declare
                  Result : constant Syntax.Node_Reference :=
                    Node (Syntax.Unary_Node, "^");
               begin
                  Syntax.Add_Child (Tree, Result, Parse_Path_Primary);
                  return Result;
               end;
            elsif Peek = Lexers.Open_Paren_Token then
               Advance;
               declare
                  Inner : constant Syntax.Node_Reference := Parse_Path;
               begin
                  Expect (Lexers.Close_Paren_Token,
                          "a closing parenthesis");
                  return Inner;
               end;
            end if;
            declare
               Result : constant Syntax.Node_Reference := Parse_Term;
            begin
               if Syntax.Kind (Syntax.To_Query (Tree), Result)
                  in Syntax.Literal_Node | Syntax.Blank_Node
               then
                  Fail ("a predicate is an IRI, a variable or a path");
               end if;
               return Result;
            end;
         end Parse_Path_Primary;

         function Parse_Path_Unary return Syntax.Node_Reference is
            Base : Syntax.Node_Reference := Parse_Path_Primary;
         begin
            while Peek in Lexers.Star_Token | Lexers.Plus_Token
                        | Lexers.Variable_Token
            loop
               --  '?' as a cardinality marker reaches the scanner as an
               --  empty variable only when a name follows, so a bare '?'
               --  never gets here; the loop covers '*' and '+'.
               exit when Peek = Lexers.Variable_Token;
               declare
                  Operator : constant String :=
                    (if Peek = Lexers.Star_Token then "*" else "+");
                  Result : Syntax.Node_Reference;
               begin
                  Advance;
                  Result := Node (Syntax.Unary_Node, Operator, "postfix");
                  Syntax.Add_Child (Tree, Result, Base);
                  Base := Result;
               end;
            end loop;
            return Base;
         end Parse_Path_Unary;

         Left : Syntax.Node_Reference := Parse_Path_Unary;
      begin
         loop
            if Peek = Lexers.Slash_Token then
               Advance;
               declare
                  Result : constant Syntax.Node_Reference :=
                    Node (Syntax.Arithmetic_Node, "/");
               begin
                  Syntax.Add_Child (Tree, Result, Left);
                  Syntax.Add_Child (Tree, Result, Parse_Path_Unary);
                  Left := Result;
               end;
            elsif Peek = Lexers.Forward_Path_Token then
               Advance;
               declare
                  Result : constant Syntax.Node_Reference :=
                    Node (Syntax.Arithmetic_Node, "|");
               begin
                  Syntax.Add_Child (Tree, Result, Left);
                  Syntax.Add_Child (Tree, Result, Parse_Path_Unary);
                  Left := Result;
               end;
            else
               exit;
            end if;
         end loop;
         return Left;
      end Parse_Path;

      --  A term in a pattern is not the same as a term in an expression:
      --  a collection, a property list, or a reified triple names
      --  something and states triples about it at the same time, so the
      --  group being built has to be reachable from here.
      --  Quoted marks the positions inside << >> and <<( )>>, which are
      --  narrower than a pattern term in general: no collection, no
      --  property list with content, and no path as the predicate.
      function Parse_Pattern_Term
        (Into   : Syntax.Node_Reference;
         Quoted : Boolean := False) return Syntax.Node_Reference;

      --  A predicate that is a real path rather than a plain term. An
      --  annotation may not attach to one, and a quoted triple may not
      --  carry one.
      function Is_Path (Node : Syntax.Node_Reference) return Boolean
      is (Syntax.Kind (Syntax.To_Query (Tree), Node)
          in Syntax.Unary_Node | Syntax.Arithmetic_Node);

      procedure Parse_Predicate_Objects
        (Into    : Syntax.Node_Reference;
         Subject : Syntax.Node_Reference);

      function Parse_Pattern_Term
        (Into   : Syntax.Node_Reference;
         Quoted : Boolean := False) return Syntax.Node_Reference is
      begin
         case Peek is
            when Lexers.Open_Bracket_Token =>
               Advance;
               if Quoted and then Peek /= Lexers.Close_Bracket_Token then
                  Fail ("a property list is not admitted here");
               end if;
               declare
                  Subject : constant Syntax.Node_Reference := Fresh_Blank;
               begin
                  if Peek /= Lexers.Close_Bracket_Token then
                     Parse_Predicate_Objects (Into, Subject);
                  end if;
                  Expect (Lexers.Close_Bracket_Token, "a closing bracket");
                  return Subject;
               end;

            when Lexers.Open_Paren_Token =>
               if Quoted then
                  Fail ("a collection is not admitted here");
               end if;
               --  A collection: rdf:first and rdf:rest all the way down,
               --  with the empty one being rdf:nil.
               Advance;
               declare
                  Head    : Syntax.Node_Reference :=
                    Node (Syntax.IRI_Node,
                          "http://www.w3.org/1999/02/22-rdf-syntax-ns#nil");
                  Last    : Syntax.Node_Reference := Head;
                  Started : Boolean := False;
               begin
                  while Peek /= Lexers.Close_Paren_Token and then not At_End
                  loop
                     declare
                        Cell    : constant Syntax.Node_Reference :=
                          Fresh_Blank;
                        Element : constant Syntax.Node_Reference :=
                          Parse_Pattern_Term (Into);
                        First   : constant Syntax.Node_Reference :=
                          Node (Syntax.Triple_Node);
                     begin
                        Syntax.Add_Child (Tree, First, Cell);
                        Syntax.Add_Child
                          (Tree, First,
                           Node (Syntax.IRI_Node,
                                 "http://www.w3.org/1999/02/22-rdf-syntax"
                                 & "-ns#first"));
                        Syntax.Add_Child (Tree, First, Element);
                        Syntax.Add_Child (Tree, Into, First);

                        if Started then
                           declare
                              Rest : constant Syntax.Node_Reference :=
                                Node (Syntax.Triple_Node);
                           begin
                              Syntax.Add_Child (Tree, Rest, Last);
                              Syntax.Add_Child
                                (Tree, Rest,
                                 Node (Syntax.IRI_Node,
                                       "http://www.w3.org/1999/02/22-rdf"
                                       & "-syntax-ns#rest"));
                              Syntax.Add_Child (Tree, Rest, Cell);
                              Syntax.Add_Child (Tree, Into, Rest);
                           end;
                        else
                           Head := Cell;
                           Started := True;
                        end if;
                        Last := Cell;
                     end;
                  end loop;
                  Expect (Lexers.Close_Paren_Token,
                          "a closing parenthesis");
                  if Started then
                     declare
                        Rest : constant Syntax.Node_Reference :=
                          Node (Syntax.Triple_Node);
                     begin
                        Syntax.Add_Child (Tree, Rest, Last);
                        Syntax.Add_Child
                          (Tree, Rest,
                           Node (Syntax.IRI_Node,
                                 "http://www.w3.org/1999/02/22-rdf-syntax"
                                 & "-ns#rest"));
                        Syntax.Add_Child
                          (Tree, Rest,
                           Node (Syntax.IRI_Node,
                                 "http://www.w3.org/1999/02/22-rdf-syntax"
                                 & "-ns#nil"));
                        Syntax.Add_Child (Tree, Into, Rest);
                     end;
                  end if;
                  return Head;
               end;

            when Lexers.Open_Triple_Term_Token =>
               Advance;
               declare
                  Result : constant Syntax.Node_Reference :=
                    Node (Syntax.Triple_Term_Node);
               begin
                  Syntax.Add_Child
                    (Tree, Result, Parse_Pattern_Term (Into, Quoted => True));
                  declare
                     Predicate : constant Syntax.Node_Reference := Parse_Path;
                  begin
                     if Is_Path (Predicate) then
                        Fail ("a triple term admits no property path");
                     end if;
                     Syntax.Add_Child (Tree, Result, Predicate);
                  end;
                  Syntax.Add_Child
                    (Tree, Result, Parse_Pattern_Term (Into, Quoted => True));
                  Expect (Lexers.Close_Triple_Term_Token,
                          "a triple term terminator");
                  return Result;
               end;

            when Lexers.Open_Quoted_Token =>
               --  A reified triple names the reifying node and states the
               --  triple about it.
               Advance;
               declare
                  Result : constant Syntax.Node_Reference :=
                    Node (Syntax.Reified_Node);
               begin
                  Syntax.Add_Child
                    (Tree, Result, Parse_Pattern_Term (Into, Quoted => True));
                  declare
                     Predicate : constant Syntax.Node_Reference := Parse_Path;
                  begin
                     if Is_Path (Predicate) then
                        Fail ("a quoted triple admits no property path");
                     end if;
                     Syntax.Add_Child (Tree, Result, Predicate);
                  end;
                  Syntax.Add_Child
                    (Tree, Result, Parse_Pattern_Term (Into, Quoted => True));
                  if Peek = Lexers.Reifier_Token then
                     Advance;
                     if Peek in Lexers.IRI_Reference_Token
                              | Lexers.Prefixed_Name_Token
                              | Lexers.Blank_Label_Token
                              | Lexers.Variable_Token
                     then
                        Syntax.Add_Child (Tree, Result, Parse_Term);
                     else
                        Syntax.Add_Child (Tree, Result, Fresh_Blank);
                     end if;
                  end if;
                  Expect (Lexers.Close_Quoted_Token,
                          "a quoted triple terminator");
                  Syntax.Add_Child (Tree, Into, Result);
                  return Result;
               end;

            when others =>
               return Parse_Term;
         end case;
      end Parse_Pattern_Term;

      --  A reifier or annotation block attaching to the triple just read.
      procedure Parse_Annotation
        (Into   : Syntax.Node_Reference;
         Triple : Syntax.Node_Reference) is
      begin
         while Peek in Lexers.Reifier_Token | Lexers.Open_Annotation_Token
         loop
            declare
               Marker : constant Syntax.Node_Reference :=
                 Node (Syntax.Reified_Node, "annotation");
            begin
               Syntax.Add_Child (Tree, Marker, Triple);
               if Peek = Lexers.Reifier_Token then
                  Advance;
                  if Peek in Lexers.IRI_Reference_Token
                           | Lexers.Prefixed_Name_Token
                           | Lexers.Blank_Label_Token
                           | Lexers.Variable_Token
                  then
                     Syntax.Add_Child (Tree, Marker, Parse_Term);
                  else
                     Syntax.Add_Child (Tree, Marker, Fresh_Blank);
                  end if;
               else
                  Syntax.Add_Child (Tree, Marker, Fresh_Blank);
               end if;

               if Peek = Lexers.Open_Annotation_Token then
                  Advance;
                  Parse_Predicate_Objects
                    (Into, Syntax.Child
                             (Syntax.To_Query (Tree), Marker, 2));
                  Expect (Lexers.Close_Annotation_Token,
                          "an annotation terminator");
               end if;
               Syntax.Add_Child (Tree, Into, Marker);
            end;
         end loop;
      end Parse_Annotation;

      procedure Parse_Predicate_Objects
        (Into    : Syntax.Node_Reference;
         Subject : Syntax.Node_Reference) is
      begin
         loop
            declare
               Predicate : constant Syntax.Node_Reference := Parse_Path;
            begin
               loop
                  declare
                     Triple : constant Syntax.Node_Reference :=
                       Node (Syntax.Triple_Node);
                  begin
                     Syntax.Add_Child (Tree, Triple, Subject);
                     Syntax.Add_Child (Tree, Triple, Predicate);
                     Syntax.Add_Child
                       (Tree, Triple, Parse_Pattern_Term (Into));
                     Syntax.Add_Child (Tree, Into, Triple);
                     if Peek in Lexers.Reifier_Token
                              | Lexers.Open_Annotation_Token
                       and then Is_Path (Predicate)
                     then
                        Fail ("an annotation cannot attach to a triple"
                              & " whose predicate is a property path");
                     end if;
                     Parse_Annotation (Into, Triple);
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
              or else Peek in Lexers.Dot_Token | Lexers.Close_Brace_Token
                            | Lexers.Close_Bracket_Token
                            | Lexers.Close_Annotation_Token;
            --  A trailing semicolon may be followed by the next pattern
            --  rather than by another predicate.
            exit when Peek = Lexers.Keyword_Token
              and then Upper (Lexers.Text (Current)) in
                "OPTIONAL" | "FILTER" | "GRAPH" | "MINUS" | "BIND"
                | "SERVICE" | "VALUES" | "UNION";
         end loop;
      end Parse_Predicate_Objects;

      --  A block of triples sharing subjects and predicates.
      procedure Parse_Triples (Into : Syntax.Node_Reference) is
      begin
         loop
            declare
               --  A term may stand without predicates only if reading it
               --  stated something: a property list carrying predicates, a
               --  non-empty collection, or a reified triple. A plain node,
               --  an empty list, a bare "[]" and a triple term all state
               --  nothing, and a pattern made only of them is not a
               --  pattern. Counting what reading it contributed answers
               --  all six cases at once.
               Before  : constant Natural :=
                 Syntax.Child_Count (Syntax.To_Query (Tree), Into);
               Subject : constant Syntax.Node_Reference :=
                 Parse_Pattern_Term (Into);
            begin
               if Peek in Lexers.Dot_Token | Lexers.Close_Brace_Token then
                  if Syntax.Child_Count (Syntax.To_Query (Tree), Into)
                     = Before
                  then
                     Fail ("this term states nothing on its own");
                  end if;
               else
                  Parse_Predicate_Objects (Into, Subject);
               end if;
            end;

            if Peek /= Lexers.Dot_Token then
               if Peek in Lexers.IRI_Reference_Token
                        | Lexers.Prefixed_Name_Token
                        | Lexers.Blank_Label_Token | Lexers.Variable_Token
                        | Lexers.String_Token | Lexers.Integer_Token
                        | Lexers.Decimal_Token | Lexers.Double_Token
                        | Lexers.Boolean_Token | Lexers.Open_Quoted_Token
                        | Lexers.Open_Triple_Term_Token
               then
                  Fail ("a triple is missing its terminator");
               end if;
               exit;
            end if;
            Advance;
            exit when At_End or else Peek = Lexers.Close_Brace_Token;
            exit when Peek = Lexers.Keyword_Token
              and then Upper (Lexers.Text (Current)) in
                "OPTIONAL" | "FILTER" | "GRAPH" | "MINUS" | "BIND"
                | "SERVICE" | "VALUES" | "UNION";
            exit when Peek = Lexers.Open_Brace_Token;
         end loop;
      end Parse_Triples;

      --  Parse a SELECT that is nested inside a pattern. The braces around
      --  it belong to the caller, because the grammar lets a subquery be a
      --  group's whole content as well as one item within it.
      procedure Parse_Subselect (Item : Syntax.Node_Reference);

      --  An inline data block. It may close a query as well as sit inside
      --  a pattern, so it is written once and called from both.
      function Parse_Values return Syntax.Node_Reference is
         Item : constant Syntax.Node_Reference :=
           Node (Syntax.Values_Node);
         Vars : constant Syntax.Node_Reference :=
           Node (Syntax.Projection_Node);
      begin
               --  Two spellings: one variable with bare values, or a
               --  parenthesised list with parenthesised rows.
               if Peek = Lexers.Open_Paren_Token then
                  Advance;
                  while Peek = Lexers.Variable_Token loop
                     Syntax.Add_Child (Tree, Vars, Parse_Term);
                  end loop;
                  Expect (Lexers.Close_Paren_Token,
                          "a closing parenthesis");
                  Syntax.Add_Child (Tree, Item, Vars);
                  Expect (Lexers.Open_Brace_Token, "an opening brace");
                  while Peek = Lexers.Open_Paren_Token loop
                     Advance;
                     declare
                        Row : constant Syntax.Node_Reference :=
                          Node (Syntax.Projection_Node, "row");
                     begin
                        while Peek /= Lexers.Close_Paren_Token
                          and then not At_End
                        loop
                           if At_Keyword ("UNDEF") then
                              Advance;
                              Syntax.Add_Child
                                (Tree, Row,
                                 Node (Syntax.Call_Node, "UNDEF"));
                           else
                              Syntax.Add_Child (Tree, Row, Parse_Term);
                           end if;
                        end loop;
                        Expect (Lexers.Close_Paren_Token,
                                "a closing parenthesis");
                        Syntax.Add_Child (Tree, Item, Row);
                     end;
                  end loop;
                  Expect (Lexers.Close_Brace_Token, "a closing brace");
               else
                  Syntax.Add_Child (Tree, Vars, Parse_Term);
                  Syntax.Add_Child (Tree, Item, Vars);
                  Expect (Lexers.Open_Brace_Token, "an opening brace");
                  while Peek /= Lexers.Close_Brace_Token
                    and then not At_End
                  loop
                     declare
                        Row : constant Syntax.Node_Reference :=
                          Node (Syntax.Projection_Node, "row");
                     begin
                        if At_Keyword ("UNDEF") then
                           Advance;
                           Syntax.Add_Child
                             (Tree, Row,
                              Node (Syntax.Call_Node, "UNDEF"));
                        else
                           Syntax.Add_Child (Tree, Row, Parse_Term);
                        end if;
                        Syntax.Add_Child (Tree, Item, Row);
                     end;
                  end loop;
                  Expect (Lexers.Close_Brace_Token, "a closing brace");
         end if;

         declare
            Width : constant Natural :=
              Syntax.Child_Count (Syntax.To_Query (Tree), Vars);
            Seen  : String_Sets.Set;
            Built : constant Syntax.Query := Syntax.To_Query (Tree);
         begin
            for Index in 1 .. Width loop
               declare
                  Name : constant String :=
                    Syntax.Text (Built, Syntax.Child (Built, Vars, Index));
               begin
                  if Seen.Contains (Name) then
                     Fail ("?" & Name & " is bound twice by one VALUES");
                  end if;
                  Seen.Include (Name);
               end;
            end loop;

            --  Each row supplies one value per variable; a row of another
            --  length does not describe a binding.
            for Index in 2 .. Syntax.Child_Count (Built, Item) loop
               if Syntax.Child_Count
                    (Built, Syntax.Child (Built, Item, Index)) /= Width
               then
                  Fail ("a VALUES row does not match the variable list");
               end if;
            end loop;
         end;

         return Item;
      end Parse_Values;

      function Parse_Group return Syntax.Node_Reference is
         Result : constant Syntax.Node_Reference := Node (Syntax.Group_Node);
      begin
         Expect (Lexers.Open_Brace_Token, "an opening brace");

         if At_Keyword ("SELECT") then
            declare
               Item : constant Syntax.Node_Reference :=
                 Node (Syntax.Subquery_Node);
            begin
               Advance;
               Parse_Subselect (Item);
               Syntax.Add_Child (Tree, Result, Item);
               Expect (Lexers.Close_Brace_Token, "a closing brace");
               return Result;
            end;
         end if;

         while not At_End and then Peek /= Lexers.Close_Brace_Token loop
            if At_Keyword ("OPTIONAL") then
               Advance;
               declare
                  Item : constant Syntax.Node_Reference :=
                    Node (Syntax.Optional_Node);
               begin
                  Syntax.Add_Child (Tree, Item, Parse_Group);
                  Syntax.Add_Child (Tree, Result, Item);
               end;

            elsif At_Keyword ("MINUS") then
               Advance;
               declare
                  Item : constant Syntax.Node_Reference :=
                    Node (Syntax.Minus_Node);
               begin
                  Syntax.Add_Child (Tree, Item, Parse_Group);
                  Syntax.Add_Child (Tree, Result, Item);
               end;

            elsif At_Keyword ("GRAPH") or else At_Keyword ("SERVICE") then
               declare
                  Is_Graph : constant Boolean := At_Keyword ("GRAPH");
                  Item     : Syntax.Node_Reference;
               begin
                  Advance;
                  Item := Node (if Is_Graph then Syntax.Graph_Node
                                else Syntax.Service_Node);
                  Syntax.Add_Child (Tree, Item, Parse_Term);
                  Syntax.Add_Child (Tree, Item, Parse_Group);
                  Syntax.Add_Child (Tree, Result, Item);
               end;

            elsif At_Keyword ("FILTER") then
               Advance;
               if Peek not in Lexers.Open_Paren_Token | Lexers.Keyword_Token
                            | Lexers.IRI_Reference_Token
                            | Lexers.Prefixed_Name_Token
               then
                  --  A constraint is a bracketed expression or a call;
                  --  a bare term is neither.
                  Fail ("FILTER takes a bracketed expression or a call");
               end if;
               declare
                  Item : constant Syntax.Node_Reference :=
                    Node (Syntax.Filter_Node);
               begin
                  Syntax.Add_Child (Tree, Item, Parse_Expression);
                  Syntax.Add_Child (Tree, Result, Item);
               end;

            elsif At_Keyword ("BIND") then
               Advance;
               Expect (Lexers.Open_Paren_Token, "an opening parenthesis");
               declare
                  Item  : constant Syntax.Node_Reference :=
                    Node (Syntax.Bind_Node);
                  Value : constant Syntax.Node_Reference := Parse_Expression;
               begin
                  Expect_Keyword ("AS");
                  Syntax.Add_Child (Tree, Item, Value);
                  Syntax.Add_Child (Tree, Item, Parse_Term);
                  Expect (Lexers.Close_Paren_Token,
                          "a closing parenthesis");
                  Syntax.Add_Child (Tree, Result, Item);
               end;

            elsif At_Keyword ("VALUES") then
               Advance;
               Syntax.Add_Child (Tree, Result, Parse_Values);

            elsif Peek = Lexers.Open_Brace_Token
              and then Next + 1 <= Tokens.Last_Index
              and then Lexers.Kind (Tokens (Next + 1)) = Lexers.Keyword_Token
              and then Upper (Lexers.Text (Tokens (Next + 1))) = "SELECT"
            then
               --  A subquery written as one item of a group.
               Advance;
               declare
                  Item : constant Syntax.Node_Reference :=
                    Node (Syntax.Subquery_Node);
               begin
                  Advance;
                  Parse_Subselect (Item);
                  Expect (Lexers.Close_Brace_Token, "a closing brace");
                  Syntax.Add_Child (Tree, Result, Item);
               end;

            elsif Peek = Lexers.Open_Brace_Token then
               declare
                  Left : Syntax.Node_Reference := Parse_Group;
               begin
                  while At_Keyword ("UNION") loop
                     Advance;
                     declare
                        Item : constant Syntax.Node_Reference :=
                          Node (Syntax.Union_Node);
                     begin
                        Syntax.Add_Child (Tree, Item, Left);
                        Syntax.Add_Child (Tree, Item, Parse_Group);
                        Left := Item;
                     end;
                  end loop;
                  Syntax.Add_Child (Tree, Result, Left);
               end;

            elsif Peek = Lexers.Dot_Token then
               if Syntax.Child_Count (Syntax.To_Query (Tree), Result) = 0
               then
                  Fail ("a terminator with nothing before it");
               end if;
               Advance;

            else
               Parse_Triples (Result);
            end if;
         end loop;

         Expect (Lexers.Close_Brace_Token, "a closing brace");
         return Result;
      end Parse_Group;

      procedure Parse_Subselect (Item : Syntax.Node_Reference) is
         Items : constant Syntax.Node_Reference :=
           Node (Syntax.Projection_Node);
      begin
            if Take_Keyword ("DISTINCT") then
               Syntax.Add_Child
                 (Tree, Item, Node (Syntax.Call_Node, "DISTINCT"));
            elsif Take_Keyword ("REDUCED") then
               Syntax.Add_Child
                 (Tree, Item, Node (Syntax.Call_Node, "REDUCED"));
            end if;

            if Peek = Lexers.Star_Token then
               Advance;
               Syntax.Add_Child
                 (Tree, Items, Node (Syntax.Variable_Node, "*"));
            else
               loop
                  if Peek = Lexers.Open_Paren_Token then
                     Advance;
                     declare
                        Bound : constant Syntax.Node_Reference :=
                          Node (Syntax.Projection_Node, "AS");
                        Value : constant Syntax.Node_Reference :=
                          Parse_Expression;
                     begin
                        Expect_Keyword ("AS");
                        Syntax.Add_Child (Tree, Bound, Value);
                        Syntax.Add_Child (Tree, Bound, Parse_Term);
                        Expect (Lexers.Close_Paren_Token,
                                "a closing parenthesis");
                        Syntax.Add_Child (Tree, Items, Bound);
                     end;
                  else
                     Syntax.Add_Child (Tree, Items, Parse_Term);
                  end if;
                  exit when Peek /= Lexers.Variable_Token
                    and then Peek /= Lexers.Open_Paren_Token;
               end loop;
            end if;
            Syntax.Add_Child (Tree, Item, Items);

            if Take_Keyword ("WHERE") then
               null;
            end if;
            Syntax.Add_Child (Tree, Item, Parse_Group);

            --  Trailing modifiers belong to the subquery.
            while At_Keyword ("GROUP") or else At_Keyword ("HAVING")
              or else At_Keyword ("ORDER") or else At_Keyword ("LIMIT")
              or else At_Keyword ("OFFSET")
            loop
               declare
                  Word : constant String :=
                    Upper (Lexers.Text (Current));
                  Modifier : constant Syntax.Node_Reference :=
                    Node (Syntax.Call_Node, Word);
               begin
                  Advance;
                  if Word in "GROUP" | "ORDER" then
                     Expect_Keyword ("BY");
                  end if;
                  if Word in "LIMIT" | "OFFSET" then
                     Syntax.Add_Child (Tree, Modifier, Parse_Term);
                  else
                     Syntax.Add_Child
                       (Tree, Modifier, Parse_Expression);
                  end if;
                  Syntax.Add_Child (Tree, Item, Modifier);
               end;
            end loop;

      end Parse_Subselect;

      ------------------------------------------------------------------
      --  Clauses
      ------------------------------------------------------------------

      procedure Parse_Prologue is
      begin
         loop
            if Take_Keyword ("BASE") then
               if Peek /= Lexers.IRI_Reference_Token then
                  Fail ("expected a base IRI");
               end if;
               Syntax.Set_Base (Tree, Lexers.Text (Current));
               Advance;
            elsif Peek = Lexers.Version_Directive_Token
              or else At_Keyword ("VERSION")
            then
               Advance;
               if Peek /= Lexers.String_Token then
                  Fail ("expected a version string");
               elsif Lexers.Form (Current) = Lexers.Long_Quoted then
                  --  A version is a short-quoted string, as it is in
                  --  Turtle.
                  Fail ("a version must be a short-quoted string");
               end if;
               Syntax.Set_Version (Tree, Lexers.Text (Current));
               Advance;
            elsif At_Keyword ("PREFIX") then
               Advance;
               if Peek /= Lexers.Prefixed_Name_Token
                 or else Lexers.Text (Current) /= ""
               then
                  Fail ("expected a prefix name");
               end if;
               declare
                  Name : constant String := Lexers.Prefix (Current);
               begin
                  Advance;
                  if Peek /= Lexers.IRI_Reference_Token then
                     Fail ("expected a namespace IRI");
                  end if;
                  Syntax.Add_Prefix (Tree, Name, Lexers.Text (Current));
                  Advance;
               end;
            else
               exit;
            end if;
         end loop;
      end Parse_Prologue;

      --  FROM and FROM NAMED, which name the dataset a query runs over.
      procedure Parse_Dataset is
         Items : constant Syntax.Node_Reference :=
           Node (Syntax.Dataset_Node);
         Any   : Boolean := False;
      begin
         while At_Keyword ("FROM") loop
            Advance;
            declare
               Named : constant Boolean := Take_Keyword ("NAMED");
               Item  : constant Syntax.Node_Reference :=
                 Node (Syntax.Dataset_Node,
                       (if Named then "FROM NAMED" else "FROM"));
            begin
               Syntax.Add_Child (Tree, Item, Parse_Term);
               Syntax.Add_Child (Tree, Items, Item);
               Any := True;
            end;
         end loop;
         if Any then
            Syntax.Set_Dataset (Tree, Items);
         end if;
      end Parse_Dataset;

      --  A query may close with an inline data block, which joins whatever
      --  the pattern produced.
      procedure Parse_Trailing_Values is
      begin
         if At_Keyword ("VALUES") then
            Advance;
            declare
               Where : constant Syntax.Node_Reference :=
                 Syntax.Where_Clause (Syntax.To_Query (Tree));
               Data  : constant Syntax.Node_Reference := Parse_Values;
            begin
               if Where /= Syntax.No_Node then
                  Syntax.Add_Child (Tree, Where, Data);
               end if;
            end;
         end if;
      end Parse_Trailing_Values;

      procedure Parse_Modifiers is
      begin
         if At_Keyword ("GROUP") then
            Advance;
            Expect_Keyword ("BY");
            declare
               Items : constant Syntax.Node_Reference :=
                 Node (Syntax.Projection_Node);
            begin
               loop
                  Syntax.Add_Child (Tree, Items, Parse_Expression);
                  exit when At_End
                    or else Peek not in Lexers.Variable_Token
                                      | Lexers.Open_Paren_Token
                                      | Lexers.Keyword_Token
                                      | Lexers.IRI_Reference_Token
                                      | Lexers.Prefixed_Name_Token;
                  exit when At_Keyword ("HAVING") or else At_Keyword ("ORDER")
                    or else At_Keyword ("LIMIT") or else At_Keyword ("OFFSET");
               end loop;
               Syntax.Set_Group_By (Tree, Items);
            end;
         end if;

         if At_Keyword ("HAVING") then
            Advance;
            Syntax.Set_Having (Tree, Parse_Expression);
         end if;

         if At_Keyword ("ORDER") then
            Advance;
            Expect_Keyword ("BY");
            declare
               Items : constant Syntax.Node_Reference :=
                 Node (Syntax.Projection_Node);
            begin
               loop
                  declare
                     Direction : String (1 .. 4) := "    ";
                     Length    : Natural := 0;
                  begin
                     if At_Keyword ("ASC") then
                        Advance;
                        Direction (1 .. 3) := "ASC";
                        Length := 3;
                     elsif At_Keyword ("DESC") then
                        Advance;
                        Direction (1 .. 4) := "DESC";
                        Length := 4;
                     end if;
                     declare
                        Key : constant Syntax.Node_Reference :=
                          Node (Syntax.Order_Term_Node,
                                Direction (1 .. Length));
                     begin
                        Syntax.Add_Child (Tree, Key, Parse_Expression);
                        Syntax.Add_Child (Tree, Items, Key);
                     end;
                  end;
                  exit when At_End
                    or else At_Keyword ("LIMIT")
                    or else At_Keyword ("OFFSET")
                    or else Peek not in Lexers.Variable_Token
                                      | Lexers.Open_Paren_Token
                                      | Lexers.Keyword_Token;
               end loop;
               Syntax.Set_Order_By (Tree, Items);
            end;
         end if;

         loop
            if At_Keyword ("LIMIT") then
               Advance;
               if Peek /= Lexers.Integer_Token then
                  Fail ("expected a limit");
               end if;
               Syntax.Set_Limit (Tree, Integer'Value (Lexers.Text (Current)));
               Advance;
            elsif At_Keyword ("OFFSET") then
               Advance;
               if Peek /= Lexers.Integer_Token then
                  Fail ("expected an offset");
               end if;
               Syntax.Set_Offset
                 (Tree, Integer'Value (Lexers.Text (Current)));
               Advance;
            else
               exit;
            end if;
         end loop;

         Parse_Trailing_Values;
      end Parse_Modifiers;

      procedure Parse_Select is
         Items : constant Syntax.Node_Reference :=
           Node (Syntax.Projection_Node);
      begin
         Syntax.Start (Tree, Syntax.Select_Query);
         if Take_Keyword ("DISTINCT") then
            Syntax.Set_Duplicates (Tree, Syntax.Distinct_Solutions);
         elsif Take_Keyword ("REDUCED") then
            Syntax.Set_Duplicates (Tree, Syntax.Reduced_Solutions);
         end if;

         if Peek = Lexers.Star_Token then
            Advance;
            Syntax.Set_Selects_All (Tree, True);
         else
            loop
               if Peek = Lexers.Open_Paren_Token then
                  --  ( expression AS ?name )
                  Advance;
                  declare
                     Item  : constant Syntax.Node_Reference :=
                       Node (Syntax.Projection_Node, "AS");
                     Value : constant Syntax.Node_Reference :=
                       Parse_Expression;
                  begin
                     Expect_Keyword ("AS");
                     Syntax.Add_Child (Tree, Item, Value);
                     Syntax.Add_Child (Tree, Item, Parse_Term);
                     Expect (Lexers.Close_Paren_Token,
                             "a closing parenthesis");
                     Syntax.Add_Child (Tree, Items, Item);
                  end;
               else
                  Syntax.Add_Child (Tree, Items, Parse_Term);
               end if;
               exit when Peek /= Lexers.Variable_Token
                 and then Peek /= Lexers.Open_Paren_Token;
            end loop;
            Syntax.Set_Projection (Tree, Items);
         end if;

         Parse_Dataset;
         if Take_Keyword ("WHERE") then
            null;
         end if;
         Syntax.Set_Where (Tree, Parse_Group);
         Parse_Modifiers;
      end Parse_Select;

      --  Some of what SPARQL calls a syntax error is not expressible in
      --  its grammar: a projection that repeats a name, a BIND onto a
      --  variable already in scope, a blank node label shared between two
      --  pattern groups. A parser that only implements the grammar accepts
      --  all of them, so these are checked over the finished tree.
      procedure Validate is
         Query_Value : constant Syntax.Query := Syntax.To_Query (Tree);
         Bound       : String_Sets.Set;
         Group_Depth : Natural := 0;
         Group_Serial : Natural := 0;
         Labels      : String_Sets.Set;

         procedure Complain (Message : String) is
         begin
            raise Parse_Error with Message;
         end Complain;

         procedure Walk (Node : Syntax.Node_Reference);

         --  Every variable a pattern makes available to what follows it.
         procedure Collect_Variables (Node : Syntax.Node_Reference) is
         begin
            if Node = Syntax.No_Node then
               return;
            end if;
            if Syntax.Kind (Query_Value, Node) = Syntax.Variable_Node then
               Bound.Include (Syntax.Text (Query_Value, Node));
            end if;
            for Index in 1 .. Syntax.Child_Count (Query_Value, Node) loop
               Collect_Variables (Syntax.Child (Query_Value, Node, Index));
            end loop;
         end Collect_Variables;

         procedure Walk (Node : Syntax.Node_Reference) is
         begin
            if Node = Syntax.No_Node then
               return;
            end if;

            case Syntax.Kind (Query_Value, Node) is
               when Syntax.Triple_Node =>
                  --  A blank node label may not be shared between two
                  --  groups; within one it is an ordinary node.
                  for Index in 1 .. Syntax.Child_Count (Query_Value, Node)
                  loop
                     declare
                        Part : constant Syntax.Node_Reference :=
                          Syntax.Child (Query_Value, Node, Index);
                     begin
                        if Syntax.Kind (Query_Value, Part)
                           = Syntax.Blank_Node
                          and then Syntax.Text (Query_Value, Part)'Length > 0
                          and then Syntax.Text (Query_Value, Part) (1) /= 'g'
                        then
                           declare
                              Tag : constant String :=
                                Group_Serial'Image & ":"
                                & Syntax.Text (Query_Value, Part);
                              Bare : constant String :=
                                Syntax.Text (Query_Value, Part);
                           begin
                              if Labels.Contains (Bare)
                                and then not Labels.Contains (Tag)
                              then
                                 Complain
                                   ("blank node label """ & Bare
                                    & """ is used in more than one group");
                              end if;
                              Labels.Include (Bare);
                              Labels.Include (Tag);
                           end;
                        end if;
                     end;
                  end loop;
                  Collect_Variables (Node);

               when Syntax.Bind_Node =>
                  declare
                     Target : constant Syntax.Node_Reference :=
                       Syntax.Child (Query_Value, Node, 2);
                  begin
                     if Syntax.Kind (Query_Value, Target)
                        = Syntax.Variable_Node
                       and then Bound.Contains
                                  (Syntax.Text (Query_Value, Target))
                     then
                        Complain
                          ("BIND assigns to ?"
                           & Syntax.Text (Query_Value, Target)
                           & ", which is already in scope");
                     end if;
                     Collect_Variables (Target);
                  end;

               when Syntax.Group_Node | Syntax.Optional_Node
                  | Syntax.Union_Node | Syntax.Minus_Node
                  | Syntax.Graph_Node | Syntax.Service_Node =>
                  --  Scope runs one group at a time. A nested group starts
                  --  with none of the enclosing group's variables, which is
                  --  why a BIND inside one may name a variable bound
                  --  outside it, and why the two branches of a UNION do not
                  --  see each other. What the group binds joins the
                  --  enclosing scope once it closes, so a BIND *after* it
                  --  may not reuse those names.
                  declare
                     Enclosing : constant String_Sets.Set := Bound;
                  begin
                     Bound.Clear;
                     Group_Depth := Group_Depth + 1;
                     Group_Serial := Group_Serial + 1;
                     for Index in 1 .. Syntax.Child_Count (Query_Value, Node)
                     loop
                        Walk (Syntax.Child (Query_Value, Node, Index));
                     end loop;
                     Group_Depth := Group_Depth - 1;
                     Bound.Union (Enclosing);
                  end;

               when Syntax.Subquery_Node =>
                  --  A subquery has its own scope; nothing inside it
                  --  constrains the query around it.
                  null;

               when others =>
                  for Index in 1 .. Syntax.Child_Count (Query_Value, Node)
                  loop
                     Walk (Syntax.Child (Query_Value, Node, Index));
                  end loop;
            end case;
         end Walk;

      begin
         Walk (Syntax.Where_Clause (Query_Value));

         --  A projection may not name the same variable twice, however it
         --  arrives there.
         if Syntax.Projection (Query_Value) /= Syntax.No_Node then
            declare
               Seen : String_Sets.Set;
               List : constant Syntax.Node_Reference :=
                 Syntax.Projection (Query_Value);
            begin
               for Index in 1 .. Syntax.Child_Count (Query_Value, List) loop
                  declare
                     Item : constant Syntax.Node_Reference :=
                       Syntax.Child (Query_Value, List, Index);
                     Name : constant String :=
                       (if Syntax.Kind (Query_Value, Item)
                           = Syntax.Variable_Node
                        then Syntax.Text (Query_Value, Item)
                        elsif Syntax.Kind (Query_Value, Item)
                              = Syntax.Projection_Node
                          and then Syntax.Child_Count (Query_Value, Item) > 1
                        then Syntax.Text
                               (Query_Value,
                                Syntax.Child (Query_Value, Item, 2))
                        else "");
                  begin
                     if Name /= "" then
                        if Seen.Contains (Name) then
                           Complain
                             ("?" & Name & " is projected more than once");
                        end if;
                        Seen.Include (Name);
                     end if;
                  end;
               end loop;
            end;
         end if;

         --  Aggregates: fixed arity, and never one inside another.
         declare
            function Is_Aggregate (Name : String) return Boolean
            is (Upper (Name) in "COUNT" | "SUM" | "MIN" | "MAX" | "AVG"
                              | "SAMPLE" | "GROUP_CONCAT");

            --  DISTINCT and SEPARATOR ride along as marker children and
            --  are not arguments.
            function Argument_Count
              (Node : Syntax.Node_Reference) return Natural
            is
               Total : Natural := 0;
            begin
               for Index in 1 .. Syntax.Child_Count (Query_Value, Node) loop
                  declare
                     Item : constant Syntax.Node_Reference :=
                       Syntax.Child (Query_Value, Node, Index);
                  begin
                     if Syntax.Kind (Query_Value, Item) /= Syntax.Call_Node
                       or else Syntax.Text (Query_Value, Item)
                               not in "DISTINCT" | "SEPARATOR"
                     then
                        Total := Total + 1;
                     end if;
                  end;
               end loop;
               return Total;
            end Argument_Count;

            procedure Check_Aggregates
              (Node   : Syntax.Node_Reference;
               Inside : Boolean)
            is
               Here : Boolean := Inside;
            begin
               if Node = Syntax.No_Node then
                  return;
               end if;

               if Syntax.Kind (Query_Value, Node) = Syntax.Call_Node
                 and then Is_Aggregate (Syntax.Text (Query_Value, Node))
               then
                  if Inside then
                     Complain ("an aggregate cannot contain another");
                  end if;
                  Here := True;

                  declare
                     Name  : constant String :=
                       Upper (Syntax.Text (Query_Value, Node));
                     Count : constant Natural := Argument_Count (Node);
                  begin
                     if Name = "GROUP_CONCAT" then
                        if Count /= 1 then
                           Complain ("GROUP_CONCAT takes one expression");
                        end if;
                     elsif Count /= 1 then
                        Complain
                          (Name & " takes exactly one argument, not"
                           & Count'Image);
                     end if;
                  end;
               end if;

               for Index in 1 .. Syntax.Child_Count (Query_Value, Node) loop
                  Check_Aggregates
                    (Syntax.Child (Query_Value, Node, Index), Here);
               end loop;
            end Check_Aggregates;
         begin
            Check_Aggregates (Syntax.Projection (Query_Value), False);
            Check_Aggregates (Syntax.Having (Query_Value), False);
            Check_Aggregates (Syntax.Order_By (Query_Value), False);
         end;

         --  With GROUP BY, a bare projected variable has to be one of the
         --  grouping keys: nothing else survives the grouping.
         if Syntax.Group_By (Query_Value) /= Syntax.No_Node
           and then Syntax.Projection (Query_Value) /= Syntax.No_Node
         then
            declare
               Keys : String_Sets.Set;
               List : constant Syntax.Node_Reference :=
                 Syntax.Group_By (Query_Value);
               Items : constant Syntax.Node_Reference :=
                 Syntax.Projection (Query_Value);
            begin
               for Index in 1 .. Syntax.Child_Count (Query_Value, List) loop
                  declare
                     Key : constant Syntax.Node_Reference :=
                       Syntax.Child (Query_Value, List, Index);
                  begin
                     if Syntax.Kind (Query_Value, Key)
                        = Syntax.Variable_Node
                     then
                        Keys.Include (Syntax.Text (Query_Value, Key));
                     end if;
                  end;
               end loop;

               for Index in 1 .. Syntax.Child_Count (Query_Value, Items) loop
                  declare
                     Item : constant Syntax.Node_Reference :=
                       Syntax.Child (Query_Value, Items, Index);
                  begin
                     if Syntax.Kind (Query_Value, Item)
                        = Syntax.Variable_Node
                       and then not Keys.Contains
                                      (Syntax.Text (Query_Value, Item))
                     then
                        Complain
                          ("?" & Syntax.Text (Query_Value, Item)
                           & " is projected but is not a grouping key");
                     end if;
                  end;
               end loop;
            end;
         end if;

         --  GROUP BY replaces the solution's variables, so "*" has nothing
         --  left to mean.
         if Syntax.Group_By (Query_Value) /= Syntax.No_Node
           and then Syntax.Selects_All (Query_Value)
         then
            Complain ("SELECT * cannot be combined with GROUP BY");
         end if;
      end Validate;

   begin
      Tokenize;
      if Tokens.Is_Empty then
         raise Parse_Error with "the query is empty";
      end if;

      Parse_Prologue;

      if Take_Keyword ("SELECT") then
         Parse_Select;

      elsif Take_Keyword ("ASK") then
         Syntax.Start (Tree, Syntax.Ask_Query);
         Parse_Dataset;
         if Take_Keyword ("WHERE") then
            null;
         end if;
         Syntax.Set_Where (Tree, Parse_Group);
         Parse_Modifiers;

      elsif Take_Keyword ("CONSTRUCT") then
         Syntax.Start (Tree, Syntax.Construct_Query);
         Parse_Dataset;

         if At_Keyword ("WHERE") then
            --  The short form: no template, the pattern serving as both.
            Advance;
            declare
               Where : constant Syntax.Node_Reference := Parse_Group;
               Built : constant Syntax.Query := Syntax.To_Query (Tree);
            begin
               --  The short form serves as its own template, so its
               --  pattern has to be something a template could contain:
               --  triples and nothing else.
               for Index in 1 .. Syntax.Child_Count (Built, Where) loop
                  if Syntax.Kind (Built, Syntax.Child (Built, Where, Index))
                     not in Syntax.Triple_Node | Syntax.Reified_Node
                          | Syntax.Triple_Term_Node
                  then
                     Fail ("CONSTRUCT WHERE admits only a triples block");
                  end if;
               end loop;
               Syntax.Set_Template (Tree, Where);
               Syntax.Set_Where (Tree, Where);
            end;
            Parse_Modifiers;
            if not At_End then
               Fail ("unexpected input after the query");
            end if;
            Validate;
            return Syntax.To_Query (Tree);
         end if;

         declare
            Items : constant Syntax.Node_Reference :=
              Node (Syntax.Group_Node);
         begin
            Expect (Lexers.Open_Brace_Token, "an opening brace");
            while not At_End and then Peek /= Lexers.Close_Brace_Token loop
               Parse_Triples (Items);
            end loop;
            Expect (Lexers.Close_Brace_Token, "a closing brace");
            Syntax.Set_Template (Tree, Items);
         end;
         Parse_Dataset;
         if Take_Keyword ("WHERE") then
            null;
         end if;
         Syntax.Set_Where (Tree, Parse_Group);
         Parse_Modifiers;

      elsif Take_Keyword ("DESCRIBE") then
         Syntax.Start (Tree, Syntax.Describe_Query);
         declare
            Items : constant Syntax.Node_Reference :=
              Node (Syntax.Projection_Node);
         begin
            if Peek = Lexers.Star_Token then
               Advance;
               Syntax.Set_Selects_All (Tree, True);
            else
               loop
                  Syntax.Add_Child (Tree, Items, Parse_Term);
                  exit when Peek not in Lexers.Variable_Token
                                      | Lexers.IRI_Reference_Token
                                      | Lexers.Prefixed_Name_Token;
               end loop;
            end if;
            Syntax.Set_Describe (Tree, Items);
         end;
         if Take_Keyword ("WHERE") then
            Syntax.Set_Where (Tree, Parse_Group);
         elsif Peek = Lexers.Open_Brace_Token then
            Syntax.Set_Where (Tree, Parse_Group);
         end if;
         Parse_Modifiers;

      else
         Fail ("expected SELECT, ASK, CONSTRUCT or DESCRIBE");
      end if;

      if not At_End then
         Fail ("unexpected input after the query");
      end if;

      Validate;
      return Syntax.To_Query (Tree);
   end Parse;

end Flyology_SPARQL.Parsers;
