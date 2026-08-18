private with Ada.Containers.Vectors;
private with Ada.Strings.Unbounded;

--  The syntax tree a query parses into.
--
--  Nodes live in one flat vector with every reference an index, the same
--  shape the RDF and N3 term models use. An expression tree, a pattern
--  tree, and a projection list are all recursive in different ways, and one
--  flat vector removes all three recursions at once.
--
--  The tree records what was written rather than what it means. "?x" and
--  "$x" are the same variable and are stored the same way, but a FILTER
--  containing "1 + 2" keeps the addition rather than folding it: this is a
--  syntax tree, and a query that is written back should be the query that
--  was read.
package Flyology_SPARQL.Syntax is

   --  What kind of query this is.
   --  @enum Select_Query SELECT
   --  @enum Ask_Query ASK
   --  @enum Construct_Query CONSTRUCT
   --  @enum Describe_Query DESCRIBE
   type Query_Form is
     (Select_Query, Ask_Query, Construct_Query, Describe_Query);

   --  Duplicate handling on a SELECT.
   type Duplicates_Kind is (All_Solutions, Distinct_Solutions,
                            Reduced_Solutions);

   --  What a node in the tree is.
   type Node_Kind is
     (--  Terms
      IRI_Node, Prefixed_Node, Blank_Node, Literal_Node, Variable_Node,
      A_Node,

      --  Patterns
      Triple_Node,             --  one subject-predicate-object
      Group_Node,              --  { ... }
      Optional_Node,           --  OPTIONAL { ... }
      Union_Node,              --  { ... } UNION { ... }
      Minus_Node,              --  MINUS { ... }
      Graph_Node,              --  GRAPH term { ... }
      Service_Node,            --  SERVICE term { ... }
      Filter_Node,             --  FILTER expression
      Bind_Node,               --  BIND (expression AS ?v)
      Values_Node,             --  VALUES ...
      Subquery_Node,           --  { SELECT ... }
      Triple_Term_Node,        --  <<( s p o )>>
      Reified_Node,            --  << s p o ~r >>
      Dataset_Node,            --  FROM, FROM NAMED
      Exists_Node,             --  EXISTS, NOT EXISTS
      Collection_Node,         --  ( a b c ) in a pattern
      Property_List_Node,      --  [ p o ] in a pattern

      --  Expressions
      Or_Node, And_Node,
      Compare_Node,            --  =, !=, <, >, <=, >=
      Arithmetic_Node,         --  +, -, *, /
      Unary_Node,              --  !, unary + and -
      Call_Node,               --  a function or built-in call
      In_Node,                 --  IN and NOT IN

      --  Clauses
      Order_Term_Node,         --  one ORDER BY key
      Projection_Node);        --  one selected item

   --  A parsed query.
   type Query (<>) is private;

   --  Reference to one node, or zero for none.
   type Node_Reference is new Natural;

   --  No node.
   No_Node : constant Node_Reference := 0;

   --  Return the query's form.
   --  @param Value Query to inspect
   --  @return The query form
   function Form (Value : Query) return Query_Form;

   --  Return the base IRI declared by the prologue, or an empty string.
   --  @param Value Query to inspect
   --  @return The base IRI
   function Base (Value : Query) return String;

   --  Return the number of prefix declarations.
   --  @param Value Query to inspect
   --  @return Declaration count
   function Prefix_Count (Value : Query) return Natural;

   --  Return one prefix name, without its colon.
   --  @param Value Query to inspect
   --  @param Index One-based declaration position
   --  @return The prefix name
   function Prefix_Name (Value : Query; Index : Positive) return String;

   --  Return one prefix's namespace.
   --  @param Value Query to inspect
   --  @param Index One-based declaration position
   --  @return The namespace IRI
   function Prefix_Namespace
     (Value : Query; Index : Positive) return String;

   --  Return the root of the WHERE clause, or No_Node for a query with
   --  none, which only DESCRIBE may be.
   --  @param Value Query to inspect
   --  @return The pattern root
   function Where_Clause (Value : Query) return Node_Reference;

   --  Return a node's kind.
   --  @param Value Query holding the node
   --  @param Node The node
   --  @return The node's kind
   function Kind (Value : Query; Node : Node_Reference) return Node_Kind;

   --  Return a node's primary text: an IRI, a variable name, a literal's
   --  lexical form, an operator, or a function name.
   --  @param Value Query holding the node
   --  @param Node The node
   --  @return The text, empty where the kind carries none
   function Text (Value : Query; Node : Node_Reference) return String;

   --  Return a node's secondary text: a prefixed name's prefix, a
   --  literal's language tag, or a BIND target.
   --  @param Value Query holding the node
   --  @param Node The node
   --  @return The text, empty where the kind carries none
   function Detail (Value : Query; Node : Node_Reference) return String;

   --  Return how many children a node has.
   --  @param Value Query holding the node
   --  @param Node The node
   --  @return Child count
   function Child_Count
     (Value : Query; Node : Node_Reference) return Natural;

   --  Return one child of a node.
   --  @param Value Query holding the node
   --  @param Node The node
   --  @param Index One-based child position
   --  @return The child
   function Child
     (Value : Query;
      Node  : Node_Reference;
      Index : Positive) return Node_Reference;

   --  Return the SELECT duplicate mode.
   --  @param Value Query to inspect
   --  @return The duplicate mode
   function Duplicates (Value : Query) return Duplicates_Kind;

   --  Report whether a SELECT projects every variable, written "*".
   --  @param Value Query to inspect
   --  @return True for SELECT *
   function Selects_All (Value : Query) return Boolean;

   --  Return the projection, GROUP BY, ORDER BY, or CONSTRUCT template
   --  roots. Each is a list node whose children are the individual items.
   --  @param Value Query to inspect
   --  @return The list root, or No_Node
   function Projection (Value : Query) return Node_Reference;
   function Group_By (Value : Query) return Node_Reference;
   function Having (Value : Query) return Node_Reference;
   function Order_By (Value : Query) return Node_Reference;
   function Template (Value : Query) return Node_Reference;
   function Describe_Targets (Value : Query) return Node_Reference;
   function Dataset (Value : Query) return Node_Reference;

   --  Return the VERSION declaration, or an empty string.
   --  @param Value Query to inspect
   --  @return The declared version
   function Version (Value : Query) return String;

   --  Return the LIMIT or OFFSET, or -1 when absent.
   --  @param Value Query to inspect
   --  @return The bound, or -1
   function Limit (Value : Query) return Integer;
   function Offset (Value : Query) return Integer;

   --  Assembles a query. The parser is the only intended user; it is here
   --  rather than in a child of this package so that reading a tree and
   --  building one stay separate concerns with separate APIs.
   type Builder is limited private;

   --  Begin a query of the given form.
   procedure Start (Into : in out Builder; Value : Query_Form);

   --  Add a node and return a reference to it.
   function Add_Node
     (Into    : in out Builder;
      Variant : Node_Kind;
      Text    : String := "";
      Detail  : String := "") return Node_Reference;

   --  Attach a child to a node, in order.
   procedure Add_Child (Into : in out Builder; Parent, Item : Node_Reference);

   --  Record a prefix declaration.
   procedure Add_Prefix (Into : in out Builder; Name, Namespace : String);

   --  Record the parts of the query that are not nodes.
   procedure Set_Base (Into : in out Builder; Value : String);
   procedure Set_Where (Into : in out Builder; Value : Node_Reference);
   procedure Set_Projection (Into : in out Builder; Value : Node_Reference);
   procedure Set_Group_By (Into : in out Builder; Value : Node_Reference);
   procedure Set_Having (Into : in out Builder; Value : Node_Reference);
   procedure Set_Order_By (Into : in out Builder; Value : Node_Reference);
   procedure Set_Template (Into : in out Builder; Value : Node_Reference);
   procedure Set_Describe (Into : in out Builder; Value : Node_Reference);
   procedure Set_Dataset (Into : in out Builder; Value : Node_Reference);
   procedure Set_Version (Into : in out Builder; Value : String);
   procedure Set_Duplicates (Into : in out Builder; Value : Duplicates_Kind);
   procedure Set_Selects_All (Into : in out Builder; Value : Boolean);
   procedure Set_Limit (Into : in out Builder; Value : Integer);
   procedure Set_Offset (Into : in out Builder; Value : Integer);

   --  Read one node of the tree still being built. The parser asks
   --  questions of nodes it has just made, and producing a whole Query to
   --  answer one would copy the tree each time it was asked.
   function Kind (Into : Builder; Node : Node_Reference) return Node_Kind;
   function Text (Into : Builder; Node : Node_Reference) return String;
   function Child_Count
     (Into : Builder; Node : Node_Reference) return Natural;
   function Child
     (Into  : Builder;
      Node  : Node_Reference;
      Index : Positive) return Node_Reference;

   --  Return the WHERE clause recorded so far, or No_Node.
   function Where_Clause (Into : Builder) return Node_Reference;

   --  Finish, producing the query. The nodes move into it rather than
   --  being copied, which is why the builder is left empty rather than
   --  reusable.
   function To_Query (Into : in out Builder) return Query;

