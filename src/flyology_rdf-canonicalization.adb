with Ada.Containers.Indefinite_Ordered_Maps;
with Ada.Containers.Indefinite_Ordered_Sets;
with Ada.Containers.Indefinite_Vectors;

with Flyology_RDF.Digests;
with Flyology_RDF.IRIs;
with Flyology_RDF.NQuads_Writers;
with Flyology_RDF.Quads;
with Flyology_RDF.Terms;

package body Flyology_RDF.Canonicalization is

   package Unbounded renames Ada.Strings.Unbounded;
   package Writers renames Flyology_RDF.NQuads_Writers;

   use type Terms.Term_Kind;
   use type Quads.Graph_Name_Kind;
   use type Unbounded.Unbounded_String;

   package String_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Positive, Element_Type => String);

   package String_Sets is new Ada.Containers.Indefinite_Ordered_Sets
     (Element_Type => String);

   package String_Maps is new Ada.Containers.Indefinite_Ordered_Maps
     (Key_Type => String, Element_Type => String);

   package Quad_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Positive, Element_Type => Quads.Quad, "=" => Quads."=");

   package Quad_Lists is new Ada.Containers.Indefinite_Ordered_Maps
     (Key_Type     => String,
      Element_Type => Quad_Vectors.Vector,
      "="          => Quad_Vectors."=");

   package Group_Maps is new Ada.Containers.Indefinite_Ordered_Maps
     (Key_Type     => String,
      Element_Type => String_Vectors.Vector,
      "="          => String_Vectors."=");

   --  Raised internally when the work bound is reached; caught at the top.
   Exhausted : exception;

   ----------------------------------------------------------------------
   --  Identifier issuer
   ----------------------------------------------------------------------

   --  Hands out labels in the order they are first asked for, remembering
   --  the mapping. The issue order matters: the algorithm reads it back to
   --  decide which of several equally-shaped nodes gets which label.
   type Issuer is record
      Prefix : Unbounded.Unbounded_String;
      Issued : String_Maps.Map;
      Order  : String_Vectors.Vector;
   end record;

   function New_Issuer (Prefix : String) return Issuer is
     (Prefix => Unbounded.To_Unbounded_String (Prefix),
      Issued => String_Maps.Empty_Map,
      Order  => String_Vectors.Empty_Vector);

   function Has_Issued (Value : Issuer; Label : String) return Boolean
   is (Value.Issued.Contains (Label));

   function Issued_For (Value : Issuer; Label : String) return String
   is (Value.Issued.Element (Label));

   function Issue
     (Value : in out Issuer; Label : String) return String is
   begin
      if Value.Issued.Contains (Label) then
         return Value.Issued.Element (Label);
      end if;

      declare
         Count : constant String :=
           Natural'Image (Natural (Value.Order.Length));
         Fresh : constant String :=
           Unbounded.To_String (Value.Prefix)
           & Count (Count'First + 1 .. Count'Last);
      begin
         Value.Issued.Insert (Label, Fresh);
         Value.Order.Append (Label);
         return Fresh;
      end;
   end Issue;

   ----------------------------------------------------------------------
   --  Relabelling
   ----------------------------------------------------------------------

   --  Rebuild a term with each blank node label replaced. Triple terms are
   --  descended into: a blank node inside a quoted triple is still a blank
   --  node of the dataset and has to be relabelled with the rest.
   function Relabel_Term
     (Value   : Terms.Term;
      Mapping : String_Maps.Map) return Terms.Term is
   begin
      case Terms.Kind (Value) is
         when Terms.Blank_Node_Kind =>
            declare
               Label : constant String := Terms.Label (Value);
            begin
               if Mapping.Contains (Label) then
                  return Terms.Blank_Node (Mapping.Element (Label));
               end if;
               return Value;
            end;
         when Terms.Triple_Term_Kind =>
            return Terms.Triple_Term
              (Relabel_Term (Terms.Triple_Subject (Value), Mapping),
               Terms.Triple_Predicate (Value),
               Relabel_Term (Terms.Triple_Object (Value), Mapping));
         when others =>
            return Value;
      end case;
   end Relabel_Term;

   function Relabel_Quad
     (Value   : Quads.Quad;
      Mapping : String_Maps.Map) return Quads.Quad
   is
      Graph : constant Quads.Graph_Name := Quads.Graph (Value);
   begin
      return Quads.Create
        (Graph     =>
           (if Quads.Kind (Graph) = Quads.Blank_Node_Graph_Kind
            then Quads.Blank_Node_Graph
                   (Relabel_Term (Quads.Name_Term (Graph), Mapping))
            else Graph),
         Subject   => Relabel_Term (Quads.Subject (Value), Mapping),
         Predicate => Quads.Predicate (Value),
         Object    => Relabel_Term (Quads.Object (Value), Mapping));
   end Relabel_Quad;

   --  Every blank node label a term mentions, including inside quoted
   --  triples.
   procedure Collect_Labels
     (Value : Terms.Term;
      Into  : in out String_Sets.Set) is
   begin
      case Terms.Kind (Value) is
         when Terms.Blank_Node_Kind =>
            Into.Include (Terms.Label (Value));
         when Terms.Triple_Term_Kind =>
            Collect_Labels (Terms.Triple_Subject (Value), Into);
            Collect_Labels (Terms.Triple_Object (Value), Into);
         when others =>
            null;
      end case;
   end Collect_Labels;

   procedure Collect_Labels
     (Value : Quads.Quad;
      Into  : in out String_Sets.Set)
   is
      Graph : constant Quads.Graph_Name := Quads.Graph (Value);
   begin
      Collect_Labels (Quads.Subject (Value), Into);
      Collect_Labels (Quads.Object (Value), Into);
      if Quads.Kind (Graph) = Quads.Blank_Node_Graph_Kind then
         Collect_Labels (Quads.Name_Term (Graph), Into);
      end if;
   end Collect_Labels;

   ----------------------------------------------------------------------
   --  Permutations
   ----------------------------------------------------------------------

   --  Advance to the next permutation in lexicographic order, returning
   --  False once the sequence is exhausted.
   function Next_Permutation
     (Value : in out String_Vectors.Vector) return Boolean
   is
      Last  : constant Natural := Natural (Value.Length);
      Pivot : Natural := 0;
   begin
      if Last < 2 then
         return False;
      end if;

      for Index in reverse 1 .. Last - 1 loop
         if Value (Index) < Value (Index + 1) then
            Pivot := Index;
            exit;
         end if;
      end loop;

      if Pivot = 0 then
         return False;
      end if;

      declare
         Successor : Natural := Pivot + 1;
      begin
         for Index in Pivot + 1 .. Last loop
            if Value (Index) > Value (Pivot) then
               Successor := Index;
            end if;
         end loop;
         declare
            Swap : constant String := Value (Pivot);
         begin
            Value.Replace_Element (Pivot, Value (Successor));
            Value.Replace_Element (Successor, Swap);
         end;
      end;

      --  Reverse the tail, which is descending by construction.
      declare
         Low  : Natural := Pivot + 1;
         High : Natural := Last;
      begin
         while Low < High loop
            declare
               Swap : constant String := Value (Low);
            begin
               Value.Replace_Element (Low, Value (High));
               Value.Replace_Element (High, Swap);
            end;
            Low := Low + 1;
            High := High - 1;
         end loop;
      end;
      return True;
   end Next_Permutation;

   ----------------------------------------------------------------------
   --  The algorithm
   ----------------------------------------------------------------------

   procedure Canonicalize
     (Value        : Datasets.Dataset;
      Output       : out Unbounded.Unbounded_String;
      Status       : out Result_Status;
      Maximum_Work : Positive := Default_Maximum_Work)
   is
      All_Quads   : Quad_Vectors.Vector;
      Blank_Quads : Quad_Lists.Map;
      Blanks      : String_Sets.Set;
      Canonical   : Issuer := New_Issuer ("c14n");
      Work        : Natural := 0;

      procedure Spend (Amount : Positive := 1);

      procedure Spend (Amount : Positive := 1) is
      begin
         Work := Work + Amount;
         if Work > Maximum_Work then
            raise Exhausted;
         end if;
      end Spend;

      procedure Note (Statement : Quads.Quad);

      procedure Note (Statement : Quads.Quad) is
         Mentioned : String_Sets.Set;
      begin
         All_Quads.Append (Statement);
         Collect_Labels (Statement, Mentioned);
         for Label of Mentioned loop
            Blanks.Include (Label);
            if not Blank_Quads.Contains (Label) then
               Blank_Quads.Insert (Label, Quad_Vectors.Empty_Vector);
            end if;
            declare
               Bucket : Quad_Vectors.Vector := Blank_Quads.Element (Label);
            begin
               Bucket.Append (Statement);
               Blank_Quads.Replace (Label, Bucket);
            end;
         end loop;
      end Note;

      --  RDFC-1.0 section 4.6. Every blank node other than the one being
      --  hashed becomes the same placeholder, so the result describes the
      --  node's immediate surroundings without depending on what anything
      --  was called.
      function Hash_First_Degree (Label : String) return String;

      function Hash_First_Degree (Label : String) return String is
         Lines  : String_Vectors.Vector;
         Sorted : String_Sets.Set;
         Buffer : Unbounded.Unbounded_String;

         function Placeholder (Value : Terms.Term) return Terms.Term;

         function Placeholder (Value : Terms.Term) return Terms.Term is
         begin
            case Terms.Kind (Value) is
               when Terms.Blank_Node_Kind =>
                  return Terms.Blank_Node
                    (if Terms.Label (Value) = Label then "a" else "z");
               when Terms.Triple_Term_Kind =>
                  return Terms.Triple_Term
                    (Placeholder (Terms.Triple_Subject (Value)),
                     Terms.Triple_Predicate (Value),
                     Placeholder (Terms.Triple_Object (Value)));
               when others =>
                  return Value;
            end case;
         end Placeholder;

      begin
         Spend;
         if not Blank_Quads.Contains (Label) then
            return Digests.SHA_256 ("");
         end if;

         for Statement of Blank_Quads.Element (Label) loop
            declare
               Graph : constant Quads.Graph_Name := Quads.Graph (Statement);
               Copy  : constant Quads.Quad :=
                 Quads.Create
                   (Graph     =>
                      (if Quads.Kind (Graph) = Quads.Blank_Node_Graph_Kind
                       then Quads.Blank_Node_Graph
                              (Placeholder (Quads.Name_Term (Graph)))
                       else Graph),
                    Subject   => Placeholder (Quads.Subject (Statement)),
                    Predicate => Quads.Predicate (Statement),
                    Object    => Placeholder (Quads.Object (Statement)));
            begin
               --  Duplicates are kept: a node related to the same shape
               --  twice is not the same as one related to it once.
               Lines.Append
                 (Writers.Write_Quad (Copy, Writers.Implicit_Datatype)
                  & ASCII.LF);
            end;
         end loop;

         --  A set would collapse duplicates, so sort a copy instead.
         declare
            Ordered : String_Vectors.Vector := Lines;
         begin
            --  Insertion sort: these lists are short, and this keeps the
            --  dependency surface at zero.
            for Index in 2 .. Natural (Ordered.Length) loop
               declare
                  Item  : constant String := Ordered (Index);
                  Place : Natural := Index - 1;
               begin
                  while Place >= 1 and then Ordered (Place) > Item loop
                     Ordered.Replace_Element (Place + 1, Ordered (Place));
                     Place := Place - 1;
                  end loop;
                  Ordered.Replace_Element (Place + 1, Item);
               end;
            end loop;

            for Line of Ordered loop
               Unbounded.Append (Buffer, Line);
            end loop;
         end;
         pragma Unreferenced (Sorted);

         return Digests.SHA_256 (Unbounded.To_String (Buffer));
      end Hash_First_Degree;

      function Hash_N_Degree
        (Label  : String;
         Temp   : in out Issuer) return String;

      --  RDFC-1.0 section 4.7.
      function Hash_Related
        (Related   : String;
         Statement : Quads.Quad;
         Temp      : Issuer;
         Position  : Character) return String
      is
         Buffer : Unbounded.Unbounded_String;
      begin
         Spend;
         Unbounded.Append (Buffer, (1 => Position));
         if Position /= 'g' then
            Unbounded.Append
              (Buffer,
               "<" & IRIs.To_UTF_8 (Quads.Predicate (Statement)) & ">");
         end if;

         if Has_Issued (Canonical, Related) then
            Unbounded.Append (Buffer, "_:" & Issued_For (Canonical, Related));
         elsif Has_Issued (Temp, Related) then
            Unbounded.Append (Buffer, "_:" & Issued_For (Temp, Related));
         else
            Unbounded.Append (Buffer, Hash_First_Degree (Related));
         end if;

         return Digests.SHA_256 (Unbounded.To_String (Buffer));
      end Hash_Related;

      --  RDFC-1.0 section 4.8. This is where the cost lives: when several
      --  related nodes hash alike, every ordering of them has to be tried.
      function Hash_N_Degree
        (Label  : String;
         Temp   : in out Issuer) return String
      is
         Groups : Group_Maps.Map;
         Buffer : Unbounded.Unbounded_String;

         procedure Add_Related
           (Value     : Terms.Term;
            Statement : Quads.Quad;
            Position  : Character);

         procedure Add_Related
           (Value     : Terms.Term;
            Statement : Quads.Quad;
            Position  : Character) is
         begin
            case Terms.Kind (Value) is
               when Terms.Blank_Node_Kind =>
                  if Terms.Label (Value) /= Label then
                     declare
                        Key : constant String :=
                          Hash_Related (Terms.Label (Value), Statement,
                                        Temp, Position);
                     begin
                        if not Groups.Contains (Key) then
                           Groups.Insert (Key, String_Vectors.Empty_Vector);
                        end if;
                        declare
                           Bucket : String_Vectors.Vector :=
                             Groups.Element (Key);
                        begin
                           Bucket.Append (Terms.Label (Value));
                           Groups.Replace (Key, Bucket);
                        end;
                     end;
                  end if;
               when Terms.Triple_Term_Kind =>
                  Add_Related (Terms.Triple_Subject (Value), Statement,
                               Position);
                  Add_Related (Terms.Triple_Object (Value), Statement,
                               Position);
               when others =>
                  null;
            end case;
         end Add_Related;

      begin
         Spend;

         if Blank_Quads.Contains (Label) then
            for Statement of Blank_Quads.Element (Label) loop
               Add_Related (Quads.Subject (Statement), Statement, 's');
               Add_Related (Quads.Object (Statement), Statement, 'o');
               declare
                  Graph : constant Quads.Graph_Name :=
                    Quads.Graph (Statement);
               begin
                  if Quads.Kind (Graph) = Quads.Blank_Node_Graph_Kind then
                     Add_Related (Quads.Name_Term (Graph), Statement, 'g');
                  end if;
               end;
            end loop;
         end if;

         for Position in Groups.Iterate loop
            declare
               Related_Hash : constant String := Group_Maps.Key (Position);
               Members      : String_Vectors.Vector :=
                 Group_Maps.Element (Position);
               Chosen_Path  : Unbounded.Unbounded_String;
               Chosen       : Issuer := Temp;
               Have_Chosen  : Boolean := False;
            begin
               Unbounded.Append (Buffer, Related_Hash);

               --  Permutations are generated in lexicographic order, so
               --  start from the sorted arrangement.
               declare
                  Ordered : String_Vectors.Vector := Members;
               begin
                  for Index in 2 .. Natural (Ordered.Length) loop
                     declare
                        Item  : constant String := Ordered (Index);
                        Place : Natural := Index - 1;
                     begin
                        while Place >= 1
                          and then Ordered (Place) > Item
                        loop
                           Ordered.Replace_Element
                             (Place + 1, Ordered (Place));
                           Place := Place - 1;
                        end loop;
                        Ordered.Replace_Element (Place + 1, Item);
                     end;
                  end loop;
                  Members := Ordered;
               end;

               loop
                  Spend;
                  declare
                     Working   : Issuer := Temp;
                     Path      : Unbounded.Unbounded_String;
                     Recurse   : String_Vectors.Vector;
                     Abandoned : Boolean := False;
                  begin
                     for Related of Members loop
                        if Has_Issued (Canonical, Related) then
                           Unbounded.Append
                             (Path,
                              "_:" & Issued_For (Canonical, Related));
                        else
                           if not Has_Issued (Working, Related) then
                              Recurse.Append (Related);
                           end if;
                           Unbounded.Append
                             (Path, "_:" & Issue (Working, Related));
                        end if;

                        --  A path already worse than the best one cannot
                        --  become better, so stop extending it.
                        if Have_Chosen
                          and then Unbounded.Length (Path)
                                   >= Unbounded.Length (Chosen_Path)
                          and then Path > Chosen_Path
                        then
                           Abandoned := True;
                           exit;
                        end if;
                     end loop;

                     if not Abandoned then
                        for Related of Recurse loop
                           declare
                              Result : constant String :=
                                Hash_N_Degree (Related, Working);
                           begin
                              Unbounded.Append
                                (Path, "_:" & Issue (Working, Related));
                              Unbounded.Append (Path, "<" & Result & ">");
                           end;

                           if Have_Chosen
                             and then Unbounded.Length (Path)
                                      >= Unbounded.Length (Chosen_Path)
                             and then Path > Chosen_Path
                           then
                              Abandoned := True;
                              exit;
                           end if;
                        end loop;
                     end if;

                     if not Abandoned
                       and then (not Have_Chosen or else Path < Chosen_Path)
                     then
                        Chosen_Path := Path;
                        Chosen := Working;
                        Have_Chosen := True;
                     end if;
                  end;

                  exit when not Next_Permutation (Members);
               end loop;

               Unbounded.Append (Buffer, Unbounded.To_String (Chosen_Path));
               Temp := Chosen;
            end;
         end loop;

         return Digests.SHA_256 (Unbounded.To_String (Buffer));
      end Hash_N_Degree;

      Non_Normalized : String_Sets.Set;

   begin
      Output := Unbounded.Null_Unbounded_String;
      Status := Canonicalized;

      Datasets.Iterate (Value, Note'Access);
      Non_Normalized := Blanks;

      --  Section 4.4.3 steps 4 and 5: repeatedly issue canonical labels to
      --  every node whose first-degree hash is unique, since a unique hash
      --  fixes that node without reference to any other.
      loop
         declare
            Groups  : Group_Maps.Map;
            Changed : Boolean := False;
         begin
            for Label of Non_Normalized loop
               declare
                  Key : constant String := Hash_First_Degree (Label);
               begin
                  if not Groups.Contains (Key) then
                     Groups.Insert (Key, String_Vectors.Empty_Vector);
                  end if;
                  declare
                     Bucket : String_Vectors.Vector := Groups.Element (Key);
                  begin
                     Bucket.Append (Label);
                     Groups.Replace (Key, Bucket);
                  end;
               end;
            end loop;

            for Position in Groups.Iterate loop
               declare
                  Members : constant String_Vectors.Vector :=
                    Group_Maps.Element (Position);
               begin
                  if Natural (Members.Length) = 1 then
                     declare
                        Ignored : constant String :=
                          Issue (Canonical, Members.First_Element);
                     begin
                        pragma Unreferenced (Ignored);
                     end;
                     Non_Normalized.Exclude (Members.First_Element);
                     Changed := True;
                  end if;
               end;
            end loop;

            exit when not Changed or else Non_Normalized.Is_Empty;
         end;
      end loop;

      --  Section 4.4.3 step 6: what remains is nodes that look alike from
      --  their immediate surroundings, and have to be told apart by looking
      --  further out.
      declare
         Groups : Group_Maps.Map;
      begin
         for Label of Non_Normalized loop
            declare
               Key : constant String := Hash_First_Degree (Label);
            begin
               if not Groups.Contains (Key) then
                  Groups.Insert (Key, String_Vectors.Empty_Vector);
               end if;
               declare
                  Bucket : String_Vectors.Vector := Groups.Element (Key);
               begin
                  Bucket.Append (Label);
                  Groups.Replace (Key, Bucket);
               end;
            end;
         end loop;

         for Position in Groups.Iterate loop
            declare
               Members : constant String_Vectors.Vector :=
                 Group_Maps.Element (Position);
               Results : Group_Maps.Map;
            begin
               for Label of Members loop
                  if not Has_Issued (Canonical, Label) then
                     declare
                        Temp : Issuer := New_Issuer ("b");
                        Root : constant String := Issue (Temp, Label);
                        Key  : String_Vectors.Vector;
                     begin
                        pragma Unreferenced (Root);
                        declare
                           Digest : constant String :=
                             Hash_N_Degree (Label, Temp);
                        begin
                           --  Order the results by hash, then replay each
                           --  temporary issuer's order into the canonical
                           --  one.
                           Key := Temp.Order;
                           if not Results.Contains (Digest) then
                              Results.Insert (Digest, Key);
                           else
                              declare
                                 Existing : String_Vectors.Vector :=
                                   Results.Element (Digest);
                              begin
                                 for Item of Key loop
                                    Existing.Append (Item);
                                 end loop;
                                 Results.Replace (Digest, Existing);
                              end;
                           end if;
                        end;
                     end;
                  end if;
               end loop;

               for Result_Position in Results.Iterate loop
                  for Label of Group_Maps.Element (Result_Position) loop
                     declare
                        Ignored : constant String :=
                          Issue (Canonical, Label);
                     begin
                        pragma Unreferenced (Ignored);
                     end;
                  end loop;
               end loop;
            end;
         end loop;
      end;

      --  Emit: relabel every statement and sort the serializations.
      declare
         Mapping : String_Maps.Map;
         Lines   : String_Sets.Set;
      begin
         for Label of Blanks loop
            if Has_Issued (Canonical, Label) then
               Mapping.Insert (Label, Issued_For (Canonical, Label));
            end if;
         end loop;

         for Statement of All_Quads loop
            Lines.Include
              (Writers.Write_Quad
                 (Relabel_Quad (Statement, Mapping),
                  Writers.Implicit_Datatype));
         end loop;

         for Line of Lines loop
            Unbounded.Append (Output, Line);
            Unbounded.Append (Output, ASCII.LF);
         end loop;
      end;

   exception
      when Exhausted =>
         Output := Unbounded.Null_Unbounded_String;
         Status := Work_Limit_Reached;
   end Canonicalize;

   function To_Canonical_NQuads
     (Value        : Datasets.Dataset;
      Maximum_Work : Positive := Default_Maximum_Work) return String
   is
      Output : Unbounded.Unbounded_String;
      Status : Result_Status;
   begin
      Canonicalize (Value, Output, Status, Maximum_Work);
      if Status = Work_Limit_Reached then
         raise Work_Limit_Error with
           "canonicalization exceeded its work bound";
      end if;
      return Unbounded.To_String (Output);
   end To_Canonical_NQuads;

   function Is_Isomorphic
     (Left, Right  : Datasets.Dataset;
      Maximum_Work : Positive := Default_Maximum_Work) return Boolean
   is (To_Canonical_NQuads (Left, Maximum_Work)
       = To_Canonical_NQuads (Right, Maximum_Work));

end Flyology_RDF.Canonicalization;
