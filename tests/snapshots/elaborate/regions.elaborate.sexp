(Unit main$1 [(VarDecl x$2 int)] [(Assign x$2 (Int 1))])
(Unit main$2
  [(VarDecl main$3 int)]
  [(Assign main$3 (Int 2)) (Check 1 (BinOp == (Var main$3) (Int 2)))])

(obligation 1 :kind assert :node 19)
