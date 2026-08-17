with Ada.Strings.Unbounded;

with Flyology_RDF.IRIs;
with Flyology_RDF.NQuads_Writers;
with Flyology_RDF.Terms;

package body Flyology_N3.Writers is

   package Unbounded renames Ada.Strings.Unbounded;
   package IRIs renames Flyology_RDF.IRIs;
   package RDF_Writers renames Flyology_RDF.NQuads_Writers;
   package Terms renames Flyology_RDF.Terms;

   use type Model.Term_Kind;
   use type Terms.Term_Kind;

   Log_Implies : constant String :=
     "http://www.w3.org/2000/10/swap/log#implies";
   OWL_Same_As : constant String := "http://www.w3.org/2002/07/owl#sameAs";
   RDF_Type    : constant String :=
     "http://www.w3.org/1999/02/22-rdf-syntax-ns#type";

   function Indent (Depth : Natural) return String
   is (if Depth = 0 then "" else [1 .. 4 * Depth => ' ']);

   function Render
     (Value : Model.Term;
      Style : Verb_Style;
      Depth : Natural) return String;

   function Render_Statement
     (Value : Model.Statement;
      Style : Verb_Style;
      Depth : Natural) return String;

   --  A predicate that names one of the three well-known relations is
   --  written as the operator N3 provides for it.
   function Render_Verb
     (Value : Model.Term;
      Style : Verb_Style;
      Depth : Natural) return String is
   begin
      if Style = Shorthand_Verbs
        and then Model.Kind (Value) = Model.RDF_Kind
        and then Terms.Kind (Model.RDF_Value (Value)) = Terms.IRI_Kind
      then
         declare
            Text : constant String :=
              IRIs.To_UTF_8 (Terms.IRI_Value (Model.RDF_Value (Value)));
         begin
            if Text = RDF_Type then
               return "a";
            elsif Text = Log_Implies then
               return "=>";
            elsif Text = OWL_Same_As then
               return "=";
            end if;
         end;
      end if;
      return Render (Value, Style, Depth);
   end Render_Verb;

   function Render
     (Value : Model.Term;
      Style : Verb_Style;
      Depth : Natural) return String is
   begin
      case Model.Kind (Value) is
         when Model.RDF_Kind =>
            --  Blank nodes, literals and IRIs have one written form, and
            --  the N-Quads writer already escapes them correctly.
            return RDF_Writers.Write_Term
              (Model.RDF_Value (Value), RDF_Writers.Implicit_Datatype);

         when Model.Variable_Kind =>
            return "?" & Model.Name (Value);

         when Model.List_Kind =>
            declare
               Buffer : Unbounded.Unbounded_String;
            begin
               Unbounded.Append (Buffer, "(");
               for Index in 1 .. Model.Length (Value) loop
                  Unbounded.Append (Buffer, " ");
                  Unbounded.Append
                    (Buffer,
                     Render (Model.Element (Value, Index), Style, Depth));
               end loop;
               Unbounded.Append (Buffer, " )");
               return Unbounded.To_String (Buffer);
            end;

         when Model.Formula_Kind =>
            if Model.Statement_Count (Value) = 0 then
               return "{}";
            end if;
            declare
               Buffer : Unbounded.Unbounded_String;
            begin
               Unbounded.Append (Buffer, "{" & ASCII.LF);
               for Index in 1 .. Model.Statement_Count (Value) loop
                  Unbounded.Append
                    (Buffer,
                     Render_Statement
                       (Model.Statement_At (Value, Index), Style,
                        Depth + 1));
               end loop;
               Unbounded.Append (Buffer, Indent (Depth) & "}");
               return Unbounded.To_String (Buffer);
            end;
      end case;
   end Render;

   function Render_Statement
     (Value : Model.Statement;
      Style : Verb_Style;
      Depth : Natural) return String
   is (Indent (Depth)
       & Render (Model.Subject (Value), Style, Depth)
       & " " & Render_Verb (Model.Predicate (Value), Style, Depth)
       & " " & Render (Model.Object (Value), Style, Depth)
       & " ." & ASCII.LF);

   function Write_Term
     (Value : Model.Term;
      Style : Verb_Style := Shorthand_Verbs) return String
   is (Render (Value, Style, 0));

   function To_N3
     (Value : Model.Term;
      Style : Verb_Style := Shorthand_Verbs) return String
   is
      Buffer : Unbounded.Unbounded_String;
   begin
      --  A document is a formula written without its braces, which is what
      --  makes To_N3 the inverse of Parse rather than of Write_Term.
      for Index in 1 .. Model.Statement_Count (Value) loop
         Unbounded.Append
           (Buffer,
            Render_Statement (Model.Statement_At (Value, Index), Style, 0));
      end loop;
      return Unbounded.To_String (Buffer);
   end To_N3;

end Flyology_N3.Writers;
