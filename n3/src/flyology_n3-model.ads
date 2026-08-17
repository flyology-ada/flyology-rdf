private with Ada.Containers.Indefinite_Holders;
private with Ada.Containers.Indefinite_Vectors;
private with Ada.Containers.Vectors;
private with Ada.Strings.Unbounded;

with Flyology_RDF.IRIs;
with Flyology_RDF.Terms;

--  The N3 term model.
--
--  Terms are stored the way the RDF model stores them: one flat vector of
--  nodes in child-before-parent order, with every reference an index. A
--  formula holding statements holding terms holding formulas is mutually
--  recursive, and a flat vector removes the recursion instead of managing
--  it -- no cycle is representable, and a whole term is one allocation.
package Flyology_N3.Model is

   package RDF renames Flyology_RDF;

   --  What an N3 term can be.
   --  @enum RDF_Kind An IRI, blank node, or literal -- an RDF term
   --  @enum Variable_Kind A universally or existentially quantified name
   --  @enum List_Kind A first-class list
   --  @enum Formula_Kind A quoted graph, written in braces
   type Term_Kind is (RDF_Kind, Variable_Kind, List_Kind, Formula_Kind);

   --  Raised when a selector is applied to a term of the wrong kind.
   Invalid_Term : exception;

   --  Deepest nesting of formulas and lists a term may reach.
   Maximum_Depth : constant Positive := 128;

   --  An N3 term.
   type Term (<>) is private;

   --  An N3 statement. Unlike RDF, the predicate is a term rather than an
   --  IRI, because N3 allows a variable or a path there.
   type Statement (<>) is private;

   --  Accumulates the parts of a list or a formula.
   --
   --  Terms are indefinite, so a sequence of them cannot be an array, and a
   --  container instantiated over them here would be a container over a
   --  type whose completion has not been seen. A builder sidesteps both,
   --  and holds the flat nodes directly rather than a sequence of whole
   --  terms that would only be spliced together afterwards.
   type Builder is limited private;

   --  Add a list element.
   --  @param Into Builder to extend
   --  @param Value Element to add
   procedure Append (Into : in out Builder; Value : Term);

   --  Add a formula statement.
   --  @param Into Builder to extend
   --  @param Value Statement to add
   procedure Append (Into : in out Builder; Value : Statement);

   --  Report how many parts have been added.
   --  @param Value Builder to measure
   --  @return Part count
   function Count (Value : Builder) return Natural;

   --  Wrap an RDF term.
   --  @param Value The RDF term
   --  @return The corresponding N3 term
   function From_RDF (Value : RDF.Terms.Term) return Term;

   --  Build an IRI term.
   --  @param Value The IRI
   --  @return The corresponding N3 term
   function IRI_Term (Value : RDF.IRIs.IRI) return Term;

   --  Build a variable.
   --  @param Name Variable name without its question mark
   --  @return The corresponding N3 term
   --  @exception Invalid_Term Name is empty
   function Variable (Name : String) return Term;

   --  Build a list from accumulated elements.
   --  @param Items Builder holding the elements, in order
   --  @return The corresponding N3 term
   --  @exception Invalid_Term The result would exceed Maximum_Depth
   function List (Items : Builder) return Term;

   --  Build a formula from accumulated statements.
   --  @param Items Builder holding the statements, in order
   --  @return The corresponding N3 term
   --  @exception Invalid_Term The result would exceed Maximum_Depth
   function Formula (Items : Builder) return Term;

   --  The empty formula, which N3 writes as {}.
   --  @return A formula holding no statements
   function Empty_Formula return Term;

   --  Build a statement.
   --  @param Subject Subject term
   --  @param Predicate Predicate term
   --  @param Object Object term
   --  @return The corresponding statement
   function Create (Subject, Predicate, Object : Term) return Statement;

   --  Report which kind this term is.
   --  @param Value Term to inspect
   --  @return The term's kind
   function Kind (Value : Term) return Term_Kind;

   --  Return the wrapped RDF term.
   --  @param Value Term to inspect
   --  @return The RDF term
   --  @exception Invalid_Term Value is not an RDF term
   function RDF_Value (Value : Term) return RDF.Terms.Term;

   --  Return a variable's name, without its question mark.
   --  @param Value Term to inspect
   --  @return The variable name
   --  @exception Invalid_Term Value is not a variable
   function Name (Value : Term) return String;

   --  Return the number of elements in a list.
   --  @param Value Term to inspect
   --  @return Element count
   --  @exception Invalid_Term Value is not a list
   function Length (Value : Term) return Natural;

   --  Return one element of a list.
   --  @param Value Term to inspect
   --  @param Index One-based element position
   --  @return The element
   --  @exception Invalid_Term Value is not a list
   function Element (Value : Term; Index : Positive) return Term;

   --  Return the number of statements in a formula.
   --  @param Value Term to inspect
   --  @return Statement count
   --  @exception Invalid_Term Value is not a formula
   function Statement_Count (Value : Term) return Natural;

   --  Return one statement of a formula.
   --  @param Value Term to inspect
   --  @param Index One-based statement position
   --  @return The statement
   --  @exception Invalid_Term Value is not a formula
   function Statement_At (Value : Term; Index : Positive) return Statement;

   --  Return a statement's subject.
   --  @param Value Statement to inspect
   --  @return The subject term
   function Subject (Value : Statement) return Term;

   --  Return a statement's predicate.
   --  @param Value Statement to inspect
   --  @return The predicate term
   function Predicate (Value : Statement) return Term;

   --  Return a statement's object.
   --  @param Value Statement to inspect
   --  @return The object term
   function Object (Value : Statement) return Term;

private

   package Unbounded renames Ada.Strings.Unbounded;

   package RDF_Holders is new Ada.Containers.Indefinite_Holders
     (Element_Type => RDF.Terms.Term,
      "="          => RDF.Terms."=");

   package Index_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Positive);

   --  A node is either a term or a statement; keeping both in one vector is
   --  what lets a formula name its statements by index like anything else.
   type Node_Kind is
     (RDF_Node, Variable_Node, List_Node, Formula_Node, Statement_Node);

   type Node (Variant : Node_Kind := RDF_Node) is record
      Depth : Natural := 0;
      case Variant is
         when RDF_Node =>
            RDF_Data : RDF_Holders.Holder;
         when Variable_Node =>
            Name_Data : Unbounded.Unbounded_String;
         when List_Node | Formula_Node =>
            Children : Index_Vectors.Vector;
         when Statement_Node =>
            Subject_Node   : Positive := 1;
            Predicate_Node : Positive := 1;
            Object_Node    : Positive := 1;
      end case;
   end record;

   package Node_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Positive, Element_Type => Node);

   type Term (Initialized : Boolean) is record
      Nodes : Node_Vectors.Vector;
   end record;

   type Statement (Initialized : Boolean) is record
      Nodes : Node_Vectors.Vector;
   end record;

   type Builder is limited record
      Parts : Node_Vectors.Vector;
      Roots : Index_Vectors.Vector;
      Depth : Natural := 0;
   end record;

   overriding function "=" (Left, Right : Term) return Boolean;
   overriding function "=" (Left, Right : Statement) return Boolean;

end Flyology_N3.Model;
