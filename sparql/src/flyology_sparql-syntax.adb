package body Flyology_SPARQL.Syntax is

   function Form (Value : Query) return Query_Form is (Value.Form_Value);

   function Base (Value : Query) return String
   is (Unbounded.To_String (Value.Base_Value));

   function Prefix_Count (Value : Query) return Natural
   is (Natural (Value.Bindings.Length));

   function Prefix_Name (Value : Query; Index : Positive) return String
   is (Unbounded.To_String (Value.Bindings (Index).Name));

   function Prefix_Namespace (Value : Query; Index : Positive) return String
   is (Unbounded.To_String (Value.Bindings (Index).Namespace));

   function Where_Clause (Value : Query) return Node_Reference
   is (Value.Where_Value);

   --  Each of these reads one component through a reference into the
   --  vector. Materializing the node to answer would copy its texts and
   --  its child list every time anything was asked about it.

   function Kind (Value : Query; Node : Node_Reference) return Node_Kind
   is (Value.Nodes (Positive (Node)).Variant);

   function Text (Value : Query; Node : Node_Reference) return String
   is (Unbounded.To_String (Value.Nodes (Positive (Node)).Text));

   function Detail (Value : Query; Node : Node_Reference) return String
   is (Unbounded.To_String (Value.Nodes (Positive (Node)).Detail));

   function Child_Count (Value : Query; Node : Node_Reference) return Natural
   is (Natural (Value.Nodes (Positive (Node)).Children.Length));

   function Child
     (Value : Query;
      Node  : Node_Reference;
      Index : Positive) return Node_Reference
   is (Value.Nodes (Positive (Node)).Children (Index));

   function Duplicates (Value : Query) return Duplicates_Kind
   is (Value.Duplicates_Value);

   function Selects_All (Value : Query) return Boolean
   is (Value.Selects_All_Flag);

   function Projection (Value : Query) return Node_Reference
   is (Value.Projection_Value);

   function Group_By (Value : Query) return Node_Reference
   is (Value.Group_Value);

   function Having (Value : Query) return Node_Reference
   is (Value.Having_Value);

   function Order_By (Value : Query) return Node_Reference
   is (Value.Order_Value);

   function Template (Value : Query) return Node_Reference
   is (Value.Template_Value);

   function Describe_Targets (Value : Query) return Node_Reference
   is (Value.Describe_Value);

   function Dataset (Value : Query) return Node_Reference
   is (Value.Dataset_Value);

   function Version (Value : Query) return String
   is (Unbounded.To_String (Value.Version_Value));

   function Limit (Value : Query) return Integer is (Value.Limit_Value);

   function Offset (Value : Query) return Integer is (Value.Offset_Value);

   ----------------------------------------------------------------------

   procedure Start (Into : in out Builder; Value : Query_Form) is
   begin
      Into.Draft.Form_Value := Value;
   end Start;

   function Add_Node
     (Into    : in out Builder;
      Variant : Node_Kind;
      Text    : String := "";
      Detail  : String := "") return Node_Reference is
   begin
      Into.Draft.Nodes.Append
        (Syntax.Node'(Variant  => Variant,
                      Text     => Unbounded.To_Unbounded_String (Text),
                      Detail   => Unbounded.To_Unbounded_String (Detail),
                      Children => Reference_Vectors.Empty_Vector));
      return Node_Reference (Into.Draft.Nodes.Length);
   end Add_Node;

   procedure Add_Child
     (Into : in out Builder; Parent, Item : Node_Reference) is
   begin
      --  Extended in place: taking the node out and putting it back would
      --  copy its texts and its child list for every child attached.
      Into.Draft.Nodes (Positive (Parent)).Children.Append (Item);
   end Add_Child;

   procedure Add_Prefix (Into : in out Builder; Name, Namespace : String) is
   begin
      Into.Draft.Bindings.Append
        (Prefix_Binding'
           (Name      => Unbounded.To_Unbounded_String (Name),
            Namespace => Unbounded.To_Unbounded_String (Namespace)));
   end Add_Prefix;

   procedure Set_Base (Into : in out Builder; Value : String) is
   begin
      Into.Draft.Base_Value := Unbounded.To_Unbounded_String (Value);
   end Set_Base;

   procedure Set_Where (Into : in out Builder; Value : Node_Reference) is
   begin
      Into.Draft.Where_Value := Value;
   end Set_Where;

   procedure Set_Projection
     (Into : in out Builder; Value : Node_Reference) is
   begin
      Into.Draft.Projection_Value := Value;
   end Set_Projection;

   procedure Set_Group_By (Into : in out Builder; Value : Node_Reference) is
   begin
      Into.Draft.Group_Value := Value;
   end Set_Group_By;

   procedure Set_Having (Into : in out Builder; Value : Node_Reference) is
   begin
      Into.Draft.Having_Value := Value;
   end Set_Having;

   procedure Set_Order_By (Into : in out Builder; Value : Node_Reference) is
   begin
      Into.Draft.Order_Value := Value;
   end Set_Order_By;

   procedure Set_Template (Into : in out Builder; Value : Node_Reference) is
   begin
      Into.Draft.Template_Value := Value;
   end Set_Template;

   procedure Set_Describe (Into : in out Builder; Value : Node_Reference) is
   begin
      Into.Draft.Describe_Value := Value;
   end Set_Describe;

   procedure Set_Dataset (Into : in out Builder; Value : Node_Reference) is
   begin
      Into.Draft.Dataset_Value := Value;
   end Set_Dataset;

   procedure Set_Version (Into : in out Builder; Value : String) is
   begin
      Into.Draft.Version_Value := Unbounded.To_Unbounded_String (Value);
   end Set_Version;

   procedure Set_Duplicates
     (Into : in out Builder; Value : Duplicates_Kind) is
   begin
      Into.Draft.Duplicates_Value := Value;
   end Set_Duplicates;

   procedure Set_Selects_All (Into : in out Builder; Value : Boolean) is
   begin
      Into.Draft.Selects_All_Flag := Value;
   end Set_Selects_All;

   procedure Set_Limit (Into : in out Builder; Value : Integer) is
   begin
      Into.Draft.Limit_Value := Value;
   end Set_Limit;

   procedure Set_Offset (Into : in out Builder; Value : Integer) is
   begin
      Into.Draft.Offset_Value := Value;
   end Set_Offset;

   function Kind (Into : Builder; Node : Node_Reference) return Node_Kind
   is (Into.Draft.Nodes (Positive (Node)).Variant);

   function Text (Into : Builder; Node : Node_Reference) return String
   is (Unbounded.To_String (Into.Draft.Nodes (Positive (Node)).Text));

   function Child_Count
     (Into : Builder; Node : Node_Reference) return Natural
   is (Natural (Into.Draft.Nodes (Positive (Node)).Children.Length));

   function Child
     (Into  : Builder;
      Node  : Node_Reference;
      Index : Positive) return Node_Reference
   is (Into.Draft.Nodes (Positive (Node)).Children (Index));

   function Where_Clause (Into : Builder) return Node_Reference
   is (Into.Draft.Where_Value);

   function To_Query (Into : in out Builder) return Query is
   begin
      return Result : Query (Initialized => True) do
         Node_Vectors.Move
           (Target => Result.Nodes, Source => Into.Draft.Nodes);
         Binding_Vectors.Move
           (Target => Result.Bindings, Source => Into.Draft.Bindings);
         Result.Form_Value       := Into.Draft.Form_Value;
         Result.Base_Value       := Into.Draft.Base_Value;
         Result.Where_Value      := Into.Draft.Where_Value;
         Result.Projection_Value := Into.Draft.Projection_Value;
         Result.Group_Value      := Into.Draft.Group_Value;
         Result.Having_Value     := Into.Draft.Having_Value;
         Result.Order_Value      := Into.Draft.Order_Value;
         Result.Template_Value   := Into.Draft.Template_Value;
         Result.Describe_Value   := Into.Draft.Describe_Value;
         Result.Dataset_Value    := Into.Draft.Dataset_Value;
         Result.Version_Value    := Into.Draft.Version_Value;
         Result.Duplicates_Value := Into.Draft.Duplicates_Value;
         Result.Selects_All_Flag := Into.Draft.Selects_All_Flag;
         Result.Limit_Value      := Into.Draft.Limit_Value;
         Result.Offset_Value     := Into.Draft.Offset_Value;
      end return;
   end To_Query;

end Flyology_SPARQL.Syntax;
