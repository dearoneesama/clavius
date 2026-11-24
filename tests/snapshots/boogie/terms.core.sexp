; fails:
; Every term kind and operator appears in a check that holds.
(Unit terms
  [(VarDecl x int) (VarDecl p bool) (VarDecl q bool)]
  [(Havoc x)
   (Check 1 (BinOp == (BinOp * (Int 3) (Int -2)) (Int -6)))
   (Check 2 (BinOp > (BinOp - (Var x) (Int 1)) (BinOp - (Var x) (Int 2))))
   (Check 3 (BinOp and (BinOp < (Int 1) (Int 2)) (BinOp >= (Int 2) (Int 2))))
   (Check 4 (BinOp => (BinOp and (Var p) (Var q)) (BinOp or (Var p) (Bool false))))
   (Check 5 (Not (BinOp != (Ite (Var p) (Int 1) (Int 2)) (Ite (Not (Var p)) (Int 2) (Int 1)))))
   (Assign p (Bool true))
   (Check 6 (BinOp == (Var p) (BinOp or (Var q) (Not (Var q)))))
   (Check 7
     (BinOp and
       (BinOp == (BinOp mod (Int -7) (Int 3)) (Int 2))
       (BinOp == (BinOp mod (Int 7) (Int -3)) (Int 1))))
   (Check 8 (BinOp == (Let k (BinOp + (Var x) (Int 1)) (BinOp - (Var k) (Var x))) (Int 1)))])

(obligation 1 :kind assert :node 0)
(obligation 2 :kind assert :node 0)
(obligation 3 :kind assert :node 0)
(obligation 4 :kind assert :node 0)
(obligation 5 :kind assert :node 0)
(obligation 6 :kind assert :node 0)
(obligation 7 :kind assert :node 0)
(obligation 8 :kind assert :node 0)
