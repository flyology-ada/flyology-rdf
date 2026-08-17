with Ada.Strings.Unbounded;

package body Flyology_SPARQL.Writers is

   package Unbounded renames Ada.Strings.Unbounded;

   use type Syntax.Node_Kind;

   Quote : constant Character := Character'Val (34);
   use type Syntax.Node_Reference;

   function To_SPARQL (Value : Syntax.Query) return String is
      Buffer : Unbounded.Unbounded_String;

      procedure Put (Text : String) is
      begin
         Unbounded.Append (Buffer, Text);
      end Put;

      function Indent (Depth : Natural) return String
      is (if Depth = 0 then "" else [1 .. 2 * Depth => ' ']);

      function Render (Node : Syntax.Node_Reference) return String;

      function Children_From
        (Node      : Syntax.Node_Reference;
         First     : Positive;
         Separator : String) return String
      is
         Result : Unbounded.Unbounded_String;
      begin
         for Index in First .. Syntax.Child_Count (Value, Node) loop
            if Index > First then
               Unbounded.Append (Result, Separator);
            end if;
            Unbounded.Append
              (Result, Render (Syntax.Child (Value, Node, Index)));
         end loop;
         return Unbounded.To_String (Result);
      end Children_From;

      function Children_Of
        (Node      : Syntax.Node_Reference;
         Separator : String) return String
      is (Children_From (Node, 1, Separator));

      function Render (Node : Syntax.Node_Reference) return String is
      begin
         if Node = Syntax.No_Node then
            return "";
         end if;

         case Syntax.Kind (Value, Node) is
            when Syntax.IRI_Node =>
               return "<" & Syntax.Text (Value, Node) & ">";

            when Syntax.Prefixed_Node =>
               return Syntax.Detail (Value, Node) & ":"
                 & Syntax.Text (Value, Node);

            when Syntax.Blank_Node =>
               return "_:" & Syntax.Text (Value, Node);

            when Syntax.Variable_Node =>
               --  "*" reaches here from COUNT(*) and SELECT *, where it is
               --  not a variable name.
               if Syntax.Text (Value, Node) = "*" then
                  return "*";
               end if;
               return "?" & Syntax.Text (Value, Node);

            when Syntax.A_Node =>
               return "a";

            when Syntax.Literal_Node =>
               declare
                  Detail : constant String := Syntax.Detail (Value, Node);
               begin
                  if Detail = "^^" then
                     return """" & Syntax.Text (Value, Node) & """^^"
                       & Render (Syntax.Child (Value, Node, 1));
                  elsif Detail'Length > 1 and then Detail (Detail'First) = '@'
                  then
                     return """" & Syntax.Text (Value, Node) & """" & Detail;
                  elsif Detail'Length > 0 then
                     --  A numeric or boolean literal is written as it was.
                     return Syntax.Text (Value, Node);
                  end if;
                  return """" & Syntax.Text (Value, Node) & """";
               end;

            when Syntax.Or_Node | Syntax.And_Node | Syntax.Compare_Node
               | Syntax.Arithmetic_Node =>
               return "(" & Render (Syntax.Child (Value, Node, 1)) & " "
                 & Syntax.Text (Value, Node) & " "
                 & Render (Syntax.Child (Value, Node, 2)) & ")";

            when Syntax.Unary_Node =>
               --  Expression operators are written before their operand
               --  and path cardinality after it, so the two cannot share
               --  one rendering.
               if Syntax.Detail (Value, Node) = "postfix" then
                  return Render (Syntax.Child (Value, Node, 1))
                    & Syntax.Text (Value, Node);
               end if;
               return Syntax.Text (Value, Node)
                 & Render (Syntax.Child (Value, Node, 1));

            when Syntax.In_Node =>
               --  The first child is the tested expression; the rest are
               --  the list it is tested against.
               return Render (Syntax.Child (Value, Node, 1)) & " "
                 & Syntax.Text (Value, Node) & " ("
                 & Children_From (Node, 2, ", ") & ")";

            when Syntax.Call_Node =>
               if Syntax.Text (Value, Node) = "" then
                  --  A function call: the first child names the function.
                  return Render (Syntax.Child (Value, Node, 1)) & "("
                    & Children_From (Node, 2, ", ") & ")";
               end if;
               if Syntax.Child_Count (Value, Node) = 0 then
                  return Syntax.Text (Value, Node);
               end if;
               return Syntax.Text (Value, Node) & "("
                 & Children_Of (Node, ", ") & ")";

            when Syntax.Order_Term_Node =>
               if Syntax.Text (Value, Node) = "" then
                  return Render (Syntax.Child (Value, Node, 1));
               end if;
               return Syntax.Text (Value, Node) & "("
                 & Render (Syntax.Child (Value, Node, 1)) & ")";

            when Syntax.Triple_Term_Node =>
               return "<<( " & Render (Syntax.Child (Value, Node, 1)) & " "
                 & Render (Syntax.Child (Value, Node, 2)) & " "
                 & Render (Syntax.Child (Value, Node, 3)) & " )>>";

            when Syntax.Reified_Node =>
               --  An annotation marker renders as its reifier; the triple
               --  it annotates was already written on its own line.
               if Syntax.Text (Value, Node) = "annotation" then
                  return Render (Syntax.Child (Value, Node, 2));
               end if;
               return "<< " & Render (Syntax.Child (Value, Node, 1)) & " "
                 & Render (Syntax.Child (Value, Node, 2)) & " "
                 & Render (Syntax.Child (Value, Node, 3))
                 & (if Syntax.Child_Count (Value, Node) > 3
                    then " ~" & Render (Syntax.Child (Value, Node, 4))
                    else "")
                 & " >>";

            when Syntax.Dataset_Node =>
               if Syntax.Text (Value, Node) = "" then
                  return Children_Of (Node, " ");
               end if;
               return Syntax.Text (Value, Node) & " "
                 & Render (Syntax.Child (Value, Node, 1));

            when Syntax.Exists_Node =>
               return Syntax.Text (Value, Node) & " { }";

            when Syntax.Projection_Node =>
               if Syntax.Text (Value, Node) = "AS" then
                  return "(" & Render (Syntax.Child (Value, Node, 1))
                    & " AS " & Render (Syntax.Child (Value, Node, 2)) & ")";
               end if;
               return Children_Of (Node, " ");

            when others =>
               return "";
         end case;
      end Render;

      procedure Write_Pattern (Node : Syntax.Node_Reference; Depth : Natural);

      procedure Write_Group (Node : Syntax.Node_Reference; Depth : Natural) is
      begin
         Put ("{" & (1 => ASCII.LF));
         for Index in 1 .. Syntax.Child_Count (Value, Node) loop
            Write_Pattern (Syntax.Child (Value, Node, Index), Depth + 1);
         end loop;
         Put (Indent (Depth) & "}");
      end Write_Group;

      procedure Write_Pattern
        (Node : Syntax.Node_Reference; Depth : Natural) is
      begin
         case Syntax.Kind (Value, Node) is
            when Syntax.Triple_Node =>
               Put (Indent (Depth)
                    & Render (Syntax.Child (Value, Node, 1)) & " "
                    & Render (Syntax.Child (Value, Node, 2)) & " "
                    & Render (Syntax.Child (Value, Node, 3)) & " ."
                    & (1 => ASCII.LF));

            when Syntax.Group_Node =>
               Put (Indent (Depth));
               Write_Group (Node, Depth);
               Put ((1 => ASCII.LF));

            when Syntax.Optional_Node =>
               Put (Indent (Depth) & "OPTIONAL ");
               Write_Group (Syntax.Child (Value, Node, 1), Depth);
               Put ((1 => ASCII.LF));

            when Syntax.Minus_Node =>
               Put (Indent (Depth) & "MINUS ");
               Write_Group (Syntax.Child (Value, Node, 1), Depth);
               Put ((1 => ASCII.LF));

            when Syntax.Graph_Node | Syntax.Service_Node =>
               Put (Indent (Depth)
                    & (if Syntax.Kind (Value, Node) = Syntax.Graph_Node
                       then "GRAPH " else "SERVICE ")
                    & Render (Syntax.Child (Value, Node, 1)) & " ");
               Write_Group (Syntax.Child (Value, Node, 2), Depth);
               Put ((1 => ASCII.LF));

            when Syntax.Union_Node =>
               Put (Indent (Depth));
               Write_Group (Syntax.Child (Value, Node, 1), Depth);
               Put (" UNION ");
               Write_Group (Syntax.Child (Value, Node, 2), Depth);
               Put ((1 => ASCII.LF));

            when Syntax.Filter_Node =>
               Put (Indent (Depth) & "FILTER "
                    & Render (Syntax.Child (Value, Node, 1)) & (1 => ASCII.LF));

            when Syntax.Reified_Node =>
               Put (Indent (Depth) & Render (Node) & " ." & (1 => ASCII.LF));

            when Syntax.Values_Node =>
               Put (Indent (Depth) & "VALUES ("
                    & Render (Syntax.Child (Value, Node, 1)) & ") {"
                    & (1 => ASCII.LF));
               for Index in 2 .. Syntax.Child_Count (Value, Node) loop
                  Put (Indent (Depth + 1) & "("
                       & Render (Syntax.Child (Value, Node, Index)) & ")"
                       & (1 => ASCII.LF));
               end loop;
               Put (Indent (Depth) & "}" & (1 => ASCII.LF));

            when Syntax.Triple_Term_Node =>
               Put (Indent (Depth) & Render (Node) & " ." & (1 => ASCII.LF));

            when Syntax.Subquery_Node =>
               Put (Indent (Depth) & "{" & (1 => ASCII.LF));
               Put (Indent (Depth + 1) & "SELECT");
               for Index in 1 .. Syntax.Child_Count (Value, Node) loop
                  declare
                     Item : constant Syntax.Node_Reference :=
                       Syntax.Child (Value, Node, Index);
                  begin
                     case Syntax.Kind (Value, Item) is
                        when Syntax.Projection_Node =>
                           Put (" " & Render (Item));
                        when Syntax.Group_Node =>
                           Put ((1 => ASCII.LF) & Indent (Depth + 1)
                                & "WHERE ");
                           Write_Group (Item, Depth + 1);
                           Put ((1 => ASCII.LF));
                        when Syntax.Call_Node =>
                           if Syntax.Child_Count (Value, Item) = 0 then
                              Put (" " & Syntax.Text (Value, Item));
                           else
                              Put (Indent (Depth + 1)
                                   & Syntax.Text (Value, Item)
                                   & (if Syntax.Text (Value, Item)
                                           in "GROUP" | "ORDER"
                                      then " BY " else " ")
                                   & Render (Syntax.Child (Value, Item, 1))
                                   & (1 => ASCII.LF));
                           end if;
                        when others =>
                           null;
                     end case;
                  end;
               end loop;
               Put (Indent (Depth) & "}" & (1 => ASCII.LF));

            when Syntax.Bind_Node =>
               Put (Indent (Depth) & "BIND ("
                    & Render (Syntax.Child (Value, Node, 1)) & " AS "
                    & Render (Syntax.Child (Value, Node, 2)) & ")"
                    & (1 => ASCII.LF));

            when others =>
               null;
         end case;
      end Write_Pattern;

   begin
      if Syntax.Version (Value) /= "" then
         Put ("VERSION " & Quote & Syntax.Version (Value)
              & Quote & (1 => ASCII.LF));
      end if;
      if Syntax.Base (Value) /= "" then
         Put ("BASE <" & Syntax.Base (Value) & ">" & (1 => ASCII.LF));
      end if;
      for Index in 1 .. Syntax.Prefix_Count (Value) loop
         Put ("PREFIX " & Syntax.Prefix_Name (Value, Index) & ": <"
              & Syntax.Prefix_Namespace (Value, Index) & ">" & (1 => ASCII.LF));
      end loop;

      case Syntax.Form (Value) is
         when Syntax.Select_Query =>
            Put ("SELECT");
            case Syntax.Duplicates (Value) is
               when Syntax.Distinct_Solutions => Put (" DISTINCT");
               when Syntax.Reduced_Solutions  => Put (" REDUCED");
               when Syntax.All_Solutions      => null;
            end case;
            if Syntax.Selects_All (Value) then
               Put (" *");
            else
               Put (" " & Render (Syntax.Projection (Value)));
            end if;
            Put (ASCII.LF & "WHERE ");

         when Syntax.Ask_Query =>
            Put ("ASK ");

         when Syntax.Construct_Query =>
            Put ("CONSTRUCT ");
            Write_Group (Syntax.Template (Value), 0);
            Put (ASCII.LF & "WHERE ");

         when Syntax.Describe_Query =>
            Put ("DESCRIBE ");
            if Syntax.Selects_All (Value) then
               Put ("*");
            else
               Put (Render (Syntax.Describe_Targets (Value)));
            end if;
            Put ((1 => ASCII.LF));
            if Syntax.Where_Clause (Value) /= Syntax.No_Node then
               Put ("WHERE ");
            end if;
      end case;

      if Syntax.Dataset (Value) /= Syntax.No_Node then
         Put (Render (Syntax.Dataset (Value)) & (1 => ASCII.LF));
      end if;

      if Syntax.Where_Clause (Value) /= Syntax.No_Node then
         Write_Group (Syntax.Where_Clause (Value), 0);
         Put ((1 => ASCII.LF));
      end if;

      if Syntax.Group_By (Value) /= Syntax.No_Node then
         Put ("GROUP BY " & Render (Syntax.Group_By (Value)) & (1 => ASCII.LF));
      end if;
      if Syntax.Having (Value) /= Syntax.No_Node then
         Put ("HAVING " & Render (Syntax.Having (Value)) & (1 => ASCII.LF));
      end if;
      if Syntax.Order_By (Value) /= Syntax.No_Node then
         Put ("ORDER BY " & Render (Syntax.Order_By (Value)) & (1 => ASCII.LF));
      end if;
      if Syntax.Limit (Value) >= 0 then
         Put ("LIMIT" & Syntax.Limit (Value)'Image & (1 => ASCII.LF));
      end if;
      if Syntax.Offset (Value) >= 0 then
         Put ("OFFSET" & Syntax.Offset (Value)'Image & (1 => ASCII.LF));
      end if;

      return Unbounded.To_String (Buffer);
   end To_SPARQL;

end Flyology_SPARQL.Writers;
