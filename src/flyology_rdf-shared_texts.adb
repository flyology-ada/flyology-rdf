with Ada.Unchecked_Deallocation;
with System.Atomic_Counters;

package body Flyology_RDF.Shared_Texts is

   procedure Free is new Ada.Unchecked_Deallocation
     (Object => Shared_Text, Name => Shared_Text_Access);

   function Empty return Text is
     (Ada.Finalization.Controlled with Payload => null);

   function To_Text (Value : String) return Text is
   begin
      if Value'Length = 0 then
         return Empty;
      end if;

      --  The count and the characters are one block, so holding text
      --  costs one allocation rather than a cell pointing at a string.
      return Result : Text do
         Result.Payload :=
           new Shared_Text'
             (Length     => Value'Length,
              References => <>,
              Data       => Value);
      end return;
   end To_Text;

   function To_String (Value : Text) return String is
     (if Value.Payload = null then "" else Value.Payload.Data);

   function Length (Value : Text) return Natural is
     (if Value.Payload = null then 0 else Value.Payload.Length);

   procedure Query
     (Value   : Text;
      Process : not null access procedure (Item : String)) is
   begin
      if Value.Payload = null then
         Process ("");
      else
         Process (Value.Payload.Data);
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
      return Left.Payload.Data = Right.Payload.Data;
   end "=";

   overriding procedure Adjust (Value : in out Text) is
   begin
      if Value.Payload /= null then
         System.Atomic_Counters.Increment (Value.Payload.References);
      end if;
   end Adjust;

   overriding procedure Finalize (Value : in out Text) is
      Doomed : Shared_Text_Access := Value.Payload;
   begin
      Value.Payload := null;
      if Doomed /= null
        and then System.Atomic_Counters.Decrement (Doomed.References)
      then
         Free (Doomed);
      end if;
   end Finalize;

end Flyology_RDF.Shared_Texts;
