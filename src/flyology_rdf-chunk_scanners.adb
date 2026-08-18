package body Flyology_RDF.Chunk_Scanners is

   package Cursors renames Flyology_RDF.Parser_Cursors;

   use type Lexers.Scan_Status;

   procedure Scan_Chunk
     (Text     : String;
      Ended    : Boolean;
      Dialect  : Lexers.Dialect_Kind;
      Limits   : Scan_Limits;
      State    : in out Scan_State;
      Tokens   : in out Token_Vectors.Vector;
      Consumed : out Natural;
      Outcome  : out Scan_Outcome;
      Stopped  : out Parser_Cursors.Cursor_State;
      Error    : out Lexers.Scan_Error_Kind)
   is
      Position : Cursors.Cursor_State := State.Origin;
      Index    : Positive := Text'First;
      Result   : Lexers.Token := Lexers.Null_Token;
      Status   : Lexers.Scan_Status;
      Why      : Lexers.Scan_Error_Kind;

      Consumed_Index    : Natural := Text'First;
      Consumed_Position : Cursors.Cursor_State := State.Origin;
   begin
      Outcome := Scanned;
      Error   := Lexers.No_Error;
      Stopped := Position;

      loop
         Lexers.Scan
           (Text, Position, Index, Ended, Result, Status, Why, Dialect);
         case Status is
            when Lexers.Token_Found =>
               if Lexers.Text (Result)'Length > Limits.Maximum_Token_Bytes
               then
                  Outcome := Token_Bytes_Limit;
                  Stopped := Position;
                  exit;
               end if;

               Tokens.Append (Result);
               Consumed_Index := Index;
               Consumed_Position := Position;

               if Limits.Maximum_Tokens /= 0
                 and then Natural (Tokens.Length) > Limits.Maximum_Tokens
               then
                  Outcome := Token_Limit;
                  Stopped := Position;
                  exit;
               end if;

            when Lexers.Needs_More_Input =>
               exit;

            when Lexers.End_Of_Input =>
               Consumed_Index := Index;
               Consumed_Position := Position;
               exit;

            when Lexers.Scan_Error =>
               Outcome := Malformed;
               Error   := Why;
               Stopped := Position;
               exit;
         end case;
      end loop;

      Consumed := Consumed_Index;
      State.Origin := Consumed_Position;

      if Outcome /= Scanned then
         return;
      end if;

      --  What is left is one token that has not finished. Bounding it here
      --  is what stops it being retained and rescanned from its first byte
      --  on every chunk, which costs time quadratic in the token's length
      --  and holds all of it in memory meanwhile.
      if Text'Last - Consumed_Index + 1 > Limits.Maximum_Token_Bytes then
         Outcome := Token_Bytes_Limit;
         Stopped := Consumed_Position;
      end if;
   end Scan_Chunk;

end Flyology_RDF.Chunk_Scanners;
