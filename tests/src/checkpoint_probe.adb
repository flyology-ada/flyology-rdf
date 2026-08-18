package body Checkpoint_Probe is

   procedure Bump is
   begin
      if Fail then
         raise Refused with "checkpoint deliberately refusing";
      end if;
      Calls := Calls + 1;
   end Bump;

   procedure Reset is
   begin
      Calls := 0;
      Fail := False;
   end Reset;

end Checkpoint_Probe;
