; fails: O1 O2 O4 O6
; Every failure in every unit is reported in one run. A check that can fail only when an earlier
; one fails isn't: O3 holds once O2 is assumed.
(Unit several
  [(VarDecl x int) (VarDecl y int)]
  [(Check 1 (BinOp > (Var x) (Int 0)))
   (Check 2 (BinOp > (Var y) (Int 0)))
   (Check 3 (BinOp > (BinOp + (Var x) (Var y)) (Var x)))
   (Branch (BinOp > (Var x) (Int 10))
     [(Check 4 (BinOp > (Var x) (Int 20)))]
     [(Check 5 (BinOp <= (Var x) (Int 10)))])])
(Unit other
  [(VarDecl z int)]
  [(Check 6 (BinOp == (Var z) (Int 0)))])

(obligation 1 :kind assert :node 0)
(obligation 2 :kind assert :node 0)
(obligation 3 :kind assert :node 0)
(obligation 4 :kind assert :node 0)
(obligation 5 :kind assert :node 0)
(obligation 6 :kind unreachable :node 0)
