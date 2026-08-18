with Ada.Strings.Unbounded;

with Flyology_RDF.IRIs;
with Flyology_RDF.NQuads_Writers;
with Flyology_RDF.Quads;
with Flyology_RDF.Terms;

package body Flyology_RDF.Turtle_Writers is

   package Unbounded renames Ada.Strings.Unbounded;
   package Writers renames Flyology_RDF.NQuads_Writers;

   use type Quads.Graph_Name_Kind;
   use type Terms.Term_Kind;

   --  Statements of one graph, grouped by subject and then by predicate.
   package Object_Maps is new Ada.Containers.Indefinite_Ordered_Maps
     (Key_Type     => String,
      Element_Type => Boolean);

   package Predicate_Maps is new Ada.Containers.Indefinite_Ordered_Maps
     (Key_Type     => String,
      Element_Type => Object_Maps.Map,
      "="          => Object_Maps."=");

   package Subject_Maps is new Ada.Containers.Indefinite_Ordered_Maps
     (Key_Type     => String,
      Element_Type => Predicate_Maps.Map,
      "="          => Predicate_Maps."=");

   package Graph_Maps is new Ada.Containers.Indefinite_Ordered_Maps
     (Key_Type     => String,
      Element_Type => Subject_Maps.Map,
      "="          => Subject_Maps."=");

   function No_Prefixes return Prefix_Map is
      Result : Prefix_Map;
   begin
      return Result;
   end No_Prefixes;

   procedure Bind
     (Into      : in out Prefix_Map;
      Prefix    : String;
      Namespace : String)
   is
      Position : Namespace_Maps.Cursor := Into.By_Namespace.First;
   begin
      --  The map is keyed by namespace, so replacing a binding for the
      --  same prefix means finding the namespace that held it. Keeping
      --  both would write two @prefix declarations for one prefix, and
      --  every name abbreviated against the first would read back
      --  against the second.
      while Namespace_Maps.Has_Element (Position) loop
         if Namespace_Maps.Element (Position) = Prefix then
            declare
               Doomed : Namespace_Maps.Cursor := Position;
            begin
               Namespace_Maps.Next (Position);
               Into.By_Namespace.Delete (Doomed);
            end;
         else
            Namespace_Maps.Next (Position);
         end if;
      end loop;
      Into.By_Namespace.Include (Namespace, Prefix);
   end Bind;

   --  The prefixed-name grammar admits more than this -- escapes, and a
   --  range of non-ASCII name characters -- but everything outside this
   --  set is written as a full IRI instead, which is always legal and
   --  always parses back. A byte-level check cannot tell a non-ASCII name
   --  character from one the grammar forbids, so bytes above ASCII are
   --  not abbreviated at all.
   function Is_Simple_Local (Value : String) return Boolean is
   begin
      for Item of Value loop
         if Item not in 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9'
                      | '_' | '-' | '.'
         then
            return False;
         end if;
      end loop;
      --  A local name may not open with a hyphen or a dot, and may not
      --  end with a dot.
      if Value'Length > 0
        and then (Value (Value'First) in '-' | '.'
                  or else Value (Value'Last) = '.')
      then
         return False;
      end if;
      return True;
   end Is_Simple_Local;

   function Abbreviate
     (Value    : IRIs.IRI;
      Prefixes : Prefix_Map) return String
   is
      Text : constant String := IRIs.To_UTF_8 (Value);
   begin
      for Position in Prefixes.By_Namespace.Iterate loop
         declare
            Namespace : constant String := Namespace_Maps.Key (Position);
            Prefix    : constant String :=
              Namespace_Maps.Element (Position);
         begin
            if Text'Length > Namespace'Length
              and then Text (Text'First .. Text'First + Namespace'Length - 1)
                       = Namespace
            then
               declare
                  Local : constant String :=
                    Text (Text'First + Namespace'Length .. Text'Last);
               begin
                  if Is_Simple_Local (Local) then
                     return Prefix & ":" & Local;
                  end if;
               end;
            end if;
         end;
      end loop;
      return Writers.Write_Term (Terms.IRI_Term (Value));
   end Abbreviate;

   function Render
     (Value    : Terms.Term;
      Prefixes : Prefix_Map) return String is
   begin
      case Terms.Kind (Value) is
         when Terms.IRI_Kind =>
            return Abbreviate (Terms.IRI_Value (Value), Prefixes);
         when Terms.Triple_Term_Kind =>
            return "<<(" & Render (Terms.Triple_Subject (Value), Prefixes)
              & " " & Abbreviate (Terms.Triple_Predicate (Value), Prefixes)
              & " " & Render (Terms.Triple_Object (Value), Prefixes)
              & ")>>";
         when Terms.Blank_Node_Kind | Terms.Literal_Kind =>
            --  Blank nodes and literals have one written form, and the
            --  N-Quads writer already produces it with the right escaping.
            return Writers.Write_Term (Value, Writers.Implicit_Datatype);
      end case;
   end Render;

   --  Collect the dataset into graph / subject / predicate / object order.
   procedure Group
     (Value    : Datasets.Dataset;
      Prefixes : Prefix_Map;
      Result   : out Graph_Maps.Map)
   is
      Grouped : Graph_Maps.Map;

      procedure Note (Statement : Quads.Quad);

      procedure Note (Statement : Quads.Quad) is
         Graph_Key : constant String :=
           (if Quads.Kind (Quads.Graph (Statement))
                 = Quads.Default_Graph_Kind
            then ""
            else Render (Quads.Name_Term (Quads.Graph (Statement)),
                         Prefixes));
         Subject   : constant String :=
           Render (Quads.Subject (Statement), Prefixes);
         Predicate : constant String :=
           Abbreviate (Quads.Predicate (Statement), Prefixes);
         Object    : constant String :=
           Render (Quads.Object (Statement), Prefixes);
      begin
         if not Grouped.Contains (Graph_Key) then
            Grouped.Insert (Graph_Key, Subject_Maps.Empty_Map);
         end if;

         declare
            Subjects : Subject_Maps.Map := Grouped.Element (Graph_Key);
         begin
            if not Subjects.Contains (Subject) then
               Subjects.Insert (Subject, Predicate_Maps.Empty_Map);
            end if;

            declare
               Predicates : Predicate_Maps.Map :=
                 Subjects.Element (Subject);
            begin
               if not Predicates.Contains (Predicate) then
                  Predicates.Insert (Predicate, Object_Maps.Empty_Map);
               end if;

               declare
                  Objects : Object_Maps.Map :=
                    Predicates.Element (Predicate);
               begin
                  Objects.Include (Object, True);
                  Predicates.Replace (Predicate, Objects);
               end;
               Subjects.Replace (Subject, Predicates);
            end;
            Grouped.Replace (Graph_Key, Subjects);
         end;
      end Note;

   begin
      Datasets.Iterate (Value, Note'Access);
      Result := Grouped;
   end Group;

   procedure Write_Subjects
     (Buffer  : in out Unbounded.Unbounded_String;
      Subject : Subject_Maps.Map;
      Indent  : String)
   is
      First_Subject : Boolean := True;
   begin
      for Subject_Position in Subject.Iterate loop
         if not First_Subject then
            Unbounded.Append (Buffer, ASCII.LF);
         end if;
         First_Subject := False;

         Unbounded.Append
           (Buffer, Indent & Subject_Maps.Key (Subject_Position));

         declare
            Predicates : constant Predicate_Maps.Map :=
              Subject_Maps.Element (Subject_Position);
            First_Predicate : Boolean := True;
         begin
            for Predicate_Position in Predicates.Iterate loop
               if First_Predicate then
                  Unbounded.Append (Buffer, " ");
               else
                  Unbounded.Append (Buffer, " ;" & ASCII.LF & Indent
                                    & "    ");
               end if;
               First_Predicate := False;

               Unbounded.Append
                 (Buffer, Predicate_Maps.Key (Predicate_Position));

               declare
                  Objects : constant Object_Maps.Map :=
                    Predicate_Maps.Element (Predicate_Position);
                  First_Object : Boolean := True;
               begin
                  for Object_Position in Objects.Iterate loop
                     if First_Object then
                        Unbounded.Append (Buffer, " ");
                     else
                        Unbounded.Append (Buffer, ", ");
                     end if;
                     First_Object := False;
                     Unbounded.Append
                       (Buffer, Object_Maps.Key (Object_Position));
                  end loop;
               end;
            end loop;
         end;

         Unbounded.Append (Buffer, " ." & ASCII.LF);
      end loop;
   end Write_Subjects;

   procedure Write_Prefixes
     (Buffer   : in out Unbounded.Unbounded_String;
      Prefixes : Prefix_Map)
   is
      Any : Boolean := False;
   begin
      for Position in Prefixes.By_Namespace.Iterate loop
         Any := True;
         Unbounded.Append
           (Buffer,
            "@prefix " & Namespace_Maps.Element (Position) & ": <"
            & Namespace_Maps.Key (Position) & "> ." & ASCII.LF);
      end loop;
      if Any then
         Unbounded.Append (Buffer, ASCII.LF);
      end if;
   end Write_Prefixes;

   function To_TriG
     (Value    : Datasets.Dataset;
      Prefixes : Prefix_Map := No_Prefixes) return String
   is
      Grouped : Graph_Maps.Map;
      Buffer  : Unbounded.Unbounded_String;
      First   : Boolean := True;
   begin
      Group (Value, Prefixes, Grouped);
      Write_Prefixes (Buffer, Prefixes);

      --  The default graph's key is the empty string, which sorts first, so
      --  it leads the output without a special case.
      for Position in Grouped.Iterate loop
         if not First then
            Unbounded.Append (Buffer, ASCII.LF);
         end if;
         First := False;

         if Graph_Maps.Key (Position) = "" then
            Write_Subjects
              (Buffer, Graph_Maps.Element (Position), "");
         else
            Unbounded.Append
              (Buffer, "GRAPH " & Graph_Maps.Key (Position) & " {"
               & ASCII.LF);
            Write_Subjects
              (Buffer, Graph_Maps.Element (Position), "    ");
            Unbounded.Append (Buffer, "}" & ASCII.LF);
         end if;
      end loop;

      return Unbounded.To_String (Buffer);
   end To_TriG;

   function To_Turtle
     (Value    : Datasets.Dataset;
      Prefixes : Prefix_Map := No_Prefixes) return String
   is
      Named : Boolean := False;

      procedure Check_Graph (Graph : Quads.Graph_Name);

      procedure Check_Graph (Graph : Quads.Graph_Name) is
      begin
         if Quads.Kind (Graph) /= Quads.Default_Graph_Kind then
            Named := True;
         end if;
      end Check_Graph;
   begin
      Datasets.Iterate_Graphs (Value, Check_Graph'Access);
      if Named then
         raise Constraint_Error with
           "Turtle cannot express a named graph; use To_TriG";
      end if;
      return To_TriG (Value, Prefixes);
   end To_Turtle;

end Flyology_RDF.Turtle_Writers;
