--  Exercises the term model, concentrating on the flat-tree representation.
--
--  Nested quoted triples are stored as one contiguous vector in
--  child-before-parent order, with children named by index. Splitting a
--  subtree back out therefore involves index arithmetic that is easy to get
--  wrong in a way nothing else notices, so most of what follows builds a
--  nested term and takes it apart again.

with Ada.Command_Line;
with Ada.Text_IO;
with Flyology_RDF.IRIs;
with Flyology_RDF.Terms;

procedure Terms_Tests is

   package IO renames Ada.Text_IO;
   package IRIs renames Flyology_RDF.IRIs;
   package Terms renames Flyology_RDF.Terms;

   use type Terms.Term;
   use type Terms.Term_Kind;
   use type Terms.Node_ID;
   use type Terms.Base_Direction;
   use type IRIs.IRI;

   Checks   : Natural := 0;
   Failures : Natural := 0;

   procedure Check (Condition : Boolean; Label : String) is
   begin
      Checks := Checks + 1;
      if not Condition then
         Failures := Failures + 1;
         IO.Put_Line ("  FAIL  " & Label);
      end if;
   end Check;

   procedure Check_Equal (Actual, Expected, Label : String) is
   begin
      Checks := Checks + 1;
      if Actual /= Expected then
         Failures := Failures + 1;
         IO.Put_Line
           ("  FAIL  " & Label & ": got """ & Actual
            & """, expected """ & Expected & """");
      end if;
   end Check_Equal;

   function Alice return IRIs.IRI is
     (IRIs.From_UTF_8 ("http://example.org/alice"));
   function Bob return IRIs.IRI is
     (IRIs.From_UTF_8 ("http://example.org/bob"));
   function Knows return IRIs.IRI is
     (IRIs.From_UTF_8 ("http://xmlns.com/foaf/0.1/knows"));
   function Said return IRIs.IRI is
     (IRIs.From_UTF_8 ("http://example.org/said"));

   --  Visit_Nodes accumulators.
   Visited_Order   : String (1 .. 64);
   Visited_Length  : Natural := 0;
   Children_Before : Boolean := True;

   procedure Note (Marker : Character) is
   begin
      if Visited_Length < Visited_Order'Last then
         Visited_Length := Visited_Length + 1;
         Visited_Order (Visited_Length) := Marker;
      end if;
   end Note;

   procedure On_IRI (Node : Terms.Node_ID; Value : IRIs.IRI) is
      pragma Unreferenced (Node, Value);
   begin
      Note ('i');
   end On_IRI;

   procedure On_Blank (Node : Terms.Node_ID; Label : String) is
      pragma Unreferenced (Node, Label);
   begin
      Note ('b');
   end On_Blank;

   procedure On_Literal
     (Node          : Terms.Node_ID;
      Lexical_Form  : String;
      Datatype      : IRIs.IRI;
      Has_Language  : Boolean;
      Language      : String;
      Has_Direction : Boolean;
      Direction     : Terms.Base_Direction)
   is
      pragma Unreferenced
        (Node, Lexical_Form, Datatype, Has_Language, Language,
         Has_Direction, Direction);
   begin
      Note ('l');
   end On_Literal;

   procedure On_Triple
     (Node, Subject_Node : Terms.Node_ID;
      Predicate          : IRIs.IRI;
      Object_Node        : Terms.Node_ID)
   is
      pragma Unreferenced (Predicate);
   begin
      --  The contract is that a triple's children are already visited when
      --  the triple itself is reached.
      if Subject_Node >= Node or else Object_Node >= Node then
         Children_Before := False;
      end if;
      Note ('t');
   end On_Triple;

begin
   IO.Put_Line ("Terms tests");

   ------------------------------------------------------------------
   --  Leaf terms
   ------------------------------------------------------------------
   declare
      Node : constant Terms.Term := Terms.IRI_Term (Alice);
   begin
      Check (Terms.Kind (Node) = Terms.IRI_Kind, "IRI term kind");
      Check (Terms.IRI_Value (Node) = Alice, "IRI term round trip");
      Check (Terms.Node_Count (Node) = 1, "IRI term node count");
      Check (Terms.Depth (Node) = 0, "IRI term depth");
   end;

   declare
      Node : constant Terms.Term := Terms.Blank_Node ("b0");
   begin
      Check (Terms.Kind (Node) = Terms.Blank_Node_Kind, "blank kind");
      Check_Equal (Terms.Label (Node), "b0", "blank label");
   end;

   declare
      Node : constant Terms.Term :=
        Terms.Literal ("42", IRIs.From_UTF_8
          ("http://www.w3.org/2001/XMLSchema#integer"));
   begin
      Check (Terms.Kind (Node) = Terms.Literal_Kind, "literal kind");
      Check_Equal (Terms.Lexical_Form (Node), "42", "literal lexical form");
      Check (not Terms.Has_Language (Node), "typed literal has no language");
      Check (not Terms.Has_Direction (Node), "typed literal has no dir");
   end;

   ------------------------------------------------------------------
   --  Language tags are normalised to lower case
   ------------------------------------------------------------------
   declare
      Node : constant Terms.Term := Terms.Language_Literal ("Hello", "en-US");
   begin
      Check_Equal (Terms.Language (Node), "en-us", "language lowercased");
      Check (Terms.Has_Language (Node), "language literal has language");
      Check (Terms.Datatype (Node) = Terms.Language_String_Datatype,
             "language literal datatype is rdf:langString");
   end;

   declare
      Node : constant Terms.Term :=
        Terms.Directional_Literal ("مرحبا", "ar", Terms.Right_To_Left);
   begin
      Check (Terms.Has_Direction (Node), "directional literal has direction");
      Check (Terms.Direction (Node) = Terms.Right_To_Left, "direction rtl");
   end;

   ------------------------------------------------------------------
   --  Rejections
   ------------------------------------------------------------------
   declare
      Ignored : Terms.Term := Terms.Blank_Node ("x");
   begin
      Ignored := Terms.Literal ("x", Terms.Language_String_Datatype);
      Check (False, "rdf:langString via Literal must be rejected");
      pragma Unreferenced (Ignored);
   exception
      when Terms.Invalid_Literal =>
         Check (True, "rdf:langString via Literal rejected");
   end;

   declare
      Ignored : Terms.Term := Terms.Blank_Node ("x");
   begin
      Ignored := Terms.Language_Literal ("x", "");
      Check (False, "empty language tag must be rejected");
      pragma Unreferenced (Ignored);
   exception
      when Terms.Invalid_Language_Tag =>
         Check (True, "empty language tag rejected");
   end;

   declare
      Ignored : Terms.Term := Terms.Blank_Node ("x");
   begin
      Ignored := Terms.Language_Literal ("x", "en-");
      Check (False, "trailing hyphen language tag must be rejected");
      pragma Unreferenced (Ignored);
   exception
      when Terms.Invalid_Language_Tag =>
         Check (True, "trailing hyphen language tag rejected");
   end;

   declare
      Ignored : Terms.Term := Terms.Blank_Node ("x");
   begin
      Ignored := Terms.Blank_Node ("");
      Check (False, "empty blank label must be rejected");
      pragma Unreferenced (Ignored);
   exception
      when Terms.Invalid_Term =>
         Check (True, "empty blank label rejected");
   end;

   declare
      Node    : constant Terms.Term := Terms.IRI_Term (Alice);
      Ignored : IRIs.IRI := Alice;
   begin
      Ignored := Terms.Datatype (Node);
      Check (False, "Datatype on an IRI term must be rejected");
      pragma Unreferenced (Ignored);
   exception
      when Terms.Invalid_Term =>
         Check (True, "Datatype on an IRI term rejected");
   end;

   ------------------------------------------------------------------
   --  One level of quoting
   ------------------------------------------------------------------
   declare
      Inner : constant Terms.Term :=
        Terms.Triple_Term
          (Subject   => Terms.IRI_Term (Alice),
           Predicate => Knows,
           Object    => Terms.IRI_Term (Bob));
   begin
      Check (Terms.Kind (Inner) = Terms.Triple_Term_Kind, "quoted kind");
      Check (Terms.Node_Count (Inner) = 3, "quoted node count");
      Check (Terms.Depth (Inner) = 1, "quoted depth");
      Check (Terms.Triple_Predicate (Inner) = Knows, "quoted predicate");
      Check (Terms.Triple_Subject (Inner) = Terms.IRI_Term (Alice),
             "quoted subject");
      Check (Terms.Triple_Object (Inner) = Terms.IRI_Term (Bob),
             "quoted object");
   end;

   ------------------------------------------------------------------
   --  Two levels: the object is itself a quoted triple.
   --  This is the case the index arithmetic can get wrong.
   ------------------------------------------------------------------
   declare
      Inner : constant Terms.Term :=
        Terms.Triple_Term
          (Subject   => Terms.IRI_Term (Alice),
           Predicate => Knows,
           Object    => Terms.IRI_Term (Bob));
      Outer : constant Terms.Term :=
        Terms.Triple_Term
          (Subject   => Terms.Blank_Node ("witness"),
           Predicate => Said,
           Object    => Inner);
   begin
      Check (Terms.Node_Count (Outer) = 5, "nested node count");
      Check (Terms.Depth (Outer) = 2, "nested depth");
      Check (Terms.Triple_Subject (Outer) = Terms.Blank_Node ("witness"),
             "nested subject survives extraction");
      Check (Terms.Triple_Object (Outer) = Inner,
             "nested object survives extraction");

      --  Take the recovered inner term apart again: if the index shift on
      --  extraction were wrong, this is where it shows.
      declare
         Recovered : constant Terms.Term := Terms.Triple_Object (Outer);
      begin
         Check (Terms.Node_Count (Recovered) = 3, "recovered node count");
         Check (Terms.Triple_Subject (Recovered) = Terms.IRI_Term (Alice),
                "recovered inner subject");
         Check (Terms.Triple_Object (Recovered) = Terms.IRI_Term (Bob),
                "recovered inner object");
         Check (Terms.Triple_Predicate (Recovered) = Knows,
                "recovered inner predicate");
      end;
   end;

   ------------------------------------------------------------------
   --  Quoting on the subject side, so the shift applies to the object
   ------------------------------------------------------------------
   declare
      Inner : constant Terms.Term :=
        Terms.Triple_Term
          (Subject   => Terms.IRI_Term (Alice),
           Predicate => Knows,
           Object    => Terms.IRI_Term (Bob));
      Outer : constant Terms.Term :=
        Terms.Triple_Term
          (Subject   => Inner,
           Predicate => Said,
           Object    => Terms.Blank_Node ("witness"));
   begin
      Check (Terms.Node_Count (Outer) = 5, "subject-nested node count");
      Check (Terms.Triple_Subject (Outer) = Inner,
             "subject-nested subject survives extraction");
      Check (Terms.Triple_Object (Outer) = Terms.Blank_Node ("witness"),
             "subject-nested object survives extraction");
   end;

   ------------------------------------------------------------------
   --  Quoted on both sides at once
   ------------------------------------------------------------------
   declare
      Left_Inner : constant Terms.Term :=
        Terms.Triple_Term (Terms.IRI_Term (Alice), Knows,
                           Terms.IRI_Term (Bob));
      Right_Inner : constant Terms.Term :=
        Terms.Triple_Term (Terms.IRI_Term (Bob), Knows,
                           Terms.IRI_Term (Alice));
      Outer : constant Terms.Term :=
        Terms.Triple_Term (Left_Inner, Said, Right_Inner);
   begin
      Check (Terms.Node_Count (Outer) = 7, "both-nested node count");
      Check (Terms.Triple_Subject (Outer) = Left_Inner,
             "both-nested subject");
      Check (Terms.Triple_Object (Outer) = Right_Inner,
             "both-nested object");
      Check (Left_Inner /= Right_Inner,
             "differently ordered quoted triples differ");
   end;

   ------------------------------------------------------------------
   --  Visit_Nodes ordering
   ------------------------------------------------------------------
   declare
      Inner : constant Terms.Term :=
        Terms.Triple_Term (Terms.IRI_Term (Alice), Knows,
                           Terms.IRI_Term (Bob));
      Outer : constant Terms.Term :=
        Terms.Triple_Term (Terms.Blank_Node ("witness"), Said, Inner);
      Root  : Terms.Node_ID;
   begin
      Root := Terms.Visit_Nodes
        (Outer, On_IRI'Access, On_Blank'Access,
         On_Literal'Access, On_Triple'Access);
      Check (Natural (Root) = 5, "Visit_Nodes returns the root identity");
      Check (Visited_Length = 5, "Visit_Nodes visited every node once");
      Check_Equal (Visited_Order (1 .. Visited_Length), "biitt",
                   "Visit_Nodes order");
      Check (Children_Before, "children visited before their parent");
   end;

   ------------------------------------------------------------------
   --  Depth limit
   ------------------------------------------------------------------
   declare
      Node : Terms.Term := Terms.IRI_Term (Alice);
   begin
      for Level in 1 .. Terms.Maximum_Triple_Term_Depth loop
         Node := Terms.Triple_Term (Terms.IRI_Term (Alice), Knows, Node);
      end loop;
      Check (Terms.Depth (Node) = Terms.Maximum_Triple_Term_Depth,
             "maximum depth is reachable");
      Check (Terms.Node_Count (Node) = Terms.Maximum_Term_Nodes,
             "maximum depth uses exactly the node budget");

      begin
         Node := Terms.Triple_Term (Terms.IRI_Term (Alice), Knows, Node);
         Check (False, "exceeding the depth limit must be rejected");
      exception
         when Terms.Term_Limit_Error =>
            Check (True, "exceeding the depth limit rejected");
      end;
   end;

   ------------------------------------------------------------------
   --  Equality
   ------------------------------------------------------------------
   Check (Terms.IRI_Term (Alice) = Terms.IRI_Term (Alice), "IRI equality");
   Check (Terms.IRI_Term (Alice) /= Terms.IRI_Term (Bob), "IRI inequality");
   Check (Terms.Blank_Node ("a") /= Terms.IRI_Term (Alice),
          "kinds differ");
   Check (Terms.Language_Literal ("x", "EN") = Terms.Language_Literal
            ("x", "en"),
          "language tags compare case insensitively after normalisation");
   Check (Terms.Directional_Literal ("x", "en", Terms.Left_To_Right)
            /= Terms.Language_Literal ("x", "en"),
          "direction participates in equality");

   IO.Put_Line ("  checks              " & Checks'Image);
   IO.Put_Line ("  failures            " & Failures'Image);

   if Failures = 0 then
      IO.Put_Line ("PASS terms_tests");
   else
      IO.Put_Line ("FAIL terms_tests");
      Ada.Command_Line.Set_Exit_Status (1);
   end if;
end Terms_Tests;
