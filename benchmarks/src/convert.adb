--  Turtle to N-Triples, streaming, for comparison against another
--  implementation doing the same job on the same file.
--
--  This is deliberately the whole job a consumer would ask for -- read a
--  file, parse it, write the lines out -- rather than a phase of it, so
--  that a number from here can be compared with one from a tool that
--  offers no way to measure a phase.

with Ada.Command_Line;
with Ada.Streams.Stream_IO;
with Ada.Text_IO;

with Flyology_RDF.NQuads_Writers;
with Flyology_RDF.Quads;
with Flyology_RDF.Turtle_Parsers;

procedure Convert is

   package IO renames Ada.Text_IO;
   package Stream_IO renames Ada.Streams.Stream_IO;
   package Parsers renames Flyology_RDF.Turtle_Parsers;
   package Quads renames Flyology_RDF.Quads;
   package Writers renames Flyology_RDF.NQuads_Writers;

   use type Parsers.Parse_Status;
   use type Ada.Streams.Stream_Element_Offset;

   Read_Chunk : constant := 64 * 1024;
   Out_Buffer : constant := 1024 * 1024;

   --  Writing a line at a time through Text_IO would measure Text_IO, so
   --  the lines are gathered and handed over a megabyte at a time.
   type Writer_Sink is limited new Parsers.Event_Sink with record
      File   : Stream_IO.File_Type;
      Buffer : String (1 .. Out_Buffer);
      Held   : Natural := 0;
      Lines  : Natural := 0;
   end record;

   procedure Flush (Target : in out Writer_Sink);

   overriding procedure On_Graph_Declaration
     (Target : in out Writer_Sink;
      Graph  : Quads.Graph_Name;
      Span   : Parsers.Source_Span) is null;

   overriding procedure On_Diagnostic
     (Target : in out Writer_Sink;
      Value  : Parsers.Parse_Diagnostic);

   overriding procedure On_Quad
     (Target : in out Writer_Sink;
      Value  : Quads.Quad;
      Span   : Parsers.Source_Span);

   procedure Flush (Target : in out Writer_Sink) is
   begin
      if Target.Held > 0 then
         String'Write
           (Stream_IO.Stream (Target.File),
            Target.Buffer (1 .. Target.Held));
         Target.Held := 0;
      end if;
   end Flush;

   overriding procedure On_Diagnostic
     (Target : in out Writer_Sink;
      Value  : Parsers.Parse_Diagnostic) is
   begin
      IO.Put_Line
        (IO.Standard_Error,
         "convert: " & Parsers.Diagnostic_Code'Image (Parsers.Code (Value)));
   end On_Diagnostic;

   overriding procedure On_Quad
     (Target : in out Writer_Sink;
      Value  : Quads.Quad;
      Span   : Parsers.Source_Span)
   is
      --  A statement can be long; keep a margin rather than guess.
      Margin : constant := 64 * 1024;
   begin
      if Target.Held + Margin > Target.Buffer'Length then
         Flush (Target);
      end if;
      Writers.Put_Quad
        (Value, Target.Buffer, Target.Held, Writers.Implicit_Datatype);
      Target.Held := Target.Held + 1;
      Target.Buffer (Target.Held) := ASCII.LF;
      Target.Lines := Target.Lines + 1;
   end On_Quad;

   Source : Stream_IO.File_Type;
   Sink   : Writer_Sink;
   --  The grammar follows the extension, so the same tool measures a
   --  Turtle document and a TriG one with named graphs.
   function Chosen_Syntax return Parsers.Syntax_Kind is
     (if Ada.Command_Line.Argument_Count >= 1
        and then Ada.Command_Line.Argument (1)'Length > 5
        and then Ada.Command_Line.Argument (1)
                   (Ada.Command_Line.Argument (1)'Last - 4
                    .. Ada.Command_Line.Argument (1)'Last) = ".trig"
      then Parsers.TriG_Syntax
      else Parsers.Turtle_Syntax);

   Parser : Parsers.Parser :=
     Parsers.Create (Source_Name => "input", Syntax => Chosen_Syntax);
   Status : Parsers.Parse_Status;

begin
   if Ada.Command_Line.Argument_Count < 2 then
      IO.Put_Line (IO.Standard_Error, "usage: convert <in.ttl> <out.nt>");
      Ada.Command_Line.Set_Exit_Status (2);
      return;
   end if;

   Stream_IO.Open
     (Source, Stream_IO.In_File, Ada.Command_Line.Argument (1));
   Stream_IO.Create
     (Sink.File, Stream_IO.Out_File, Ada.Command_Line.Argument (2));

   --  Read and feed a block at a time, which keeps the whole file out of
   --  memory: the case a chunk-fed parser exists for. The String is laid
   --  over the block rather than copied out of it, so what is measured is
   --  the parse and not a byte loop beside it.
   declare
      Block : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Read_Chunk));
      Last  : Ada.Streams.Stream_Element_Offset;
      Text  : String (1 .. Read_Chunk);
      for Text'Address use Block'Address;
      pragma Import (Ada, Text);
   begin
      loop
         Stream_IO.Read (Source, Block, Last);
         exit when Last < Block'First;
         Parsers.Feed (Parser, Text (1 .. Natural (Last)), Sink);
         exit when Last < Block'Last;
      end loop;
   end;

   Status := Parsers.Finish (Parser, Sink);
   Flush (Sink);
   Stream_IO.Close (Sink.File);
   Stream_IO.Close (Source);

   if Status /= Parsers.Parse_Succeeded then
      IO.Put_Line (IO.Standard_Error, "convert: parse failed");
      Ada.Command_Line.Set_Exit_Status (1);
   end if;
end Convert;