private

   package Unbounded renames Ada.Strings.Unbounded;

   package Reference_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Node_Reference);

   type Node is record
      Variant  : Node_Kind := IRI_Node;
      Text     : Unbounded.Unbounded_String;
      Detail   : Unbounded.Unbounded_String;
      Children : Reference_Vectors.Vector;
   end record;

   --  The node type is definite, so the nodes can live in the vector
   --  itself; a vector that kept each one behind its own allocation would
   --  pay that allocation on every append.
   package Node_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Node);

   type Prefix_Binding is record
      Name      : Unbounded.Unbounded_String;
      Namespace : Unbounded.Unbounded_String;
   end record;

   package Binding_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Prefix_Binding);

   type Query (Initialized : Boolean) is record
      Form_Value       : Query_Form := Select_Query;
      Base_Value       : Unbounded.Unbounded_String;
      Bindings         : Binding_Vectors.Vector;
      Nodes            : Node_Vectors.Vector;
      Where_Value      : Node_Reference := No_Node;
      Projection_Value : Node_Reference := No_Node;
      Group_Value      : Node_Reference := No_Node;
      Having_Value     : Node_Reference := No_Node;
      Order_Value      : Node_Reference := No_Node;
      Template_Value   : Node_Reference := No_Node;
      Describe_Value   : Node_Reference := No_Node;
      Dataset_Value    : Node_Reference := No_Node;
      Version_Value    : Unbounded.Unbounded_String;
      Duplicates_Value : Duplicates_Kind := All_Solutions;
      Selects_All_Flag : Boolean := False;
      Limit_Value      : Integer := -1;
      Offset_Value     : Integer := -1;
   end record;

   type Builder is limited record
      Draft : Query (Initialized => True);
   end record;

end Flyology_SPARQL.Syntax;
