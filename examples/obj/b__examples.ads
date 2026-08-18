pragma Warnings (Off);
pragma Ada_95;
with System;
with System.Parameters;
with System.Secondary_Stack;
package ada_main is

   gnat_argc : Integer;
   gnat_argv : System.Address;
   gnat_envp : System.Address;

   pragma Import (C, gnat_argc);
   pragma Import (C, gnat_argv);
   pragma Import (C, gnat_envp);

   gnat_exit_status : Integer;
   pragma Import (C, gnat_exit_status);

   GNAT_Version : constant String :=
                    "GNAT Version: 16.1.0" & ASCII.NUL;
   pragma Export (C, GNAT_Version, "__gnat_version");

   GNAT_Version_Address : constant System.Address := GNAT_Version'Address;
   pragma Export (C, GNAT_Version_Address, "__gnat_version_address");

   Ada_Main_Program_Name : constant String := "_ada_examples" & ASCII.NUL;
   pragma Export (C, Ada_Main_Program_Name, "__gnat_ada_main_program_name");

   procedure adainit;
   pragma Export (C, adainit, "adainit");

   procedure adafinal;
   pragma Export (C, adafinal, "adafinal");

   function main
     (argc : Integer;
      argv : System.Address;
      envp : System.Address)
      return Integer;
   pragma Export (C, main, "main");

   type Version_32 is mod 2 ** 32;
   u00001 : constant Version_32 := 16#c050d401#;
   pragma Export (C, u00001, "examplesB");
   u00002 : constant Version_32 := 16#b2cfab41#;
   pragma Export (C, u00002, "system__standard_libraryB");
   u00003 : constant Version_32 := 16#986fbd5a#;
   pragma Export (C, u00003, "system__standard_libraryS");
   u00004 : constant Version_32 := 16#76789da1#;
   pragma Export (C, u00004, "adaS");
   u00005 : constant Version_32 := 16#6ce3be0f#;
   pragma Export (C, u00005, "ada__exceptionsB");
   u00006 : constant Version_32 := 16#0fa7c4bb#;
   pragma Export (C, u00006, "ada__exceptionsS");
   u00007 : constant Version_32 := 16#85bf25f7#;
   pragma Export (C, u00007, "ada__exceptions__last_chance_handlerB");
   u00008 : constant Version_32 := 16#c1262c0b#;
   pragma Export (C, u00008, "ada__exceptions__last_chance_handlerS");
   u00009 : constant Version_32 := 16#8a611ac3#;
   pragma Export (C, u00009, "systemS");
   u00010 : constant Version_32 := 16#7fa0a598#;
   pragma Export (C, u00010, "system__soft_linksB");
   u00011 : constant Version_32 := 16#acdd2381#;
   pragma Export (C, u00011, "system__soft_linksS");
   u00012 : constant Version_32 := 16#33935a56#;
   pragma Export (C, u00012, "system__secondary_stackB");
   u00013 : constant Version_32 := 16#b0931c82#;
   pragma Export (C, u00013, "system__secondary_stackS");
   u00014 : constant Version_32 := 16#3007a9ef#;
   pragma Export (C, u00014, "system__parametersB");
   u00015 : constant Version_32 := 16#2bcfb19f#;
   pragma Export (C, u00015, "system__parametersS");
   u00016 : constant Version_32 := 16#46bfce2b#;
   pragma Export (C, u00016, "system__storage_elementsS");
   u00017 : constant Version_32 := 16#0286ce9f#;
   pragma Export (C, u00017, "system__soft_links__initializeB");
   u00018 : constant Version_32 := 16#ac2e8b53#;
   pragma Export (C, u00018, "system__soft_links__initializeS");
   u00019 : constant Version_32 := 16#8599b27b#;
   pragma Export (C, u00019, "system__stack_checkingB");
   u00020 : constant Version_32 := 16#4d3e0fd5#;
   pragma Export (C, u00020, "system__stack_checkingS");
   u00021 : constant Version_32 := 16#45e1965e#;
   pragma Export (C, u00021, "system__exception_tableB");
   u00022 : constant Version_32 := 16#074a6cda#;
   pragma Export (C, u00022, "system__exception_tableS");
   u00023 : constant Version_32 := 16#b8c4a5f1#;
   pragma Export (C, u00023, "system__exceptionsS");
   u00024 : constant Version_32 := 16#c367aa24#;
   pragma Export (C, u00024, "system__exceptions__machineB");
   u00025 : constant Version_32 := 16#8d1d496c#;
   pragma Export (C, u00025, "system__exceptions__machineS");
   u00026 : constant Version_32 := 16#2f7ce883#;
   pragma Export (C, u00026, "system__exceptions_debugB");
   u00027 : constant Version_32 := 16#ba6f4290#;
   pragma Export (C, u00027, "system__exceptions_debugS");
   u00028 : constant Version_32 := 16#1d4109f1#;
   pragma Export (C, u00028, "system__img_intS");
   u00029 : constant Version_32 := 16#5c7d9c20#;
   pragma Export (C, u00029, "system__tracebackB");
   u00030 : constant Version_32 := 16#0cfbee7e#;
   pragma Export (C, u00030, "system__tracebackS");
   u00031 : constant Version_32 := 16#5f6b6486#;
   pragma Export (C, u00031, "system__traceback_entriesB");
   u00032 : constant Version_32 := 16#427da54f#;
   pragma Export (C, u00032, "system__traceback_entriesS");
   u00033 : constant Version_32 := 16#727e0fa1#;
   pragma Export (C, u00033, "system__traceback__symbolicB");
   u00034 : constant Version_32 := 16#3e2e1203#;
   pragma Export (C, u00034, "system__traceback__symbolicS");
   u00035 : constant Version_32 := 16#701f9d88#;
   pragma Export (C, u00035, "ada__exceptions__tracebackB");
   u00036 : constant Version_32 := 16#47e3d2a3#;
   pragma Export (C, u00036, "ada__exceptions__tracebackS");
   u00037 : constant Version_32 := 16#f9910acc#;
   pragma Export (C, u00037, "system__address_imageB");
   u00038 : constant Version_32 := 16#2b8d87f9#;
   pragma Export (C, u00038, "system__address_imageS");
   u00039 : constant Version_32 := 16#bfdff066#;
   pragma Export (C, u00039, "system__img_address_32S");
   u00040 : constant Version_32 := 16#9111f9c1#;
   pragma Export (C, u00040, "interfacesS");
   u00041 : constant Version_32 := 16#92ff51e4#;
   pragma Export (C, u00041, "system__img_address_64S");
   u00042 : constant Version_32 := 16#fd158a37#;
   pragma Export (C, u00042, "system__wch_conB");
   u00043 : constant Version_32 := 16#536239a0#;
   pragma Export (C, u00043, "system__wch_conS");
   u00044 : constant Version_32 := 16#5c289972#;
   pragma Export (C, u00044, "system__wch_stwB");
   u00045 : constant Version_32 := 16#7e7315a1#;
   pragma Export (C, u00045, "system__wch_stwS");
   u00046 : constant Version_32 := 16#7cd63de5#;
   pragma Export (C, u00046, "system__wch_cnvB");
   u00047 : constant Version_32 := 16#55a2f3d0#;
   pragma Export (C, u00047, "system__wch_cnvS");
   u00048 : constant Version_32 := 16#e538de43#;
   pragma Export (C, u00048, "system__wch_jisB");
   u00049 : constant Version_32 := 16#e01591fa#;
   pragma Export (C, u00049, "system__wch_jisS");
   u00050 : constant Version_32 := 16#e6d4fa36#;
   pragma Export (C, u00050, "ada__stringsS");
   u00051 : constant Version_32 := 16#a201b8c5#;
   pragma Export (C, u00051, "ada__strings__text_buffersB");
   u00052 : constant Version_32 := 16#a7cfd09b#;
   pragma Export (C, u00052, "ada__strings__text_buffersS");
   u00053 : constant Version_32 := 16#8b7604c4#;
   pragma Export (C, u00053, "ada__strings__utf_encodingB");
   u00054 : constant Version_32 := 16#c9e86997#;
   pragma Export (C, u00054, "ada__strings__utf_encodingS");
   u00055 : constant Version_32 := 16#bb780f45#;
   pragma Export (C, u00055, "ada__strings__utf_encoding__stringsB");
   u00056 : constant Version_32 := 16#b85ff4b6#;
   pragma Export (C, u00056, "ada__strings__utf_encoding__stringsS");
   u00057 : constant Version_32 := 16#d1d1ed0b#;
   pragma Export (C, u00057, "ada__strings__utf_encoding__wide_stringsB");
   u00058 : constant Version_32 := 16#5678478f#;
   pragma Export (C, u00058, "ada__strings__utf_encoding__wide_stringsS");
   u00059 : constant Version_32 := 16#c2b98963#;
   pragma Export (C, u00059, "ada__strings__utf_encoding__wide_wide_stringsB");
   u00060 : constant Version_32 := 16#d7af3358#;
   pragma Export (C, u00060, "ada__strings__utf_encoding__wide_wide_stringsS");
   u00061 : constant Version_32 := 16#df45aed8#;
   pragma Export (C, u00061, "ada__tagsB");
   u00062 : constant Version_32 := 16#99822aba#;
   pragma Export (C, u00062, "ada__tagsS");
   u00063 : constant Version_32 := 16#3548d972#;
   pragma Export (C, u00063, "system__htableB");
   u00064 : constant Version_32 := 16#0bb84228#;
   pragma Export (C, u00064, "system__htableS");
   u00065 : constant Version_32 := 16#1f1abe38#;
   pragma Export (C, u00065, "system__string_hashB");
   u00066 : constant Version_32 := 16#acfdc257#;
   pragma Export (C, u00066, "system__string_hashS");
   u00067 : constant Version_32 := 16#704b659a#;
   pragma Export (C, u00067, "system__unsigned_typesS");
   u00068 : constant Version_32 := 16#159aaf05#;
   pragma Export (C, u00068, "system__val_lluS");
   u00069 : constant Version_32 := 16#0d1904b9#;
   pragma Export (C, u00069, "system__val_utilB");
   u00070 : constant Version_32 := 16#66caf8e0#;
   pragma Export (C, u00070, "system__val_utilS");
   u00071 : constant Version_32 := 16#8b956324#;
   pragma Export (C, u00071, "system__case_util_nssB");
   u00072 : constant Version_32 := 16#ef0e9ee9#;
   pragma Export (C, u00072, "system__case_util_nssS");
   u00073 : constant Version_32 := 16#7e321c90#;
   pragma Export (C, u00073, "ada__strings__unboundedB");
   u00074 : constant Version_32 := 16#d6cc3e91#;
   pragma Export (C, u00074, "ada__strings__unboundedS");
   u00075 : constant Version_32 := 16#8e328749#;
   pragma Export (C, u00075, "system__finalization_primitivesB");
   u00076 : constant Version_32 := 16#a30892a3#;
   pragma Export (C, u00076, "system__finalization_primitivesS");
   u00077 : constant Version_32 := 16#afd63177#;
   pragma Export (C, u00077, "system__os_locksS");
   u00078 : constant Version_32 := 16#b9ada65a#;
   pragma Export (C, u00078, "interfaces__cB");
   u00079 : constant Version_32 := 16#610373b9#;
   pragma Export (C, u00079, "interfaces__cS");
   u00080 : constant Version_32 := 16#1311b8a5#;
   pragma Export (C, u00080, "system__os_constantsS");
   u00081 : constant Version_32 := 16#44f765f3#;
   pragma Export (C, u00081, "system__put_imagesB");
   u00082 : constant Version_32 := 16#9a7e9601#;
   pragma Export (C, u00082, "system__put_imagesS");
   u00083 : constant Version_32 := 16#22b9eb9f#;
   pragma Export (C, u00083, "ada__strings__text_buffers__utilsB");
   u00084 : constant Version_32 := 16#89062ac3#;
   pragma Export (C, u00084, "ada__strings__text_buffers__utilsS");
   u00085 : constant Version_32 := 16#49d4c8e0#;
   pragma Export (C, u00085, "system__return_stackS");
   u00086 : constant Version_32 := 16#7598b591#;
   pragma Export (C, u00086, "ada__finalizationS");
   u00087 : constant Version_32 := 16#6e6e3f5b#;
   pragma Export (C, u00087, "ada__streamsB");
   u00088 : constant Version_32 := 16#bd793559#;
   pragma Export (C, u00088, "ada__streamsS");
   u00089 : constant Version_32 := 16#367911c4#;
   pragma Export (C, u00089, "ada__io_exceptionsS");
   u00090 : constant Version_32 := 16#d00f339c#;
   pragma Export (C, u00090, "system__finalization_rootB");
   u00091 : constant Version_32 := 16#801d2417#;
   pragma Export (C, u00091, "system__finalization_rootS");
   u00092 : constant Version_32 := 16#9a8aed35#;
   pragma Export (C, u00092, "ada__strings__mapsB");
   u00093 : constant Version_32 := 16#879d83f1#;
   pragma Export (C, u00093, "ada__strings__mapsS");
   u00094 : constant Version_32 := 16#d55f7fbe#;
   pragma Export (C, u00094, "system__bit_opsB");
   u00095 : constant Version_32 := 16#4792b6ff#;
   pragma Export (C, u00095, "system__bit_opsS");
   u00096 : constant Version_32 := 16#5b4659fa#;
   pragma Export (C, u00096, "ada__charactersS");
   u00097 : constant Version_32 := 16#cde9ea2d#;
   pragma Export (C, u00097, "ada__characters__latin_1S");
   u00098 : constant Version_32 := 16#28efec31#;
   pragma Export (C, u00098, "ada__strings__searchB");
   u00099 : constant Version_32 := 16#7f896bb3#;
   pragma Export (C, u00099, "ada__strings__searchS");
   u00100 : constant Version_32 := 16#52627794#;
   pragma Export (C, u00100, "system__atomic_countersB");
   u00101 : constant Version_32 := 16#5679f500#;
   pragma Export (C, u00101, "system__atomic_countersS");
   u00102 : constant Version_32 := 16#553a519e#;
   pragma Export (C, u00102, "system__atomic_primitivesB");
   u00103 : constant Version_32 := 16#b0203cad#;
   pragma Export (C, u00103, "system__atomic_primitivesS");
   u00104 : constant Version_32 := 16#72726776#;
   pragma Export (C, u00104, "system__stream_attributesB");
   u00105 : constant Version_32 := 16#3bf21799#;
   pragma Export (C, u00105, "system__stream_attributesS");
   u00106 : constant Version_32 := 16#c027a94e#;
   pragma Export (C, u00106, "system__stream_attributes__xdrB");
   u00107 : constant Version_32 := 16#35ff530d#;
   pragma Export (C, u00107, "system__stream_attributes__xdrS");
   u00108 : constant Version_32 := 16#4953c5af#;
   pragma Export (C, u00108, "system__fat_fltS");
   u00109 : constant Version_32 := 16#6f61cca2#;
   pragma Export (C, u00109, "system__fat_lfltS");
   u00110 : constant Version_32 := 16#15b16248#;
   pragma Export (C, u00110, "system__fat_llfS");
   u00111 : constant Version_32 := 16#c7620b41#;
   pragma Export (C, u00111, "ada__text_ioB");
   u00112 : constant Version_32 := 16#46a4a696#;
   pragma Export (C, u00112, "ada__text_ioS");
   u00113 : constant Version_32 := 16#1cacf006#;
   pragma Export (C, u00113, "interfaces__c_streamsB");
   u00114 : constant Version_32 := 16#ecfa876a#;
   pragma Export (C, u00114, "interfaces__c_streamsS");
   u00115 : constant Version_32 := 16#22b1fb99#;
   pragma Export (C, u00115, "system__crtlB");
   u00116 : constant Version_32 := 16#a9f4d4a9#;
   pragma Export (C, u00116, "system__crtlS");
   u00117 : constant Version_32 := 16#a94e7662#;
   pragma Export (C, u00117, "system__file_ioB");
   u00118 : constant Version_32 := 16#ec2e4f85#;
   pragma Export (C, u00118, "system__file_ioS");
   u00119 : constant Version_32 := 16#14fb286b#;
   pragma Export (C, u00119, "system__case_utilB");
   u00120 : constant Version_32 := 16#5499fba9#;
   pragma Export (C, u00120, "system__case_utilS");
   u00121 : constant Version_32 := 16#861c956a#;
   pragma Export (C, u00121, "system__os_libB");
   u00122 : constant Version_32 := 16#b4b4641d#;
   pragma Export (C, u00122, "system__os_libS");
   u00123 : constant Version_32 := 16#94d23d25#;
   pragma Export (C, u00123, "system__atomic_operations__test_and_setB");
   u00124 : constant Version_32 := 16#57acee8e#;
   pragma Export (C, u00124, "system__atomic_operations__test_and_setS");
   u00125 : constant Version_32 := 16#4d0260e6#;
   pragma Export (C, u00125, "system__atomic_operationsS");
   u00126 : constant Version_32 := 16#256dbbe5#;
   pragma Export (C, u00126, "system__stringsB");
   u00127 : constant Version_32 := 16#11e31adb#;
   pragma Export (C, u00127, "system__stringsS");
   u00128 : constant Version_32 := 16#e0daad44#;
   pragma Export (C, u00128, "system__file_control_blockS");
   u00129 : constant Version_32 := 16#e3779319#;
   pragma Export (C, u00129, "flyology_n3S");
   u00130 : constant Version_32 := 16#3d1df191#;
   pragma Export (C, u00130, "flyology_n3__modelB");
   u00131 : constant Version_32 := 16#d7dfd73b#;
   pragma Export (C, u00131, "flyology_n3__modelS");
   u00132 : constant Version_32 := 16#179d7d28#;
   pragma Export (C, u00132, "ada__containersS");
   u00133 : constant Version_32 := 16#c3b32edd#;
   pragma Export (C, u00133, "ada__containers__helpersB");
   u00134 : constant Version_32 := 16#f29f054d#;
   pragma Export (C, u00134, "ada__containers__helpersS");
   u00135 : constant Version_32 := 16#478e2b79#;
   pragma Export (C, u00135, "flyology_rdfB");
   u00136 : constant Version_32 := 16#adf1b7f3#;
   pragma Export (C, u00136, "flyology_rdfS");
   u00137 : constant Version_32 := 16#4be7000e#;
   pragma Export (C, u00137, "flyology_rdf__irisB");
   u00138 : constant Version_32 := 16#5cd11604#;
   pragma Export (C, u00138, "flyology_rdf__irisS");
   u00139 : constant Version_32 := 16#dd887b66#;
   pragma Export (C, u00139, "flyology_iriB");
   u00140 : constant Version_32 := 16#ba6b5e77#;
   pragma Export (C, u00140, "flyology_iriS");
   u00141 : constant Version_32 := 16#75913d83#;
   pragma Export (C, u00141, "ada__characters__handlingB");
   u00142 : constant Version_32 := 16#729cc5db#;
   pragma Export (C, u00142, "ada__characters__handlingS");
   u00143 : constant Version_32 := 16#5c2ece6d#;
   pragma Export (C, u00143, "ada__strings__maps__constantsS");
   u00144 : constant Version_32 := 16#cfbd1264#;
   pragma Export (C, u00144, "flyology_iri__webB");
   u00145 : constant Version_32 := 16#891f5b14#;
   pragma Export (C, u00145, "flyology_iri__webS");
   u00146 : constant Version_32 := 16#6b121d04#;
   pragma Export (C, u00146, "flyology_iri__idnaB");
   u00147 : constant Version_32 := 16#81b0d05f#;
   pragma Export (C, u00147, "flyology_iri__idnaS");
   u00148 : constant Version_32 := 16#714167ff#;
   pragma Export (C, u00148, "ada__strings__wide_wide_unboundedB");
   u00149 : constant Version_32 := 16#67f619a1#;
   pragma Export (C, u00149, "ada__strings__wide_wide_unboundedS");
   u00150 : constant Version_32 := 16#311e8639#;
   pragma Export (C, u00150, "ada__strings__wide_wide_searchB");
   u00151 : constant Version_32 := 16#d5f3cbcc#;
   pragma Export (C, u00151, "ada__strings__wide_wide_searchS");
   u00152 : constant Version_32 := 16#f2759eae#;
   pragma Export (C, u00152, "ada__strings__wide_wide_mapsB");
   u00153 : constant Version_32 := 16#53339820#;
   pragma Export (C, u00153, "ada__strings__wide_wide_mapsS");
   u00154 : constant Version_32 := 16#ef3937cc#;
   pragma Export (C, u00154, "system__compare_array_unsigned_32B");
   u00155 : constant Version_32 := 16#445c6044#;
   pragma Export (C, u00155, "system__compare_array_unsigned_32S");
   u00156 : constant Version_32 := 16#57b06f13#;
   pragma Export (C, u00156, "ada__wide_wide_charactersS");
   u00157 : constant Version_32 := 16#1e812477#;
   pragma Export (C, u00157, "ada__wide_wide_characters__handlingB");
   u00158 : constant Version_32 := 16#a3feeaf1#;
   pragma Export (C, u00158, "ada__wide_wide_characters__handlingS");
   u00159 : constant Version_32 := 16#23673975#;
   pragma Export (C, u00159, "ada__wide_wide_characters__unicodeB");
   u00160 : constant Version_32 := 16#f6976fba#;
   pragma Export (C, u00160, "ada__wide_wide_characters__unicodeS");
   u00161 : constant Version_32 := 16#1f3e80d3#;
   pragma Export (C, u00161, "system__utf_32B");
   u00162 : constant Version_32 := 16#0e00cb7c#;
   pragma Export (C, u00162, "system__utf_32S");
   u00163 : constant Version_32 := 16#b2148485#;
   pragma Export (C, u00163, "system__img_lliS");
   u00164 : constant Version_32 := 16#cff87fce#;
   pragma Export (C, u00164, "flyology_rdf__termsB");
   u00165 : constant Version_32 := 16#94d9464b#;
   pragma Export (C, u00165, "flyology_rdf__termsS");
   u00166 : constant Version_32 := 16#83571fa6#;
   pragma Export (C, u00166, "system__assertionsB");
   u00167 : constant Version_32 := 16#ac626558#;
   pragma Export (C, u00167, "system__assertionsS");
   u00168 : constant Version_32 := 16#8b2c6428#;
   pragma Export (C, u00168, "ada__assertionsB");
   u00169 : constant Version_32 := 16#cc3ec2fd#;
   pragma Export (C, u00169, "ada__assertionsS");
   u00170 : constant Version_32 := 16#02e43f40#;
   pragma Export (C, u00170, "system__pool_globalB");
   u00171 : constant Version_32 := 16#928ad74c#;
   pragma Export (C, u00171, "system__pool_globalS");
   u00172 : constant Version_32 := 16#a56a70fa#;
   pragma Export (C, u00172, "system__memoryB");
   u00173 : constant Version_32 := 16#92f586d9#;
   pragma Export (C, u00173, "system__memoryS");
   u00174 : constant Version_32 := 16#9969561e#;
   pragma Export (C, u00174, "system__storage_poolsB");
   u00175 : constant Version_32 := 16#0a664c89#;
   pragma Export (C, u00175, "system__storage_poolsS");
   u00176 : constant Version_32 := 16#36601f03#;
   pragma Export (C, u00176, "system__storage_pools__subpoolsB");
   u00177 : constant Version_32 := 16#219014ff#;
   pragma Export (C, u00177, "system__storage_pools__subpoolsS");
   u00178 : constant Version_32 := 16#20ec7aa3#;
   pragma Export (C, u00178, "system__ioB");
   u00179 : constant Version_32 := 16#1423ed8c#;
   pragma Export (C, u00179, "system__ioS");
   u00180 : constant Version_32 := 16#3676fd0b#;
   pragma Export (C, u00180, "system__storage_pools__subpools__finalizationB");
   u00181 : constant Version_32 := 16#4c972977#;
   pragma Export (C, u00181, "system__storage_pools__subpools__finalizationS");
   u00182 : constant Version_32 := 16#be6f5d2e#;
   pragma Export (C, u00182, "system__strings__stream_opsB");
   u00183 : constant Version_32 := 16#9a9c0b11#;
   pragma Export (C, u00183, "system__strings__stream_opsS");
   u00184 : constant Version_32 := 16#6a445260#;
   pragma Export (C, u00184, "flyology_n3__parsersB");
   u00185 : constant Version_32 := 16#5ad9da1f#;
   pragma Export (C, u00185, "flyology_n3__parsersS");
   u00186 : constant Version_32 := 16#f4ca97ce#;
   pragma Export (C, u00186, "ada__containers__red_black_treesS");
   u00187 : constant Version_32 := 16#94531187#;
   pragma Export (C, u00187, "flyology_rdf__lexersB");
   u00188 : constant Version_32 := 16#3b091070#;
   pragma Export (C, u00188, "flyology_rdf__lexersS");
   u00189 : constant Version_32 := 16#5baa95d3#;
   pragma Export (C, u00189, "flyology_rdf__parser_cursorsB");
   u00190 : constant Version_32 := 16#8f5b0f1a#;
   pragma Export (C, u00190, "flyology_rdf__parser_cursorsS");
   u00191 : constant Version_32 := 16#ae9f7b8e#;
   pragma Export (C, u00191, "flyology_n3__writersB");
   u00192 : constant Version_32 := 16#31a826e1#;
   pragma Export (C, u00192, "flyology_n3__writersS");
   u00193 : constant Version_32 := 16#1968f4b1#;
   pragma Export (C, u00193, "flyology_rdf__nquads_writersB");
   u00194 : constant Version_32 := 16#2c545ed8#;
   pragma Export (C, u00194, "flyology_rdf__nquads_writersS");
   u00195 : constant Version_32 := 16#6c2faff6#;
   pragma Export (C, u00195, "flyology_rdf__quadsB");
   u00196 : constant Version_32 := 16#edd2f316#;
   pragma Export (C, u00196, "flyology_rdf__quadsS");
   u00197 : constant Version_32 := 16#6f4953ea#;
   pragma Export (C, u00197, "flyology_rdf__triplesB");
   u00198 : constant Version_32 := 16#78ace471#;
   pragma Export (C, u00198, "flyology_rdf__triplesS");
   u00199 : constant Version_32 := 16#f6b53445#;
   pragma Export (C, u00199, "flyology_rdf__canonicalizationB");
   u00200 : constant Version_32 := 16#4cc36831#;
   pragma Export (C, u00200, "flyology_rdf__canonicalizationS");
   u00201 : constant Version_32 := 16#0cfaff2b#;
   pragma Export (C, u00201, "flyology_rdf__datasetsB");
   u00202 : constant Version_32 := 16#81a99616#;
   pragma Export (C, u00202, "flyology_rdf__datasetsS");
   u00203 : constant Version_32 := 16#6dd6f53b#;
   pragma Export (C, u00203, "flyology_rdf__digestsB");
   u00204 : constant Version_32 := 16#62d413b9#;
   pragma Export (C, u00204, "flyology_rdf__digestsS");
   u00205 : constant Version_32 := 16#b5988c27#;
   pragma Export (C, u00205, "gnatS");
   u00206 : constant Version_32 := 16#c083f050#;
   pragma Export (C, u00206, "gnat__sha256B");
   u00207 : constant Version_32 := 16#11461484#;
   pragma Export (C, u00207, "gnat__sha256S");
   u00208 : constant Version_32 := 16#2375494c#;
   pragma Export (C, u00208, "gnat__secure_hashesB");
   u00209 : constant Version_32 := 16#55c8a468#;
   pragma Export (C, u00209, "gnat__secure_hashesS");
   u00210 : constant Version_32 := 16#1538efc3#;
   pragma Export (C, u00210, "gnat__secure_hashes__sha2_32B");
   u00211 : constant Version_32 := 16#ebdefe7d#;
   pragma Export (C, u00211, "gnat__secure_hashes__sha2_32S");
   u00212 : constant Version_32 := 16#0668360c#;
   pragma Export (C, u00212, "gnat__byte_swappingB");
   u00213 : constant Version_32 := 16#9b2b80dd#;
   pragma Export (C, u00213, "gnat__byte_swappingS");
   u00214 : constant Version_32 := 16#062495ea#;
   pragma Export (C, u00214, "system__byte_swappingS");
   u00215 : constant Version_32 := 16#25a43d5d#;
   pragma Export (C, u00215, "gnat__secure_hashes__sha2_commonB");
   u00216 : constant Version_32 := 16#21653399#;
   pragma Export (C, u00216, "gnat__secure_hashes__sha2_commonS");
   u00217 : constant Version_32 := 16#1238b91b#;
   pragma Export (C, u00217, "gnat__sha384B");
   u00218 : constant Version_32 := 16#06bc17f1#;
   pragma Export (C, u00218, "gnat__sha384S");
   u00219 : constant Version_32 := 16#5aefc971#;
   pragma Export (C, u00219, "gnat__secure_hashes__sha2_64B");
   u00220 : constant Version_32 := 16#2e9fb443#;
   pragma Export (C, u00220, "gnat__secure_hashes__sha2_64S");
   u00221 : constant Version_32 := 16#7a68fb63#;
   pragma Export (C, u00221, "flyology_rdf__codecsB");
   u00222 : constant Version_32 := 16#6a682237#;
   pragma Export (C, u00222, "flyology_rdf__codecsS");
   u00223 : constant Version_32 := 16#46146b03#;
   pragma Export (C, u00223, "flyology_rdf__turtle_parsersB");
   u00224 : constant Version_32 := 16#f058b688#;
   pragma Export (C, u00224, "flyology_rdf__turtle_parsersS");
   u00225 : constant Version_32 := 16#579d64c6#;
   pragma Export (C, u00225, "system__taskingB");
   u00226 : constant Version_32 := 16#1ee3a9a0#;
   pragma Export (C, u00226, "system__taskingS");
   u00227 : constant Version_32 := 16#1472808a#;
   pragma Export (C, u00227, "system__task_primitivesS");
   u00228 : constant Version_32 := 16#2f25b9f8#;
   pragma Export (C, u00228, "system__os_interfaceB");
   u00229 : constant Version_32 := 16#27d51d6d#;
   pragma Export (C, u00229, "system__os_interfaceS");
   u00230 : constant Version_32 := 16#75266e31#;
   pragma Export (C, u00230, "system__c_timeB");
   u00231 : constant Version_32 := 16#f6136865#;
   pragma Export (C, u00231, "system__c_timeS");
   u00232 : constant Version_32 := 16#0343f0e1#;
   pragma Export (C, u00232, "system__task_primitives__operationsB");
   u00233 : constant Version_32 := 16#0a98e1c8#;
   pragma Export (C, u00233, "system__task_primitives__operationsS");
   u00234 : constant Version_32 := 16#4d23c29f#;
   pragma Export (C, u00234, "system__interrupt_managementB");
   u00235 : constant Version_32 := 16#96a36b4a#;
   pragma Export (C, u00235, "system__interrupt_managementS");
   u00236 : constant Version_32 := 16#414d8432#;
   pragma Export (C, u00236, "system__multiprocessorsB");
   u00237 : constant Version_32 := 16#b2cd85b0#;
   pragma Export (C, u00237, "system__multiprocessorsS");
   u00238 : constant Version_32 := 16#fb4ecb85#;
   pragma Export (C, u00238, "system__os_primitivesB");
   u00239 : constant Version_32 := 16#8d9c7f35#;
   pragma Export (C, u00239, "system__os_primitivesS");
   u00240 : constant Version_32 := 16#e0fce7f8#;
   pragma Export (C, u00240, "system__task_infoB");
   u00241 : constant Version_32 := 16#0a7ba7c2#;
   pragma Export (C, u00241, "system__task_infoS");
   u00242 : constant Version_32 := 16#3779e0d0#;
   pragma Export (C, u00242, "system__tasking__debugB");
   u00243 : constant Version_32 := 16#2f318f36#;
   pragma Export (C, u00243, "system__tasking__debugS");
   u00244 : constant Version_32 := 16#ca878138#;
   pragma Export (C, u00244, "system__concat_2B");
   u00245 : constant Version_32 := 16#3f9a6934#;
   pragma Export (C, u00245, "system__concat_2S");
   u00246 : constant Version_32 := 16#752a67ed#;
   pragma Export (C, u00246, "system__concat_3B");
   u00247 : constant Version_32 := 16#001b0361#;
   pragma Export (C, u00247, "system__concat_3S");
   u00248 : constant Version_32 := 16#7c6f2528#;
   pragma Export (C, u00248, "system__stack_usageB");
   u00249 : constant Version_32 := 16#7bb67a7d#;
   pragma Export (C, u00249, "system__stack_usageS");
   u00250 : constant Version_32 := 16#a757285c#;
   pragma Export (C, u00250, "flyology_rdf__turtle_writersB");
   u00251 : constant Version_32 := 16#76879558#;
   pragma Export (C, u00251, "flyology_rdf__turtle_writersS");
   u00252 : constant Version_32 := 16#26faa3de#;
   pragma Export (C, u00252, "flyology_sparqlS");
   u00253 : constant Version_32 := 16#39460fdc#;
   pragma Export (C, u00253, "flyology_sparql__parsersB");
   u00254 : constant Version_32 := 16#614e9be2#;
   pragma Export (C, u00254, "flyology_sparql__parsersS");
   u00255 : constant Version_32 := 16#53662346#;
   pragma Export (C, u00255, "system__val_intS");
   u00256 : constant Version_32 := 16#bfedde8f#;
   pragma Export (C, u00256, "system__val_unsS");
   u00257 : constant Version_32 := 16#c5ccb7cf#;
   pragma Export (C, u00257, "flyology_sparql__syntaxB");
   u00258 : constant Version_32 := 16#a7166a13#;
   pragma Export (C, u00258, "flyology_sparql__syntaxS");
   u00259 : constant Version_32 := 16#a6a8bf31#;
   pragma Export (C, u00259, "flyology_sparql__writersB");
   u00260 : constant Version_32 := 16#db3351e2#;
   pragma Export (C, u00260, "flyology_sparql__writersS");
   u00261 : constant Version_32 := 16#bcc987d2#;
   pragma Export (C, u00261, "system__concat_4B");
   u00262 : constant Version_32 := 16#b99945fd#;
   pragma Export (C, u00262, "system__concat_4S");
   u00263 : constant Version_32 := 16#ebb39bbb#;
   pragma Export (C, u00263, "system__concat_5B");
   u00264 : constant Version_32 := 16#caf8cb18#;
   pragma Export (C, u00264, "system__concat_5S");
   u00265 : constant Version_32 := 16#02cecc7b#;
   pragma Export (C, u00265, "system__concat_6B");
   u00266 : constant Version_32 := 16#0833ebcb#;
   pragma Export (C, u00266, "system__concat_6S");
   u00267 : constant Version_32 := 16#3e33b3e2#;
   pragma Export (C, u00267, "system__img_llliS");

   --  BEGIN ELABORATION ORDER
   --  ada%s
   --  ada.characters%s
   --  ada.characters.latin_1%s
   --  ada.wide_wide_characters%s
   --  interfaces%s
   --  system%s
   --  system.atomic_operations%s
   --  system.byte_swapping%s
   --  system.case_util_nss%s
   --  system.case_util_nss%b
   --  system.io%s
   --  system.io%b
   --  system.parameters%s
   --  system.parameters%b
   --  system.crtl%s
   --  system.crtl%b
   --  interfaces.c_streams%s
   --  interfaces.c_streams%b
   --  system.storage_elements%s
   --  system.img_address_32%s
   --  system.img_address_64%s
   --  system.return_stack%s
   --  system.stack_checking%s
   --  system.stack_checking%b
   --  system.string_hash%s
   --  system.string_hash%b
   --  system.htable%s
   --  system.htable%b
   --  system.strings%s
   --  system.strings%b
   --  system.task_info%s
   --  system.task_info%b
   --  system.traceback_entries%s
   --  system.traceback_entries%b
   --  system.unsigned_types%s
   --  system.utf_32%s
   --  system.utf_32%b
   --  ada.wide_wide_characters.unicode%s
   --  ada.wide_wide_characters.unicode%b
   --  system.wch_con%s
   --  system.wch_con%b
   --  system.wch_jis%s
   --  system.wch_jis%b
   --  system.wch_cnv%s
   --  system.wch_cnv%b
   --  system.compare_array_unsigned_32%s
   --  system.compare_array_unsigned_32%b
   --  system.concat_2%s
   --  system.concat_2%b
   --  system.concat_3%s
   --  system.concat_3%b
   --  system.concat_4%s
   --  system.concat_4%b
   --  system.concat_5%s
   --  system.concat_5%b
   --  system.concat_6%s
   --  system.concat_6%b
   --  system.img_int%s
   --  system.stack_usage%s
   --  system.stack_usage%b
   --  system.img_lli%s
   --  system.img_llli%s
   --  system.traceback%s
   --  system.traceback%b
   --  system.secondary_stack%s
   --  system.standard_library%s
   --  ada.exceptions%s
   --  system.exceptions_debug%s
   --  system.exceptions_debug%b
   --  system.soft_links%s
   --  system.wch_stw%s
   --  system.wch_stw%b
   --  ada.exceptions.last_chance_handler%s
   --  ada.exceptions.last_chance_handler%b
   --  ada.exceptions.traceback%s
   --  ada.exceptions.traceback%b
   --  system.address_image%s
   --  system.address_image%b
   --  system.exception_table%s
   --  system.exception_table%b
   --  system.exceptions%s
   --  system.exceptions.machine%s
   --  system.exceptions.machine%b
   --  system.memory%s
   --  system.memory%b
   --  system.secondary_stack%b
   --  system.soft_links.initialize%s
   --  system.soft_links.initialize%b
   --  system.soft_links%b
   --  system.standard_library%b
   --  system.traceback.symbolic%s
   --  system.traceback.symbolic%b
   --  ada.exceptions%b
   --  ada.assertions%s
   --  ada.assertions%b
   --  ada.containers%s
   --  ada.io_exceptions%s
   --  ada.strings%s
   --  ada.strings.utf_encoding%s
   --  ada.strings.utf_encoding%b
   --  ada.strings.utf_encoding.strings%s
   --  ada.strings.utf_encoding.strings%b
   --  ada.strings.utf_encoding.wide_strings%s
   --  ada.strings.utf_encoding.wide_strings%b
   --  ada.strings.utf_encoding.wide_wide_strings%s
   --  ada.strings.utf_encoding.wide_wide_strings%b
   --  ada.wide_wide_characters.handling%s
   --  ada.wide_wide_characters.handling%b
   --  gnat%s
   --  gnat.byte_swapping%s
   --  gnat.byte_swapping%b
   --  interfaces.c%s
   --  interfaces.c%b
   --  system.atomic_primitives%s
   --  system.atomic_primitives%b
   --  system.atomic_counters%s
   --  system.atomic_counters%b
   --  system.atomic_operations.test_and_set%s
   --  system.atomic_operations.test_and_set%b
   --  system.case_util%s
   --  system.case_util%b
   --  system.fat_flt%s
   --  system.fat_lflt%s
   --  system.fat_llf%s
   --  system.multiprocessors%s
   --  system.multiprocessors%b
   --  system.os_constants%s
   --  system.c_time%s
   --  system.c_time%b
   --  system.os_lib%s
   --  system.os_lib%b
   --  system.os_locks%s
   --  system.finalization_primitives%s
   --  system.finalization_primitives%b
   --  system.os_interface%s
   --  system.os_interface%b
   --  system.interrupt_management%s
   --  system.interrupt_management%b
   --  system.os_primitives%s
   --  system.os_primitives%b
   --  system.task_primitives%s
   --  system.tasking%s
   --  system.task_primitives.operations%s
   --  system.tasking.debug%s
   --  system.tasking.debug%b
   --  system.task_primitives.operations%b
   --  system.tasking%b
   --  system.val_util%s
   --  system.val_util%b
   --  system.val_llu%s
   --  ada.tags%s
   --  ada.tags%b
   --  ada.strings.text_buffers%s
   --  ada.strings.text_buffers%b
   --  ada.strings.text_buffers.utils%s
   --  ada.strings.text_buffers.utils%b
   --  system.put_images%s
   --  system.put_images%b
   --  ada.streams%s
   --  ada.streams%b
   --  system.file_control_block%s
   --  system.finalization_root%s
   --  system.finalization_root%b
   --  ada.finalization%s
   --  ada.containers.helpers%s
   --  ada.containers.helpers%b
   --  ada.containers.red_black_trees%s
   --  system.file_io%s
   --  system.file_io%b
   --  system.storage_pools%s
   --  system.storage_pools%b
   --  system.storage_pools.subpools%s
   --  system.storage_pools.subpools.finalization%s
   --  system.storage_pools.subpools.finalization%b
   --  system.storage_pools.subpools%b
   --  system.stream_attributes%s
   --  system.stream_attributes.xdr%s
   --  system.stream_attributes.xdr%b
   --  system.stream_attributes%b
   --  ada.strings.wide_wide_maps%s
   --  ada.strings.wide_wide_maps%b
   --  ada.strings.wide_wide_search%s
   --  ada.strings.wide_wide_search%b
   --  ada.strings.wide_wide_unbounded%s
   --  ada.strings.wide_wide_unbounded%b
   --  system.val_uns%s
   --  system.val_int%s
   --  ada.text_io%s
   --  ada.text_io%b
   --  gnat.secure_hashes%s
   --  gnat.secure_hashes%b
   --  gnat.secure_hashes.sha2_common%s
   --  gnat.secure_hashes.sha2_common%b
   --  gnat.secure_hashes.sha2_32%s
   --  gnat.secure_hashes.sha2_32%b
   --  gnat.secure_hashes.sha2_64%s
   --  gnat.secure_hashes.sha2_64%b
   --  gnat.sha256%s
   --  gnat.sha256%b
   --  gnat.sha384%s
   --  gnat.sha384%b
   --  system.assertions%s
   --  system.assertions%b
   --  system.bit_ops%s
   --  system.bit_ops%b
   --  ada.strings.maps%s
   --  ada.strings.maps%b
   --  ada.strings.maps.constants%s
   --  ada.characters.handling%s
   --  ada.characters.handling%b
   --  ada.strings.search%s
   --  ada.strings.search%b
   --  ada.strings.unbounded%s
   --  ada.strings.unbounded%b
   --  system.pool_global%s
   --  system.pool_global%b
   --  system.strings.stream_ops%s
   --  system.strings.stream_ops%b
   --  flyology_iri%s
   --  flyology_iri.idna%s
   --  flyology_iri.idna%b
   --  flyology_iri.web%s
   --  flyology_iri.web%b
   --  flyology_iri%b
   --  flyology_n3%s
   --  flyology_rdf%s
   --  flyology_rdf%b
   --  flyology_rdf.digests%s
   --  flyology_rdf.digests%b
   --  flyology_rdf.iris%s
   --  flyology_rdf.iris%b
   --  flyology_rdf.parser_cursors%s
   --  flyology_rdf.parser_cursors%b
   --  flyology_rdf.lexers%s
   --  flyology_rdf.lexers%b
   --  flyology_rdf.terms%s
   --  flyology_rdf.terms%b
   --  flyology_n3.model%s
   --  flyology_n3.model%b
   --  flyology_n3.parsers%s
   --  flyology_n3.parsers%b
   --  flyology_rdf.triples%s
   --  flyology_rdf.triples%b
   --  flyology_rdf.quads%s
   --  flyology_rdf.quads%b
   --  flyology_rdf.codecs%s
   --  flyology_rdf.codecs%b
   --  flyology_rdf.nquads_writers%s
   --  flyology_rdf.nquads_writers%b
   --  flyology_n3.writers%s
   --  flyology_n3.writers%b
   --  flyology_rdf.datasets%s
   --  flyology_rdf.datasets%b
   --  flyology_rdf.canonicalization%s
   --  flyology_rdf.canonicalization%b
   --  flyology_rdf.turtle_parsers%s
   --  flyology_rdf.turtle_parsers%b
   --  flyology_rdf.turtle_writers%s
   --  flyology_rdf.turtle_writers%b
   --  flyology_sparql%s
   --  flyology_sparql.syntax%s
   --  flyology_sparql.syntax%b
   --  flyology_sparql.parsers%s
   --  flyology_sparql.parsers%b
   --  flyology_sparql.writers%s
   --  flyology_sparql.writers%b
   --  examples%b
   --  END ELABORATION ORDER

end ada_main;
