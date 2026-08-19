with Ada.Unchecked_Deallocation;
with System.Atomic_Counters;

package body Flyology_RDF.Shared_Texts is

   procedure Free is new Ada.Unchecked_Deallocation
     (Object => Shared_Text, Name => Shared_Text_Access);

   --  A document builds a great many short texts -- an IRI, a label, a
   --  lexical form -- and drops them again, so released blocks are kept
   --  and handed back out rather than returned to the allocator.
   --
   --  Blocks are held in a few capacity classes, because a block can serve
   --  any text that fits it. Anything longer than the largest class is
   --  allocated exactly and freed on release: those are rare, and holding
   --  one would tie up as much memory as all the small ones together.
   --
   --  The lists are per task. A shared one would need a lock, and the
   --  point of this is to be cheaper than the allocator it replaces; a
   --  block released by a task other than the one that took it joins that
   --  task's list, which is correct because a free block belongs to
   --  nobody. Each class is bounded so a burst of text does not hold
   --  memory for the life of the process.
   Class_Sizes  : constant array (1 .. 4) of Natural := [32, 64, 128, 256];
   Class_Limit  : constant := 128;

   type Class_Lists is array (Class_Sizes'Range) of Shared_Text_Access;
   type Class_Counts is array (Class_Sizes'Range) of Natural;

   Recycled       : Class_Lists := [others => null];
   Recycled_Count : Class_Counts := [others => 0];
   pragma Thread_Local_Storage (Recycled);
   pragma Thread_Local_Storage (Recycled_Count);

   --  Smallest class that holds Length characters, or zero for none.
   function Class_For (Length : Natural) return Natural;

   function Class_For (Length : Natural) return Natural is
   begin
      for Index in Class_Sizes'Range loop
         if Length <= Class_Sizes (Index) then
            return Index;
         end if;
      end loop;
      return 0;
   end Class_For;

   function Empty return Text is
     (Ada.Finalization.Controlled with Payload => null);

   function To_Text (Value : String) return Text is
      Class : constant Natural := Class_For (Value'Length);
      Block : Shared_Text_Access;
   begin
      if Value'Length = 0 then
         return Empty;
      end if;

      if Class /= 0 and then Recycled (Class) /= null then
         Block := Recycled (Class);
         Recycled (Class) := Block.Next_Free;
         Recycled_Count (Class) := Recycled_Count (Class) - 1;
         Block.Next_Free := null;
         System.Atomic_Counters.Initialize (Block.References);
      elsif Class /= 0 then
         Block := new Shared_Text (Capacity => Class_Sizes (Class));
      else
         Block := new Shared_Text (Capacity => Value'Length);
      end if;

      Block.Length := Value'Length;
      Block.Data (1 .. Value'Length) := Value;

      return Result : Text do
         Result.Payload := Block;
      end return;
   end To_Text;

   function To_String (Value : Text) return String is
     (if Value.Payload = null then ""
      else Value.Payload.Data (1 .. Value.Payload.Length));

   function Length (Value : Text) return Natural is
     (if Value.Payload = null then 0 else Value.Payload.Length);

   procedure Query
     (Value   : Text;
      Process : not null access procedure (Item : String)) is
   begin
      if Value.Payload = null then
         Process ("");
      else
         Process (Value.Payload.Data (1 .. Value.Payload.Length));
      end if;
   end Query;

   function "=" (Left, Right : Text) return Boolean is
   begin
      --  Sharing a block is the common case once a document repeats an
      --  IRI, and it answers without looking at the characters.
      if Left.Payload = Right.Payload then
         return True;
      elsif Left.Payload = null or else Right.Payload = null then
         return False;
      end if;
      return Left.Payload.Data (1 .. Left.Payload.Length)
             = Right.Payload.Data (1 .. Right.Payload.Length);
   end "=";

   overriding procedure Adjust (Value : in out Text) is
   begin
      if Value.Payload /= null then
         System.Atomic_Counters.Increment (Value.Payload.References);
      end if;
   end Adjust;

   overriding procedure Finalize (Value : in out Text) is
      Doomed : Shared_Text_Access := Value.Payload;
      Class  : Natural;
   begin
      Value.Payload := null;
      if Doomed = null
        or else not System.Atomic_Counters.Decrement (Doomed.References)
      then
         return;
      end if;

      Class := Class_For (Doomed.Capacity);
      if Class /= 0
        and then Class_Sizes (Class) = Doomed.Capacity
        and then Recycled_Count (Class) < Class_Limit
      then
         Doomed.Length := 0;
         Doomed.Next_Free := Recycled (Class);
         Recycled (Class) := Doomed;
         Recycled_Count (Class) := Recycled_Count (Class) + 1;
      else
         Free (Doomed);
      end if;
   end Finalize;

end Flyology_RDF.Shared_Texts;
