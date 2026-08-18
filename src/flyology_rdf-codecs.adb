with Ada.Strings.Unbounded;

with Flyology_RDF.IRIs;

package body Flyology_RDF.Codecs is

   package Unbounded renames Ada.Strings.Unbounded;

   use type Terms.Term_Kind;
   use type Terms.Base_Direction;
   use type Quads.Graph_Name_Kind;

   --  Tags name the kind before anything variable appears, so two terms of
   --  different kinds cannot share a prefix, let alone an encoding.
   Tag_IRI     : constant Character := Character'Val (1);
   Tag_Blank   : constant Character := Character'Val (2);
   Tag_Literal : constant Character := Character'Val (3);
   Tag_Triple  : constant Character := Character'Val (4);

   RDF_Lang_String : constant String :=
     "http://www.w3.org/1999/02/22-rdf-syntax-ns#langString";
   RDF_Dir_Lang_String : constant String :=
     "http://www.w3.org/1999/02/22-rdf-syntax-ns#dirLangString";

   Graph_Default : constant Character := Character'Val (0);
   Graph_IRI     : constant Character := Character'Val (1);
   Graph_Blank   : constant Character := Character'Val (2);

   Flag_Language  : constant := 1;
   Flag_Direction : constant := 2;

   --  Bound on a decoded term's nesting, matching what the term model will
   --  build. Without it, a crafted encoding could ask for unbounded
   --  recursion before the constructor ever sees it.
   Maximum_Depth : constant := 256;

   ----------------------------------------------------------------------
   --  Self-delimiting lengths
   ----------------------------------------------------------------------

   procedure Put_Length
     (Buffer : in out Unbounded.Unbounded_String;
      Value  : Natural)
   is
      Remaining : Natural := Value;
   begin
      --  Base 128, low group first, high bit marking continuation. Self
      --  delimiting, so a length can never be confused with the bytes that
      --  follow it.
      loop
         declare
            Group : constant Natural := Remaining mod 128;
         begin
            Remaining := Remaining / 128;
            if Remaining = 0 then
               Unbounded.Append (Buffer, Character'Val (Group));
               exit;
            end if;
            Unbounded.Append (Buffer, Character'Val (Group + 128));
         end;
      end loop;
   end Put_Length;

   procedure Put_Bytes
     (Buffer : in out Unbounded.Unbounded_String;
      Value  : String) is
   begin
      Put_Length (Buffer, Value'Length);
      Unbounded.Append (Buffer, Value);
   end Put_Bytes;

   ----------------------------------------------------------------------
   --  Encoding
   ----------------------------------------------------------------------

   procedure Put_Term
     (Buffer : in out Unbounded.Unbounded_String;
      Value  : Terms.Term) is
   begin
      case Terms.Kind (Value) is
         when Terms.IRI_Kind =>
            Unbounded.Append (Buffer, Tag_IRI);
            Put_Bytes (Buffer, IRIs.To_UTF_8 (Terms.IRI_Value (Value)));

         when Terms.Blank_Node_Kind =>
            Unbounded.Append (Buffer, Tag_Blank);
            Put_Bytes (Buffer, Terms.Label (Value));

         when Terms.Literal_Kind =>
            declare
               Flags : Natural := 0;
            begin
               if Terms.Has_Language (Value) then
                  Flags := Flags + Flag_Language;
               end if;
               if Terms.Has_Direction (Value) then
                  Flags := Flags + Flag_Direction;
               end if;

               Unbounded.Append (Buffer, Tag_Literal);
               Unbounded.Append (Buffer, Character'Val (Flags));
               Put_Bytes (Buffer, Terms.Lexical_Form (Value));
               Put_Bytes (Buffer, IRIs.To_UTF_8 (Terms.Datatype (Value)));
               if Terms.Has_Language (Value) then
                  Put_Bytes (Buffer, Terms.Language (Value));
               end if;
               if Terms.Has_Direction (Value) then
                  Unbounded.Append
                    (Buffer,
                     Character'Val
                       (if Terms.Direction (Value) = Terms.Left_To_Right
                        then 0 else 1));
               end if;
            end;

         when Terms.Triple_Term_Kind =>
            Unbounded.Append (Buffer, Tag_Triple);
            Put_Term (Buffer, Terms.Triple_Subject (Value));
            Put_Bytes
              (Buffer, IRIs.To_UTF_8 (Terms.Triple_Predicate (Value)));
            Put_Term (Buffer, Terms.Triple_Object (Value));
      end case;
   end Put_Term;

   function Encode (Value : Terms.Term) return String is
      Buffer : Unbounded.Unbounded_String;
   begin
      Put_Term (Buffer, Value);
      return Unbounded.To_String (Buffer);
   end Encode;

   function Encode (Value : Quads.Quad) return String is
      Buffer : Unbounded.Unbounded_String;
      Graph  : constant Quads.Graph_Name := Quads.Graph (Value);
   begin
      case Quads.Kind (Graph) is
         when Quads.Default_Graph_Kind =>
            Unbounded.Append (Buffer, Graph_Default);
         when Quads.IRI_Graph_Kind =>
            Unbounded.Append (Buffer, Graph_IRI);
            Put_Bytes
              (Buffer,
               IRIs.To_UTF_8 (Terms.IRI_Value (Quads.Name_Term (Graph))));
         when Quads.Blank_Node_Graph_Kind =>
            Unbounded.Append (Buffer, Graph_Blank);
            Put_Bytes (Buffer, Terms.Label (Quads.Name_Term (Graph)));
      end case;

      Put_Term (Buffer, Quads.Subject (Value));
      Put_Bytes (Buffer, IRIs.To_UTF_8 (Quads.Predicate (Value)));
      Put_Term (Buffer, Quads.Object (Value));
      return Unbounded.To_String (Buffer);
   end Encode;

   ----------------------------------------------------------------------
   --  Decoding
   ----------------------------------------------------------------------

   procedure Fail;

   procedure Fail is
   begin
      raise Invalid_Encoding with "malformed binary term encoding";
   end Fail;

   procedure Get_Length
     (Bytes : String;
      Index : in out Positive;
      Value : out Natural)
   is
      Shift  : Natural := 1;
      Groups : Natural := 0;
   begin
      Value := 0;
      loop
         if Index > Bytes'Last then
            Fail;
         end if;

         --  Five groups is already more than a 32-bit length can need, and
         --  refusing more keeps a crafted encoding from spinning here.
         Groups := Groups + 1;
         if Groups > 5 then
            Fail;
         end if;

         declare
            Item : constant Natural := Character'Pos (Bytes (Index));
         begin
            Index := Index + 1;
            Value := Value + (Item mod 128) * Shift;
            exit when Item < 128;
            Shift := Shift * 128;
         end;
      end loop;
   end Get_Length;

   procedure Get_Bytes
     (Bytes : String;
      Index : in out Positive;
      Value : out Unbounded.Unbounded_String)
   is
      Length : Natural;
   begin
      Get_Length (Bytes, Index, Length);
      if Length > Bytes'Last - Index + 1 then
         Fail;
      end if;
      Value := Unbounded.To_Unbounded_String
        (Bytes (Index .. Index + Length - 1));
      Index := Index + Length;
   end Get_Bytes;

   function Get_Term
     (Bytes : String;
      Index : in out Positive;
      Depth : Natural) return Terms.Term
   is
      Tag : Character;
   begin
      if Depth > Maximum_Depth then
         Fail;
      elsif Index > Bytes'Last then
         Fail;
      end if;

      Tag := Bytes (Index);
      Index := Index + 1;

      if Tag = Tag_IRI then
         declare
            Text : Unbounded.Unbounded_String;
         begin
            Get_Bytes (Bytes, Index, Text);
            return Terms.IRI_Term
              (IRIs.From_UTF_8 (Unbounded.To_String (Text)));
         end;

      elsif Tag = Tag_Blank then
         declare
            Text : Unbounded.Unbounded_String;
         begin
            Get_Bytes (Bytes, Index, Text);
            return Terms.Blank_Node (Unbounded.To_String (Text));
         end;

      elsif Tag = Tag_Literal then
         if Index > Bytes'Last then
            Fail;
         end if;
         declare
            Flags     : constant Natural := Character'Pos (Bytes (Index));
            Has_Tag   : constant Boolean := Flags mod 2 = 1;
            Directed  : constant Boolean := (Flags / 2) mod 2 = 1;
            Lexical   : Unbounded.Unbounded_String;
            Datatype  : Unbounded.Unbounded_String;
            Language  : Unbounded.Unbounded_String;
            Direction : Terms.Base_Direction := Terms.Left_To_Right;
         begin
            if Flags > Flag_Language + Flag_Direction then
               Fail;
            end if;
            --  A direction without a language is not a term this model can
            --  build, so refuse it here rather than let the constructor
            --  raise something the caller was not told to expect.
            if Directed and then not Has_Tag then
               Fail;
            end if;
            Index := Index + 1;

            Get_Bytes (Bytes, Index, Lexical);
            Get_Bytes (Bytes, Index, Datatype);

            --  The model fixes the datatype of a language-tagged literal,
            --  so an encoding that names any other one describes a term
            --  this crate will not build. Accepting it would also let two
            --  distinct byte strings decode to equal terms.
            if Has_Tag
              and then Unbounded.To_String (Datatype)
                       /= (if Directed then RDF_Dir_Lang_String
                           else RDF_Lang_String)
            then
               Fail;
            end if;

            if Has_Tag then
               Get_Bytes (Bytes, Index, Language);
            end if;

            if Directed then
               if Index > Bytes'Last then
                  Fail;
               end if;
               case Character'Pos (Bytes (Index)) is
                  when 0 => Direction := Terms.Left_To_Right;
                  when 1 => Direction := Terms.Right_To_Left;
                  when others => Fail;
               end case;
               Index := Index + 1;

               return Terms.Directional_Literal
                 (Unbounded.To_String (Lexical),
                  Unbounded.To_String (Language),
                  Direction);
            end if;

            if Has_Tag then
               return Terms.Language_Literal
                 (Unbounded.To_String (Lexical),
                  Unbounded.To_String (Language));
            end if;

            return Terms.Literal
              (Unbounded.To_String (Lexical),
               IRIs.From_UTF_8 (Unbounded.To_String (Datatype)));
         end;

      elsif Tag = Tag_Triple then
         declare
            Subject   : constant Terms.Term :=
              Get_Term (Bytes, Index, Depth + 1);
            Predicate : Unbounded.Unbounded_String;
         begin
            Get_Bytes (Bytes, Index, Predicate);
            declare
               Object : constant Terms.Term :=
                 Get_Term (Bytes, Index, Depth + 1);
            begin
               return Terms.Triple_Term
                 (Subject,
                  IRIs.From_UTF_8 (Unbounded.To_String (Predicate)),
                  Object);
            end;
         end;
      end if;

      Fail;
      raise Program_Error;
   end Get_Term;

   --  Every exception the term model raises for a value it will not build
   --  is reported as Invalid_Encoding, so a caller has one thing to handle
   --  rather than a list that grows with the model.
   function Decode_Term (Bytes : String) return Terms.Term is
      Index : Positive := Bytes'First;
   begin
      return Result : constant Terms.Term := Get_Term (Bytes, Index, 0) do
         if Index /= Bytes'Last + 1 then
            Fail;
         end if;
      end return;
   exception
      when IRIs.Invalid_IRI | IRIs.Invalid_UTF_8
         | Terms.Invalid_Term | Terms.Invalid_Literal
         | Terms.Invalid_Language_Tag | Terms.Term_Limit_Error
         | Constraint_Error =>
         raise Invalid_Encoding with
           "encoding describes a term that cannot be built";
   end Decode_Term;

   function Decode_Quad (Bytes : String) return Quads.Quad is
      Index : Positive := Bytes'First;

      --  Graph_Name is discriminated and indefinite, so its variant is
      --  fixed at the point a name is created. It has to be built once,
      --  from a function, rather than declared and then reassigned.
      function Get_Graph return Quads.Graph_Name is
      begin
         if Index > Bytes'Last then
            Fail;
         end if;

         declare
            Kind : constant Character := Bytes (Index);
            Text : Unbounded.Unbounded_String;
         begin
            Index := Index + 1;
            if Kind = Graph_Default then
               return Quads.Default_Graph;
            elsif Kind = Graph_IRI then
               Get_Bytes (Bytes, Index, Text);
               return Quads.IRI_Graph
                 (IRIs.From_UTF_8 (Unbounded.To_String (Text)));
            elsif Kind = Graph_Blank then
               Get_Bytes (Bytes, Index, Text);
               return Quads.Blank_Node_Graph
                 (Terms.Blank_Node (Unbounded.To_String (Text)));
            end if;
         end;

         Fail;
         raise Program_Error;
      end Get_Graph;

   begin
      --  The components are built inside the handled sequence rather than
      --  in the declarative part: an exception raised while elaborating a
      --  declaration would propagate past the handler below and reach the
      --  caller untranslated.
      declare
         Graph     : constant Quads.Graph_Name := Get_Graph;
         Subject   : constant Terms.Term := Get_Term (Bytes, Index, 0);
         Predicate : Unbounded.Unbounded_String;
      begin
         Get_Bytes (Bytes, Index, Predicate);

         declare
            Object : constant Terms.Term := Get_Term (Bytes, Index, 0);
         begin
            if Index /= Bytes'Last + 1 then
               Fail;
            end if;
            return Quads.Create
              (Graph, Subject,
               IRIs.From_UTF_8 (Unbounded.To_String (Predicate)),
               Object);
         end;
      end;
   exception
      when IRIs.Invalid_IRI | IRIs.Invalid_UTF_8
         | Terms.Invalid_Term | Terms.Invalid_Literal
         | Terms.Invalid_Language_Tag | Terms.Term_Limit_Error
         | Constraint_Error =>
         raise Invalid_Encoding with
           "encoding describes a statement that cannot be built";
   end Decode_Quad;

end Flyology_RDF.Codecs;
