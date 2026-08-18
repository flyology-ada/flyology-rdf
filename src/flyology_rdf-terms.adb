with Ada.Characters.Handling;

package body Flyology_RDF.Terms is

   package Unbounded renames Ada.Strings.Unbounded;

   use type Ada.Containers.Count_Type;

   RDF_Lang_String : constant String :=
     "http://www.w3.org/1999/02/22-rdf-syntax-ns#langString";
   RDF_Dir_Lang_String : constant String :=
     "http://www.w3.org/1999/02/22-rdf-syntax-ns#dirLangString";
   XSD_String : constant String :=
     "http://www.w3.org/2001/XMLSchema#string";

   function String_Datatype return IRIs.IRI is
     (IRIs.From_UTF_8 (XSD_String));

   function Language_String_Datatype return IRIs.IRI is
     (IRIs.From_UTF_8 (RDF_Lang_String));

   --  BCP 47 shape, checked structurally rather than against the registry:
   --  non-empty alphanumeric subtags separated by single hyphens, the first
   --  of which is alphabetic.
   function Is_Well_Formed_Language (Value : String) return Boolean;

   function Root (Value : Term) return Term_Node;

   procedure Require_Kind (Value : Term; Expected : Term_Kind);

   ----------------------------------------------------------------------

   function Is_Well_Formed_Language (Value : String) return Boolean is
      Subtag_Length : Natural := 0;
      First_Subtag  : Boolean := True;
   begin
      if Value'Length = 0 then
         return False;
      end if;

      for Index in Value'Range loop
         declare
            Item : constant Character := Value (Index);
         begin
            if Item = '-' then
               if Subtag_Length = 0 then
                  return False;
               end if;
               Subtag_Length := 0;
               First_Subtag := False;
            elsif Item in 'a' .. 'z' | 'A' .. 'Z' then
               Subtag_Length := Subtag_Length + 1;
               --  No subtag runs past eight characters.
               if Subtag_Length > 8 then
                  return False;
               end if;
            elsif Item in '0' .. '9' then
               --  Digits are permitted in continuation subtags only.
               if First_Subtag then
                  return False;
               end if;
               Subtag_Length := Subtag_Length + 1;
               if Subtag_Length > 8 then
                  return False;
               end if;
            else
               return False;
            end if;
         end;
      end loop;

      --  A trailing hyphen leaves an empty final subtag.
      return Subtag_Length /= 0;
   end Is_Well_Formed_Language;

   function Root (Value : Term) return Term_Node is
     (Value.Nodes.Last_Element);

   procedure Require_Kind (Value : Term; Expected : Term_Kind) is
   begin
      if Root (Value).Variant /= Expected then
         raise Invalid_Term with
           "term is " & Root (Value).Variant'Image
           & ", not " & Expected'Image;
      end if;
   end Require_Kind;

   procedure Require_Payload (Length : Natural);

   procedure Require_Payload (Length : Natural) is
   begin
      if Length > Maximum_Payload_Bytes then
         raise Term_Limit_Error with "term payload exceeds the maximum";
      end if;
   end Require_Payload;

   ----------------------------------------------------------------------
   --  Construction
   ----------------------------------------------------------------------

   function Single (Node : Term_Node) return Term;

   function Single (Node : Term_Node) return Term is
      Result : Term (Initialized => True);
   begin
      Result.Nodes.Append (Node);
      return Result;
   end Single;

   function IRI_Term (Value : IRIs.IRI) return Term is
      Length : constant Natural := IRIs.Byte_Length (Value);
   begin
      Require_Payload (Length);
      return Single
        ((Variant        => IRI_Kind,
          Subtree_Size   => 1,
          Subtree_Depth  => 0,
          Payload_Length => Length,
          IRI_Data       => IRI_Holders.To_Holder (Value)));
   end IRI_Term;

   function Blank_Node (Label : String) return Term is
   begin
      if Label'Length = 0 then
         raise Invalid_Term with "blank node label is empty";
      end if;
      Require_Payload (Label'Length);
      return Single
        ((Variant        => Blank_Node_Kind,
          Subtree_Size   => 1,
          Subtree_Depth  => 0,
          Payload_Length => Label'Length,
          Label_Data     => Unbounded.To_Unbounded_String (Label)));
   end Blank_Node;

   function Build_Literal
     (Lexical_Form  : String;
      Datatype      : IRIs.IRI;
      Has_Language  : Boolean;
      Language      : String;
      Has_Direction : Boolean;
      Direction     : Base_Direction) return Term;

   function Build_Literal
     (Lexical_Form  : String;
      Datatype      : IRIs.IRI;
      Has_Language  : Boolean;
      Language      : String;
      Has_Direction : Boolean;
      Direction     : Base_Direction) return Term
   is
      Length : constant Natural :=
        Lexical_Form'Length + IRIs.Byte_Length (Datatype) + Language'Length;
   begin
      Require_Payload (Length);
      return Single
        ((Variant            => Literal_Kind,
          Subtree_Size       => 1,
          Subtree_Depth      => 0,
          Payload_Length     => Length,
          Lexical_Data       => Unbounded.To_Unbounded_String (Lexical_Form),
          Datatype_Data      => IRI_Holders.To_Holder (Datatype),
          Language_Data      => Unbounded.To_Unbounded_String (Language),
          Has_Language_Data  => Has_Language,
          Direction_Data     => Direction,
          Has_Direction_Data => Has_Direction));
   end Build_Literal;

   function Literal
     (Lexical_Form : String;
      Datatype     : IRIs.IRI) return Term
   is
      use type IRIs.IRI;
   begin
      if Datatype = Language_String_Datatype then
         raise Invalid_Literal with
           "rdf:langString requires a language tag; use Language_Literal";
      elsif IRIs.To_UTF_8 (Datatype) = RDF_Dir_Lang_String then
         raise Invalid_Literal with
           "rdf:dirLangString requires a language tag and a direction;"
           & " use Directional_Literal";
      end if;

      return Build_Literal
        (Lexical_Form  => Lexical_Form,
         Datatype      => Datatype,
         Has_Language  => False,
         Language      => "",
         Has_Direction => False,
         Direction     => Left_To_Right);
   end Literal;

   function Language_Literal
     (Lexical_Form : String;
      Language     : String) return Term is
   begin
      if not Is_Well_Formed_Language (Language) then
         raise Invalid_Language_Tag with
           "language tag is empty or malformed";
      end if;

      return Build_Literal
        (Lexical_Form  => Lexical_Form,
         Datatype      => Language_String_Datatype,
         Has_Language  => True,
         Language      => Ada.Characters.Handling.To_Lower (Language),
         Has_Direction => False,
         Direction     => Left_To_Right);
   end Language_Literal;

   function Directional_Literal
     (Lexical_Form : String;
      Language     : String;
      Direction    : Base_Direction) return Term is
   begin
      if not Is_Well_Formed_Language (Language) then
         raise Invalid_Language_Tag with
           "language tag is empty or malformed";
      end if;

      --  RDF 1.2 gives a literal that carries a base direction the
      --  rdf:dirLangString datatype, not rdf:langString.
      return Build_Literal
        (Lexical_Form  => Lexical_Form,
         Datatype      => IRIs.From_UTF_8 (RDF_Dir_Lang_String),
         Has_Language  => True,
         Language      => Ada.Characters.Handling.To_Lower (Language),
         Has_Direction => True,
         Direction     => Direction);
   end Directional_Literal;

   function Triple_Term
     (Subject   : Term;
      Predicate : IRIs.IRI;
      Object    : Term) return Term
   is
      Subject_Count : constant Positive :=
        Positive (Subject.Nodes.Length);
      Object_Count  : constant Positive := Positive (Object.Nodes.Length);
      Total         : constant Natural := Subject_Count + Object_Count + 1;

      Result_Depth : constant Natural :=
        1 + Natural'Max
              (Root (Subject).Subtree_Depth, Root (Object).Subtree_Depth);

      Payload : constant Natural :=
        Root (Subject).Payload_Length
        + Root (Object).Payload_Length
        + IRIs.Byte_Length (Predicate);

      Result : Term (Initialized => True);
   begin
      if Result_Depth > Maximum_Triple_Term_Depth then
         raise Term_Limit_Error with
           "quoted triple nesting exceeds the maximum depth";
      elsif Total > Maximum_Term_Nodes then
         raise Term_Limit_Error with
           "term exceeds the maximum node count";
      end if;
      Require_Payload (Payload);

      --  Subject's nodes keep their indices; the object's shift by exactly
      --  the subject's size, so any triple node inside the object has to be
      --  renumbered as it is copied across.
      Result.Nodes.Reserve_Capacity
        (Ada.Containers.Count_Type (Total));

      for Node of Subject.Nodes loop
         Result.Nodes.Append (Node);
      end loop;

      for Node of Object.Nodes loop
         if Node.Variant = Triple_Term_Kind then
            declare
               Shifted : Term_Node := Node;
            begin
               Shifted.Subject_Node := Node.Subject_Node + Subject_Count;
               Shifted.Object_Node := Node.Object_Node + Subject_Count;
               Result.Nodes.Append (Shifted);
            end;
         else
            Result.Nodes.Append (Node);
         end if;
      end loop;

      Result.Nodes.Append
        (Term_Node'
           (Variant        => Triple_Term_Kind,
            Subtree_Size   => Total,
            Subtree_Depth  => Result_Depth,
            Payload_Length => Payload,
            Subject_Node   => Subject_Count,
            Predicate_Data => IRI_Holders.To_Holder (Predicate),
            Object_Node    => Subject_Count + Object_Count));

      return Result;
   end Triple_Term;

   ----------------------------------------------------------------------
   --  Inspection
   ----------------------------------------------------------------------

   function Kind (Value : Term) return Term_Kind is
     (Root (Value).Variant);

   function IRI_Value (Value : Term) return IRIs.IRI is
   begin
      Require_Kind (Value, IRI_Kind);
      return IRI_Holders.Element (Root (Value).IRI_Data);
   end IRI_Value;

   function Label (Value : Term) return String is
   begin
      Require_Kind (Value, Blank_Node_Kind);
      return Unbounded.To_String (Root (Value).Label_Data);
   end Label;

   function Lexical_Form (Value : Term) return String is
   begin
      Require_Kind (Value, Literal_Kind);
      return Unbounded.To_String (Root (Value).Lexical_Data);
   end Lexical_Form;

   function Datatype (Value : Term) return IRIs.IRI is
   begin
      Require_Kind (Value, Literal_Kind);
      return IRI_Holders.Element (Root (Value).Datatype_Data);
   end Datatype;

   function Has_Language (Value : Term) return Boolean is
   begin
      Require_Kind (Value, Literal_Kind);
      return Root (Value).Has_Language_Data;
   end Has_Language;

   function Language (Value : Term) return String is
   begin
      Require_Kind (Value, Literal_Kind);
      if not Root (Value).Has_Language_Data then
         raise Invalid_Term with "literal has no language tag";
      end if;
      return Unbounded.To_String (Root (Value).Language_Data);
   end Language;

   function Has_Direction (Value : Term) return Boolean is
   begin
      Require_Kind (Value, Literal_Kind);
      return Root (Value).Has_Direction_Data;
   end Has_Direction;

   function Direction (Value : Term) return Base_Direction is
   begin
      Require_Kind (Value, Literal_Kind);
      if not Root (Value).Has_Direction_Data then
         raise Invalid_Term with "literal has no base direction";
      end if;
      return Root (Value).Direction_Data;
   end Direction;

   --  Lift the subtree rooted at Index out into a standalone term. The
   --  subtree occupies a contiguous run ending at Index, because children
   --  are emitted before their parent and each subtree is built as a unit.
   function Subtree (Value : Term; Index : Positive) return Term;

   function Subtree (Value : Term; Index : Positive) return Term is
      Node   : constant Term_Node := Value.Nodes (Index);
      First  : constant Positive := Index - Node.Subtree_Size + 1;
      Offset : constant Natural := First - 1;
      Result : Term (Initialized => True);
   begin
      Result.Nodes.Reserve_Capacity
        (Ada.Containers.Count_Type (Node.Subtree_Size));

      for Position in First .. Index loop
         declare
            Current : Term_Node := Value.Nodes (Position);
         begin
            if Current.Variant = Triple_Term_Kind then
               Current.Subject_Node := Current.Subject_Node - Offset;
               Current.Object_Node := Current.Object_Node - Offset;
            end if;
            Result.Nodes.Append (Current);
         end;
      end loop;
      return Result;
   end Subtree;

   function Triple_Subject (Value : Term) return Term is
   begin
      Require_Kind (Value, Triple_Term_Kind);
      return Subtree (Value, Root (Value).Subject_Node);
   end Triple_Subject;

   function Triple_Predicate (Value : Term) return IRIs.IRI is
   begin
      Require_Kind (Value, Triple_Term_Kind);
      return IRI_Holders.Element (Root (Value).Predicate_Data);
   end Triple_Predicate;

   function Triple_Object (Value : Term) return Term is
   begin
      Require_Kind (Value, Triple_Term_Kind);
      return Subtree (Value, Root (Value).Object_Node);
   end Triple_Object;

   function Node_Count (Value : Term) return Positive is
     (Positive (Value.Nodes.Length));

   function Depth (Value : Term) return Natural is
     (Root (Value).Subtree_Depth);

   function Visit_Nodes
     (Value      : Term;
      On_IRI     : not null access procedure
        (Node : Node_ID; Value : IRIs.IRI);
      On_Blank   : not null access procedure
        (Node : Node_ID; Label : String);
      On_Literal : not null access procedure
        (Node          : Node_ID;
         Lexical_Form  : String;
         Datatype      : IRIs.IRI;
         Has_Language  : Boolean;
         Language      : String;
         Has_Direction : Boolean;
         Direction     : Base_Direction);
      On_Triple  : not null access procedure
        (Node, Subject_Node : Node_ID;
         Predicate          : IRIs.IRI;
         Object_Node        : Node_ID)) return Node_ID is
   begin
      for Index in Value.Nodes.First_Index .. Value.Nodes.Last_Index loop
         declare
            Node : constant Term_Node := Value.Nodes (Index);
            Here : constant Node_ID := Node_ID (Index);
         begin
            case Node.Variant is
               when IRI_Kind =>
                  On_IRI (Here, IRI_Holders.Element (Node.IRI_Data));
               when Blank_Node_Kind =>
                  On_Blank (Here, Unbounded.To_String (Node.Label_Data));
               when Literal_Kind =>
                  On_Literal
                    (Here,
                     Unbounded.To_String (Node.Lexical_Data),
                     IRI_Holders.Element (Node.Datatype_Data),
                     Node.Has_Language_Data,
                     Unbounded.To_String (Node.Language_Data),
                     Node.Has_Direction_Data,
                     Node.Direction_Data);
               when Triple_Term_Kind =>
                  On_Triple
                    (Here,
                     Node_ID (Node.Subject_Node),
                     IRI_Holders.Element (Node.Predicate_Data),
                     Node_ID (Node.Object_Node));
            end case;
         end;
      end loop;
      return Node_ID (Value.Nodes.Last_Index);
   end Visit_Nodes;

   function Same_Node (Left, Right : Term_Node) return Boolean;

   function Same_Node (Left, Right : Term_Node) return Boolean is
      use type IRI_Holders.Holder;
      use type Unbounded.Unbounded_String;
   begin
      if Left.Variant /= Right.Variant then
         return False;
      end if;

      case Left.Variant is
         when IRI_Kind =>
            return Left.IRI_Data = Right.IRI_Data;
         when Blank_Node_Kind =>
            return Left.Label_Data = Right.Label_Data;
         when Literal_Kind =>
            return Left.Lexical_Data = Right.Lexical_Data
              and then Left.Datatype_Data = Right.Datatype_Data
              and then Left.Has_Language_Data = Right.Has_Language_Data
              and then Left.Language_Data = Right.Language_Data
              and then Left.Has_Direction_Data = Right.Has_Direction_Data
              and then (not Left.Has_Direction_Data
                        or else Left.Direction_Data = Right.Direction_Data);
         when Triple_Term_Kind =>
            return Left.Subject_Node = Right.Subject_Node
              and then Left.Object_Node = Right.Object_Node
              and then Left.Predicate_Data = Right.Predicate_Data;
      end case;
   end Same_Node;

   overriding function "=" (Left, Right : Term) return Boolean is
   begin
      --  Both operands are built by the constructors above, which emit
      --  nodes in a canonical order, so equal terms have identical vectors
      --  and a positional comparison is exact rather than approximate.
      if Left.Nodes.Length /= Right.Nodes.Length then
         return False;
      end if;

      for Index in Left.Nodes.First_Index .. Left.Nodes.Last_Index loop
         if not Same_Node (Left.Nodes (Index), Right.Nodes (Index)) then
            return False;
         end if;
      end loop;
      return True;
   end "=";

end Flyology_RDF.Terms;
