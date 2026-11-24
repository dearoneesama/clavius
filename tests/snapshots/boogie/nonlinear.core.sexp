; fails: O1
; Only a nonlinear unit may use Z3's nonlinear arithmetic, so the same product bound fails in a
; linear one.
(Unit area linear
  [(VarDecl w int) (VarDecl h int)]
  [(Assume 1 (BinOp and (BinOp <= (Int 0) (Var w)) (BinOp <= (Var w) (Int 4096))))
   (Assume 2 (BinOp and (BinOp <= (Int 0) (Var h)) (BinOp <= (Var h) (Int 4096))))
   (Check 1 (BinOp <= (BinOp * (Var w) (Var h)) (Int 16777216)))])
(Unit nonlinear_area nonlinear
  [(VarDecl w int) (VarDecl h int)]
  [(Assume 3 (BinOp and (BinOp <= (Int 0) (Var w)) (BinOp <= (Var w) (Int 4096))))
   (Assume 4 (BinOp and (BinOp <= (Int 0) (Var h)) (BinOp <= (Var h) (Int 4096))))
   (Check 2 (BinOp <= (BinOp * (Var w) (Var h)) (Int 16777216)))])

(obligation 1 :kind assert :node 0)
(obligation 2 :kind assert :node 0)

(assumption 1 :kind branch :node 0)
(assumption 2 :kind branch :node 0)
(assumption 3 :kind branch :node 0)
(assumption 4 :kind branch :node 0)
