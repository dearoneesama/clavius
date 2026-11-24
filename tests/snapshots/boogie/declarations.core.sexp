; fails: O3
; Sorts, functions and axioms come before the units, and every unit may assume the axioms. A
; constant is a function with no parameters.
(SortDecl S)
(FunDecl empty [] S)
(FunDecl size [(VarDecl s S) (VarDecl k int)] int)
(Axiom
  (Forall
    [(VarDecl s S) (VarDecl k int)]
    [(Trigger [(App size [(Var s) (Var k)])])]
    (BinOp <= (Var k) (App size [(Var s) (Var k)]))))
(Unit sizes linear
  [(VarDecl t S)]
  [(Havoc t)
   (Check 1 (BinOp >= (App size [(Var t) (Int 3)]) (Int 3)))
   (Check 2 (BinOp >= (App size [(App empty []) (Int 0)]) (Int 0)))
   (Check 3 (BinOp > (App size [(App empty []) (Int 0)]) (Int 0)))])

(obligation 1 :kind assert :node 0)
(obligation 2 :kind assert :node 0)
(obligation 3 :kind assert :node 0)
