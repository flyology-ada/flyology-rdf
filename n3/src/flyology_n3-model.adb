package body Flyology_N3.Model is

   use type Ada.Containers.Count_Type;

   function Root (Value : Term) return Node is (Value.Nodes.Last_Element);

   function Root (Value : Statement) return Node
   is (Value.Nodes.Last_Element);

   procedure Require (Value : Term; Expected : Node_Kind) is
   begin
      if Root (Value).Variant /= Expected then
         raise Invalid_Term with
           "term is " & Root (Value).Variant'Image
           & ", not " & Expected'Image;
      end if;
   end Require;

   function Single (Item : Node) return Term is
      Result : Term (Initialized => True);
   begin
      Result.Nodes.Append (Item);
      return Result;
   end Single;

   --  Copy a subtree's nodes into a growing vector, renumbering every index
   --  reference by the offset the copy introduces. This is the one place
   --  the flat representation costs anything, and it is why nothing else
   --  has to think about aliasing.
   procedure Splice
     (Into   : in out Node_Vectors.Vector;
      From   : Node_Vectors.Vector;
      Root_At : out Positive)
   is
      Offset : constant Natural := Natural (Into.Length);
   begin
      for Item of From loop
         declare
            Copy : Node := Item;
         begin
            --  A node has a defaulted discriminant, so its variant
            --  components cannot be assigned one at a time. Each shifted
            --  node is built whole instead.
            case Item.Variant is
               when List_Node | Formula_Node =>
                  declare
                     Shifted : Index_Vectors.Vector;
                  begin
                     for Child of Item.Children loop
                        Shifted.Append (Child + Offset);
                     end loop;
                     if Item.Variant = List_Node then
                        Copy := (Variant  => List_Node,
                                 Depth    => Item.Depth,
                                 Children => Shifted);
                     else
                        Copy := (Variant  => Formula_Node,
                                 Depth    => Item.Depth,
                                 Children => Shifted);
                     end if;
                  end;
               when Statement_Node =>
                  Copy := (Variant        => Statement_Node,
                           Depth          => Item.Depth,
                           Subject_Node   => Item.Subject_Node + Offset,
                           Predicate_Node => Item.Predicate_Node + Offset,
                           Object_Node    => Item.Object_Node + Offset);
               when others =>
                  null;
            end case;
            Into.Append (Copy);
         end;
      end loop;
      Root_At := Natural (Into.Length);
   end Splice;

   --  Lift the subtree rooted at Index out as a standalone value. Children
   --  are always emitted before their parent and each subtree is built as a
   --  unit, so a subtree is a contiguous run -- but its extent is not
   --  recorded, so it is found by walking the references.
   procedure Extract
     (Source : Node_Vectors.Vector;
      Index  : Positive;
      Into   : out Node_Vectors.Vector)
   is
      Needed  : array (1 .. Natural (Source.Length)) of Boolean :=
        [others => False];
      Mapping : array (1 .. Natural (Source.Length)) of Natural :=
        [others => 0];

      procedure Mark (At_Index : Positive);

      procedure Mark (At_Index : Positive) is
         Item : constant Node := Source (At_Index);
      begin
         if Needed (At_Index) then
            return;
         end if;
         Needed (At_Index) := True;
         case Item.Variant is
            when List_Node | Formula_Node =>
               for Child of Item.Children loop
                  Mark (Child);
               end loop;
            when Statement_Node =>
               Mark (Item.Subject_Node);
               Mark (Item.Predicate_Node);
               Mark (Item.Object_Node);
            when others =>
               null;
         end case;
      end Mark;

   begin
      Mark (Index);
      Into := Node_Vectors.Empty_Vector;

      --  Ascending order preserves child-before-parent, because a reference
      --  always points backwards.
      for Position in 1 .. Natural (Source.Length) loop
         if Needed (Position) then
            Into.Append (Source (Position));
            Mapping (Position) := Natural (Into.Length);
         end if;
      end loop;

      for Position in 1 .. Natural (Into.Length) loop
         declare
            Item : constant Node := Into (Position);
         begin
            case Item.Variant is
               when List_Node | Formula_Node =>
                  declare
                     Shifted : Index_Vectors.Vector;
                  begin
                     for Child of Item.Children loop
                        Shifted.Append (Mapping (Child));
                     end loop;
                     if Item.Variant = List_Node then
                        Into.Replace_Element
                          (Position,
                           Node'(Variant  => List_Node,
                                 Depth    => Item.Depth,
                                 Children => Shifted));
                     else
                        Into.Replace_Element
                          (Position,
                           Node'(Variant  => Formula_Node,
                                 Depth    => Item.Depth,
                                 Children => Shifted));
                     end if;
                  end;
               when Statement_Node =>
                  Into.Replace_Element
                    (Position,
                     Node'(Variant        => Statement_Node,
                           Depth          => Item.Depth,
                           Subject_Node   => Mapping (Item.Subject_Node),
                           Predicate_Node =>
                             Mapping (Item.Predicate_Node),
                           Object_Node    => Mapping (Item.Object_Node)));
               when others =>
                  null;
            end case;
         end;
      end loop;
   end Extract;

   ----------------------------------------------------------------------
   --  Construction
   ----------------------------------------------------------------------

   function From_RDF (Value : RDF.Terms.Term) return Term
   is (Single ((Variant  => RDF_Node,
                Depth    => 0,
                RDF_Data => RDF_Holders.To_Holder (Value))));

   function IRI_Term (Value : RDF.IRIs.IRI) return Term
   is (From_RDF (RDF.Terms.IRI_Term (Value)));

   function Variable (Name : String) return Term is
   begin
      if Name'Length = 0 then
         raise Invalid_Term with "variable name is empty";
      end if;
      return Single ((Variant   => Variable_Node,
                      Depth     => 0,
                      Name_Data => Unbounded.To_Unbounded_String (Name)));
   end Variable;

   function Build
     (Variant : Node_Kind;
      Parts   : Node_Vectors.Vector;
      Roots   : Index_Vectors.Vector;
      Depth   : Natural) return Term
   is
      Result : Term (Initialized => True);
   begin
      if Depth > Maximum_Depth then
         raise Invalid_Term with "term nesting exceeds the maximum depth";
      end if;
      Result.Nodes := Parts;
      if Variant = List_Node then
         Result.Nodes.Append
           (Node'(Variant => List_Node, Depth => Depth, Children => Roots));
      else
         Result.Nodes.Append
           (Node'(Variant  => Formula_Node,
                  Depth    => Depth,
                  Children => Roots));
      end if;
      return Result;
   end Build;

   procedure Append (Into : in out Builder; Value : Term) is
      Where : Positive;
   begin
      Splice (Into.Parts, Value.Nodes, Where);
      Into.Roots.Append (Where);
      Into.Depth := Natural'Max (Into.Depth, Root (Value).Depth);
   end Append;

   procedure Append (Into : in out Builder; Value : Statement) is
      Where : Positive;
   begin
      Splice (Into.Parts, Value.Nodes, Where);
      Into.Roots.Append (Where);
      Into.Depth := Natural'Max (Into.Depth, Root (Value).Depth);
   end Append;

   function Count (Value : Builder) return Natural
   is (Natural (Value.Roots.Length));

   function List (Items : Builder) return Term
   is (Build (List_Node, Items.Parts, Items.Roots, Items.Depth + 1));

   function Formula (Items : Builder) return Term
   is (Build (Formula_Node, Items.Parts, Items.Roots, Items.Depth + 1));

   function Empty_Formula return Term is
      Nothing : Builder;
   begin
      return Formula (Nothing);
   end Empty_Formula;

   function Create (Subject, Predicate, Object : Term) return Statement is
      Result : Statement (Initialized => True);
      Parts  : Node_Vectors.Vector;
      S, P, O : Positive;
      Depth  : Natural := 0;
   begin
      Splice (Parts, Subject.Nodes, S);
      Splice (Parts, Predicate.Nodes, P);
      Splice (Parts, Object.Nodes, O);
      Depth := Natural'Max
        (Root (Subject).Depth,
         Natural'Max (Root (Predicate).Depth, Root (Object).Depth));

      Result.Nodes := Parts;
      Result.Nodes.Append
        (Node'(Variant        => Statement_Node,
               Depth          => Depth,
               Subject_Node   => S,
               Predicate_Node => P,
               Object_Node    => O));
      return Result;
   end Create;

   ----------------------------------------------------------------------
   --  Inspection
   ----------------------------------------------------------------------

   function Kind (Value : Term) return Term_Kind is
   begin
      case Root (Value).Variant is
         when RDF_Node       => return RDF_Kind;
         when Variable_Node  => return Variable_Kind;
         when List_Node      => return List_Kind;
         when Formula_Node   => return Formula_Kind;
         when Statement_Node =>
            raise Invalid_Term with "a statement is not a term";
      end case;
   end Kind;

   function RDF_Value (Value : Term) return RDF.Terms.Term is
   begin
      Require (Value, RDF_Node);
      return RDF_Holders.Element (Root (Value).RDF_Data);
   end RDF_Value;

   function Name (Value : Term) return String is
   begin
      Require (Value, Variable_Node);
      return Unbounded.To_String (Root (Value).Name_Data);
   end Name;

   function Length (Value : Term) return Natural is
   begin
      Require (Value, List_Node);
      return Natural (Root (Value).Children.Length);
   end Length;

   function Child (Value : Term; Index : Positive) return Term is
      Result : Term (Initialized => True);
   begin
      Extract (Value.Nodes, Root (Value).Children (Index), Result.Nodes);
      return Result;
   end Child;

   function Element (Value : Term; Index : Positive) return Term is
   begin
      Require (Value, List_Node);
      return Child (Value, Index);
   end Element;

   function Statement_Count (Value : Term) return Natural is
   begin
      Require (Value, Formula_Node);
      return Natural (Root (Value).Children.Length);
   end Statement_Count;

   function Statement_At (Value : Term; Index : Positive) return Statement is
      Result : Statement (Initialized => True);
   begin
      Require (Value, Formula_Node);
      Extract (Value.Nodes, Root (Value).Children (Index), Result.Nodes);
      return Result;
   end Statement_At;

   function Part (Value : Statement; Index : Positive) return Term is
      Result : Term (Initialized => True);
   begin
      Extract (Value.Nodes, Index, Result.Nodes);
      return Result;
   end Part;

   function Subject (Value : Statement) return Term
   is (Part (Value, Root (Value).Subject_Node));

   function Predicate (Value : Statement) return Term
   is (Part (Value, Root (Value).Predicate_Node));

   function Object (Value : Statement) return Term
   is (Part (Value, Root (Value).Object_Node));

   ----------------------------------------------------------------------
   --  Equality
   ----------------------------------------------------------------------

   function Same (Left, Right : Node) return Boolean is
      use type RDF_Holders.Holder;
      use type Unbounded.Unbounded_String;
      use type Index_Vectors.Vector;
   begin
      if Left.Variant /= Right.Variant then
         return False;
      end if;
      case Left.Variant is
         when RDF_Node =>
            return Left.RDF_Data = Right.RDF_Data;
         when Variable_Node =>
            return Left.Name_Data = Right.Name_Data;
         when List_Node | Formula_Node =>
            return Left.Children = Right.Children;
         when Statement_Node =>
            return Left.Subject_Node = Right.Subject_Node
              and then Left.Predicate_Node = Right.Predicate_Node
              and then Left.Object_Node = Right.Object_Node;
      end case;
   end Same;

   function Same (Left, Right : Node_Vectors.Vector) return Boolean is
   begin
      if Left.Length /= Right.Length then
         return False;
      end if;
      for Index in 1 .. Natural (Left.Length) loop
         if not Same (Left (Index), Right (Index)) then
            return False;
         end if;
      end loop;
      return True;
   end Same;

   overriding function "=" (Left, Right : Term) return Boolean
   is (Same (Left.Nodes, Right.Nodes));

   overriding function "=" (Left, Right : Statement) return Boolean
   is (Same (Left.Nodes, Right.Nodes));

end Flyology_N3.Model;
