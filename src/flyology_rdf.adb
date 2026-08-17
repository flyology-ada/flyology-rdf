with Ada.Unchecked_Deallocation;
with System.Atomic_Counters;

package body Flyology_RDF is

   package body Immutable_Holders is

      type Shared_Element is limited record
         References : System.Atomic_Counters.Atomic_Counter;
         Element    : Element_Access;
      end record;

      procedure Free_Element is new Ada.Unchecked_Deallocation
        (Object => Element_Type,
         Name   => Element_Access);

      procedure Free_Shared is new Ada.Unchecked_Deallocation
        (Object => Shared_Element,
         Name   => Shared_Element_Access);

      function To_Holder (Value : Element_Type) return Holder is
         Shared : Shared_Element_Access := new Shared_Element;
      begin
         --  The two allocations are sequenced rather than nested so that a
         --  Storage_Error on the second one cannot strand the first. A
         --  nested allocator would leak whichever half already succeeded.
         begin
            Shared.Element := new Element_Type'(Value);
         exception
            when others =>
               Free_Shared (Shared);
               raise;
         end;

         return Result : Holder do
            Result.Shared := Shared;
         end return;
      end To_Holder;

      function Element (Value : Holder) return Element_Type is
      begin
         if Value.Shared = null then
            raise Constraint_Error with "immutable holder is empty";
         end if;
         return Value.Shared.Element.all;
      end Element;

      procedure Query_Element
        (Value   : Holder;
         Process : not null access procedure (Element : Element_Type)) is
      begin
         if Value.Shared = null then
            raise Constraint_Error with "immutable holder is empty";
         end if;
         Process (Value.Shared.Element.all);
      end Query_Element;

      overriding function "=" (Left, Right : Holder) return Boolean is
      begin
         if Left.Shared = Right.Shared then
            return True;
         elsif Left.Shared = null or else Right.Shared = null then
            return False;
         else
            return Left.Shared.Element.all = Right.Shared.Element.all;
         end if;
      end "=";

      overriding procedure Adjust (Value : in out Holder) is
      begin
         if Value.Shared /= null then
            System.Atomic_Counters.Increment (Value.Shared.References);
         end if;
      end Adjust;

      overriding procedure Finalize (Value : in out Holder) is
         Shared : Shared_Element_Access := Value.Shared;
      begin
         --  Clearing first makes Finalize idempotent, which the language
         --  permits the runtime to rely on.
         Value.Shared := null;
         if Shared /= null
           and then System.Atomic_Counters.Decrement (Shared.References)
         then
            Free_Element (Shared.Element);
            Free_Shared (Shared);
         end if;
      end Finalize;

   end Immutable_Holders;

end Flyology_RDF;
