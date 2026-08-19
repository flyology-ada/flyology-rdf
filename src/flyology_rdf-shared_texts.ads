private with Ada.Finalization;
private with System.Atomic_Counters;

--  Immutable text that is cheap to copy.
--
--  An Unbounded_String copies its characters on every assignment, which
--  for values that are built once and then carried through several layers
--  -- an IRI into a term, into a statement, out to a consumer -- means an
--  allocation per layer for bytes that never change.
--
--  This holds the characters in one heap block together with a reference
--  count, so constructing costs a single allocation and copying costs an
--  increment. The count is atomic, so a value may be copied from several
--  tasks; the characters are never mutated, so sharing them is safe.
package Flyology_RDF.Shared_Texts is

   --  Immutable shared text. Copying is an increment.
   type Text is private;

   --  The empty text, which holds nothing and allocates nothing.
   function Empty return Text;

   --  Take a copy of Value into a fresh shared block.
   --  @param Value Characters to hold
   --  @return Text holding those characters
   function To_Text (Value : String) return Text;

   --  The held characters.
   --  @param Value Text to read
   --  @return Copy of the characters
   function To_String (Value : Text) return String;

   --  How many characters are held.
   --  @param Value Text to measure
   --  @return Length in characters
   function Length (Value : Text) return Natural;

   --  Borrow the characters without copying them.
   --  @param Value Text to borrow from
   --  @param Process Callback receiving the held characters
   procedure Query
     (Value   : Text;
      Process : not null access procedure (Item : String));

   --  Compare by identity first, then character by character.
   function "=" (Left, Right : Text) return Boolean;

private

   type Shared_Text;
   type Shared_Text_Access is access Shared_Text;

   --  Capacity is what was allocated, Length what is in use. They are
   --  separate so a released block can serve any later text that fits,
   --  which is what makes recycling them possible at all: a document
   --  builds hundreds of thousands of short texts and drops them.
   type Shared_Text (Capacity : Natural) is limited record
      References : System.Atomic_Counters.Atomic_Counter;
      Next_Free  : Shared_Text_Access;
      Length     : Natural := 0;
      Data       : String (1 .. Capacity);
   end record;

   type Text is new Ada.Finalization.Controlled with record
      Payload : Shared_Text_Access;
   end record;

   overriding procedure Adjust (Value : in out Text);
   overriding procedure Finalize (Value : in out Text);

end Flyology_RDF.Shared_Texts;
