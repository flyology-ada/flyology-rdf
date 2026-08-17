with Ada.Strings.Unbounded;

with Flyology_RDF.NQuads_Writers;

package body Flyology_RDF.Datasets is

   package Unbounded renames Ada.Strings.Unbounded;
   package Writers renames Flyology_RDF.NQuads_Writers;

   function Statement_Key (Value : Quads.Quad) return String
   is (Writers.Write_Quad (Value));

   function Graph_Key (Value : Quads.Graph_Name) return String
   is (Writers.Write_Graph_Name (Value));

   function Empty return Dataset is
      Result : Dataset;
   begin
      return Result;
   end Empty;

   procedure Insert
     (Into     : in out Dataset;
      Value    : Quads.Quad;
      Inserted : out Boolean)
   is
      Key : constant String := Statement_Key (Value);
   begin
      if Into.Statements.Contains (Key) then
         Inserted := False;
         return;
      end if;

      Into.Statements.Insert (Key, Value);
      Inserted := True;

      declare
         Graph : constant Quads.Graph_Name := Quads.Graph (Value);
         Name  : constant String := Graph_Key (Graph);
      begin
         if Into.Counts.Contains (Name) then
            Into.Counts.Replace (Name, Into.Counts.Element (Name) + 1);
         else
            Into.Counts.Insert (Name, 1);
            Into.Graphs.Insert (Name, Graph);
         end if;
      end;
   end Insert;

   procedure Insert (Into : in out Dataset; Value : Quads.Quad) is
      Ignored : Boolean;
   begin
      Insert (Into, Value, Ignored);
   end Insert;

   procedure Delete (From : in out Dataset; Value : Quads.Quad) is
      Key : constant String := Statement_Key (Value);
   begin
      if not From.Statements.Contains (Key) then
         return;
      end if;
      From.Statements.Delete (Key);

      declare
         Name      : constant String := Graph_Key (Quads.Graph (Value));
         Remaining : constant Natural := From.Counts.Element (Name) - 1;
      begin
         if Remaining = 0 then
            From.Counts.Delete (Name);
            From.Graphs.Delete (Name);
         else
            From.Counts.Replace (Name, Remaining);
         end if;
      end;
   end Delete;

   procedure Clear (Value : in out Dataset) is
   begin
      Value.Statements.Clear;
      Value.Graphs.Clear;
      Value.Counts.Clear;
   end Clear;

   function Contains
     (Value : Dataset; Statement : Quads.Quad) return Boolean
   is (Value.Statements.Contains (Statement_Key (Statement)));

   function Length (Value : Dataset) return Natural
   is (Natural (Value.Statements.Length));

   function Is_Empty (Value : Dataset) return Boolean
   is (Value.Statements.Is_Empty);

   procedure Iterate
     (Value   : Dataset;
      Process : not null access procedure (Statement : Quads.Quad)) is
   begin
      for Statement of Value.Statements loop
         Process (Statement);
      end loop;
   end Iterate;

   function Graph_Count (Value : Dataset) return Natural
   is (Natural (Value.Graphs.Length));

   procedure Iterate_Graphs
     (Value   : Dataset;
      Process : not null access procedure (Graph : Quads.Graph_Name)) is
   begin
      for Graph of Value.Graphs loop
         Process (Graph);
      end loop;
   end Iterate_Graphs;

   procedure Iterate_Graph
     (Value   : Dataset;
      Graph   : Quads.Graph_Name;
      Process : not null access procedure (Statement : Quads.Quad))
   is
      use type Quads.Graph_Name;
   begin
      for Statement of Value.Statements loop
         if Quads.Graph (Statement) = Graph then
            Process (Statement);
         end if;
      end loop;
   end Iterate_Graph;

   function To_NQuads (Value : Dataset) return String is
      Buffer : Unbounded.Unbounded_String;
   begin
      --  The map is keyed by the serialization, so the keys are the output.
      for Position in Value.Statements.Iterate loop
         Unbounded.Append (Buffer, Statement_Maps.Key (Position));
         Unbounded.Append (Buffer, ASCII.LF);
      end loop;
      return Unbounded.To_String (Buffer);
   end To_NQuads;

   overriding function "=" (Left, Right : Dataset) return Boolean is
      use type Statement_Maps.Map;
   begin
      --  Only the statement map participates: the graph map and the counts
      --  are derived from it, so comparing them would be redundant and,
      --  worse, would make equality depend on how a dataset was built.
      return Left.Statements = Right.Statements;
   end "=";

end Flyology_RDF.Datasets;
