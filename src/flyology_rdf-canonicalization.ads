with Ada.Strings.Unbounded;

with Flyology_RDF.Datasets;

--  RDF Dataset Canonicalization, RDFC-1.0.
--
--  Two datasets that differ only in their blank node labels denote the same
--  thing, and nothing built so far can tell you that: the dataset compares
--  labelled statements, and the round-trip tests deliberately claim less
--  than isomorphism because they had no way to decide it. Canonicalization
--  is what decides it. It assigns every blank node a label derived from its
--  position in the graph rather than from what it was called, so two
--  isomorphic datasets canonicalize to identical bytes.
--
--  The algorithm has a documented adversarial case. Distinguishing blank
--  nodes that look alike from every direction requires trying permutations,
--  and a dataset can be built specifically to make that combinatorial. This
--  implementation therefore takes a work bound and reports reaching it as a
--  result rather than running until something else gives out.
package Flyology_RDF.Canonicalization is

   --  Outcome of a canonicalization attempt.
   --  @enum Canonicalized The dataset was canonicalized
   --  @enum Work_Limit_Reached The bound was hit before finishing, so the
   --     output is not usable
   type Result_Status is (Canonicalized, Work_Limit_Reached);

   --  Default bound on permutation and recursion work.
   --
   --  Ordinary data does not approach this: the bound exists for datasets
   --  designed to be expensive, not for large ones.
   Default_Maximum_Work : constant := 1_000_000;

   --  Raised by the function form when the work bound is reached.
   Work_Limit_Error : exception;

   --  Canonicalize, reporting rather than raising.
   --  @param Value Dataset to canonicalize
   --  @param Output Canonical N-Quads, meaningful only when Canonicalized
   --  @param Status Whether canonicalization completed
   --  @param Maximum_Work Bound on permutation and recursion work
   procedure Canonicalize
     (Value        : Datasets.Dataset;
      Output       : out Ada.Strings.Unbounded.Unbounded_String;
      Status       : out Result_Status;
      Maximum_Work : Positive := Default_Maximum_Work);

   --  Canonicalize into canonical N-Quads.
   --
   --  Blank nodes are labelled c14n0, c14n1, and so on, in an order derived
   --  from the graph rather than from the input.
   --  @param Value Dataset to canonicalize
   --  @param Maximum_Work Bound on permutation and recursion work
   --  @return The canonical N-Quads serialization
   --  @exception Work_Limit_Error The bound was reached
   function To_Canonical_NQuads
     (Value        : Datasets.Dataset;
      Maximum_Work : Positive := Default_Maximum_Work) return String;

   --  Report whether two datasets denote the same thing.
   --
   --  This is isomorphism: equal apart from a consistent renaming of blank
   --  nodes. It is what a round-trip test wants when the serialization it
   --  passed through was entitled to rename them.
   --  @param Left First dataset
   --  @param Right Second dataset
   --  @param Maximum_Work Bound applied to each canonicalization
   --  @return True when the two canonicalize identically
   --  @exception Work_Limit_Error The bound was reached
   function Is_Isomorphic
     (Left, Right  : Datasets.Dataset;
      Maximum_Work : Positive := Default_Maximum_Work) return Boolean;

end Flyology_RDF.Canonicalization;
