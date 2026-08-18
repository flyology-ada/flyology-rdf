pragma Warnings (Off);
pragma Ada_95;
pragma Source_File_Name (ada_main, Spec_File_Name => "b__examples.ads");
pragma Source_File_Name (ada_main, Body_File_Name => "b__examples.adb");
pragma Suppress (Overflow_Check);
with Ada.Exceptions;

package body ada_main is

   E006 : Short_Integer; pragma Import (Ada, E006, "ada__exceptions_E");
   E011 : Short_Integer; pragma Import (Ada, E011, "system__soft_links_E");
   E022 : Short_Integer; pragma Import (Ada, E022, "system__exception_table_E");
   E023 : Short_Integer; pragma Import (Ada, E023, "system__exceptions_E");
   E018 : Short_Integer; pragma Import (Ada, E018, "system__soft_links__initialize_E");
   E169 : Short_Integer; pragma Import (Ada, E169, "ada__assertions_E");
   E113 : Short_Integer; pragma Import (Ada, E113, "ada__containers_E");
   E077 : Short_Integer; pragma Import (Ada, E077, "ada__io_exceptions_E");
   E052 : Short_Integer; pragma Import (Ada, E052, "ada__strings_E");
   E054 : Short_Integer; pragma Import (Ada, E054, "ada__strings__utf_encoding_E");
   E205 : Short_Integer; pragma Import (Ada, E205, "gnat_E");
   E097 : Short_Integer; pragma Import (Ada, E097, "interfaces__c_E");
   E100 : Short_Integer; pragma Import (Ada, E100, "system__os_lib_E");
   E062 : Short_Integer; pragma Import (Ada, E062, "ada__tags_E");
   E051 : Short_Integer; pragma Import (Ada, E051, "ada__strings__text_buffers_E");
   E076 : Short_Integer; pragma Import (Ada, E076, "ada__streams_E");
   E108 : Short_Integer; pragma Import (Ada, E108, "system__file_control_block_E");
   E090 : Short_Integer; pragma Import (Ada, E090, "system__finalization_root_E");
   E088 : Short_Integer; pragma Import (Ada, E088, "ada__finalization_E");
   E087 : Short_Integer; pragma Import (Ada, E087, "system__file_io_E");
   E175 : Short_Integer; pragma Import (Ada, E175, "system__storage_pools_E");
   E177 : Short_Integer; pragma Import (Ada, E177, "system__storage_pools__subpools_E");
   E153 : Short_Integer; pragma Import (Ada, E153, "ada__strings__wide_wide_maps_E");
   E149 : Short_Integer; pragma Import (Ada, E149, "ada__strings__wide_wide_unbounded_E");
   E074 : Short_Integer; pragma Import (Ada, E074, "ada__text_io_E");
   E209 : Short_Integer; pragma Import (Ada, E209, "gnat__secure_hashes_E");
   E216 : Short_Integer; pragma Import (Ada, E216, "gnat__secure_hashes__sha2_common_E");
   E211 : Short_Integer; pragma Import (Ada, E211, "gnat__secure_hashes__sha2_32_E");
   E220 : Short_Integer; pragma Import (Ada, E220, "gnat__secure_hashes__sha2_64_E");
   E207 : Short_Integer; pragma Import (Ada, E207, "gnat__sha256_E");
   E218 : Short_Integer; pragma Import (Ada, E218, "gnat__sha384_E");
   E121 : Short_Integer; pragma Import (Ada, E121, "ada__strings__maps_E");
   E143 : Short_Integer; pragma Import (Ada, E143, "ada__strings__maps__constants_E");
   E119 : Short_Integer; pragma Import (Ada, E119, "ada__strings__unbounded_E");
   E171 : Short_Integer; pragma Import (Ada, E171, "system__pool_global_E");
   E140 : Short_Integer; pragma Import (Ada, E140, "flyology_iri_E");
   E147 : Short_Integer; pragma Import (Ada, E147, "flyology_iri__idna_E");
   E145 : Short_Integer; pragma Import (Ada, E145, "flyology_iri__web_E");
   E136 : Short_Integer; pragma Import (Ada, E136, "flyology_rdf_E");
   E204 : Short_Integer; pragma Import (Ada, E204, "flyology_rdf__digests_E");
   E138 : Short_Integer; pragma Import (Ada, E138, "flyology_rdf__iris_E");
   E190 : Short_Integer; pragma Import (Ada, E190, "flyology_rdf__parser_cursors_E");
   E188 : Short_Integer; pragma Import (Ada, E188, "flyology_rdf__lexers_E");
   E165 : Short_Integer; pragma Import (Ada, E165, "flyology_rdf__terms_E");
   E111 : Short_Integer; pragma Import (Ada, E111, "flyology_n3__model_E");
   E185 : Short_Integer; pragma Import (Ada, E185, "flyology_n3__parsers_E");
   E198 : Short_Integer; pragma Import (Ada, E198, "flyology_rdf__triples_E");
   E196 : Short_Integer; pragma Import (Ada, E196, "flyology_rdf__quads_E");
   E222 : Short_Integer; pragma Import (Ada, E222, "flyology_rdf__codecs_E");
   E194 : Short_Integer; pragma Import (Ada, E194, "flyology_rdf__nquads_writers_E");
   E192 : Short_Integer; pragma Import (Ada, E192, "flyology_n3__writers_E");
   E202 : Short_Integer; pragma Import (Ada, E202, "flyology_rdf__datasets_E");
   E200 : Short_Integer; pragma Import (Ada, E200, "flyology_rdf__canonicalization_E");
   E224 : Short_Integer; pragma Import (Ada, E224, "flyology_rdf__turtle_parsers_E");
   E251 : Short_Integer; pragma Import (Ada, E251, "flyology_rdf__turtle_writers_E");
   E258 : Short_Integer; pragma Import (Ada, E258, "flyology_sparql__syntax_E");
   E254 : Short_Integer; pragma Import (Ada, E254, "flyology_sparql__parsers_E");
   E260 : Short_Integer; pragma Import (Ada, E260, "flyology_sparql__writers_E");

   Sec_Default_Sized_Stacks : array (1 .. 1) of aliased System.Secondary_Stack.SS_Stack (System.Parameters.Runtime_Default_Sec_Stack_Size);

   Local_Priority_Specific_Dispatching : constant String := "";
   Local_Interrupt_States : constant String := "";

   Is_Elaborated : Boolean := False;

   procedure finalize_library is
   begin
      declare
         procedure F1;
         pragma Import (Ada, F1, "flyology_sparql__parsers__finalize_body");
      begin
         E254 := E254 - 1;
         F1;
      end;
      declare
         procedure F2;
         pragma Import (Ada, F2, "flyology_sparql__parsers__finalize_spec");
      begin
         F2;
      end;
      E258 := E258 - 1;
      declare
         procedure F3;
         pragma Import (Ada, F3, "flyology_sparql__syntax__finalize_spec");
      begin
         F3;
      end;
      declare
         procedure F4;
         pragma Import (Ada, F4, "flyology_rdf__turtle_writers__finalize_body");
      begin
         E251 := E251 - 1;
         F4;
      end;
      declare
         procedure F5;
         pragma Import (Ada, F5, "flyology_rdf__turtle_writers__finalize_spec");
      begin
         F5;
      end;
      declare
         procedure F6;
         pragma Import (Ada, F6, "flyology_rdf__turtle_parsers__finalize_body");
      begin
         E224 := E224 - 1;
         F6;
      end;
      declare
         procedure F7;
         pragma Import (Ada, F7, "flyology_rdf__turtle_parsers__finalize_spec");
      begin
         F7;
      end;
      declare
         procedure F8;
         pragma Import (Ada, F8, "flyology_rdf__canonicalization__finalize_body");
      begin
         E200 := E200 - 1;
         F8;
      end;
      declare
         procedure F9;
         pragma Import (Ada, F9, "flyology_rdf__canonicalization__finalize_spec");
      begin
         F9;
      end;
      E202 := E202 - 1;
      declare
         procedure F10;
         pragma Import (Ada, F10, "flyology_rdf__datasets__finalize_spec");
      begin
         F10;
      end;
      E196 := E196 - 1;
      declare
         procedure F11;
         pragma Import (Ada, F11, "flyology_rdf__quads__finalize_spec");
      begin
         F11;
      end;
      E198 := E198 - 1;
      declare
         procedure F12;
         pragma Import (Ada, F12, "flyology_rdf__triples__finalize_spec");
      begin
         F12;
      end;
      declare
         procedure F13;
         pragma Import (Ada, F13, "flyology_n3__parsers__finalize_body");
      begin
         E185 := E185 - 1;
         F13;
      end;
      declare
         procedure F14;
         pragma Import (Ada, F14, "flyology_n3__parsers__finalize_spec");
      begin
         F14;
      end;
      E111 := E111 - 1;
      declare
         procedure F15;
         pragma Import (Ada, F15, "flyology_n3__model__finalize_spec");
      begin
         F15;
      end;
      declare
         procedure F16;
         pragma Import (Ada, F16, "flyology_rdf__terms__finalize_body");
      begin
         E165 := E165 - 1;
         F16;
      end;
      declare
         procedure F17;
         pragma Import (Ada, F17, "flyology_rdf__terms__finalize_spec");
      begin
         F17;
      end;
      E171 := E171 - 1;
      declare
         procedure F18;
         pragma Import (Ada, F18, "system__pool_global__finalize_spec");
      begin
         F18;
      end;
      E119 := E119 - 1;
      declare
         procedure F19;
         pragma Import (Ada, F19, "ada__strings__unbounded__finalize_spec");
      begin
         F19;
      end;
      E218 := E218 - 1;
      declare
         procedure F20;
         pragma Import (Ada, F20, "gnat__sha384__finalize_spec");
      begin
         F20;
      end;
      E207 := E207 - 1;
      declare
         procedure F21;
         pragma Import (Ada, F21, "gnat__sha256__finalize_spec");
      begin
         F21;
      end;
      E074 := E074 - 1;
      declare
         procedure F22;
         pragma Import (Ada, F22, "ada__text_io__finalize_spec");
      begin
         F22;
      end;
      E149 := E149 - 1;
      declare
         procedure F23;
         pragma Import (Ada, F23, "ada__strings__wide_wide_unbounded__finalize_spec");
      begin
         F23;
      end;
      E153 := E153 - 1;
      declare
         procedure F24;
         pragma Import (Ada, F24, "ada__strings__wide_wide_maps__finalize_spec");
      begin
         F24;
      end;
      E177 := E177 - 1;
      declare
         procedure F25;
         pragma Import (Ada, F25, "system__storage_pools__subpools__finalize_spec");
      begin
         F25;
      end;
      declare
         procedure F26;
         pragma Import (Ada, F26, "system__file_io__finalize_body");
      begin
         E087 := E087 - 1;
         F26;
      end;
      declare
         procedure Reraise_Library_Exception_If_Any;
            pragma Import (Ada, Reraise_Library_Exception_If_Any, "__gnat_reraise_library_exception_if_any");
      begin
         Reraise_Library_Exception_If_Any;
      end;
   end finalize_library;

   procedure adafinal is
      procedure s_stalib_adafinal;
      pragma Import (Ada, s_stalib_adafinal, "system__standard_library__adafinal");

      procedure Runtime_Finalize;
      pragma Import (C, Runtime_Finalize, "__gnat_runtime_finalize");

   begin
      if not Is_Elaborated then
         return;
      end if;
      Is_Elaborated := False;
      Runtime_Finalize;
      s_stalib_adafinal;
   end adafinal;

   type No_Param_Proc is access procedure;
   pragma Favor_Top_Level (No_Param_Proc);

   procedure adainit is
      Main_Priority : Integer;
      pragma Import (C, Main_Priority, "__gl_main_priority");
      Time_Slice_Value : Integer;
      pragma Import (C, Time_Slice_Value, "__gl_time_slice_val");
      WC_Encoding : Character;
      pragma Import (C, WC_Encoding, "__gl_wc_encoding");
      Locking_Policy : Character;
      pragma Import (C, Locking_Policy, "__gl_locking_policy");
      Queuing_Policy : Character;
      pragma Import (C, Queuing_Policy, "__gl_queuing_policy");
      Task_Dispatching_Policy : Character;
      pragma Import (C, Task_Dispatching_Policy, "__gl_task_dispatching_policy");
      Priority_Specific_Dispatching : System.Address;
      pragma Import (C, Priority_Specific_Dispatching, "__gl_priority_specific_dispatching");
      Num_Specific_Dispatching : Integer;
      pragma Import (C, Num_Specific_Dispatching, "__gl_num_specific_dispatching");
      Main_CPU : Integer;
      pragma Import (C, Main_CPU, "__gl_main_cpu");
      Interrupt_States : System.Address;
      pragma Import (C, Interrupt_States, "__gl_interrupt_states");
      Num_Interrupt_States : Integer;
      pragma Import (C, Num_Interrupt_States, "__gl_num_interrupt_states");
      Unreserve_All_Interrupts : Integer;
      pragma Import (C, Unreserve_All_Interrupts, "__gl_unreserve_all_interrupts");
      Detect_Blocking : Integer;
      pragma Import (C, Detect_Blocking, "__gl_detect_blocking");
      Default_Stack_Size : Integer;
      pragma Import (C, Default_Stack_Size, "__gl_default_stack_size");
      Default_Secondary_Stack_Size : System.Parameters.Size_Type;
      pragma Import (C, Default_Secondary_Stack_Size, "__gnat_default_ss_size");
      Bind_Env_Addr : System.Address;
      pragma Import (C, Bind_Env_Addr, "__gl_bind_env_addr");
      Interrupts_Default_To_System : Integer;
      pragma Import (C, Interrupts_Default_To_System, "__gl_interrupts_default_to_system");

      procedure Runtime_Initialize (Install_Handler : Integer);
      pragma Import (C, Runtime_Initialize, "__gnat_runtime_initialize");

      procedure Tasking_Runtime_Initialize;
      pragma Import (C, Tasking_Runtime_Initialize, "__gnat_tasking_runtime_initialize");

      Finalize_Library_Objects : No_Param_Proc;
      pragma Import (C, Finalize_Library_Objects, "__gnat_finalize_library_objects");
      Binder_Sec_Stacks_Count : Natural;
      pragma Import (Ada, Binder_Sec_Stacks_Count, "__gnat_binder_ss_count");
      Default_Sized_SS_Pool : System.Address;
      pragma Import (Ada, Default_Sized_SS_Pool, "__gnat_default_ss_pool");

   begin
      if Is_Elaborated then
         return;
      end if;
      Is_Elaborated := True;
      Main_Priority := -1;
      Time_Slice_Value := -1;
      WC_Encoding := 'b';
      Locking_Policy := ' ';
      Queuing_Policy := ' ';
      Task_Dispatching_Policy := ' ';
      Priority_Specific_Dispatching :=
        Local_Priority_Specific_Dispatching'Address;
      Num_Specific_Dispatching := 0;
      Main_CPU := -1;
      Interrupt_States := Local_Interrupt_States'Address;
      Num_Interrupt_States := 0;
      Unreserve_All_Interrupts := 0;
      Detect_Blocking := 0;
      Default_Stack_Size := -1;

      ada_main'Elab_Body;
      Default_Secondary_Stack_Size := System.Parameters.Runtime_Default_Sec_Stack_Size;
      Binder_Sec_Stacks_Count := 1;
      Default_Sized_SS_Pool := Sec_Default_Sized_Stacks'Address;

      Runtime_Initialize (1);
      Tasking_Runtime_Initialize;

      Finalize_Library_Objects := finalize_library'access;

      Ada.Exceptions'Elab_Spec;
      System.Soft_Links'Elab_Spec;
      System.Exception_Table'Elab_Body;
      E022 := E022 + 1;
      System.Exceptions'Elab_Spec;
      E023 := E023 + 1;
      System.Soft_Links.Initialize'Elab_Body;
      E018 := E018 + 1;
      E011 := E011 + 1;
      E006 := E006 + 1;
      Ada.Assertions'Elab_Spec;
      E169 := E169 + 1;
      Ada.Containers'Elab_Spec;
      E113 := E113 + 1;
      Ada.Io_Exceptions'Elab_Spec;
      E077 := E077 + 1;
      Ada.Strings'Elab_Spec;
      E052 := E052 + 1;
      Ada.Strings.Utf_Encoding'Elab_Spec;
      E054 := E054 + 1;
      Gnat'Elab_Spec;
      E205 := E205 + 1;
      Interfaces.C'Elab_Spec;
      E097 := E097 + 1;
      System.Os_Lib'Elab_Body;
      E100 := E100 + 1;
      Ada.Tags'Elab_Spec;
      Ada.Tags'Elab_Body;
      E062 := E062 + 1;
      Ada.Strings.Text_Buffers'Elab_Spec;
      E051 := E051 + 1;
      Ada.Streams'Elab_Spec;
      E076 := E076 + 1;
      System.File_Control_Block'Elab_Spec;
      E108 := E108 + 1;
      System.Finalization_Root'Elab_Spec;
      E090 := E090 + 1;
      Ada.Finalization'Elab_Spec;
      E088 := E088 + 1;
      System.File_Io'Elab_Body;
      E087 := E087 + 1;
      System.Storage_Pools'Elab_Spec;
      E175 := E175 + 1;
      System.Storage_Pools.Subpools'Elab_Spec;
      E177 := E177 + 1;
      Ada.Strings.Wide_Wide_Maps'Elab_Spec;
      E153 := E153 + 1;
      Ada.Strings.Wide_Wide_Unbounded'Elab_Spec;
      E149 := E149 + 1;
      Ada.Text_Io'Elab_Spec;
      Ada.Text_Io'Elab_Body;
      E074 := E074 + 1;
      E209 := E209 + 1;
      E216 := E216 + 1;
      E211 := E211 + 1;
      Gnat.Secure_Hashes.Sha2_64'Elab_Spec;
      E220 := E220 + 1;
      Gnat.Sha256'Elab_Spec;
      E207 := E207 + 1;
      Gnat.Sha384'Elab_Spec;
      E218 := E218 + 1;
      Ada.Strings.Maps'Elab_Spec;
      E121 := E121 + 1;
      Ada.Strings.Maps.Constants'Elab_Spec;
      E143 := E143 + 1;
      Ada.Strings.Unbounded'Elab_Spec;
      E119 := E119 + 1;
      System.Pool_Global'Elab_Spec;
      E171 := E171 + 1;
      Flyology_Iri'Elab_Spec;
      E147 := E147 + 1;
      E145 := E145 + 1;
      E140 := E140 + 1;
      E136 := E136 + 1;
      E204 := E204 + 1;
      Flyology_Rdf.Iris'Elab_Spec;
      E138 := E138 + 1;
      E190 := E190 + 1;
      E188 := E188 + 1;
      Flyology_Rdf.Terms'Elab_Spec;
      Flyology_Rdf.Terms'Elab_Body;
      E165 := E165 + 1;
      Flyology_N3.Model'Elab_Spec;
      E111 := E111 + 1;
      Flyology_N3.Parsers'Elab_Spec;
      Flyology_N3.Parsers'Elab_Body;
      E185 := E185 + 1;
      Flyology_Rdf.Triples'Elab_Spec;
      E198 := E198 + 1;
      Flyology_Rdf.Quads'Elab_Spec;
      E196 := E196 + 1;
      Flyology_Rdf.Codecs'Elab_Spec;
      E222 := E222 + 1;
      E194 := E194 + 1;
      E192 := E192 + 1;
      Flyology_Rdf.Datasets'Elab_Spec;
      E202 := E202 + 1;
      Flyology_Rdf.Canonicalization'Elab_Spec;
      Flyology_Rdf.Canonicalization'Elab_Body;
      E200 := E200 + 1;
      Flyology_Rdf.Turtle_Parsers'Elab_Spec;
      Flyology_Rdf.Turtle_Parsers'Elab_Body;
      E224 := E224 + 1;
      Flyology_Rdf.Turtle_Writers'Elab_Spec;
      Flyology_Rdf.Turtle_Writers'Elab_Body;
      E251 := E251 + 1;
      Flyology_Sparql.Syntax'Elab_Spec;
      E258 := E258 + 1;
      Flyology_Sparql.Parsers'Elab_Spec;
      Flyology_Sparql.Parsers'Elab_Body;
      E254 := E254 + 1;
      E260 := E260 + 1;
   end adainit;

   procedure Ada_Main_Program;
   pragma Import (Ada, Ada_Main_Program, "_ada_examples");

   function main
     (argc : Integer;
      argv : System.Address;
      envp : System.Address)
      return Integer
   is
      procedure Initialize (Addr : System.Address);
      pragma Import (C, Initialize, "__gnat_initialize");

      procedure Finalize;
      pragma Import (C, Finalize, "__gnat_finalize");
      SEH : aliased array (1 .. 2) of Integer;

      Ensure_Reference : aliased System.Address := Ada_Main_Program_Name'Address;
      pragma Volatile (Ensure_Reference);

   begin
      if gnat_argc = 0 then
         gnat_argc := argc;
         gnat_argv := argv;
      end if;
      gnat_envp := envp;

      Initialize (SEH'Address);
      adainit;
      Ada_Main_Program;
      adafinal;
      Finalize;
      return (gnat_exit_status);
   end;

--  BEGIN Object file/option list
   --   /Users/yrashk/Projects/flyology-ada/flyology-rdf/examples/obj/examples.o
   --   -L/Users/yrashk/Projects/flyology-ada/flyology-rdf/examples/obj/
   --   -L/Users/yrashk/Projects/flyology-ada/flyology-rdf/examples/obj/
   --   -L/Users/yrashk/Projects/flyology-ada/flyology-rdf/lib/
   --   -L/Users/yrashk/.local/share/alire/builds/flyology_http_ddbba90d/d8b85050a13bfb5066e845e574971f1361446e8531cc5a134bec32f900a752dc/flyology_iri/lib/
   --   -L/Users/yrashk/Projects/flyology-ada/flyology-rdf/n3/lib/
   --   -L/Users/yrashk/Projects/flyology-ada/flyology-rdf/sparql/lib/
   --   -L/users/yrashk/.local/share/alire/toolchains/gnat_native_16.1.0_657cf254/lib/gcc/aarch64-apple-darwin24.6.0/16.1.0/adalib/
   --   -static
   --   -lgnarl
   --   -lgnat
--  END Object file/option list   

end ada_main;
