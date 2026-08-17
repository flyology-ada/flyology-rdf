with Ada.Finalization;

--  Root of the RDF 1.2 model.
--
--  The crate has no runtime dependency and creates no tasks. Every public
--  type below this root is immutable and indefinite, so a partially built
--  value is not representable.
package Flyology_RDF is

private

   --  Immutable shared ownership for private representation components.
   --
   --  Querying does not mutate a tampering counter, so concurrent readers may
   --  borrow the same value while its owner remains alive. Reference counting
   --  is atomic, which makes copying a holder safe from several tasks; it
   --  does not make the referenced element mutable, because nothing in this
   --  crate ever mutates one after construction.
   generic
      type Element_Type (<>) is private;
      with function "=" (Left, Right : Element_Type) return Boolean is <>;
   package Immutable_Holders is

      type Holder is tagged private;

      --  Take ownership of a copy of Value.
      --  @param Value Element to copy into a fresh shared cell
      --  @return Holder owning the only reference to that copy
      function To_Holder (Value : Element_Type) return Holder;

      --  Return an independent copy of the held element.
      --  @param Value Holder to read
      --  @return Copy of the held element
      --  @exception Constraint_Error Value holds nothing
      function Element (Value : Holder) return Element_Type;

      --  Borrow the held element for the duration of Process without
      --  copying it. Prefer this to Element on any path that runs per term.
      --  @param Value Holder to borrow from
      --  @param Process Callback receiving the held element
      --  @exception Constraint_Error Value holds nothing
      procedure Query_Element
        (Value   : Holder;
         Process : not null access procedure (Element : Element_Type));

      --  Compare by identity first, then structurally.
      --  @param Left First holder
      --  @param Right Second holder
      --  @return True when both are empty, share a cell, or hold equal
      --     elements
      overriding function "=" (Left, Right : Holder) return Boolean;

   private
      type Element_Access is access Element_Type;
      type Shared_Element;
      type Shared_Element_Access is access Shared_Element;

      type Holder is new Ada.Finalization.Controlled with record
         Shared : Shared_Element_Access := null;
      end record;

      overriding procedure Adjust (Value : in out Holder);
      overriding procedure Finalize (Value : in out Holder);
   end Immutable_Holders;

end Flyology_RDF;
