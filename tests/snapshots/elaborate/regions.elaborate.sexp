(Unit main$1 linear [(VarDecl x$2 int)] [(Assign x$2 (Int 1))])
(Unit main$2 linear
  [(VarDecl main$3 int)]
  [(Assign main$3 (Int 2)) (Check 1 (BinOp == (Var main$3) (Int 2)))])
(Unit main$3 nonlinear
  [(VarDecl y$4 int)]
  [(Check 2
     (BinOp and
       (BinOp <= (Int -9007199254740992) (BinOp * (Int 1) (Int 2)))
       (BinOp <= (BinOp * (Int 1) (Int 2)) (Int 9007199254740992))))
   (Assign y$4 (BinOp * (Int 1) (Int 2)))])

(obligation 1 :kind assert :node 19)
(obligation 2 :kind range :node 23)
