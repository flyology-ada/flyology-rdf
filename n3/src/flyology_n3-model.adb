package body Flyology_N3.Model is

   use type Ada.Containers.Count_Type;

   --  The root is read through a reference: materializing the node would
   --  copy its payload -- for an RDF node, the whole wrapped term -- on
   --  every inspection.
   function Root_Variant (Value : Node_Vectors.Vector) return Node_Kind
   is (Value (Value.Last_Index).Variant);

   function Root_Depth (Value : Node_Vectors.Vector) return Natural
   is (Value (Value.Last_Index).Depth);

   procedure Require (Value : Term; Expected : Node_Kind) is
   begin
      if Root_Variant (Value.Nodes) /= Expected then
         raise Invalid_Term with
           "term is " & Root_Variant (Value.Nodes)'Image
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
   --  has to think about aliasing. Each node is copied once and renumbered
   --  where it landed: renumbering first would build a second copy only to
   --  copy it again.
   procedure Splice
     (Into   : in out Node_Vectors.Vector;
      From   : Node_Vectors.Vector;
      Root_At : out Positive)
   is
      Offset : constant Natural := Natural (Into.Length);
   begin
      for Item of From loop
         Into.Append (Item);
         declare
            Landed : Node renames Into (Into.Last_Index);
         begin
            case Landed.Variant is
               when List_Node | Formula_Node =>
                  for Child of Landed.Children loop
                     Child := Child + Offset;
                  end loop;
               when Statement_Node =>
                  Landed.Subject_Node := Landed.Subject_Node + Offset;
                  Landed.Predicate_Node := Landed.Predicate_Node + Offset;
                  Landed.Object_Node := Landed.Object_Node + Offset;
               when others =>
                  null;
            end case;
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
         Item : Node renames Source (At_Index);
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

      --  Renumbered where it stands: replacing a node wholesale would
      --  copy its payload once out and once back in.
      for Position in 1 .. Natural (Into.Length) loop
         declare
            Item : Node renames Into (Position);
         begin
            case Item.Variant is
               when List_Node | Formula_Node =>
                  for Child of Item.Children loop
                     Child := Mapping (Child);
                  end loop;
               when Statement_Node =>
                  Item.Subject_Node := Mapping (Item.Subject_Node);
                  Item.Predicate_Node := Mapping (Item.Predicate_Node);
                  Item.Object_Node := Mapping (Item.Object_Node);
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

   --  The builder's parts move into the term rather than being copied:
   --  they were already copied once on the way in, and every part is an
   --  allocation-bearing node.
   function Build
     (Variant : Node_Kind;
      Items   : in out Builder;
      Depth   : Natural) return Term
   is
      Result : Term (Initialized => True);
   begin
      if Depth > Maximum_Depth then
         raise Invalid_Term with "term nesting exceeds the maximum depth";
      end if;
      Node_Vectors.Move (Target => Result.Nodes, Source => Items.Parts);
      if Variant = List_Node then
         Result.Nodes.Append
           (Node'(Variant  => List_Node,
                  Depth    => Depth,
                  Children => Index_Vectors.Empty_Vector));
      else
         Result.Nodes.Append
           (Node'(Variant  => Formula_Node,
                  Depth    => Depth,
                  Children => Index_Vectors.Empty_Vector));
      end if;
      Index_Vectors.Move
        (Target => Result.Nodes (Result.Nodes.Last_Index).Children,
         Source => Items.Roots);
      Items.Depth := 0;
      return Result;
   end Build;

   procedure Append (Into : in out Builder; Value : Term) is
      Where : Positive;
   begin
      Splice (Into.Parts, Value.Nodes, Where);
      Into.Roots.Append (Where);
      Into.Depth := Natural'Max (Into.Depth, Root_Depth (Value.Nodes));
   end Append;

   procedure Append (Into : in out Builder; Value : Statement) is
      Where : Positive;
   begin
      Splice (Into.Parts, Value.Nodes, Where);
      Into.Roots.Append (Where);
      Into.Depth := Natural'Max (Into.Depth, Root_Depth (Value.Nodes));
   end Append;

   procedure Append
     (Into : in out Builder; Subject, Predicate, Object : Term)
   is
      S, P, O : Positive;
      Depth   : constant Natural :=
        Natural'Max
          (Root_Depth (Subject.Nodes),
           Natural'Max
             (Root_Depth (Predicate.Nodes), Root_Depth (Object.Nodes)));
   begin
      Splice (Into.Parts, Subject.Nodes, S);
      Splice (Into.Parts, Predicate.Nodes, P);
      Splice (Into.Parts, Object.Nodes, O);
      Into.Parts.Append
        (Node'(Variant        => Statement_Node,
               Depth          => Depth,
               Subject_Node   => S,
               Predicate_Node => P,
               Object_Node    => O));
      Into.Roots.Append (Natural (Into.Parts.Length));
      Into.Depth := Natural'Max (Into.Depth, Depth);
   end Append;

   function Count (Value : Builder) return Natural
   is (Natural (Value.Roots.Length));

   function List (Items : in out Builder) return Term
   is (Build (List_Node, Items, Items.Depth + 1));

   function Formula (Items : in out Builder) return Term
   is (Build (Formula_Node, Items, Items.Depth + 1));

   function Empty_Formula return Term is
      Nothing : Builder;
   begin
      return Formula (Nothing);
   end Empty_Formula;

   function Create (Subject, Predicate, Object : Term) return Statement is
      Result : Statement (Initialized => True);
      S, P, O : Positive;
   begin
      --  Spliced straight into the result: a staging vector would copy
      --  every node a second time on its way out. The size is known here,
      --  so the vector is grown once rather than by doubling.
      Result.Nodes.Reserve_Capacity
        (Subject.Nodes.Length + Predicate.Nodes.Length
         + Object.Nodes.Length + 1);
      Splice (Result.Nodes, Subject.Nodes, S);
      Splice (Result.Nodes, Predicate.Nodes, P);
      Splice (Result.Nodes, Object.Nodes, O);
      Result.Nodes.Append
        (Node'(Variant        => Statement_Node,
               Depth          => Natural'Max
                 (Root_Depth (Subject.Nodes),
                  Natural'Max
                    (Root_Depth (Predicate.Nodes),
                     Root_Depth (Object.Nodes))),
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
      case Root_Variant (Value.Nodes) is
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
      return RDF_Holders.Element
        (Value.Nodes (Value.Nodes.Last_Index).RDF_Data);
   end RDF_Value;

   function Name (Value : Term) return String is
   begin
      Require (Value, Variable_Node);
      return Unbounded.To_String
        (Value.Nodes (Value.Nodes.Last_Index).Name_Data);
   end Name;

   function Length (Value : Term) return Natural is
   begin
      Require (Value, List_Node);
      return Natural
        (Value.Nodes (Value.Nodes.Last_Index).Children.Length);
   end Length;

   function Child (Value : Term; Index : Positive) return Term is
      Result : Term (Initialized => True);
   begin
      Extract
        (Value.Nodes,
         Value.Nodes (Value.Nodes.Last_Index).Children (Index),
         Result.Nodes);
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
      return Natural
        (Value.Nodes (Value.Nodes.Last_Index).Children.Length);
   end Statement_Count;

   function Statement_At (Value : Term; Index : Positive) return Statement is
      Result : Statement (Initialized => True);
   begin
      Require (Value, Formula_Node);
      Extract
        (Value.Nodes,
         Value.Nodes (Value.Nodes.Last_Index).Children (Index),
         Result.Nodes);
      return Result;
   end Statement_At;

   function Part (Value : Statement; Index : Positive) return Term is
      Result : Term (Initialized => True);
   begin
      Extract (Value.Nodes, Index, Result.Nodes);
      return Result;
   end Part;

   function Subject (Value : Statement) return Term
   is (Part (Value, Value.Nodes (Value.Nodes.Last_Index).Subject_Node));

   function Predicate (Value : Statement) return Term
   is (Part (Value, Value.Nodes (Value.Nodes.Last_Index).Predicate_Node));

   function Object (Value : Statement) return Term
   is (Part (Value, Value.Nodes (Value.Nodes.Last_Index).Object_Node));

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
