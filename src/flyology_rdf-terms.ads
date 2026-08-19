private with Ada.Finalization;
private with System;
private with System.Atomic_Counters;
private with Ada.Strings.Unbounded;

with Flyology_RDF.IRIs;

--  Immutable RDF 1.2 terms with constructor-enforced invariants.
--
--  A Term is stored as a flat vector of nodes in child-before-parent order.
--  Nested triple terms name their children by index rather than by access
--  value, so no cycle is representable, traversal is iterative, and the
--  whole term is one contiguous allocation rather than a pointer graph.
package Flyology_RDF.Terms is

   --  The four term kinds of the RDF 1.2 abstract syntax.
   --  @enum IRI_Kind An IRI
   --  @enum Blank_Node_Kind A blank node, identified by a label
   --  @enum Literal_Kind A literal, always carrying a datatype
   --  @enum Triple_Term_Kind A quoted triple used as a term
   type Term_Kind is
     (IRI_Kind, Blank_Node_Kind, Literal_Kind, Triple_Term_Kind);

   --  Base direction of a directional language-tagged literal.
   --  @enum Left_To_Right Corresponds to the --ltr direction
   --  @enum Right_To_Left Corresponds to the --rtl direction
   type Base_Direction is (Left_To_Right, Right_To_Left);

   --  Raised when a selector is applied to a term of the wrong kind, or to
   --  an optional literal component that is absent.
   Invalid_Term : exception;

   --  Raised when a literal's components are individually well formed but
   --  inconsistent, such as a language-tagged literal whose datatype is not
   --  rdf:langString.
   Invalid_Literal : exception;

   --  Raised when a language tag is empty or not well formed.
   Invalid_Language_Tag : exception;

   --  Raised when a construction would exceed a published bound below.
   Term_Limit_Error : exception;

   --  Deepest nesting of quoted triples a term may reach.
   Maximum_Triple_Term_Depth : constant Positive := 256;

   --  Most nodes a single term may contain. A maximally deep chain of quoted
   --  triples contributes one triple node and one leaf per level, plus the
   --  innermost leaf.
   Maximum_Term_Nodes : constant Positive :=
     2 * Maximum_Triple_Term_Depth + 1;

   --  Largest total payload a single term may carry, in UTF-8 bytes.
   Maximum_Payload_Bytes : constant Positive := 16 * 1_024 * 1_024;

   --  The datatype of a plain string literal.
   --  @return xsd:string
   function String_Datatype return IRIs.IRI;

   --  The datatype every language-tagged literal carries.
   --  @return rdf:langString
   function Language_String_Datatype return IRIs.IRI;

   --  An immutable RDF term.
   type Term is private;

   --  Visit-local identity of one node in a term's immutable tree. Values
   --  are meaningful only for the duration of the Visit_Nodes call that
   --  supplied them.
   type Node_ID is range 1 .. Maximum_Term_Nodes;

   ----------------------------------------------------------------------
   --  Construction
   ----------------------------------------------------------------------

   --  Build a term denoting an IRI.
   --  @param Value The IRI
   --  @return The corresponding term
   function IRI_Term (Value : IRIs.IRI) return Term;

   --  Build a blank node with the given label.
   --
   --  The label is an identifier local to whatever scope the caller is
   --  working in; this package attaches no meaning to it beyond equality,
   --  and in particular does not treat two equal labels from different
   --  documents as denoting the same node. Managing that is the caller's
   --  job, because only the caller knows what a document boundary is.
   --  @param Label Non-empty blank node label
   --  @return The corresponding term
   --  @exception Invalid_Term Label is empty
   --  @exception Invalid_Term Label is empty, or is not a
   --     BLANK_NODE_LABEL. A dataset identifies a statement by its N-Quads
   --     serialization and a label is written into it verbatim, so a label
   --     carrying N-Quads syntax would forge another statement's identity.
   function Blank_Node (Label : String) return Term;

   --  Build a typed literal.
   --  @param Lexical_Form The literal's lexical form
   --  @param Datatype The datatype IRI
   --  @return The corresponding term
   --  @exception Invalid_Literal Datatype is rdf:langString, which requires
   --     a language tag and must be built with Language_Literal
   --  @exception Term_Limit_Error The payload exceeds Maximum_Payload_Bytes
   function Literal
     (Lexical_Form : String;
      Datatype     : IRIs.IRI) return Term;

   --  Build a language-tagged literal. Its datatype is rdf:langString.
   --
   --  The tag is stored lowercased. RDF defines the value space of language
   --  tags as lowercase, so this is a normalisation the abstract syntax
   --  calls for rather than one this package invents -- but it does mean a
   --  literal written @en-US is returned as en-us, which anything comparing
   --  serialisations byte for byte has to account for.
   --  @param Lexical_Form The literal's lexical form
   --  @param Language Non-empty language tag
   --  @return The corresponding term
   --  @exception Invalid_Language_Tag Language is empty or malformed
   --  @exception Term_Limit_Error The payload exceeds Maximum_Payload_Bytes
   function Language_Literal
     (Lexical_Form : String;
      Language     : String) return Term;

   --  Build a language-tagged literal that also carries a base direction.
   --  @param Lexical_Form The literal's lexical form
   --  @param Language Non-empty language tag
   --  @param Direction The base direction
   --  @return The corresponding term
   --  @exception Invalid_Language_Tag Language is empty or malformed
   --  @exception Term_Limit_Error The payload exceeds Maximum_Payload_Bytes
   function Directional_Literal
     (Lexical_Form : String;
      Language     : String;
      Direction    : Base_Direction) return Term;

   --  Build a quoted triple used as a term.
   --
   --  The predicate is typed as an IRI rather than a Term, so a literal or
   --  blank node in predicate position is rejected at compile time rather
   --  than checked here.
   --  @param Subject Subject term
   --  @param Predicate Predicate IRI
   --  @param Object Object term
   --  @return The corresponding term
   --  @exception Term_Limit_Error The result would exceed
   --     Maximum_Triple_Term_Depth, Maximum_Term_Nodes, or
   --     Maximum_Payload_Bytes
   function Triple_Term
     (Subject   : Term;
      Predicate : IRIs.IRI;
      Object    : Term) return Term;

   ----------------------------------------------------------------------
   --  Inspection
   ----------------------------------------------------------------------

   --  Report which of the four kinds this term is.
   --  @param Value Term to inspect
   --  @return The term's kind
   function Kind (Value : Term) return Term_Kind;

   --  Return the IRI of an IRI term.
   --  @param Value Term to inspect
   --  @return The IRI
   --  @exception Invalid_Term Value is not an IRI term
   function IRI_Value (Value : Term) return IRIs.IRI;

   --  Return the label of a blank node.
   --  @param Value Term to inspect
   --  @return The label
   --  @exception Invalid_Term Value is not a blank node
   function Label (Value : Term) return String;

   --  Return the lexical form of a literal.
   --  @param Value Term to inspect
   --  @return The lexical form
   --  @exception Invalid_Term Value is not a literal
   function Lexical_Form (Value : Term) return String;

   --  Return the datatype of a literal.
   --  @param Value Term to inspect
   --  @return The datatype IRI
   --  @exception Invalid_Term Value is not a literal
   function Datatype (Value : Term) return IRIs.IRI;

   --  Report whether a literal carries a language tag.
   --  @param Value Term to inspect
   --  @return True when Language would succeed
   --  @exception Invalid_Term Value is not a literal
   function Has_Language (Value : Term) return Boolean;

   --  Return the lowercased language tag of a literal.
   --  @param Value Term to inspect
   --  @return The language tag
   --  @exception Invalid_Term Value is not a language-tagged literal
   function Language (Value : Term) return String;

   --  Report whether a literal carries a base direction.
   --  @param Value Term to inspect
   --  @return True when Direction would succeed
   --  @exception Invalid_Term Value is not a literal
   function Has_Direction (Value : Term) return Boolean;

   --  Return the base direction of a directional literal.
   --  @param Value Term to inspect
   --  @return The base direction
   --  @exception Invalid_Term Value is not a directional literal
   function Direction (Value : Term) return Base_Direction;

   --  Return the subject of a quoted triple.
   --  @param Value Term to inspect
   --  @return The subject term
   --  @exception Invalid_Term Value is not a triple term
   function Triple_Subject (Value : Term) return Term;

   --  Return the predicate of a quoted triple.
   --  @param Value Term to inspect
   --  @return The predicate IRI
   --  @exception Invalid_Term Value is not a triple term
   function Triple_Predicate (Value : Term) return IRIs.IRI;

   --  Return the object of a quoted triple.
   --  @param Value Term to inspect
   --  @return The object term
   --  @exception Invalid_Term Value is not a triple term
   function Triple_Object (Value : Term) return Term;

   --  Return the number of nodes in the term's flat tree.
   --  @param Value Term to inspect
   --  @return Node count, at least one
   function Node_Count (Value : Term) return Positive;

   --  Return the quoted-triple nesting depth, zero for a leaf term.
   --  @param Value Term to inspect
   --  @return Nesting depth
   function Depth (Value : Term) return Natural;

   --  Visit every node exactly once in child-before-parent order and return
   --  the root's identity. A triple node's child identities always name
   --  nodes already visited, so a consumer can build its own representation
   --  bottom-up in a single pass. No subtree escapes and nothing is copied.
   --  @param Value Term to traverse
   --  @param On_IRI Called for each IRI node
   --  @param On_Blank Called for each blank node
   --  @param On_Literal Called for each literal node
   --  @param On_Triple Called for each quoted-triple node
   --  @return Identity of the root node
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
         Object_Node        : Node_ID)) return Node_ID;

   --  Compare two terms structurally.
   --  @param Left First term
   --  @param Right Second term
   --  @return True when both denote the same RDF term
   overriding function "=" (Left, Right : Term) return Boolean;

