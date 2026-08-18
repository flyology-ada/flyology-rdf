--  A checkpoint callback and somewhere to count it.
--
--  Work_Checkpoint_Access is a library-level access-to-procedure, so what
--  it designates must be library level too. A procedure nested inside the
--  test would fail the accessibility check, which is why this is its own
--  unit rather than a few lines inside one.
package Checkpoint_Probe is

   --  How many times Bump has been called since the last Reset.
   Calls : Natural := 0;

   --  Raised by Bump when Fail is set, to check that a checkpoint which
   --  refuses to continue stops the parse rather than being swallowed.
   Refused : exception;

   --  When set, Bump raises Refused instead of counting.
   Fail : Boolean := False;

   --  Count one call, or refuse.
   procedure Bump;

   --  Forget every call counted so far.
   procedure Reset;

end Checkpoint_Probe;