private

   type Term_Node (Variant : Term_Kind := IRI_Kind) is record
      Subtree_Size   : Positive := 1;
      Subtree_Depth  : Natural  := 0;
      Payload_Length : Natural  := 0;
      case Variant is
         when IRI_Kind =>
            IRI_Data : IRIs.IRI;
         when Blank_Node_Kind =>
            Label_Data : Ada.Strings.Unbounded.Unbounded_String;
         when Literal_Kind =>
            Lexical_Data       : Ada.Strings.Unbounded.Unbounded_String;
            Datatype_Data      : IRIs.IRI;
            Language_Data      : Ada.Strings.Unbounded.Unbounded_String;
            Has_Language_Data  : Boolean := False;
            Direction_Data     : Base_Direction := Left_To_Right;
            Has_Direction_Data : Boolean := False;
         when Triple_Term_Kind =>
            Subject_Node   : Positive := 1;
            Predicate_Data : IRIs.IRI;
            Object_Node    : Positive := 1;
      end case;
   end record;

   --  The nodes are shared and reference counted rather than held by
   --  value. A term is immutable once built, and it is copied constantly:
   --  into a triple, into a quad, out to a consumer. Holding the vector
   --  directly made each of those a deep copy -- an allocation and a walk
   --  over every node -- where this makes them an atomic increment.
   --
   --  The count is atomic for the same reason the holders in the parent
   --  package use an atomic one: copying a term must be safe from several
   --  tasks, even though the nodes it shares are never mutated.
   type Node_Array is array (Positive range <>) of Term_Node;

   --  Sized on creation rather than grown. Every constructor knows how
   --  many nodes it is about to write, so the count and the nodes are one
   --  allocation instead of a store pointing at a vector's own array.
   type Node_Store (Count : Positive) is limited record
      References : System.Atomic_Counters.Atomic_Counter;
      Items      : Node_Array (1 .. Count);
   end record;

   type Node_Store_Access is access Node_Store;

   --  The root is always the last element, which is what makes
   --  child-before-parent order and index-only child references consistent.
   --  Definite, so a triple can hold three of these directly instead of
   --  wrapping each in a holder that allocates. The value is one pointer
   --  to the shared nodes, so holding it by value costs nothing.
   --  Nearly every term is one node -- an IRI, a blank node, a literal --
   --  and only a triple term nests. The single node is held here, so the
   --  common term costs no allocation at all; Store carries the rest and
   --  is null until a term actually needs more than one.
   type Term is
     new Ada.Finalization.Controlled with record
      Solo  : Term_Node;
      Store : Node_Store_Access;
   end record;

   overriding procedure Adjust (Value : in out Term);
   overriding procedure Finalize (Value : in out Term);

end Flyology_RDF.Terms;
